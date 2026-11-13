import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/client.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/alimento.dart';

abstract class AlimentosRepository {
  Future<List<Alimento>> listar();
  Future<void> guardar({
    int? id,
    required String nombre,
    required int categoriaId,
    required String unidadBase,
    required bool esPerecible,
    int? vidaUtilDiasRef,
  });
  Future<void> cambiarEstado(int id, bool activo);
  Future<void> eliminar(int id);
}

final alimentosRepositoryProvider = Provider<AlimentosRepository>(
  (ref) => SupabaseAlimentosRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(authRepositoryProvider),
  ),
);

class SupabaseAlimentosRepository implements AlimentosRepository {
  SupabaseAlimentosRepository(this.client, this.auth);
  final SupabaseClient client;
  final AuthRepository auth;
  @override
  Future<List<Alimento>> listar() async {
    final result = <Alimento>[];
    for (var offset = 0; ; offset += 500) {
      final rows = await client
          .from('alimento')
          .select(
            'id,nombre,categoria_id,vida_util_dias_ref,unidad_base,es_perecible,activo',
          )
          .isFilter('hogar_id', null)
          .order('nombre', ascending: true)
          .order('id', ascending: true)
          .range(offset, offset + 499);
      result.addAll(rows.map(Alimento.fromJson));
      if (rows.length < 500) return result;
    }
  }

  @override
  Future<void> guardar({
    int? id,
    required String nombre,
    required int categoriaId,
    required String unidadBase,
    required bool esPerecible,
    int? vidaUtilDiasRef,
  }) async {
    final data = <String, dynamic>{
      'nombre': nombre.trim(),
      'categoria_id': categoriaId,
      'unidad_base': unidadBase,
      'es_perecible': esPerecible,
      'vida_util_dias_ref': vidaUtilDiasRef,
    };
    if (id == null) {
      final userId = auth.userId;
      if (userId == null) throw AuthSessionMissingException();
      await client.from('alimento').insert({
        ...data,
        'hogar_id': null,
        'estado': 'APROBADO',
        'creado_por': userId,
      });
    } else {
      await client
          .from('alimento')
          .update(data)
          .eq('id', id)
          .isFilter('hogar_id', null)
          .select('id')
          .single();
    }
  }

  @override
  Future<void> cambiarEstado(int id, bool activo) async {
    await client
        .from('alimento')
        .update({'activo': activo})
        .eq('id', id)
        .isFilter('hogar_id', null)
        .select('id')
        .single();
  }

  @override
  Future<void> eliminar(int id) async {
    await client
        .from('alimento')
        .delete()
        .eq('id', id)
        .isFilter('hogar_id', null)
        .select('id')
        .single();
  }
}
