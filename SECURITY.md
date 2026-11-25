# Política de seguridad de NFC-FoodTech

Versión 1.0 · 25 de noviembre de 2026 · Capstone PTY4614 · Proyecto APT

Este documento describe la postura de seguridad verificable de NFC-FoodTech al cierre de la Fase 2. Los datos citados provienen del catálogo de PostgreSQL capturado el 13 de noviembre de 2026, del DDL validado con pglast v8.8 y del código de la aplicación y del portal administrativo.

## Versiones soportadas

| Versión | Estado |
| --- | --- |
| Fase 2, v1.0 (noviembre de 2026) | Soportada |
| Versiones anteriores a la Fase 2 | Sin soporte |

## Controles implementados

- **Autenticación.** Supabase Auth con correo y contraseña, proveedor Google y verificación de correo. El portal administrativo exige un segundo factor TOTP antes de permitir el ingreso.
- **Aislamiento de datos.** Row Level Security activo en las 25 tablas del esquema `public`, con 89 políticas verificadas en el catálogo del motor. El acceso a los datos del hogar se resuelve dentro de la base de datos, no en el cliente.
- **Operaciones administrativas.** Las acciones sensibles pasan por funciones que validan rol y segundo factor antes de actuar. Un trigger impide que un usuario cambie por sí mismo su propio estado de cuenta, de modo que una cuenta suspendida no pueda reactivarse sola.
- **Bitácora.** La tabla `auditoria` registra nueve acciones: INSERT, UPDATE, DELETE, APROBAR, RECHAZAR, SUSPENDER, REACTIVAR, CUENTA_DESACTIVADA y CUENTA_REACTIVADA, con motivo, perfil responsable y snapshot antes/después.
- **Ciclo de vida de la cuenta.** La baja de cuenta usa un token de confirmación de un solo uso (tabla `m08_confirmacion_eliminacion`) y elimina los datos locales en el dispositivo.
- **Secretos.** El cliente solo recibe la clave publicable. La URL y la clave se pasan por `--dart-define` o por variables de entorno; `PanelAdministracion/.env.example` contiene solo la plantilla sin valores reales. Ninguna clave `service_role` aparece en el repositorio.
- **Transporte.** Todas las comunicaciones con Supabase se hacen por HTTPS.
- **Datos personales.** El RUT se guarda únicamente en `perfil_identificacion` para identificación y deduplicación, con validación de dígito verificador. La edad se calcula desde `perfil.fecha_nacimiento`; el RUT no interviene en ese cálculo ni en los indicadores.
- **Integración continua.** El flujo `.github/workflows/ci.yml` ejecuta análisis estático y pruebas de la app y del portal en cada cambio sobre `main`.

## Brechas conocidas

- No se realizó una prueba de penetración ni una revisión de seguridad por un tercero.
- La disponibilidad, la latencia y el consumo de recursos no están medidos.
- La política de respaldos y la restauración dependen del proyecto administrado; no hay configuración propia de retención en el repositorio.
- No hay agregación de logs de aplicación fuera de la bitácora de auditoría de la base de datos.
- El diseño responsivo y los temas están verificados, pero no hay una auditoría formal de accesibilidad.

## Cómo reportar una vulnerabilidad

Use la opción **Report a vulnerability** de la pestaña *Security* del repositorio `https://github.com/SamuelAcuna/NFC-FoodTech`. No abra un issue público con detalles del hallazgo. Incluya componente afectado, pasos para reproducirlo, impacto estimado y versión del repositorio. El equipo confirma la recepción y coordina la corrección antes de divulgar el caso.

## Alcance

Esta política cubre el repositorio grupal, la aplicación Flutter/Android, el panel Flutter Web, las migraciones SQL y los archivos de evidencia de la Fase 2. No cubre servicios de terceros ni el proyecto de Supabase fuera de la configuración documentada aquí.
