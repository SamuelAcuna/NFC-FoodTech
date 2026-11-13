import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/client.dart';
import '../domain/administrador.dart';

abstract class AdministradoresRepository {
  Future<AdministradoresData> cargar();
  Future<void> asignar(String email, String codigo);
  Future<void> quitar(String id, String codigo);
}

final administradoresRepositoryProvider = Provider<AdministradoresRepository>(
  (ref) => SupabaseAdministradoresRepository(ref.watch(supabaseClientProvider)),
);

class SupabaseAdministradoresRepository implements AdministradoresRepository {
  SupabaseAdministradoresRepository(this.client);
  final SupabaseClient client;
  Future<List<Map<String, dynamic>>> readAll(
    String table,
    String columns,
    String order,
  ) async {
    final result = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 500) {
      final page = await client
          .from(table)
          .select(columns)
          .order(order, ascending: true)
          .range(offset, offset + 499);
      result.addAll(page);
      if (page.length < 500) {
        return result;
      }
    }
  }

  @override
  Future<AdministradoresData> cargar() async {
    final admins = <Administrador>[];
    for (var offset = 0; ; offset += 500) {
      final page = await client
          .rpc('admin_listar_administradores')
          .range(offset, offset + 499);
      admins.addAll(
        (page as List).map(
          (r) => Administrador.fromJson(Map<String, dynamic>.from(r as Map)),
        ),
      );
      if (page.length < 500) {
        break;
      }
    }
    final roles = await readAll('rol', 'id,codigo,nombre', 'id');
    final permissions = await readAll('permiso', 'id,codigo,descripcion', 'id');
    final relations = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 500) {
      final page = await client
          .from('rol_permiso')
          .select('rol_id,permiso_id')
          .order('rol_id', ascending: true)
          .order('permiso_id', ascending: true)
          .range(offset, offset + 499);
      relations.addAll(page);
      if (page.length < 500) {
        break;
      }
    }
    return AdministradoresData(admins, [
      for (final r in roles)
        RolAdministrativo(
          id: (r['id'] as num).toInt(),
          codigo: r['codigo'] as String,
          nombre: r['nombre'] as String,
          permisos: [
            for (final relation in relations.where(
              (rp) => rp['rol_id'] == r['id'],
            ))
              for (final p in permissions.where(
                (p) => p['id'] == relation['permiso_id'],
              ))
                p['descripcion'] as String? ?? p['codigo'] as String,
          ],
        ),
    ]);
  }

  @override
  Future<void> asignar(String email, String codigo) async {
    await client.rpc(
      'admin_asignar_rol',
      params: {'p_email': email.trim(), 'p_rol_codigo': codigo},
    );
  }

  @override
  Future<void> quitar(String id, String codigo) async {
    await client.rpc(
      'admin_quitar_rol',
      params: {'p_perfil_id': id, 'p_rol_codigo': codigo},
    );
  }
}
