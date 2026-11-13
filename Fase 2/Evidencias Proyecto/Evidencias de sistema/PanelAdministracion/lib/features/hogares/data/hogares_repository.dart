import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/client.dart';
import '../domain/hogar_resumen.dart';

abstract class HogaresRepository {
  Future<List<HogarResumen>> listar({
    String? busqueda,
    String? actividad,
    int offset = 0,
  });
}

final hogaresRepositoryProvider = Provider<HogaresRepository>(
  (ref) => SupabaseHogaresRepository(ref.watch(supabaseClientProvider)),
);

class SupabaseHogaresRepository implements HogaresRepository {
  SupabaseHogaresRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<HogarResumen>> listar({
    String? busqueda,
    String? actividad,
    int offset = 0,
  }) async {
    final rows = await client.rpc(
      'admin_listar_hogares',
      params: {
        'p_busqueda': busqueda,
        'p_actividad': actividad,
        'p_limite': 50,
        'p_offset': offset,
      },
    );
    return (rows as List)
        .map((r) => HogarResumen.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }
}
