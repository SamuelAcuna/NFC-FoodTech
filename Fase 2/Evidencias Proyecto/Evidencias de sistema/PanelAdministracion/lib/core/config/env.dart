abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static String? get configurationError {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      return 'Falta configurar SUPABASE_URL y SUPABASE_ANON_KEY. '
          'Inicia el panel con los parámetros --dart-define indicados en el README.';
    }
    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return 'La configuración de SUPABASE_URL no es válida. Revisa los parámetros de inicio.';
    }
    return null;
  }
}
