import 'package:nfc_foodtech_app/shared/models/resumen_indicadores.dart';

class MesResumenHogar {
  final DateTime mes;
  final PresentacionPerdidaEconomica perdida;

  final double? porcentajeDesperdicio;

  const MesResumenHogar(this.mes, this.perdida, this.porcentajeDesperdicio);
}

List<MesResumenHogar> calcularResumenHogar({
  required Map<String, Map<String, dynamic>> items,
  required List<Map<String, dynamic>> movimientos,
  required Map<int, Map<String, dynamic>> alimentos,
  required DateTime ahora,
}) {
  return List.generate(3, (indice) {
    final mes = DateTime(ahora.year, ahora.month - 2 + indice);
    final salidas = movimientos.where((movimiento) {
      final fecha = DateTime.tryParse('${movimiento['fecha']}')?.toLocal();
      return fecha != null &&
          fecha.year == mes.year &&
          fecha.month == mes.month;
    }).toList();
    final resumen = calcularIndicadores(
      itemsPorId: items,
      movimientos: salidas,
      alimentosPorId: alimentos,
      categoriasPorId: const {},
      motivosPorId: const {},
      ahora: mes,
    );
    final aprovechamiento = resumen.aprovechamientoMes;
    return MesResumenHogar(
      mes,
      PresentacionPerdidaEconomica(
        descartes: resumen.cantidadDescartes,
        descartesConPrecio: resumen.descartesConPrecio,
        costoConocido: resumen.costoConocido,
      ),
      aprovechamiento == null || !aprovechamiento.isFinite
          ? null
          : 100 - aprovechamiento,
    );
  });
}
