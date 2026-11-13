import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/client.dart';
import '../domain/solicitud_soporte.dart';

abstract class SoporteRepository {
  Future<List<SolicitudSoporte>> listar({
    String? estado = 'ABIERTAS',
    int offset = 0,
  });
  Future<List<AgenteSoporte>> agentes();
  Future<void> asignar(String id, String agente);
  Future<void> responder(String id, String respuesta);
  Future<void> cerrar(String id);
}

final soporteRepositoryProvider = Provider<SoporteRepository>(
  (ref) => SupabaseSoporteRepository(ref.watch(supabaseClientProvider)),
);

class SupabaseSoporteRepository implements SoporteRepository {
  SupabaseSoporteRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<SolicitudSoporte>> listar({
    String? estado = 'ABIERTAS',
    int offset = 0,
  }) async =>
      ((await client.rpc(
            'admin_listar_soporte',
            params: {'p_estado': estado, 'p_limite': 50, 'p_offset': offset},
          )) as List)
          .map(
            (r) =>
                SolicitudSoporte.fromJson(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
  @override
  Future<List<AgenteSoporte>> agentes() async =>
      ((await client.rpc('admin_listar_agentes_soporte')) as List)
          .map(
            (r) => AgenteSoporte.fromJson(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
  @override
  Future<void> asignar(String id, String agente) async {
    await client.rpc(
      'admin_soporte_asignar',
      params: {'p_id': id, 'p_agente': agente},
    );
  }

  @override
  Future<void> responder(String id, String respuesta) async {
    await client.rpc(
      'admin_soporte_responder',
      params: {'p_id': id, 'p_respuesta': respuesta.trim()},
    );
  }

  @override
  Future<void> cerrar(String id) async {
    await client.rpc('admin_soporte_cerrar', params: {'p_id': id});
  }
}
