import 'package:flutter/foundation.dart';

/// Configuracion de la app.
///
/// Se puede cambiar al compilar con --dart-define, por ejemplo:
///   flutter run --dart-define=API_URL=http://192.168.1.50:8000
///
/// La clave publishable de Supabase es publica por diseno: la seguridad
/// de los datos la dan las politicas RLS, no esconder esta clave.
/// NUNCA poner aqui la clave service_role / secret.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://dpsbrniclxojsoxhgmjv.supabase.co',
  );

  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_EgZru31XDlDHemo_-BqXKA_PbjbdXFp',
  );

  static const _apiUrl = String.fromEnvironment('API_URL');

  /// Retorno de autenticación para el navegador y la aplicación Android.
  /// El enlace nativo debe coincidir con el AndroidManifest.xml.
  static String? get authRedirectUrl {
    if (kIsWeb) return Uri.base.origin;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'cl.duocuc.nfcfoodtech://login-callback/';
    }
    return null;
  }

  /// URL del servicio de integraciones (FastAPI en Docker).
  ///
  /// Por defecto:
  /// - Emulador Android: 10.0.2.2 es el "localhost" del PC visto desde el emulador.
  /// - Web y escritorio: localhost.
  /// En un telefono fisico hay que pasar la IP del PC con --dart-define=API_URL.
  static String get apiUrl {
    if (_apiUrl.isNotEmpty) {
      if (_apiUrl.startsWith('/')) {
        // Ruta relativa (version web en Docker): se resuelve contra la direccion
        // desde la que se abrio la app, y nginx reenvia /api al servicio.
        return Uri.base.resolve(_apiUrl).toString().replaceFirst(RegExp(r'/$'), '');
      }
      return _apiUrl;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://localhost:8000';
  }
}
