"""Genera documentación DDL desde las lecturas JSON del catálogo; no conecta a BD."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
C = json.loads((ROOT / 'catalogo_completo.json').read_text(encoding='utf-8'))
E = json.loads((ROOT / 'catalogo_extras.json').read_text(encoding='utf-8'))

def ident(value):
    return '"' + value.replace('"', '""') + '"'

def literal(value):
    return "'" + value.replace("'", "''") + "'"

def qualified(schema, name):
    return ident(schema) + '.' + ident(name)

sql = [
    '-- NFC-FoodTech: volcado del esquema (sin datos).',
    '-- Proyecto: dpsbrniclxojsoxhgmjv; captura: ' + C['capturado'],
    '-- Origen: consultas SELECT al catálogo PostgreSQL mediante MCP Supabase.',
    '-- Esquemas: public y nfc_m28_privado. No se ejecutó este DDL en producción.',
    '-- Documento para el Diccionario de datos; no es una migración del panel.',
    '-- Requiere PostgreSQL 17 y los esquemas/roles administrados de Supabase',
    '-- (auth, extensions, vault y otros objetos de extensiones no se vuelcan).',
    '-- No contiene filas, valores actuales de secuencias ni claves.',
    'SET standard_conforming_strings = on;',
    'SET search_path = public, pg_catalog;',
    'SET check_function_bodies = false;',
]

def emit(statement):
    sql.append(statement)

def comment(kind, target, text):
    if text is not None:
        emit('COMMENT ON ' + kind + ' ' + target + ' IS ' + literal(text) + ';')

for s in C['esquemas']:
    emit('CREATE SCHEMA IF NOT EXISTS ' + ident(s['nombre']) + ';')
    comment('SCHEMA', ident(s['nombre']), s['comentario'])

emit('\n-- Extensiones instaladas; sus objetos internos quedan a cargo de CREATE EXTENSION.')
for e in C['extensiones']:
    emit('CREATE EXTENSION IF NOT EXISTS ' + ident(e['nombre']) + ' WITH SCHEMA '
         + ident(e['esquema']) + ' VERSION ' + literal(e['version']) + ';')

# En esta captura no hay enums, dominios ni vistas propios en los dos esquemas.
assert not E['tipos'] and not E['vistas'], 'Revisar tipos/vistas antes de generar.'

sequences = C['secuencias'] or []
for s in sequences:
    if not s['identity']:
        emit('CREATE SEQUENCE ' + qualified(s['esquema'], s['nombre'])
             + ' AS ' + s['tipo'] + ' START WITH ' + str(s['inicio'])
             + ' INCREMENT BY ' + str(s['incremento']) + ' MINVALUE ' + str(s['minimo'])
             + ' MAXVALUE ' + str(s['maximo']) + ' CACHE ' + str(s['cache'])
             + (' CYCLE;' if s['ciclo'] else ' NO CYCLE;'))

tables = sorted(C['tablas'], key=lambda t: (t['esquema'], t['nombre']))
for t in tables:
    table = qualified(t['esquema'], t['nombre'])
    columns = []
    for a in t['columnas']:
        line = '  ' + ident(a['nombre']) + ' ' + a['tipo']
        if a['identity']:
            seq = next(s for s in sequences if s['identity']
                       and s['tabla'] == t['esquema'] + '.' + t['nombre']
                       and s['columna'] == a['nombre'])
            line += ' GENERATED ' + ('ALWAYS' if a['identity'] == 'a' else 'BY DEFAULT')
            line += ' AS IDENTITY (SEQUENCE NAME ' + qualified(seq['esquema'], seq['nombre'])
            line += ' START WITH ' + str(seq['inicio']) + ' INCREMENT BY ' + str(seq['incremento'])
            line += ' MINVALUE ' + str(seq['minimo']) + ' MAXVALUE ' + str(seq['maximo'])
            line += ' CACHE ' + str(seq['cache']) + (' CYCLE)' if seq['ciclo'] else ' NO CYCLE)')
        elif a['generated']:
            line += ' GENERATED ALWAYS AS (' + a['default'] + ') STORED'
        elif a['default'] is not None:
            line += ' DEFAULT ' + a['default']
        if not a['nulo']:
            line += ' NOT NULL'
        columns.append(line)
    emit('\nCREATE TABLE ' + table + ' (\n' + ',\n'.join(columns) + '\n);')
    comment('TABLE', table, t['comentario'])
    for a in t['columnas']:
        comment('COLUMN', table + '.' + ident(a['nombre']), a['comentario'])

# Los cuerpos se conservan literalmente desde pg_get_functiondef. Desactivar la
# validación de cuerpos permite referencias cruzadas sin ejecutar las funciones.
emit('\n-- Funciones propias (excluye dependencias de extensiones).')
for f in sorted(C['funciones'], key=lambda f: (f['esquema'], f['nombre'], f['firma'])):
    emit(f['definicion'].rstrip().rstrip(';') + ';')
    kind = 'PROCEDURE' if f['definicion'].startswith('CREATE OR REPLACE PROCEDURE') else 'FUNCTION'
    comment(kind, qualified(f['esquema'], f['nombre']) + '(' + f['firma'] + ')', f['comentario'])

emit('\n-- Restricciones locales; las FK se emiten al final del documento.')
for t in tables:
    table = qualified(t['esquema'], t['nombre'])
    for c in sorted(t['constraints'] or [], key=lambda c: c['nombre']):
        if c['tipo'] == 'f':
            continue
        emit('ALTER TABLE ' + table + ' ADD CONSTRAINT ' + ident(c['nombre']) + ' ' + c['definicion'] + ';')
        comment('CONSTRAINT', ident(c['nombre']) + ' ON ' + table, c['comentario'])
    for i in sorted(t['indices'] or [], key=lambda i: i['nombre']):
        if not i['constraint']:
            emit(i['definicion'].rstrip(';') + ';')
        comment('INDEX', qualified(t['esquema'], i['nombre']), i['comentario'])
    if t['rls']:
        emit('ALTER TABLE ' + table + ' ENABLE ROW LEVEL SECURITY;')
    if t['force_rls']:
        emit('ALTER TABLE ' + table + ' FORCE ROW LEVEL SECURITY;')
    for tr in t['triggers'] or []:
        emit(tr['definicion'].rstrip(';') + ';')
        state = {'D': 'DISABLE', 'R': 'ENABLE REPLICA', 'A': 'ENABLE ALWAYS'}
        if tr['habilitado'] in state:
            emit('ALTER TABLE ' + table + ' ' + state[tr['habilitado']] + ' TRIGGER ' + ident(tr['nombre']) + ';')
        comment('TRIGGER', ident(tr['nombre']) + ' ON ' + table, tr['comentario'])

emit('\n-- Políticas RLS: copia exacta de pg_policies, sin cambios de permisos.')
for p in sorted(C['politicas'], key=lambda p: (p['schemaname'], p['tablename'], p['policyname'])):
    line = 'CREATE POLICY ' + ident(p['policyname']) + ' ON ' + qualified(p['schemaname'], p['tablename'])
    line += ' AS ' + p['permissive'] + ' FOR ' + p['cmd']
    line += ' TO ' + ', '.join('PUBLIC' if r == 'public' else ident(r) for r in p['roles'])
    if p['qual'] is not None:
        line += ' USING (' + p['qual'] + ')'
    if p['with_check'] is not None:
        line += ' WITH CHECK (' + p['with_check'] + ')'
    emit(line + ';')

emit('\n-- Propietarios y ACL existentes, incluidos los permisos de funciones privilegiadas.')
privileges = {'r': 'SELECT', 'a': 'INSERT', 'w': 'UPDATE', 'd': 'DELETE',
              'D': 'TRUNCATE', 'x': 'REFERENCES', 't': 'TRIGGER', 'X': 'EXECUTE',
              'U': 'USAGE', 'C': 'CREATE', 'm': 'MAINTAIN'}

def acl_statements(kind, target, entries, owner, prefix=''):
    if entries is None:
        return
    # Objetos recién creados no tienen grants ajenos; se restablece PUBLIC antes
    # de copiar los ACL explícitos. Nunca se ejecuta contra la base de origen.
    emit(prefix + 'REVOKE ALL ON ' + kind + ' ' + target + ' FROM PUBLIC;')
    for entry in entries:
        role, rest = entry.split('=', 1)
        perms = rest.rsplit('/', 1)[0]
        grantee = ident(role.strip('"')) if role else 'PUBLIC'
        normal, grantable = [], []
        for i, code in enumerate(perms):
            if code == '*':
                continue
            name = privileges[code]
            (grantable if i + 1 < len(perms) and perms[i+1] == '*' else normal).append(name)
        if normal:
            emit(prefix + 'GRANT ' + ', '.join(normal) + ' ON ' + kind + ' ' + target + ' TO ' + grantee + ';')
        if grantable:
            emit(prefix + 'GRANT ' + ', '.join(grantable) + ' ON ' + kind + ' ' + target + ' TO ' + grantee + ' WITH GRANT OPTION;')

for s in E['acl_esquemas'] or []:
    target = ident(s['nombre'])
    emit('ALTER SCHEMA ' + target + ' OWNER TO ' + ident(s['propietario']) + ';')
    acl_statements('SCHEMA', target, s['acl'], s['propietario'])
seq_names = {(s['esquema'], s['nombre']) for s in sequences}
for a in E['acl_relaciones'] or []:
    kind = 'SEQUENCE' if (a['esquema'], a['nombre']) in seq_names else 'TABLE'
    target = qualified(a['esquema'], a['nombre'])
    # Las secuencias identity pertenecen al dueño de su tabla automáticamente.
    if kind != 'SEQUENCE':
        emit('ALTER ' + kind + ' ' + target + ' OWNER TO ' + ident(a['propietario']) + ';')
    acl_statements(kind, target, a['acl'], a['propietario'])
for f in E['acl_funciones'] or []:
    target = qualified(f['esquema'], f['nombre']) + '(' + f['firma'] + ')'
    emit('ALTER FUNCTION ' + target + ' OWNER TO ' + ident(f['propietario']) + ';')
    acl_statements('FUNCTION', target, f['acl'], f['propietario'])
for a in E['privilegios_por_defecto'] or []:
    kind = {'r':'TABLES', 'S':'SEQUENCES', 'f':'FUNCTIONS', 'T':'TYPES'}[a['tipo']]
    prefix = 'ALTER DEFAULT PRIVILEGES FOR ROLE ' + ident(a['rol']) + ' IN SCHEMA ' + ident(a['esquema']) + ' '
    # La sintaxis de DEFAULT PRIVILEGES usa ON TABLES, sin nombre de objeto.
    before = len(sql)
    acl_statements(kind, '', a['acl'], a['rol'], prefix)
    sql[before:] = [line.replace(kind + '  ', kind + ' ') for line in sql[before:]]

emit('\n-- Claves foráneas (después de tablas, claves únicas y funciones).')
for t in tables:
    table = qualified(t['esquema'], t['nombre'])
    for c in sorted(t['constraints'] or [], key=lambda c: c['nombre']):
        if c['tipo'] == 'f':
            emit('ALTER TABLE ' + table + ' ADD CONSTRAINT ' + ident(c['nombre']) + ' ' + c['definicion'] + ';')
            comment('CONSTRAINT', ident(c['nombre']) + ' ON ' + table, c['comentario'])

emit('\n-- cron.job (metadatos; NO se programa ni ejecuta el job).')
emit('-- jobid=1; jobname=nfc-m28-alertas-caducidad-v1; database=postgres; active=true')
emit('-- schedule: */15 * * * *')
emit('-- command: SELECT * FROM nfc_m28_privado.procesar_alertas_programadas();')

(ROOT / 'NFC-FoodTech_DDL_esquema_public.sql').write_text(
    ('\n\n'.join(sql) + '\n').replace('\r\n', '\n'), encoding='utf-8', newline='\n')
(ROOT / 'catalogo_tablas.json').write_text(json.dumps({
    'proyecto': 'dpsbrniclxojsoxhgmjv', 'capturado': C['capturado'],
    'origen': 'pg_catalog; sin filas de tablas de negocio', 'tablas': tables,
}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('Generado DDL y catálogo de', len(tables), 'tablas.')
