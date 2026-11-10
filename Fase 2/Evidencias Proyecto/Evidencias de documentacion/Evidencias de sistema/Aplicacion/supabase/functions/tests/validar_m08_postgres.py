import argparse
import json
import os
from pathlib import Path
import queue
import socket
import subprocess
import tempfile
import threading
import time
import uuid


ROOT = Path(__file__).resolve().parents[2]
HIDDEN = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0


class Sesion:
    def __init__(self, banco):
        self.proceso = subprocess.Popen(banco.comando + ['-v', 'ON_ERROR_STOP=0'],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, encoding='utf-8', errors='replace', bufsize=1,
            env=banco.env, creationflags=HIDDEN)
        self.cola = queue.Queue()
        def recoger():
            for linea in self.proceso.stdout:
                self.cola.put(linea.rstrip())
        threading.Thread(target=recoger, daemon=True).start()
        self.sql('\\set VERBOSITY verbose\nSET statement_timeout = \'8s\';')
        self.pid = int(self.sql('SELECT pg_backend_pid();').strip())

    def enviar(self, sql):
        marca = 'fin_' + uuid.uuid4().hex
        self.proceso.stdin.write(sql + '\n\\echo ' + marca + '\n')
        self.proceso.stdin.flush()
        return marca

    def esperar(self, marca):
        lineas = []
        limite = time.monotonic() + 12
        while time.monotonic() < limite:
            linea = self.cola.get(timeout=max(0.01, limite - time.monotonic()))
            if linea == marca:
                return '\n'.join(lineas)
            lineas.append(linea)
        raise AssertionError('La sesion local no completo la consulta')

    def sql(self, sql):
        return self.esperar(self.enviar(sql))

    def cerrar(self):
        if self.proceso.poll() is None:
            self.proceso.stdin.write('ROLLBACK;\n\\q\n')
            self.proceso.stdin.flush()
            self.proceso.communicate(timeout=12)


class Banco:
    def __init__(self, binarios):
        self.binarios = Path(binarios)
        self.directorio = Path(tempfile.mkdtemp(prefix='nfc_m08_aislado_'))
        self.datos = self.directorio / 'data'
        with socket.socket() as reserva:
            reserva.bind(('127.0.0.1', 0))
            self.puerto = reserva.getsockname()[1]
        self.env = {k: v for k, v in os.environ.items() if not k.startswith('PG')}
        self.env.update(PGCLIENTENCODING='UTF8', PGCONNECT_TIMEOUT='3', PGAPPNAME='m08_validacion_aislada')
        self.comando = [str(self.binarios / 'psql.exe'), '-X', '-q', '-A', '-t', '-w',
            '-h', '127.0.0.1', '-p', str(self.puerto), '-U', 'm08_validador', '-d', 'postgres']
        self.iniciado = False
        self.aprobadas = 0
        self.identidades = {n: str(uuid.uuid4()) for n in ['a','b','c','d','e','f','g','historico','h']}
        self.sesiones = {n: str(uuid.uuid4()) for n in ['a','b','c','d','e','f','g','historico']}

    def proceso(self, argumentos, entrada=None):
        r = subprocess.run(argumentos, input=entrada, capture_output=True, text=True,
            encoding='utf-8', errors='replace', env=self.env, creationflags=HIDDEN, timeout=45)
        if r.returncode:
            raise RuntimeError(r.stdout + '\n' + r.stderr)
        return r.stdout.strip()

    def sql(self, texto):
        return self.proceso(self.comando + ['-v','ON_ERROR_STOP=1'], texto)

    def iniciar(self):
        self.proceso([str(self.binarios/'initdb.exe'), '-D', str(self.datos), '-U', 'm08_validador',
            '-A', 'trust', '--encoding=UTF8', '--locale=C'])
        opciones = f'-h 127.0.0.1 -p {self.puerto} -c listen_addresses=127.0.0.1'
        self.proceso([str(self.binarios/'pg_ctl.exe'), '-D', str(self.datos), '-l', str(self.directorio/'postgres.log'),
            '-o', opciones, '-w', 'start'])
        self.iniciado = True
        actual = Path(self.sql('SHOW data_directory;')).resolve()
        assert actual == self.datos.resolve(), 'La conexion no apunta al cluster temporal propio'
        print(f'Cluster propio confirmado: {self.directorio}; solo loopback:{self.puerto}', flush=True)

    def detener(self):
        if self.iniciado:
            self.proceso([str(self.binarios/'pg_ctl.exe'), '-D', str(self.datos), '-m', 'fast', '-w', 'stop'])
            print('Cluster temporal detenido. No se borraron cuentas ni hogares.', flush=True)

    def claims(self, usuario, rol='authenticated'):
        return (f"SET ROLE {rol}; SELECT set_config('request.jwt.claim.sub','{usuario}',false); "
            f"SELECT set_config('request.jwt.claim.role','{rol}',false);")

    def rpc(self, expresion):
        return json.loads(self.sql(self.claims(self.identidades['g'], 'service_role') + 'SELECT ' + expresion + ';').splitlines()[-1])

    def preflight(self, nombre):
        return self.rpc(f"public.m08_local_preflight('{self.identidades[nombre]}','{self.sesiones[nombre]}')")

    def pasa(self, nombre):
        self.aprobadas += 1
        print(f'OK {self.aprobadas}: {nombre}', flush=True)

    def fixture(self):
        self.sql('''
CREATE ROLE m08_owner NOLOGIN BYPASSRLS;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;
GRANT CREATE ON DATABASE postgres TO m08_owner;
GRANT USAGE, CREATE ON SCHEMA public TO m08_owner;
CREATE SCHEMA auth AUTHORIZATION m08_owner;
CREATE SCHEMA storage AUTHORIZATION m08_owner;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
SET ROLE m08_owner;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
$$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS
$$ SELECT nullif(current_setting('request.jwt.claim.role',true),'') $$;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE TABLE auth.sessions(id uuid PRIMARY KEY, user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(), not_after timestamptz, factor_id uuid);
CREATE TABLE public.perfil(id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  estado_cuenta text NOT NULL);
CREATE TABLE public.hogar(id uuid PRIMARY KEY, creado_por uuid REFERENCES public.perfil(id),
  updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.hogar_miembro(hogar_id uuid REFERENCES public.hogar(id) ON DELETE CASCADE, perfil_id uuid REFERENCES public.perfil(id) ON DELETE CASCADE,
  rol text NOT NULL, estado text NOT NULL, PRIMARY KEY(hogar_id,perfil_id));
CREATE UNIQUE INDEX uq_fixture_hogar_activo ON public.hogar_miembro(perfil_id) WHERE estado = 'ACTIVO';
CREATE TABLE public.rol(id integer PRIMARY KEY, codigo text);
CREATE TABLE public.perfil_rol(perfil_id uuid REFERENCES public.perfil(id) ON DELETE CASCADE,rol_id integer REFERENCES public.rol(id));
CREATE TABLE storage.objects(owner_id text, bucket_id text, name text);
CREATE TABLE public.solicitud_soporte(solicitado_por uuid REFERENCES public.perfil(id) ON DELETE CASCADE);
CREATE TABLE public.auditoria(perfil_id uuid REFERENCES public.perfil(id) ON DELETE SET NULL,
  entidad_id text, antes jsonb, despues jsonb);
ALTER TABLE public.perfil ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hogar ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hogar_miembro ENABLE ROW LEVEL SECURITY;
CREATE FUNCTION public.m16_gestionar_miembro(p_hogar_id uuid,p_accion text,p_perfil_id uuid DEFAULT NULL::uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS
$$ BEGIN RAISE EXCEPTION 'Fixture: definicion por reemplazar'; END $$;
REVOKE ALL ON FUNCTION public.m16_gestionar_miembro(uuid,text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.m16_gestionar_miembro(uuid,text,uuid) TO authenticated;
''')
        for n in self.sesiones:
            estado = {'d':'DESACTIVADA','e':'SUSPENDIDA','f':'BANEADA'}.get(n, 'ACTIVA')
            self.sql(f"INSERT INTO auth.users VALUES('{self.identidades[n]}'); "
                f"INSERT INTO public.perfil VALUES('{self.identidades[n]}','{estado}'); "
                f"INSERT INTO auth.sessions(id,user_id) VALUES('{self.sesiones[n]}','{self.identidades[n]}');")
        self.sql(f"INSERT INTO public.hogar(id,creado_por) VALUES('{self.identidades['h']}','{self.identidades['a']}');")
        for n in ['a','b','c','d','e','f','historico']:
            rol = 'MIEMBRO' if n in ['c','historico'] else 'ADMIN'
            estado = 'REMOVIDO' if n == 'historico' else 'ACTIVO'
            self.sql(f"INSERT INTO public.hogar_miembro VALUES('{self.identidades['h']}','{self.identidades[n]}','{rol}','{estado}');")
        meta = "SELECT oid,proowner,proacl,prosecdef,proconfig FROM pg_proc WHERE oid='public.m16_gestionar_miembro(uuid,text,uuid)'::regprocedure;"
        antes = self.sql(meta)
        for nombre in ['001_m08_simulacion.sql','002_m16_destino_activo.sql']:
            self.sql('SET ROLE m08_owner;\n' + (ROOT/'proposals'/nombre).read_text(encoding='utf-8-sig'))
            self.pasa('instalacion y compilacion PostgreSQL ' + nombre)
        assert antes == self.sql(meta), 'Cambio de propietario, OID, ACL o atributos de M16'
        self.pasa('M16 preserva propietario, OID, ACL, SECURITY DEFINER y search_path')

    def validar(self):
        h, a, b, c = [self.identidades[n] for n in ['h','a','b','c']]
        for n in ['d','e','f']:
            for accion in ['PROMOVER','TRANSFERIR','ABANDONAR','REMOVER','DEGRADAR']:
                self.sql(self.claims(self.identidades[n]) + f'''
DO $$ BEGIN
  BEGIN
    PERFORM public.m16_gestionar_miembro('{h}','{accion}','{c}');
    RAISE EXCEPTION USING ERRCODE='P9000', MESSAGE='Se acepto solicitante restringido';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'M16_SOLICITANTE_NO_ACTIVO: el solicitante debe tener una cuenta ACTIVA' THEN RAISE; END IF;
  END;
END $$;''')
                self.pasa(f'M16 solicitante {n}: rechazo {accion} P0001')
            for accion in ['PROMOVER','TRANSFERIR']:
                self.sql(self.claims(a) + f'''
DO $$ BEGIN
  BEGIN
    PERFORM public.m16_gestionar_miembro('{h}','{accion}','{self.identidades[n]}');
    RAISE EXCEPTION USING ERRCODE='P9000', MESSAGE='Se acepto destinatario restringido';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'M16_DESTINO_NO_ACTIVO: el destinatario debe tener una cuenta ACTIVA' THEN RAISE; END IF;
  END;
END $$;''')
                self.pasa(f'M16 destinatario {n}: rechazo {accion} P0001')
        for accion, destino, condicion in [
            ('PROMOVER', c, f"(SELECT rol='ADMIN' FROM public.hogar_miembro WHERE hogar_id='{h}' AND perfil_id='{c}')"),
            ('DEGRADAR', b, f"(SELECT rol='MIEMBRO' AND estado='ACTIVO' FROM public.hogar_miembro WHERE hogar_id='{h}' AND perfil_id='{b}')"),
            ('REMOVER', c, f"(SELECT estado='REMOVIDO' FROM public.hogar_miembro WHERE hogar_id='{h}' AND perfil_id='{c}')"),
            ('TRANSFERIR', b, f"(SELECT creado_por='{b}'::uuid FROM public.hogar WHERE id='{h}') AND (SELECT rol='MIEMBRO' FROM public.hogar_miembro WHERE hogar_id='{h}' AND perfil_id='{a}')"),
        ]:
            self.sql('BEGIN;'+self.claims(a)+f"SELECT public.m16_gestionar_miembro('{h}','{accion}','{destino}'); RESET ROLE; DO $$BEGIN IF NOT ({condicion}) THEN RAISE EXCEPTION 'Regresion'; END IF; END$$; ROLLBACK;")
            self.pasa('M16 regresion ' + accion)
        self.sql('BEGIN;'+self.claims(c)+f"SELECT public.m16_gestionar_miembro('{h}','ABANDONAR',NULL); RESET ROLE; DO $$BEGIN IF NOT (SELECT estado='REMOVIDO' FROM public.hogar_miembro WHERE hogar_id='{h}' AND perfil_id='{c}') THEN RAISE EXCEPTION 'ABANDONAR'; END IF; END$$; ROLLBACK;")
        self.pasa('M16 regresion ABANDONAR de MIEMBRO')
        for n, codigo in [('g',None),('historico',None),('a','CREADOR_HOGAR'),('c','MEMBRESIA_ACTIVA'),('d','CUENTA_NO_ACTIVA')]:
            revision = self.preflight(n)
            if codigo is None:
                assert revision['apto'] is True, revision
            else:
                assert codigo in [v['codigo'] for v in revision['bloqueos']], revision
            self.pasa(f'preflight real SQL {n}: {codigo or "apto"}')
        solicitud, duena, recibo = str(uuid.uuid4()), 'ab'*32, 'cd'*32
        reservar = f"public.m08_local_reservar('{solicitud}','{duena}','{recibo}')"
        assert self.rpc(reservar)['nueva'] is True
        assert self.rpc(reservar)['nueva'] is False
        self.pasa('reserva SQL idempotente por mismo recibo')
        otra = self.rpc(f"public.m08_local_reservar('{uuid.uuid4()}','{duena}','{'ef'*32}')")
        assert otra['codigo'] == 'OTRA_SOLICITUD_EN_CURSO'
        self.pasa('reserva SQL impide otra solicitud del mismo propietario')
        self.rpc(f"public.m08_local_finalizar('{solicitud}','{duena}','SIMULADA','BORRADO_DESHABILITADO')")
        assert self.rpc(f"public.m08_local_estado('{solicitud}','{recibo}')")['estado']=='SIMULADA'
        assert self.rpc(f"public.m08_local_estado('{solicitud}','{'00'*32}')")['estado']=='NO_DISPONIBLE'
        self.pasa('recuperacion SQL tras respuesta perdida y rechazo de recibo ajeno')
        for rol in ['anon','authenticated']:
            salida = self.sql(f"SELECT has_function_privilege('{rol}','public.m08_local_reservar(uuid,text,text)','EXECUTE');")
            assert salida=='f'
            self.sql(self.claims(a, rol)+'''
DO $$ BEGIN
  BEGIN
    PERFORM public.m08_local_estado(gen_random_uuid(),repeat('0',64));
    RAISE EXCEPTION USING ERRCODE='P9000', MESSAGE='RPC expuesta';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM count(*) FROM nfc_m08_local.solicitud;
    RAISE EXCEPTION USING ERRCODE='P9000', MESSAGE='Tabla expuesta';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;''')
            self.pasa(f'permisos reales: {rol} sin RPC ni lectura directa del registro')
        self.pasa('RPC reales ejecutadas como service_role con RLS FORCE y propietario BYPASSRLS')

    def esperar_bloqueo(self, pid):
        limite = time.monotonic()+3
        while time.monotonic()<limite:
            if self.sql(f"SELECT wait_event_type FROM pg_stat_activity WHERE pid={pid};")=='Lock':
                return
            time.sleep(0.03)
        raise AssertionError('No se observo la espera esperada en PostgreSQL')

    def concurrencia(self):
        h,a,b,c = [self.identidades[n] for n in ['h','a','b','c']]
        for accion in ['PROMOVER','TRANSFERIR']:
            x,y = Sesion(self),Sesion(self)
            try:
                x.sql(f"BEGIN; SELECT id FROM public.perfil WHERE id='{b}' FOR UPDATE;")
                y.sql(f"BEGIN; SELECT id FROM public.hogar WHERE id='{h}' FOR UPDATE;" + self.claims(a))
                espera = x.enviar(f"SELECT id FROM public.hogar WHERE id='{h}' FOR UPDATE;")
                self.esperar_bloqueo(x.pid)
                respuesta = y.sql(f"SELECT public.m16_gestionar_miembro('{h}','{accion}','{b}');")
                assert '55P03' in respuesta and 'destinatario' in respuesta and '40P01' not in respuesta, respuesta
                y.sql('ROLLBACK;')
                assert 'ERROR' not in x.esperar(espera)
                x.sql('ROLLBACK;')
                self.pasa(f'concurrencia patron M08/M16: {accion} falla 55P03, sin ciclo')
            finally:
                x.cerrar(); y.cerrar()
        x,y = Sesion(self),Sesion(self)
        try:
            x.sql(f"BEGIN; SELECT id FROM public.perfil WHERE id='{a}' FOR UPDATE;")
            y.sql('BEGIN;'+self.claims(a))
            respuesta=y.sql(f"SELECT public.m16_gestionar_miembro('{h}','PROMOVER','{c}');")
            assert '55P03' in respuesta and 'solicitante' in respuesta, respuesta
            y.sql('ROLLBACK;'); x.sql('ROLLBACK;')
            self.pasa('concurrencia perfil del solicitante: 55P03 diferente de cuenta inactiva')
            y.sql('BEGIN;'+self.claims(a))
            respuesta=y.sql(f"SELECT public.m16_gestionar_miembro('{h}','TRANSFERIR','{b}');")
            assert 'ERROR' not in respuesta, respuesta
            for perfil in [a,b]:
                espera=x.enviar(f"BEGIN; SELECT id FROM public.perfil WHERE id='{perfil}' FOR UPDATE;")
                self.esperar_bloqueo(x.pid)
                y.sql('ROLLBACK;')
                assert 'ERROR' not in x.esperar(espera)
                x.sql('ROLLBACK;')
                if perfil==a:
                    y.sql('BEGIN;'+self.claims(a))
                    assert 'ERROR' not in y.sql(f"SELECT public.m16_gestionar_miembro('{h}','TRANSFERIR','{b}');")
            self.pasa('M16 retiene FOR SHARE de solicitante y destinatario hasta finalizar transaccion')
        finally:
            x.cerrar(); y.cerrar()


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--pg-bin', default='C:/Program Files/PostgreSQL/15/bin')
    args=parser.parse_args()
    banco=Banco(args.pg_bin)
    try:
        banco.iniciar()
        banco.fixture()
        banco.validar()
        banco.concurrencia()
        print(f'RESULTADO: {banco.aprobadas} comprobaciones aprobadas; cero eliminaciones de cuentas/hogares.', flush=True)
    finally:
        banco.detener()
