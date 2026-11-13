# Panel de administración NFC-FoodTech

Scaffold Flutter Web (T00). Requiere Flutter stable 3.47.7 / Dart 3.13.5 o compatible.

Desde esta carpeta:

```powershell
flutter pub get
flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

Usa la URL y la clave pública anon del proyecto mediante esos parámetros. No guardes credenciales en archivos ni uses claves privilegiadas. Sin parámetros se muestra una pantalla de error de configuración.

```powershell
flutter analyze
flutter test
flutter build web
```

`flutter build web` comprueba la compilación; para una distribución configurada agrega los mismos `--dart-define`. No commitear `build/`, `.dart_tool/`, archivos `*.env` ni `env.json`.

El shell contiene ocho rutas placeholder y `/login` fuera del shell. No incluye autenticación, guards ni acceso a tablas. El usuario al pie del menú es fijo y de ejemplo. Menú expandido desde 1024 px, solo íconos entre 600 y 1023 px y Drawer bajo 600 px.

Capas por feature en `lib/features/`; infraestructura compartida en `lib/core/`. Locale `es_CL`, fechas `dd-MM-yyyy` y montos CLP sin decimales.

Si Flutter no está en el PATH de esta sesión, el SDK local de validación está en `../.tools/flutter/bin/` (ignorado por Git).
