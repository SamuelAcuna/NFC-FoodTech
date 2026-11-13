import 'package:intl/intl.dart';

const reporteMessages = {
  'El rango de fechas no es válido.',
  'El rango no puede superar 366 días.',
  'La agrupación no es válida.',
};
String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String periodoLabel(DateTime d, String agrupacion) => agrupacion == 'MES'
    ? DateFormat('MMM yyyy', 'es_CL').format(d)
    : 'Sem. ${DateFormat('dd-MM-yyyy').format(d)}';
String porcentaje(num? n) =>
    n == null ? '—' : '${n.toStringAsFixed(1).replaceAll('.', ',')}%';
String? validateReporte(DateTime desde, DateTime hasta, String agrupacion) {
  if (desde.isAfter(hasta)) {
    return 'El rango de fechas no es válido.';
  }
  final days =
      DateTime.utc(
        hasta.year,
        hasta.month,
        hasta.day,
      ).difference(DateTime.utc(desde.year, desde.month, desde.day)).inDays +
      1;
  if (days > 366) {
    return 'El rango no puede superar 366 días.';
  }
  if (!['MES', 'SEMANA'].contains(agrupacion)) {
    return 'La agrupación no es válida.';
  }
  return null;
}

class UsoPeriodo {
  UsoPeriodo.fromJson(Map<String, dynamic> j)
    : periodo = DateTime.parse(j['periodo'] as String),
      altas = j['altas'] as int,
      activos = j['usuarios_activos'] as int,
      retencion = j['retencion_pct'] == null
          ? null
          : num.parse('${j['retencion_pct']}'),
      productos = j['productos_registrados'] as int,
      alertas = j['alertas_emitidas'] as int;
  final DateTime periodo;
  final int altas, activos, productos, alertas;
  final num? retencion;
}

class DesperdicioPeriodo {
  DesperdicioPeriodo.fromJson(Map<String, dynamic> j)
    : periodo = DateTime.parse(j['periodo'] as String),
      categoria = j['categoria'] as String,
      descartes = j['descartes'] as int,
      hogares = j['hogares'] as int;
  final DateTime periodo;
  final String categoria;
  final int descartes, hogares;
}
