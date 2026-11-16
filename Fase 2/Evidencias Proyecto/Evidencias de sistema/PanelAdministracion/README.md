# Panel de administración NFC-FoodTech

Panel web de administración de NFC-FoodTech, construido con Flutter Web. Requiere Flutter stable 3.47.7 / Dart 3.13.5 o compatible.

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

Incluye inicio de sesión con segundo factor (TOTP), control de acceso por rol y permiso, y las secciones de dashboard, catálogo, alimentos propuestos, usuarios, hogares, soporte, administradores, auditoría, reportes y configuración. Menú expandido desde 1024 px, solo íconos entre 600 y 1023 px y Drawer bajo 600 px.

Capas por feature en `lib/features/`; infraestructura compartida en `lib/core/`. Locale `es_CL`, fechas `dd-MM-yyyy` y montos CLP sin decimales.


## Levantar con Docker

Requiere Docker Desktop. Desde esta carpeta, en PowerShell (una línea por comando):

```powershell
docker build -t nfc-admin --build-arg SUPABASE_URL=https://dpsbrniclxojsoxhgmjv.supabase.co --build-arg SUPABASE_ANON_KEY=<clave publicable> .
docker run -d -p 8090:80 --name nfc-admin nfc-admin
```

Abrir http://localhost:8090. Si el puerto está ocupado, usar otro (`-p 9000:80`); el `:80` no se cambia.
Para reconstruir: `docker rm -f nfc-admin` y repetir los dos comandos. Solo la clave publicable; nunca la `service_role`.
La primera compilación demora varios minutos porque descarga Flutter 3.47.7.


## Docker Compose

Requiere Docker Desktop iniciado con contenedores Linux. Ejecutar desde esta carpeta, junto a `compose.yaml` y `.env.example`:

```powershell
Copy-Item .env.example .env
# Completar SUPABASE_URL y SUPABASE_ANON_KEY en .env con la URL y clave publicable.
docker compose up --build -d
curl.exe --fail http://localhost:8090
docker compose down
```

Abrir http://localhost:8090. El archivo `.env` es local y no se sube a Git; la clave publicable se integra durante la compilación. No usar claves privilegiadas. Para actualizar la configuración, reconstruir con `docker compose up --build -d`.
