import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/client.dart';
import '../domain/parametro.dart';

abstract class ParametrosRepository {
  Future<List<Parametro>> listar();
  Future<void> actualizar(String clave, String valor);
}

final parametrosRepositoryProvider = Provider<ParametrosRepository>(
  (ref) => SupabaseParametrosRepository(ref.watch(supabaseClientProvider)),
);

class SupabaseParametrosRepository implements ParametrosRepository {
  SupabaseParametrosRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<Parametro>> listar() async =>
      (await client.from('parametro').select().order('clave'))
          .map(Parametro.fromJson)
          .toList();
  @override
  Future<void> actualizar(String clave, String valor) async {
    await client.rpc(
      'admin_actualizar_parametro',
      params: {'p_clave': clave, 'p_valor': valor},
    );
  }
}
