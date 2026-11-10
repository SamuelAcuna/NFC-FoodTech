# NFC-FoodTech — Android

## Configuración

- Identificador de aplicación: `cl.duocuc.nfcfoodtech.nfc_foodtech_app`.
- Nombre visible: `NFC-FoodTech`.
- Flutter utilizado en la preparación: `3.47.6`, con Dart `3.13.5`.
- La plataforma utiliza las versiones de SDK Android y NDK definidas por Flutter.
- La conexión a Supabase utiliza HTTPS. El manifiesto declara
  `android:usesCleartextTraffic="false"`; las direcciones HTTP de desarrollo de
  `API_URL` no están habilitadas por esta preparación.
- No se agregaron paquetes ni se modificó la configuración de Supabase.

## Enlaces de autenticación

La URL Android definida en `AppConfig.authRedirectUrl` es:

```text
cl.duocuc.nfcfoodtech://login-callback/
```

El filtro de `MainActivity` declara el mismo scheme `cl.duocuc.nfcfoodtech`,
host `login-callback` y ruta `/`. La actividad incluye
`flutter_deeplinking_enabled=false` para que `supabase_flutter` procese los
enlaces mediante `app_links`, sin competir con el manejador de Flutter.

El retorno se utiliza para Google, confirmación de registro y recuperación de
contraseña. En web se conserva `Uri.base.origin`.

Para que el retorno funcione, la URL debe estar permitida en la configuración
de redirecciones de Supabase Auth. Esa configuración no se modificó ni se pudo
verificar desde los archivos del proyecto. Si falta, se debe solicitar
autorización antes de cambiarla. Las plantillas de correo también deben
respetar el destino solicitado por la aplicación.

## Compilación y pruebas locales

Desde la raíz del proyecto, con las dependencias actuales ya resueltas:

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
```

Verificación del 28 de octubre de 2026: análisis sin incidencias, las tres
pruebas existentes aprobadas y APK debug compilado correctamente. Las pruebas
existentes corresponden al modelo de búsqueda de códigos y no verifican los
retornos de autenticación. El manifiesto empaquetado conserva el enlace
declarado, el manejador de Flutter desactivado y el bloqueo de HTTP sin cifrar.

El APK de prueba, si la compilación termina correctamente, se encuentra en:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

La primera compilación puede descargar Gradle y componentes Android. Los
archivos `android/local.properties`, las cachés y los resultados de compilación
son locales y no deben compartirse como configuración de otra máquina.

La firma debug es para pruebas. La configuración de firma de distribución
queda pendiente antes de preparar una entrega de producción.

## Verificación en un teléfono Android

1. Instalar el APK de prueba y comprobar el inicio con conexión a internet.
2. Comprobar que Android resuelve el enlace hacia esta aplicación:

   ```powershell
   adb shell am start -W -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d "cl.duocuc.nfcfoodtech://login-callback/" -p cl.duocuc.nfcfoodtech.nfc_foodtech_app
   ```

   Este enlace sin credenciales solo verifica la apertura; no autentica ni
   comprueba la configuración del servidor.
3. Iniciar Google desde la aplicación, completar la autorización en el
   navegador y comprobar el regreso con sesión válida. Repetir con la aplicación
   cerrada antes de completar el retorno.
4. Solicitar recuperación desde la aplicación y abrir el correo en el mismo
   teléfono. Comprobar el regreso a la pantalla de nueva contraseña, guardar
   una contraseña de prueba y verificar el inicio de sesión posterior.
5. Repetir recuperación con la aplicación cerrada al abrir el enlace. Comprobar
   también el comportamiento de enlaces expirados o reutilizados.
6. Con una cuenta de prueba nueva, comprobar el correo de confirmación de
   registro y su retorno a la aplicación.

Las pruebas con Google, correo y actualización de contraseña requieren cuentas
de prueba y acceso al servicio real; no se sustituyen por compilar el APK.
