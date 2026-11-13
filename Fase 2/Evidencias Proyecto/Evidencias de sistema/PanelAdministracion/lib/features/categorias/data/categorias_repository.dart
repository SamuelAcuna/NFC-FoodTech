import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/client.dart';
import '../domain/categoria.dart';

abstract class CategoriasRepository {
  Future<List<Categoria>> listar();
  Future<Map<int, int>?> contarAlimentos();
  Future<void> guardar({
    int? id,
    required String nombre,
    int? parentId,
    String? conservacion,
  });
  Future<void> cambiarEstado(int id, bool activa);
  Future<void> eliminar(int id);
  Future<void> guardarDuraciones(
    int id, {
    int? despensa,
    int? refrigerador,
    int? congelador,
  });
}

final categoriasRepositoryProvider = Provider<CategoriasRepository>(
  (ref) => SupabaseCategoriasRepository(ref.watch(supabaseClientProvider)),
);

class SupabaseCategoriasRepository implements CategoriasRepository {
  SupabaseCategoriasRepository(this.client);
  final SupabaseClient client;
  static const _columns =
      'id,nombre,parent_id,temp_conservacion,vida_util_dias_ref,vida_util_refrigerado_dias,vida_util_congelado_dias,activa';
  @override
  Future<List<Categoria>> listar() async {
    final result = <Categoria>[];
    for (var offset = 0; ; offset += 500) {
      final rows = await client
          .from('categoria')
          .select(_columns)
          .order('id')
          .range(offset, offset + 499);
      result.addAll(rows.map(Categoria.fromJson));
      if (rows.length < 500) return result;
    }
  }

  @override
  Future<Map<int, int>?> contarAlimentos() async {
    try {
      final result = {for (final c in await listar()) c.id: 0};
      for (var offset = 0; ; offset += 500) {
        final rows = await client
            .from('alimento')
            .select('categoria_id')
            .isFilter('hogar_id', null)
            .order('id')
            .range(offset, offset + 499);
        for (final row in rows) {
          final id = (row['categoria_id'] as num).toInt();
          result[id] = (result[id] ?? 0) + 1;
        }
        if (rows.length < 500) return result;
      }
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> guardar({
    int? id,
    required String nombre,
    int? parentId,
    String? conservacion,
  }) async {
    final data = {
      'nombre': nombre.trim(),
      'parent_id': parentId,
      'temp_conservacion': conservacion,
    };
    if (id == null) {
      await client.from('categoria').insert(data);
    } else {
      await client
          .from('categoria')
          .update(data)
          .eq('id', id)
          .select('id')
          .single();
    }
  }

  @override
  Future<void> cambiarEstado(int id, bool activa) async {
    await client
        .from('categoria')
        .update({'activa': activa})
        .eq('id', id)
        .select('id')
        .single();
  }

  @override
  Future<void> eliminar(int id) async {
    await client.from('categoria').delete().eq('id', id).select('id').single();
  }

  @override
  Future<void> guardarDuraciones(
    int id, {
    int? despensa,
    int? refrigerador,
    int? congelador,
  }) async {
    await client
        .from('categoria')
        .update({
          'vida_util_dias_ref': despensa,
          'vida_util_refrigerado_dias': refrigerador,
          'vida_util_congelado_dias': congelador,
        })
        .eq('id', id)
        .select('id')
        .single();
  }
}
