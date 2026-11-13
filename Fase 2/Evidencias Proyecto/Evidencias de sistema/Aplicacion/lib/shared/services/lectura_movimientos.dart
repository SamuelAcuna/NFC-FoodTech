import 'package:supabase_flutter/supabase_flutter.dart';

class LecturaCancelada implements Exception {}

class LecturaMovimientos {
  final SupabaseClient cliente;
  final bool Function() vigente;
  final int tamanoPagina;

  LecturaMovimientos(this.cliente, this.vigente, {this.tamanoPagina = 500}) {
    if (tamanoPagina < 1 || tamanoPagina > 500) {
      throw ArgumentError.value(tamanoPagina, 'tamanoPagina');
    }
  }

  void comprobar() {
    if (!vigente()) throw LecturaCancelada();
  }

  Future<List<Map<String, dynamic>>> leer(
    String tabla,
    String columnas, {
    String? hogarId,
    String? columnaIds,
    List<Object>? ids,
    DateTime? desde,
    DateTime? hasta,
    List<String>? tipos,
  }) async {
    final resultado = <Map<String, dynamic>>[];
    final vistos = <Object>{};
    final unicos = ids?.toSet().toList();
    final lotes = unicos == null
        ? <List<Object>?>[null]
        : <List<Object>?>[
            for (var i = 0; i < unicos.length; i += 100)
              unicos.sublist(
                i,
                i + 100 > unicos.length ? unicos.length : i + 100,
              ),
          ];
    for (final lote in lotes) {
      Object? cursor;
      while (true) {
        comprobar();
        var consulta = cliente.from(tabla).select(columnas);
        if (hogarId != null) consulta = consulta.eq('hogar_id', hogarId);
        if (lote != null) consulta = consulta.inFilter(columnaIds!, lote);
        if (desde != null)
          consulta = consulta.gte('fecha', desde.toUtc().toIso8601String());
        if (hasta != null)
          consulta = consulta.lt('fecha', hasta.toUtc().toIso8601String());
        if (tipos != null) consulta = consulta.inFilter('tipo', tipos);
        if (cursor != null) consulta = consulta.gt('id', cursor);
        final pagina = await consulta
            .order('id', ascending: true)
            .limit(tamanoPagina)
            .timeout(const Duration(seconds: 15));
        comprobar();
        for (final fila in pagina) {
          final id = fila['id'];
          if (id == null || !vistos.add(id)) {
            throw StateError(
              'La consulta devolvió registros sin identificador o repetidos.',
            );
          }
          resultado.add(Map<String, dynamic>.from(fila));
        }
        if (pagina.isEmpty) break;
        cursor = pagina.last['id'] as Object;
      }
    }
    return resultado;
  }
}
