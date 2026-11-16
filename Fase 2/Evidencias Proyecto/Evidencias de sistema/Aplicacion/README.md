# NFC-FoodTech — App (Flutter) 🌱

## Descripción

NFC-FoodTech es una aplicación Android que ayuda a las personas a gestionar los alimentos de su hogar, reducir el desperdicio alimentario y aprovechar mejor sus recursos económicos.

La aplicación permite registrar alimentos, administrar el inventario compartido del hogar, registrar consumos y descartes, planificar compras y consultar indicadores de desperdicio.

## Funcionalidades

### Autenticación de usuarios
- Inicio de sesión con correo electrónico y contraseña.
- Registro de nuevas cuentas.
- Inicio de sesión y registro mediante Google.
- Gestión de la sesión del usuario mediante Supabase Auth.

### Gestión de alimentos
- Registro manual de alimentos.
- Clasificación por categoría y ubicación de almacenamiento.
- Registro de cantidades, unidades, precios y fechas estimadas de caducidad.
- Visualización y modificación del inventario.

### Consumo y análisis
- Registro de alimentos consumidos o descartados.
- Consulta de información relacionada con el consumo.
- Estimación de pérdidas económicas asociadas al desperdicio.
- Identificación de alimentos próximos a su fecha estimada de caducidad.


## Tecnologías utilizadas

- **Flutter:** desarrollo de la aplicación.
- **Dart:** lenguaje de programación.
- **Supabase Auth:** autenticación y gestión de sesiones.
- **PostgreSQL:** base de datos.
- **Visual Studio Code:** entorno de desarrollo.
- **Git y GitHub:** control de versiones.

## Requisitos

- Flutter SDK instalado.
- Dart SDK, incluido con Flutter.
- Visual Studio Code u otro editor compatible.
- Un proyecto configurado en Supabase.
- Un dispositivo o emulador Android para ejecutar la aplicación.

## Configuración inicial

1. Clonar el repositorio:

   ```bash
   git clone URL_DEL_REPOSITORIO
   ```

2. Ingresar a la carpeta del proyecto:

   ```bash
   cd "Fase 2/Evidencias Proyecto/Evidencias de sistema/Aplicacion"
   ```

3. Instalar las dependencias:

   ```bash
   flutter pub get
   ```

4. La URL del proyecto Supabase y su clave publicable vienen por defecto en `lib/config.dart` y pueden reemplazarse con `--dart-define`.

5. Ejecutar la aplicación en un dispositivo o emulador Android:

   ```bash
   flutter run
   ```

6. Ejecutar las pruebas automatizadas:

   ```bash
   flutter test
   ```

Los pasos para generar el APK están en `docs/ANDROID.md` y en el Manual Técnico.

## Configuración de Supabase

La aplicación utiliza Supabase para gestionar la autenticación y conectarse a la base de datos.

Se deben configurar los siguientes datos:

- `SUPABASE_URL`: URL del proyecto.
- `SUPABASE_PUBLISHABLE_KEY`: clave pública del proyecto.

La clave pública está diseñada para utilizarse en el cliente. La protección de los datos debe implementarse mediante políticas de seguridad RLS en las tablas correspondientes.

**Importante:** nunca incluir claves `service_role` ni claves secretas en el código de la aplicación o en el repositorio público.

## Estructura del proyecto

```text
lib/
├── main.dart, config.dart, theme_controller.dart
├── features/   módulos: auth, home, hogar, inventario, compras,
│               alertas, indicadores, perfil y configuracion
├── screens/    identificación y eliminación de cuenta
├── models/     modelos de datos
├── services/   notificaciones locales y eliminación de cuenta
└── shared/     componentes y lógica compartida
test/           pruebas automatizadas
supabase/       Edge Functions de la aplicación
```

## Estado del proyecto

Versión entregada al cierre de la Fase 2. Incluye autenticación (correo y Google), hogares con invitación por código, inventario por ubicación, consumo y descarte con motivo, lista de compras con sugerencias, alertas de vencimiento e indicadores de desperdicio. Cuenta con 347 pruebas automatizadas aprobadas.

## Objetivo

Desarrollar una herramienta digital sencilla y práctica que permita mejorar la organización de los alimentos en el hogar y contribuir a la reducción del desperdicio alimentario.

## Autores

Rodrigo Casanova
José Paillán 
Samuel Acuña