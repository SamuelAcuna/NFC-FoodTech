import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {crearM08, autenticacion, BORRADO_REAL_HABILITADO} from '../_shared/m08.ts';

const usuarioId = '10000000-0000-4000-8000-000000000001';
const sesionId = '20000000-0000-4000-8000-000000000001';
const solicitudId = '30000000-0000-4000-8000-000000000001';
const factorId = '40000000-0000-4000-8000-000000000001';
const token = `e30.${btoa(JSON.stringify({session_id: sesionId, aal:'aal2', amr:[{method:'totp',timestamp:Math.floor(Date.now()/1000)}]}))}.firma-simulada`;
const recibo = 'ab'.repeat(32);
const json = (datos, status = 200) => new Response(JSON.stringify(datos), {status, headers: {'Content-Type':'application/json'}});
function escenario({google = false, totp = false, bloqueos = [], estadoCuenta = 'ACTIVA'} = {}) {
  const usuario = {id: usuarioId, email: 'titular@example.invalid', email_confirmed_at: '2026-01-01',
    identities: [{provider: google ? 'google' : 'email'}],
    factors: totp ? [{id:factorId, factor_type:'totp', status:'verified', created_at:'2026-01-01'}] : []};
  const revision = {apto: bloqueos.length === 0 && estadoCuenta === 'ACTIVA',
    bloqueos: [...bloqueos, ...(estadoCuenta === 'ACTIVA' ? [] : [{codigo:'CUENTA_NO_ACTIVA',mensaje:'Cuenta no activa'}])],
    resumen: {estado_cuenta:estadoCuenta, membresias_removidas:0}, consecuencias:[], sesion_creada:'2026-02-01', sesion_factor:totp ? factorId : null};
  const ledger = new Map();
  const llamadas = [];
  let falla;
  let pierdeFinal = false;
  let cambiaRevision = false;
  let revisiones = 0;
  let tokenEnviado = token;
  const manejar = crearM08({url:'https://m08.example.invalid',publica:'publica-simulada',administrativa:'administrativa-simulada'}, async (url, opciones) => {
    const ruta = new URL(url).pathname;
    assert.equal(new URL(url).host, 'm08.example.invalid');
    assert.notEqual(opciones.method, 'DELETE');
    assert.ok(!ruta.includes('/admin/'));
    const datos = opciones.body ? JSON.parse(opciones.body) : null;
    llamadas.push({ruta, datos});
    if (ruta === falla) throw new DOMException('Timeout simulado','TimeoutError');
    if (ruta === '/auth/v1/user') return json(usuario);
    if (ruta === '/auth/v1/logout') return new Response(null,{status:204});
    if (ruta === '/auth/v1/token') return json({user:usuario, access_token:'sesion-efimera'});
    if (ruta.endsWith('/challenge')) return json({id: sesionId});
    if (ruta.endsWith('/verify')) return json({access_token:'sesion-mfa-verificada'});
    if (ruta.endsWith('m08_local_preflight')) {
      assert.equal(datos.p_usuario,usuarioId);
      assert.equal(datos.p_sesion,sesionId);
      revisiones++;
      return json(cambiaRevision && revisiones > 1 ? {...revision, apto:false, bloqueos:[{codigo:'MEMBRESIA_ACTIVA',mensaje:'Cambio concurrente'}]} : revision);
    }
    if (ruta.endsWith('m08_local_reservar')) {
      const previa = ledger.get(datos.p_solicitud);
      if (previa) return json({nueva:false, estado:previa.estado, codigo:previa.codigo});
      ledger.set(datos.p_solicitud,{...datos,estado:'RECIBIDA',codigo:'VERIFICANDO'});
      return json({nueva:true,estado:'RECIBIDA',codigo:'VERIFICANDO'});
    }
    if (ruta.endsWith('m08_local_finalizar')) {
      const fila = ledger.get(datos.p_solicitud);
      fila.estado = datos.p_estado; fila.codigo = datos.p_codigo;
      if (pierdeFinal) throw new DOMException('Respuesta perdida','TimeoutError');
      return json({estado:fila.estado,codigo:fila.codigo});
    }
    if (ruta.endsWith('m08_local_estado')) {
      const fila = ledger.get(datos.p_solicitud);
      return json(fila && fila.p_recibo_hash === datos.p_recibo_hash ? {estado:fila.estado,codigo:fila.codigo} : {estado:'NO_DISPONIBLE'});
    }
    throw new Error(`Ruta no simulada: ${ruta}`);
  });
  const llamar = async (modo, datos = {}, autorizado = true) => manejar(new Request('https://local.invalid', {
    method:'POST',headers: autorizado ? {Authorization:`Bearer ${tokenEnviado}`} : {},body:JSON.stringify(datos)
  }), modo);
  return {usuario,revision,ledger,llamadas,llamar,
    fallar: ruta => {falla=ruta;}, perderFinal: () => {pierdeFinal=true;}, cambiar: () => {cambiaRevision=true;},
    token: valor => {tokenEnviado=valor;}};
}
const confirmacion = {accion:'SIMULAR',confirmacion:'ELIMINAR',solicitud:solicitudId,recibo,contrasena:'clave-simulada',codigo:'123456'};

test('correo sin hogar verifica contraseña real por contrato Auth; solo simula', async () => {
  const e=escenario(); const r=await e.llamar('confirmar',confirmacion);
  assert.equal(r.status,200); assert.equal((await r.json()).estado,'SIMULADA');
  assert.equal(e.llamadas.filter(c=>c.ruta==='/auth/v1/token').length,1);
  assert.equal(e.llamadas.filter(c=>c.ruta.endsWith('m08_local_preflight')).length,2);
  const fila=e.ledger.get(solicitudId);
  assert.match(fila.p_propietario_hash,/^[0-9a-f]{64}$/);
  assert.ok(!JSON.stringify(fila).includes(usuarioId));
  assert.ok(!JSON.stringify(fila).includes('clave-simulada'));
});
test('Google con TOTP reciente validado en JWT y vinculado a la sesión solo simula', async () => {
  const e=escenario({google:true,totp:true}); const r=await e.llamar('confirmar',confirmacion);
  assert.equal((await r.json()).estado,'SIMULADA');
  assert.equal(e.llamadas.filter(c=>c.ruta.endsWith('/verify')).length,0);
  assert.equal(e.llamadas.filter(c=>c.ruta==='/auth/v1/token').length,0);
});
test('Google sin TOTP no simula una reautenticación inexistente', async () => {
  const e=escenario({google:true}); const r=await e.llamar('confirmar',confirmacion);
  const datos=await r.json(); assert.equal(datos.estado,'BLOQUEADA');
  assert.ok(datos.bloqueos.some(b=>b.codigo==='REAUTENTICACION_PENDIENTE'));
});
test('factor creado durante la sesión no habilita Google; requiere nuevo acceso', () => {
  const e=escenario({google:true,totp:true});
  e.usuario.factors[0].created_at='2026-03-01';
  assert.equal(autenticacion(e.usuario,'2026-02-01').disponible,false);
});
test('Google con TOTP antiguo no confirma identidad reciente', async () => {
  const e=escenario({google:true,totp:true});
  e.token(`e30.${btoa(JSON.stringify({session_id:sesionId,aal:'aal2',amr:[{method:'totp',timestamp:Math.floor(Date.now()/1000)-301}]}))}.firma-simulada`);
  const datos=await (await e.llamar('confirmar',confirmacion)).json();
  assert.equal(datos.codigo,'TOTP_SESION_RECIENTE_REQUERIDO');
});
test('Google sin factor asociado a la sesión queda bloqueado', async () => {
  const e=escenario({google:true,totp:true}); e.revision.sesion_factor=null;
  assert.equal((await (await e.llamar('confirmar',confirmacion)).json()).estado,'BLOQUEADA');
});
for (const codigo of ['MEMBRESIA_ACTIVA','CREADOR_HOGAR','CREADOR_SIN_RELEVO','ADMIN_SIN_RELEVO','REFERENCIA_BLOQUEANTE','CONSERVACION_SOPORTE','STORAGE_PENDIENTE']) {
  test(`bloqueo PostgreSQL ${codigo} impide continuar con autenticación y simulación`, async () => {
    const e=escenario({bloqueos:[{codigo,mensaje:'Requisito pendiente'}]});
    const datos=await (await e.llamar('confirmar',confirmacion)).json();
    assert.equal(datos.estado,'BLOQUEADA'); assert.equal(datos.bloqueos[0].codigo,codigo);
    assert.ok(!e.llamadas.some(c=>c.ruta==='/auth/v1/token'));
  });
}
test('membresía REMOVIDO se informa sin convertirse en bloqueo activo', async () => {
  const e=escenario(); e.revision.resumen.membresias_removidas=1;
  const datos=await (await e.llamar('preflight')).json();
  assert.equal(datos.revision.apto,true); assert.equal(datos.revision.resumen.membresias_removidas,1);
});
for (const estadoCuenta of ['DESACTIVADA','SUSPENDIDA','BANEADA']) {
  test(`cuenta ${estadoCuenta} no continúa`, async () => {
    const e=escenario({estadoCuenta});
    assert.equal((await (await e.llamar('confirmar',confirmacion)).json()).estado,'BLOQUEADA');
  });
}
test('sin sesión o UUID objetivo enviado por cliente se rechaza', async () => {
  const e=escenario(); assert.equal((await e.llamar('preflight',{},false)).status,401);
  assert.equal((await e.llamar('confirmar',{...confirmacion,usuario_id:usuarioId})).status,400);
  assert.equal(e.llamadas.length,0);
});
test('duplicados concurrentes no repiten verificación ni operación', async () => {
  const e=escenario();
  const respuestas=await Promise.all([e.llamar('confirmar',confirmacion),e.llamar('confirmar',confirmacion)]);
  const datos=await Promise.all(respuestas.map(r=>r.json()));
  assert.equal(datos.filter(d=>d.duplicada===true).length,1);
  assert.equal(e.ledger.size,1); assert.equal(e.llamadas.filter(c=>c.ruta==='/auth/v1/token').length,1);
});
test('fallo de servidor se distingue de simulación completada', async () => {
  const e=escenario(); e.fallar('/rest/v1/rpc/m08_local_preflight');
  const r=await e.llamar('preflight'); assert.equal(r.status,503);
  assert.equal((await r.json()).codigo,'RESULTADO_DESCONOCIDO');
});
test('timeout después de reservar conserva estado recuperable; no repite', async () => {
  const e=escenario(); e.fallar('/auth/v1/token');
  assert.equal((await e.llamar('confirmar',confirmacion)).status,503);
  const datos=await (await e.llamar('confirmar',{accion:'ESTADO',solicitud:solicitudId,recibo},false)).json();
  assert.equal(datos.estado,'RECIBIDA');
});
test('respuesta perdida después de registrar SIMULADA se recupera con recibo', async () => {
  const e=escenario(); e.perderFinal();
  assert.equal((await e.llamar('confirmar',confirmacion)).status,503);
  const datos=await (await e.llamar('confirmar',{accion:'ESTADO',solicitud:solicitudId,recibo},false)).json();
  assert.equal(datos.estado,'SIMULADA');
  assert.equal((await e.llamar('confirmar',{accion:'ESTADO',solicitud:solicitudId,recibo:'cd'.repeat(32)},false)).status,404);
});
test('nueva revisión detecta dependencias aparecidas durante autenticación', async () => {
  const e=escenario(); e.cambiar();
  assert.equal((await (await e.llamar('confirmar',confirmacion)).json()).codigo,'REQUISITOS_CAMBIARON');
});
test('TOTP no puede omitirse por usar contraseña cuando ya existe factor', async () => {
  const e=escenario({totp:true});
  const datos=await (await e.llamar('confirmar',{...confirmacion,codigo:''})).json();
  assert.equal(datos.codigo,'TOTP_REQUERIDO');
});
test('fuentes nuevas no contienen capacidad de borrar Auth ni UUID de prueba', () => {
  assert.equal(BORRADO_REAL_HABILITADO,false);
  const fuente=readFileSync(new URL('../_shared/m08.ts',import.meta.url),'utf8');
  assert.ok(!fuente.includes('deleteUser')); assert.ok(!fuente.includes('M08_TEST_USER_ID'));
  const sql=readFileSync(new URL('../../proposals/001_m08_simulacion.sql',import.meta.url),'utf8');
  assert.ok(!/REFERENCES\s+auth\.users/i.test(sql));
  assert.ok(sql.includes('ENABLE ROW LEVEL SECURITY'));
  assert.ok(sql.includes('FROM PUBLIC, anon, authenticated'));
  const m16=readFileSync(new URL('../../proposals/002_m16_destino_activo.sql',import.meta.url),'utf8');
  assert.ok(m16.includes("p.estado_cuenta = 'ACTIVA'"));
  assert.ok(m16.includes("ARRAY['PROMOVER', 'TRANSFERIR']"));
  assert.ok(m16.includes('FOR SHARE'));
});
