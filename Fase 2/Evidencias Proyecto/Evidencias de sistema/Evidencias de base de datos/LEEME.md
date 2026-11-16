# Esquema de producción (volcado sin datos)

Captura por MCP Supabase del proyecto `dpsbrniclxojsoxhgmjv` el 13-11-2026. La hora exacta UTC está en `capturado` en los JSON y en el encabezado del SQL. Versión consultada: PostgreSQL 17.6.

Solo se ejecutaron SELECT de catálogo (`pg_catalog`, incluido `pg_policies`) y la lectura explícitamente solicitada de los metadatos de `cron.job`. No se leyeron filas de negocio ni se aplicaron cambios.

| Objeto | Cantidad |
|---|---:|
| Esquemas documentados | 2: public, nfc_m28_privado |
| Tablas / columnas | 25 / 187 |
| Constraints / FK | 123 / 42 |
| Índices, incluidos los asociados a constraints | 78 |
| Tablas con RLS habilitado | 25 |
| Políticas | 89 |
| Funciones propias | 65: 62 public y 3 nfc_m28_privado |
| Triggers de tabla no internos | 16 |
| Secuencias identity | 6 |
| Extensiones instaladas | 6 |
| Jobs cron documentados como comentario | 1 |

`NFC-FoodTech_DDL_esquema_public.sql` incluye también `nfc_m28_privado`, defaults, identity con opciones de secuencia, claves y restricciones, índices, políticas, cuerpos de funciones, triggers, comentarios disponibles, propietarios y ACL. Las FK se emiten al final. Las restricciones PK/UNIQUE crean sus propios índices; estos no se duplican como CREATE INDEX. Las funciones pertenecientes a extensiones se excluyen y sus extensiones se declaran con su versión instalada. No se encontraron enums, dominios ni vistas propios en los dos esquemas, ni comentarios adicionales en políticas o secuencias.

`catalogo_tablas.json` es la entrada para el Diccionario: por tabla conserva columnas con nombre, tipo, nulo, default, identity y comentario; constraints con definición e índices con definición. `catalogo_completo.json` y `catalogo_extras.json` preservan la extracción usada para generar el SQL. `consultas_catalogo.sql` permite revisar las consultas; `generar_ddl.py` transforma los JSON locales y no conecta a la base.

Validación: `../Evidencias de pruebas/ddl_validacion.txt` registra 948 sentencias aceptadas por pglast 8.8 y concordancia de conteos con el catálogo. El parser valida la sintaxis SQL externa; no ejecuta funciones ni verifica su comportamiento. No se ensayó una restauración. Este es un documento del esquema existente, no una migración del panel: requiere los roles, extensiones y esquemas administrados de Supabase, en particular `auth`, `extensions` y `vault`, que no se vuelcan aquí. Los objetos globales ajenos a los dos esquemas, las filas de datos y los valores actuales de secuencias no forman parte de esta entrega.

Referencias técnicas consultadas: [funciones de información de PostgreSQL 17](https://www.postgresql.org/docs/17/functions-info.html), [changelog de Supabase](https://supabase.com/changelog.md). No se cambió ninguna versión de Supabase ni se implementaron cambios de esquema.
