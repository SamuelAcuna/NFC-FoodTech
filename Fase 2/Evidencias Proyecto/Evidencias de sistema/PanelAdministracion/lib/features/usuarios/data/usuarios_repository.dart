import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/client.dart';
import '../domain/usuario_admin.dart';

abstract class UsuariosRepository {
  Future<List<UsuarioAdmin>> listar({
    String? busqueda,
    String? estado,
    String? desde,
    String? hasta,
    String? actividad,
    int offset = 0,
  });
  Future<void> cambiarEstado(String id, String estado, String motivo);
}

final usuariosRepositoryProvider = Provider<UsuariosRepository>(
  (ref) => SupabaseUsuariosRepository(ref.watch(supabaseClientProvider)),
);

class SupabaseUsuariosRepository implements UsuariosRepository {
  SupabaseUsuariosRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<UsuarioAdmin>> listar({
    String? busqueda,
    String? estado,
    String? desde,
    String? hasta,
    String? actividad,
    int offset = 0,
  }) async {
    final rows = await client.rpc(
      'admin_listar_usuarios',
      params: {
        'p_busqueda': busqueda,
        'p_estado': estado,
        'p_registro_desde': desde,
        'p_registro_hasta': hasta,
        'p_actividad': actividad,
        'p_offset': offset,
        'p_limite': 50,
      },
    );
    return (rows as List)
        .map((r) => UsuarioAdmin.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  @override
  Future<void> cambiarEstado(String id, String estado, String motivo) async {
    await client.rpc(
      'admin_cambiar_estado_cuenta',
      params: {
        'p_perfil_id': id,
        'p_estado': estado,
        'p_motivo': motivo.trim(),
      },
    );
  }
}
