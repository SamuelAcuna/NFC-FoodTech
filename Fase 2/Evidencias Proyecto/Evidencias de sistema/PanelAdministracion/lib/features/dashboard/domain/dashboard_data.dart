class MesAprovechamiento {
  MesAprovechamiento.fromJson(Map<String, dynamic> j)
    : mes = j['mes'] as String,
      consumos = (j['consumos'] as num).toInt(),
      descartes = (j['descartes'] as num).toInt();
  final String mes;
  final int consumos, descartes;
  double? get porcentaje =>
      consumos + descartes == 0 ? null : consumos / (consumos + descartes);
  String get etiqueta => const [
    'Ene',
    'Feb',
    'Mar',
    'Abr',
    'May',
    'Jun',
    'Jul',
    'Ago',
    'Sep',
    'Oct',
    'Nov',
    'Dic',
  ][int.parse(mes.substring(5)) - 1];
}

class DashboardData {
  DashboardData.fromJson(Map<String, dynamic> j)
    : usuarios = (j['usuarios_registrados'] as num).toInt(),
      activos = (j['usuarios_activos_30d'] as num).toInt(),
      suspendidos = (j['usuarios_suspendidos'] as num).toInt(),
      hogares = (j['hogares_registrados'] as num).toInt(),
      catalogo = (j['alimentos_catalogo'] as num).toInt(),
      propuestos = (j['propuestos_pendientes'] as num).toInt(),
      solicitudes = (j['solicitudes_abiertas'] as num).toInt(),
      meses = (j['aprovechamiento'] as List)
          .map(
            (m) => MesAprovechamiento.fromJson(
              Map<String, dynamic>.from(m as Map),
            ),
          )
          .toList();
  final int usuarios,
      activos,
      suspendidos,
      hogares,
      catalogo,
      propuestos,
      solicitudes;
  final List<MesAprovechamiento> meses;
}
