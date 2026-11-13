import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/client.dart';
import '../domain/propuesta.dart';

abstract class PropuestosRepository {
  Future<List<Propuesta>> listar();
  Future<int> contar();
  Future<int> aprobar({
    required int id,
    required String nombre,
    required int categoriaId,
    required String unidadBase,
    required bool esPerecible,
    int? vidaUtilDiasRef,
  });
  Future<void> rechazar(int id);
}

final propuestosRepositoryProvider = Provider<PropuestosRepository>(
  (ref) => SupabasePropuestosRepository(ref.watch(supabaseClientProvider)),
);

class SupabasePropuestosRepository implements PropuestosRepository {
  SupabasePropuestosRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<Propuesta>> listar() async {
    final result = <Propuesta>[];
    for (var offset = 0; ; offset += 500) {
      final rows = await client
          .rpc('admin_listar_propuestos')
          .range(offset, offset + 499);
      final page = (rows as List)
          .map(
            (row) => Propuesta.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
      result.addAll(page);
      if (page.length < 500) return result;
    }
  }

  @override
  Future<int> contar() async =>
      ((await client.rpc('admin_contar_propuestos')) as num).toInt();
  @override
  Future<int> aprobar({
    required int id,
    required String nombre,
    required int categoriaId,
    required String unidadBase,
    required bool esPerecible,
    int? vidaUtilDiasRef,
  }) async => ((await client.rpc(
    'admin_aprobar_propuesto',
    params: {
      'p_id': id,
      'p_nombre': nombre.trim(),
      'p_categoria_id': categoriaId,
      'p_unidad_base': unidadBase,
      'p_es_perecible': esPerecible,
      'p_vida_util_dias_ref': vidaUtilDiasRef,
    },
  )) as num).toInt();
  @override
  Future<void> rechazar(int id) async {
    await client.rpc('admin_rechazar_propuesto', params: {'p_id': id});
  }
}
