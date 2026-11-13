import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/client.dart';
import '../domain/registro_auditoria.dart';

abstract class AuditoriaRepository {
  Future<List<RegistroAuditoria>> listar({
    String? desde,
    String? hasta,
    String? entidad,
    String? accion,
    int offset = 0,
  });
}

final auditoriaRepositoryProvider = Provider<AuditoriaRepository>(
  (ref) => SupabaseAuditoriaRepository(ref.watch(supabaseClientProvider)),
);

class SupabaseAuditoriaRepository implements AuditoriaRepository {
  SupabaseAuditoriaRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<RegistroAuditoria>> listar({
    String? desde,
    String? hasta,
    String? entidad,
    String? accion,
    int offset = 0,
  }) async {
    final rows = await client.rpc(
      'admin_listar_auditoria',
      params: {
        'p_desde': desde,
        'p_hasta': hasta,
        'p_entidad': entidad,
        'p_accion': accion,
        'p_limite': 50,
        'p_offset': offset,
      },
    );
    return (rows as List)
        .map(
          (r) =>
              RegistroAuditoria.fromJson(Map<String, dynamic>.from(r as Map)),
        )
        .toList();
  }
}
