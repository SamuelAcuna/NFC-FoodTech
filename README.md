# NFC-FoodTech — Sistema de gestión de alimentos y prevención del desperdicio

**Capstone · Ingeniería en Informática · Duoc UC · 2026**

NFC-FoodTech ayuda a los hogares a saber qué alimentos tienen, cuánto queda de cada uno, cuándo vencen y qué deben comprar. El sistema registra consumos y descartes, calcula indicadores de aprovechamiento y pérdida económica, y sugiere reposiciones a partir del consumo real del hogar.

Este repositorio contiene:

- La **especificación y documentación** del proyecto (ERS, diccionario de datos y modelo relacional).
- La **aplicación móvil Flutter/Android** en `Fase 2/.../Evidencias de sistema/Aplicacion`.
- El **panel de administración Flutter Web** en `Fase 2/.../Evidencias de sistema/PanelAdministracion`.
- Las **evidencias académicas** de las Fases 1 y 2, organizadas por fase.

La base de datos se implementó en **Supabase sobre PostgreSQL**, con **25 tablas**, claves foráneas, restricciones `CHECK` y políticas de **Row Level Security** que aíslan la información de cada hogar.

---

## Tabla de contenidos

- [Metodología de trabajo](#metodología-de-trabajo)
- [Arquitectura](#arquitectura)
- [Stack tecnológico](#stack-tecnológico)
- [Estructura del repositorio](#estructura-del-repositorio)
- [Funcionalidades implementadas](#funcionalidades-implementadas)
- [Modelo de datos](#modelo-de-datos)
- [Puesta en marcha](#puesta-en-marcha)
- [Pruebas y validación](#pruebas-y-validación)
- [Seguridad y manejo de credenciales](#seguridad-y-manejo-de-credenciales)
- [Solución de problemas](#solución-de-problemas)
- [Equipo de desarrollo](#equipo-de-desarrollo)

---

## Metodología de trabajo

El proyecto se desarrolló con **metodología Cascada**. Cada etapa partió de los productos cerrados de la etapa anterior y no se avanzó a la siguiente sin revisar su entregable:

| Etapa | Producto principal |
|---|---|
| Análisis | Especificación de Requerimientos de Software (ERS): 131 requerimientos, 116 aceptados y 15 rechazados |
| Diseño | Modelo relacional (25 tablas) y Diccionario de datos |
| Construcción | Base de datos en Supabase, aplicación móvil y panel de administración |
| Pruebas | Pruebas unitarias, de widgets, de lógica y validaciones SQL |
| Despliegue | Panel web publicado con Docker y nginx |

La ERS fue la referencia única del alcance. Las observaciones docentes llevadas a la Fase 2 permitieron acotar el proyecto: se descartaron las recetas y la lectura de códigos de barras, se incorporó el RUT como identificador único, se precisó la ubicación del hogar a nivel de comuna y sector, y se excluyeron los registros técnicos del backend del modelo de datos.

La edad se calcula a partir de `perfil.fecha_nacimiento`. El RUT se usa solo para identificación y deduplicación, nunca para inferir edad ni datos demográficos.

---

## Arquitectura

```
┌────────────────────────┐                 ┌──────────────────────────────┐
│  Aplicación móvil      │                 │  Panel de administración     │
│  Flutter / Android     │                 │  Flutter Web + nginx/Docker  │
│  (Dart)                │                 │  (Dart)                      │
└───────────┬────────────┘                 └───────────────┬──────────────┘
            │ ↓ petición HTTPS / PostgREST                 │ ↓ petición HTTPS
            │ ↑ respuesta JSON                             │ ↑ respuesta JSON
┌──────────────────────────────────────────────────────────────────────────┐
│  Supabase                                                                │
│  Auth (correo, Google, MFA) · API de datos · Storage · Edge Functions    │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ ↓ consulta SQL / RPC
                                │ ↑ filas y resultados
┌──────────────────────────────────────────────────────────────────────────┐
│  PostgreSQL — 25 tablas                                                  │
│  Claves primarias y foráneas · restricciones CHECK · RLS por hogar       │
└──────────────────────────────────────────────────────────────────────────┘
```

- La aplicación y el panel comparten lenguaje (Dart) y se conectan directamente a los servicios de Supabase; no hay un servidor de aplicación propio entre el cliente y la base de datos.
- En cada nivel la comunicación es bidireccional: el cliente envía una petición HTTPS y recibe una respuesta JSON; Supabase a su vez consulta PostgreSQL y devuelve los resultados. Las políticas RLS se aplican en esa consulta, antes de que los datos salgan de la base de datos.
- Cada usuario solo ve los datos de los hogares en los que participa. Esa regla se aplica en la base de datos mediante RLS, no solo en la interfaz.
- Las reglas de negocio críticas (formatos, estados y cantidades válidas) están expresadas como restricciones en PostgreSQL, de modo que la base rechaza datos inconsistentes aunque la aplicación falle en validarlos.
- El cliente contempla una variable `API_URL` para un servicio de integraciones externo. Por defecto apunta a `10.0.2.2:8000` en el emulador Android y a `localhost:8000` en escritorio/web; ese servicio no está incluido en este repositorio.

---

## Stack tecnológico

| Capa | Tecnología |
|---|---|
| Aplicación móvil | Flutter 3.47.6 / Dart 3.13.5, Android (Kotlin) |
| Dependencias de la app | `supabase_flutter ^2.17.2`, `mobile_scanner ^7.4.2`, `http ^1.6.0`, `shared_preferences ^2.5.6`, `image_picker ^1.2.4`, `file_saver ^0.7.0`, `flutter_local_notifications 22.0.0`, `timezone 0.11.2` |
| Panel administrativo | Flutter Web 3.47.7 / Dart 3.13.5 |
| Dependencias del panel | `supabase_flutter ^2.18.3`, `flutter_riverpod ^3.4.3`, `go_router ^18.1.0`, `intl ^0.20.3`, `flutter_svg ^2.3.0`, `http ^1.6.0`, `web ^1.1.1` |
| Backend | Supabase: Auth, PostgREST, Storage y Edge Functions |
| Funciones Edge | TypeScript / Deno (`m08-preflight-cuenta-local`, `m08-confirmar-cuenta-local`) |
| Base de datos | PostgreSQL (25 tablas, RLS, restricciones y SQL de migración) |
| Despliegue del panel | Docker multi-stage y nginx 1.27-alpine |
| Seguridad | Supabase Auth, MFA (TOTP), roles y permisos, auditoría, RLS |
| Desarrollo | Visual Studio Code, Git/GitHub, Supabase CLI, Docker |

---

## Estructura del repositorio

```text
NFC-FoodTech/
│
├── Fase 1/
│   ├── Evidencias Grupales/       # Formativa, guía y planilla de evaluación
│   └── Evidencias Individuales/   # Autoevaluaciones y diarios de reflexión
│
├── Fase 2/
│   ├── Evidencias Grupales/       # Guía de desarrollo y documentos grupales
│   ├── Evidencias Individuales/   # Reflexiones y autoevaluaciones individuales
│   └── Evidencias Proyecto/
│       ├── Evidencias de documentacion/
│       │   ├── ERS_NFC-FoodTech.docx
│       │   ├── Diccionario de datos NFC-FoodTech.docx
│       │   └── ModeloRelacional.png
│       └── Evidencias de sistema/
│           ├── Aplicacion/            # Proyecto Flutter Android
│           │   ├── lib/
│           │   │   ├── main.dart
│           │   │   ├── config.dart
│           │   │   ├── features/     # Módulos de la app
│           │   │   ├── services/     # Notificaciones y flujo M08
│           │   │   ├── shared/       # Modelos, servicios y widgets comunes
│           │   │   └── screens/      # Identificación y eliminación de cuenta
│           │   ├── supabase/         # config.toml y Edge Functions M08
│           │   ├── test/             # Pruebas de la app
│           │   └── docs/ANDROID.md   # Deep links y compilación Android
│           └── PanelAdministracion/   # Proyecto Flutter Web
│               ├── lib/core/          # Configuración, router, tema y Supabase
│               ├── lib/features/      # Módulos del panel
│               ├── supabase/          # Migrations, seed y pruebas SQL
│               ├── test/              # Pruebas del panel
│               ├── Dockerfile
│               └── nginx.conf
│
└── README.md
```

---

## Funcionalidades implementadas

### Aplicación móvil

| Módulo | Funciones |
|---|---|
| `lib/features/auth/` | Registro e inicio de sesión con correo y Google, MFA, recuperación y cambio de contraseña, aceptación de documentos, tutorial |
| `lib/features/hogar/` | Crear y seleccionar hogar, invitaciones por código, miembros y roles |
| `lib/features/inventario/` | Catálogo de alimentos, alimentos personalizados, inventario, registro múltiple, movimientos e historial |
| `lib/features/compras/` | Lista de compras, sugerencias de reposición, confirmación de compra, historial, estimación y advertencia de stock |
| `lib/features/alertas/` | Alertas de caducidad, centro de notificaciones y preferencias |
| `lib/features/indicadores/` | Indicadores, comparativa mensual y recomendaciones |
| `lib/features/perfil/` y `configuracion/` | Perfil, desactivación de cuenta, configuración y solicitudes de soporte |
| `lib/features/home/` | Resumen del hogar y pantalla de inicio |
| `lib/services/` | Coordinador de avisos, notificaciones locales y flujo local de eliminación M08 |

**Motor de sugerencias:** analiza los consumos de los últimos 30 días y calcula la cantidad necesaria para cubrir 7 días. Ordena las sugerencias por menor cobertura de stock y excluye los alimentos que ya están pendientes en la lista de compras.

### Panel de administración

Módulos disponibles en `lib/features/`: administradores, alimentos, auditoría, autenticación, categorías y duraciones, configuración, dashboard, hogares, alimentos propuestos, reportes con exportación CSV, soporte y usuarios.

El acceso al panel incluye inicio de sesión con doble factor (`core/router/` y `features/auth/`). Las acciones administrativas quedan registradas en la tabla `auditoria`, y los permisos se gestionan con las tablas `rol`, `permiso`, `rol_permiso` y `perfil_rol`.

### Funciones Edge

En `Aplicacion/supabase/functions/` se encuentran las funciones M08 de preflight y confirmación de eliminación de cuenta local, escritas en TypeScript para el entorno Deno de Supabase, junto con sus pruebas.

---

## Modelo de datos

El modelo relacional tiene 25 tablas agrupadas en cuatro dominios:

| Dominio | Tablas principales |
|---|---|
| Identidad y hogar | `perfil`, `perfil_identificacion`, `hogar`, `hogar_miembro`, `region`, `comuna` |
| Catálogo e inventario | `categoria`, `alimento`, `despensa_item`, `movimiento`, `tipo_desperdicio` |
| Compras y alertas | `lista_compra`, `lista_compra_item`, `notificacion`, `plantilla_notificacion`, `preferencia_notificacion` |
| Administración y seguridad | `rol`, `permiso`, `rol_permiso`, `perfil_rol`, `auditoria`, `solicitud_soporte` |

También forman parte del modelo `aceptacion_documentos`, `parametro` y `m08_confirmacion_eliminacion`. Los movimientos de despensa admiten los tipos `INGRESO`, `CONSUMO`, `DESCARTE` y `AJUSTE`, y `tipo_desperdicio.es_evitable` permite separar el desperdicio evitable del no evitable.

---

## Puesta en marcha

### Requisitos

- Flutter SDK 3.47.x con Dart 3.13.x (la app se preparó con 3.47.6 y el panel con 3.47.7).
- Android SDK y un emulador o dispositivo Android para la aplicación.
- Navegador Chrome para el panel en modo local.
- Docker para ejecutar el panel como imagen.
- Acceso a la URL y clave pública del proyecto Supabase.

### 1. Aplicación móvil

Desde `Fase 2/Evidencias Proyecto/Evidencias de sistema/Aplicacion`:

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

La configuración de Supabase tiene valores por defecto en `lib/config.dart`, por lo que la app puede iniciar sin parámetros. Para usar otro proyecto o entorno:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<proyecto>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxx \
  --dart-define=API_URL=http://10.0.2.2:8000
```

`SUPABASE_PUBLISHABLE_KEY` es pública por diseño. La seguridad de los datos depende de RLS, no de ocultar esa clave.

En Android, el retorno de autenticación es `cl.duocuc.nfcfoodtech://login-callback/` y debe coincidir con el filtro del `AndroidManifest.xml` y con las URL permitidas en Supabase. El manifiesto usa `android:usesCleartextTraffic="false"`: en un teléfono físico, una `API_URL` HTTP no se permite; usa HTTPS o proporciona el define con una dirección alcanzable desde el dispositivo.

### 2. Panel administrativo en local

Desde `Fase 2/Evidencias Proyecto/Evidencias de sistema/PanelAdministracion`:

```powershell
flutter pub get
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://<proyecto>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_xxx
```

Sin esos dos parámetros el panel muestra una pantalla de error de configuración. El nombre del parámetro del panel es `SUPABASE_ANON_KEY`, aunque el valor utilizado es la clave pública publishable.

### 3. Panel administrativo con Docker

Desde la carpeta del panel:

```bash
docker build \
  --build-arg SUPABASE_URL=https://<proyecto>.supabase.co \
  --build-arg SUPABASE_ANON_KEY=sb_publishable_xxx \
  -t nfc-foodtech-admin .

docker run -d --name nfc-admin -p 8080:80 nfc-foodtech-admin
```

Luego abre `http://localhost:8080`.

El `Dockerfile` usa dos etapas: compila Flutter Web 3.47.7 desde el repositorio oficial (porque las imágenes públicas no tienen ese tag exacto) y sirve los archivos con `nginx:1.27-alpine`. `nginx.conf` redirige las rutas desconocidas a `index.html` para que funcione el enrutamiento del panel.

Durante el build aparece el aviso `SecretsUsedInArgOrEnv`: corresponde a la clave publishable, que es pública, por lo que no bloquea la compilación. Nunca pases la clave `service_role` ni secretos privados como argumento.

> No versionar `build/`, `.dart_tool/`, archivos `.env` ni `env.json`.

---

## Pruebas y validación

```bash
# Aplicación
flutter analyze
flutter test

# Panel
flutter analyze
flutter test
flutter build web
```

Pruebas incluidas:

- **Aplicación:** `avisos_locales_test.dart`, `m08_eliminacion_local_test.dart`, `notificaciones_android_test.dart`, `resumen_hogar_test.dart` y `widget_test.dart`.
- **Panel:** pruebas de lógica, widgets y repositorios falsos para autenticación, categorías, alimentos, propuestos, usuarios, hogares, reportes, soporte, auditoría y dashboard.
- **Base de datos:** scripts en `PanelAdministracion/supabase/tests/` (`T01` a `T14` y `AJ_ajustes_b1.sql`) para validar roles, RLS, auditoría, usuarios, soporte y reportes.

Las metas del proyecto se evaluarán comparando el primer mes de uso de cada hogar con los meses 2 a 6: +35% en consumo de alimentos notificados, −20% en compra duplicada y +30% en compras originadas desde una lista planificada.

---

## Seguridad y manejo de credenciales

- Autenticación con Supabase Auth: correo y contraseña, Google y MFA (TOTP).
- Row Level Security por hogar: un usuario solo accede a los hogares donde es miembro activo.
- Roles y permisos para las funciones administrativas, con registro de auditoría.
- Clave publishable/anon pública en el cliente; clave `service_role` exclusiva del servidor y nunca incluida en el repositorio.
- El RUT se almacena en `perfil_identificacion` para garantizar unicidad; no se expone en reportes ni se usa para calcular edad.
- La ubicación se muestra agregada por comuna o región, sin direcciones exactas.

---

## Solución de problemas

| Síntoma | Causa probable / solución |
|---|---|
| La app o el panel no conectan con Supabase | Revisar la clave publishable: usa guiones bajos (`sb_publishable_...`). Verificar también la URL del proyecto |
| El panel muestra “Falta configurar SUPABASE_URL y SUPABASE_ANON_KEY” | Reiniciar con los dos `--dart-define` indicados arriba |
| `API_URL` no responde en teléfono físico | El manifiesto Android bloquea HTTP; usar HTTPS o probar en emulador con `10.0.2.2` |
| El retorno de login no vuelve a la app | Verificar el scheme `cl.duocuc.nfcfoodtech://login-callback/` en el `AndroidManifest.xml` y en las URL permitidas de Supabase |
| Build de Docker con aviso `SecretsUsedInArgOrEnv` | Es la clave pública; no bloquea. No usar claves secretas en `--build-arg` |
| El panel Docker no abre en `http://localhost:8080` | Revisar que el contenedor esté activo y el mapeo `-p 8080:80` |
| Cambios en el código no se reflejan en el panel | Reconstruir la imagen con `docker build` y reiniciar el contenedor |
| Errores de RLS al consultar una tabla | Revisar la membresía del usuario en `hogar_miembro` y las políticas de la tabla |

---

## Equipo de desarrollo

| Integrante | Proyecto |
|---|---|
| Rodrigo Casanova | NFC-FoodTech |
| José Paillán | NFC-FoodTech |
| Samuel Acuña | NFC-FoodTech |

**Institución:** Duoc UC, Sede Concepción · **Carrera:** Ingeniería en Informática · **Año académico:** 2026

---

**NFC-FoodTech — gestión de alimentos para un consumo más consciente y planificado.**
