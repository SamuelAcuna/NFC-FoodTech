import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/client.dart';
import '../domain/reporte.dart';

abstract class ReportesRepository {
  Future<List<UsoPeriodo>> uso(String desde, String hasta, String agrupacion);
  Future<List<DesperdicioPeriodo>> desperdicio(
    String desde,
    String hasta,
    String agrupacion,
  );
}

final reportesRepositoryProvider = Provider<ReportesRepository>(
  (ref) => SupabaseReportesRepository(ref.watch(supabaseClientProvider)),
);

class SupabaseReportesRepository implements ReportesRepository {
  SupabaseReportesRepository(this.client);
  final SupabaseClient client;
  Future<List<Map<String, dynamic>>> fetch(
    String name,
    String desde,
    String hasta,
    String agrupacion,
  ) async {
    final result = await client.rpc(
      name,
      params: {'p_desde': desde, 'p_hasta': hasta, 'p_agrupacion': agrupacion},
    );
    return (result as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  @override
  Future<List<UsoPeriodo>> uso(
    String desde,
    String hasta,
    String agrupacion,
  ) async => (await fetch(
    'admin_reporte_uso',
    desde,
    hasta,
    agrupacion,
  )).map(UsoPeriodo.fromJson).toList();
  @override
  Future<List<DesperdicioPeriodo>> desperdicio(
    String desde,
    String hasta,
    String agrupacion,
  ) async => (await fetch(
    'admin_reporte_desperdicio',
    desde,
    hasta,
    agrupacion,
  )).map(DesperdicioPeriodo.fromJson).toList();
}
