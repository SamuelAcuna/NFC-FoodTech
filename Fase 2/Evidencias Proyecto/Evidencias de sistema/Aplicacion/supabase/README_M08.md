# Preparación local M08

Esta carpeta contiene propuestas sin desplegar. No sustituye las dos funciones
de prueba existentes ni usa su UUID o `M08_TEST_USER_ID`.

## Capacidad y límites

- `functions/m08-preflight-cuenta-local`: identifica al solicitante consultando
  Auth con su Bearer y ejecuta `m08_local_preflight` solo desde el servidor.
- `functions/m08-confirmar-cuenta-local`: admite `SIMULAR` y `ESTADO`.
  No contiene llamadas de borrado de Auth, perfiles, hogares o Storage.
- `BORRADO_REAL_HABILITADO` es falso. Cambiar esa constante no agrega ninguna
  capacidad destructiva: tampoco hay un estado ELIMINADA en la propuesta SQL.
- No se modifica la lógica de desactivación/reactivación de `nfc_seguridad`.
- Los nombres `*-local` identifican una preparación separada, no un destino
  autorizado de producción. Ningún despliegue se realizó al preparar estos archivos.

## Identidad reforzada

Correo confirmado: el servidor vuelve a verificar la contraseña mediante Auth,
usando el correo obtenido de `getUser`, nunca uno suministrado por el cliente.
Si existe TOTP verificado, además exige un desafío y código nuevos en Auth.
La sesión efímera utilizada para esta verificación no se entrega a Flutter.
Se solicita su cierre con alcance local al terminar, incluso ante errores.
Si Auth no responde, esa limpieza no puede garantizarse; debe verificarse en staging.

Google: no exige vincular una identidad de correo. Requiere TOTP configurado antes
de iniciar la sesión actual, factor vinculado en `auth.sessions.factor_id` y JWT
AAL2 con AMR TOTP de hace como máximo cinco minutos. Los claims se usan después
de validar el token mediante Auth y comprobar la sesión en PostgreSQL.
Flutter reutiliza `M08VerificarMfaScreen` para actualizar su propia sesión.
Google sin ese mecanismo queda bloqueado. Configurar TOTP no basta: debe iniciarse
una nueva sesión después de configurarlo. Un factor recién agregado a una sesión
existente no habilita la confirmación de Google.

Debe verificarse en staging la disponibilidad de `factors.created_at`,
`auth.sessions.factor_id` y los AMR. Su ausencia bloquea el flujo; no se simula éxito.
La pérdida del autenticador y una alternativa OAuth de reautenticación reciente
quedan pendientes de diseño. `reauthenticate()` y su nonce de cambio de contraseña
no se usan como una autorización genérica de borrado.

## Preflight y datos

La propuesta bloquea creadores de hogares, membresías ACTIVO, administración sin
relevo activo, cuentas no ACTIVA, sesión inválida, archivos propios y referencias
directas NO ACTION/RESTRICT hacia Auth/perfil. El creador sin otro integrante
activo requiere un cierre de hogar separado que no está implementado.

REMOVIDO e INVITADO se informan sin bloquear por su mera existencia.
Las autorías SET NULL y los historiales compartidos no tienen que quedar vacíos.
Soporte solicitado por el usuario y auditoría relacionada se bloquean hasta
definir su conservación. La búsqueda de UUID en JSON no demuestra ausencia de
otra información personal: hay que revisar todos los triggers y referencias
transitivas antes de cualquier implementación destructiva.

No se modifica identificación. Los CASCADE vigentes eliminarían `perfil` y
`perfil_identificacion`; desaparecen las filas que hoy soportan sus índices UNIQUE.
La posibilidad de registrar otra cuenta con el mismo RUT sigue siendo una decisión
pendiente. Los índices independientes no resuelven unicidad cruzada entre tablas;
esta preparación no promete corregirla ni crea una lista de RUT eliminados.

## Solicitudes, fallos y privacidad

El cliente guarda un UUID de solicitud y un recibo aleatorio de 256 bits antes
de enviar. No guarda contraseñas, códigos MFA ni tokens en ese registro.
Ante timeout o respuesta incompatible solo permite consultar el mismo recibo.
Duplicar el UUID no vuelve a verificar credenciales ni crea otra solicitud.

La tabla propuesta no tiene FK a Auth. Guarda estado, código, fechas, hash del
recibo y HMAC del UUID existente, con separación de dominio y clave administrativa
del servidor. No guarda UUID personal en claro, correo, RUT, contraseña ni tokens.
El HMAC sigue siendo un dato seudónimo: requiere aprobar retención y acceso.
La rotación de la clave administrativa cambia el HMAC; debe planificarse antes
de un despliegue con solicitudes pendientes.

Propuesta de retención: recibo consultable durante 24 horas; solicitud RECIBIDA
sin finalizar expira a los 15 minutos. `m08_local_purgar` elimina solo registros
vencidos de esta tabla. No hay tarea de purga instalada: su programación y plazo
requieren autorización. Una fecha de vencimiento no elimina físicamente filas.

ESTADO permite recuperar únicamente estado/código con el recibo secreto,
incluso sin sesión Auth. Por ello la configuración local deshabilita el chequeo
JWT del gateway para estas dos funciones. Preflight y SIMULAR validan el Bearer
en el servidor; ESTADO valida el recibo. No es acceso anónimo a las RPC: estas
solo admiten `service_role`, tienen `search_path` vacío y permisos revocados
para PUBLIC/anon/authenticated. No registrar cuerpos, Authorization ni recibos.
Antes de exposición externa debe validarse limitación de solicitudes en gateway
y Auth, incluyendo consultas fallidas de recibos.

No existe una transacción conjunta entre Auth, Storage y PostgreSQL. Las propuestas
no implementan todavía un ejecutor destructivo, limpieza Storage, recuperación
de borrados parciales o una barrera transaccional contra nuevas dependencias.
La doble revisión es útil para simulación, pero no resuelve esas carreras.

## Flutter

La pantalla original reutiliza su diseño y expone únicamente preparación cuando
coinciden debug y `--dart-define=M08_PREPARACION_LOCAL=true`. Por defecto y en release
no hay acciones de confirmación habilitadas. La ruta móvil ya no invoca la función
histórica que tiene borrado real activado. Las funciones históricas desplegadas
no se modificaron.

El cliente descarta respuestas de una cuenta anterior y no instala sesiones
devueltas por el backend. Un resultado SIMULADA no cierra sesión ni anuncia borrado.
Los recibos se almacenan por cuenta en las preferencias locales privadas de la app;
solo permiten leer un estado mínimo y nunca autorizan una eliminación.

## Pruebas locales sin backend

Desde la raíz:

```
node --experimental-strip-types --test supabase/functions/tests/m08.test.mjs
flutter analyze --no-pub
flutter test --no-pub
```

Node usa transporte completamente simulado; prohíbe DELETE y rutas Auth Admin.
Las pruebas Dart usan almacenamiento y transporte en memoria. No prueban las
restricciones de PostgreSQL desplegado ni la autenticación real de Google.
No se requieren paquetes Node. Node 22.8 necesita el flag experimental para
ejecutar TypeScript; esta ejecución no equivale a `deno check`.

## Orden de validación futura, sujeto a autorización

1. Revisar DDL/triggers actuales y comparar políticas de soporte, auditoría,
   referencias transitivas, último administrador global y RUT. Aprobar retención.
2. En una copia aislada con datos sintéticos, revisar y ejecutar manualmente
   `proposals/001_m08_simulacion.sql`. No aplicarlo automáticamente a producción.
3. Revisar `002_m16_destino_activo.sql` frente a la definición desplegada. El script
   modifica solo PROMOVER/TRANSFERIR, exige destino ACTIVA y toma FOR SHARE sobre
   su perfil. Aborta si no reconoce exactamente los dos puntos de inserción.
   Comprobar además concurrencia con desactivación y posibles interbloqueos.
4. Ejecutar `003_verificaciones_lectura.sql`. Probar en staging permiso denegado
   a anon/authenticated, RLS, unicidad de solicitudes y permanencia del recibo
   después de eliminar una identidad sintética en una prueba separada autorizada.
5. Validar SQL con fixtures: sin hogar, MIEMBRO, ADMIN compartido, creador único,
   REMOVIDO, perfiles restringidos, destinatarios no ACTIVA, Storage y cada FK.
   No existen resultados de estas pruebas SQL en esta preparación.
6. Con autorización, ejecutar `deno check` y desplegar solo los dos nombres nuevos
   en staging. Usar configuración que permita recibos sin JWT y validación propia
   de sesión. No cambiar los secretos ni los endpoints de prueba anteriores.
7. Probar Auth real de correo/Google y TOTP, expiración, rotación de sesiones,
   respuestas perdidas, duplicados concurrentes y recuperación tras reiniciar app.
8. Compilar debug con la bandera local y probar Android contra staging. Verificar
   que release no muestre controles, que no se cierren sesiones nuevas y que nunca
   se invoque una eliminación. Autorizar y probar la purga con el plazo aprobado.
9. Diseñar y autorizar aparte el ejecutor real, barreras de concurrencia, tratamiento
   de Storage y recuperación parcial. Implementar y probarlo antes de considerar
   producción. No basta cambiar una bandera ni retirar restricciones del cliente.

La recuperación móvil después de un borrado real necesitará además una entrada
sin sesión para consultar el recibo. Esta preparación conserva el recibo por
cuenta y no cambia Inicio, main ni Home para agregar esa navegación todavía.
