# NFC-FoodTech — App (Flutter) 🌱

## Descripción

NFC-FoodTech es una aplicación en desarrollo que busca ayudar a las personas a gestionar los alimentos de su hogar, reducir el desperdicio alimentario y aprovechar mejor sus recursos económicos.

La aplicación permitirá registrar alimentos manualmente, administrar el inventario, llevar un seguimiento del consumo y consultar información sobre el desperdicio de alimentos.

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

*Las funcionalidades se desarrollarán progresivamente según el avance del proyecto.*

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
- Un navegador compatible o un dispositivo para realizar pruebas.

## Configuración inicial

1. Clonar el repositorio:

   ```bash
   git clone URL_DEL_REPOSITORIO
   ```

2. Ingresar a la carpeta del proyecto:

   ```bash
   cd nfc_foodtech
   ```

3. Instalar las dependencias:

   ```bash
   flutter pub get
   ```

4. Configurar la URL del proyecto Supabase y su clave pública en el archivo de configuración correspondiente.

5. Ejecutar la aplicación en Chrome:

   ```bash
   flutter run -d chrome
   ```

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
├── main.dart
├── config.dart
├── theme.dart
└── screens/
    ├── inicio_screen.dart
    ├── registro_screen.dart
    └── home_screen.dart
```

La estructura podrá ampliarse a medida que se incorporen las funcionalidades de inventario, consumo y análisis.

## Estado del proyecto

El proyecto se encuentra en etapa de desarrollo. Actualmente, el trabajo se centra en la configuración de Flutter, la autenticación de usuarios y la preparación de la estructura para implementar la gestión de alimentos.

## Objetivo

Desarrollar una herramienta digital sencilla y práctica que permita mejorar la organización de los alimentos en el hogar y contribuir a la reducción del desperdicio alimentario.

## Autores

Rodrigo Casanova
Jose Paillan 
Samuel Acuña