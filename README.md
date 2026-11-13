# NFC-FoodTech

### Sistema de gestión de alimentos y prevención del desperdicio alimentario

**Proyecto de Título / Capstone — Ingeniería en Informática**

**Duoc UC · Sede Concepción · 2026**

---

## Descripción del proyecto

**NFC-FoodTech** es una solución tecnológica orientada a mejorar la gestión de alimentos en los hogares, contribuyendo a prevenir el desperdicio alimentario mediante el seguimiento del inventario, las alertas de caducidad estimada, el registro de consumos y descartes, y la planificación de compras.

El proyecto surge ante problemáticas cotidianas como el olvido de alimentos almacenados, las compras innecesarias y la falta de control sobre las cantidades disponibles en el hogar.

La solución está compuesta por una aplicación móvil Android, un panel administrativo web y una base de datos centralizada.

## Objetivo general

Reducir el desperdicio de alimentos en los hogares, promoviendo un consumo más eficiente y una mejor planificación de las compras a partir del conocimiento de los hábitos de consumo y desperdicio de cada hogar.

## Funcionalidades principales

**Gestión de usuarios y hogares**
- Autenticación y gestión de cuentas.
- Creación y administración de hogares.
- Incorporación de integrantes y gestión de roles.
- Acceso a múltiples hogares.

**Inventario de alimentos**
- Registro y administración de alimentos.
- Control de cantidades, unidades y ubicaciones.
- Fechas estimadas de caducidad.
- Consumo parcial y registro de desperdicios.
- Historial de movimientos.

**Prevención y planificación**
- Alertas de caducidad estimada.
- Listas de compras compartidas.
- Seguimiento de productos disponibles y agotados.
- Indicadores de consumo y desperdicio.
- Comparativas y estimaciones económicas.

**Administración de la plataforma**
- Gestión del catálogo de alimentos y categorías.
- Administración de usuarios y permisos.
- Configuración de parámetros del sistema.
- Funcionalidades de soporte y auditoría.

## Tecnologías utilizadas

| Componente | Tecnologías |
|---|---|
| Aplicación móvil | Flutter, Dart, Android |
| Panel administrativo | Flutter Web |
| Backend gestionado | Supabase |
| Base de datos | PostgreSQL |
| Autenticación | Supabase Auth |
| Seguridad | Row Level Security (RLS), roles y permisos |
| Despliegue del panel | Docker, nginx |
| Desarrollo | Visual Studio Code |
| Control de versiones | Git y GitHub |

## Arquitectura del sistema

NFC-FoodTech utiliza una arquitectura organizada en tres capas lógicas:

**1. Presentación**

Aplicación Android y panel administrativo web desarrollados con Flutter, responsables de la interacción con los usuarios.

**2. Servicios**

Supabase proporciona servicios de autenticación y acceso a datos mediante su API y funciones RPC.

**3. Persistencia**

PostgreSQL centraliza la información del sistema y permite aplicar restricciones de integridad, funciones SQL y políticas de seguridad.

Esta organización permite compartir información entre los componentes, separar responsabilidades y facilitar el mantenimiento de la solución.

## Estructura del repositorio

El repositorio está organizado de acuerdo con las fases académicas del proyecto.

```text
NFC-FoodTech-app/
│
├── Fase 1/
│   ├── Evidencias Grupales/
│   └── Evidencias Individuales/
│
├── Fase 2/
│   ├── Evidencias Grupales/
│   ├── Evidencias Individuales/
│   └── Evidencias Proyecto/
│       ├── Documentación del proyecto
│       └── Evidencias de sistema/
│           ├── Aplicacion/
│           └── PanelAdministracion/
│
└── README.md
```

### Fase 1 — Definición del proyecto

Contiene los documentos asociados a la identificación de la problemática, la definición de la propuesta de solución, la planificación inicial y las evidencias académicas individuales y grupales.

### Fase 2 — Desarrollo del proyecto

Contiene las evidencias correspondientes al análisis, diseño, construcción y validación del sistema.

Entre los documentos y entregables se encuentran:

- Especificación de Requisitos de Software (ERS).
- Diccionario de datos.
- Modelo relacional.
- Código fuente de la aplicación móvil.
- Código fuente del panel administrativo.
- Evidencias de desarrollo y documentación técnica.

## Ejecución del proyecto

### Requisitos generales

- Flutter SDK y Dart.
- Android SDK para la aplicación móvil.
- Un dispositivo Android o emulador compatible.
- Acceso a la configuración autorizada del proyecto Supabase.
- Docker, cuando corresponda al despliegue del panel administrativo.

### Aplicación móvil

Desde la carpeta que contiene el archivo `pubspec.yaml` de la aplicación:

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Antes de ejecutar la aplicación, se deben configurar las variables y credenciales necesarias según el entorno de desarrollo.

### Panel administrativo

El panel administrativo dispone de su propio proyecto Flutter Web. Su ejecución y despliegue deben realizarse siguiendo la configuración incluida en su carpeta, considerando las dependencias y los servicios correspondientes.

## Seguridad y gestión de datos

El sistema contempla mecanismos de autenticación, control de roles y permisos, y políticas Row Level Security para restringir el acceso a información protegida.

El registro de movimientos, consumos y desperdicios permite mantener información relacionada con los alimentos de cada hogar.

Las fechas de caducidad estimadas son referencias orientativas y no sustituyen la evaluación del estado real de los alimentos ni las indicaciones de seguridad alimentaria.

**Importante:** las credenciales privadas, contraseñas y claves de servicio no deben almacenarse en el repositorio.

## Pruebas y validación

El proyecto contempla pruebas unitarias, funcionales, negativas, de integración y no funcionales.

Las validaciones tienen como propósito comprobar el comportamiento de los módulos, identificar errores y verificar las correcciones realizadas.

Los resultados de ejecución deben respaldarse con registros, evidencias y documentación de los casos de prueba.

## Equipo de desarrollo

| Integrante | Proyecto |
|---|---|
| Rodrigo Casanova | NFC-FoodTech |
| José Paillán | NFC-FoodTech |
| Samuel Acuña | NFC-FoodTech |

**Institución:** Duoc UC, Sede Concepción

**Carrera:** Ingeniería en Informática

**Año académico:** 2026

## Alcance del proyecto

NFC-FoodTech constituye una solución desarrollada en el contexto académico del proyecto Capstone.

La evaluación del cumplimiento de las metas de reducción del desperdicio requiere recopilar y analizar información durante un período de utilización posterior al desarrollo.

---

**NFC-FoodTech — Gestión de alimentos para un consumo más consciente y planificado.**
