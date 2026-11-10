import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'es_CL';
  await initializeDateFormatting('es_CL');
  var error = Env.configurationError;
  if (error == null) {
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabaseAnonKey,
        debug: false,
      );
    } catch (_) {
      error = 'No se pudo iniciar el panel. Revisa la configuración y vuelve a intentarlo.';
    }
  }
  runApp(ProviderScope(child: AdminApp(configurationError: error)));
}
