import 'package:admin/features/dashboard/data/dashboard_repository.dart';
import 'package:admin/features/dashboard/domain/dashboard_data.dart';

Map<String, dynamic> dashboardJson({bool empty = true}) => {
  'usuarios_registrados': 10,
  'usuarios_activos_30d': 3,
  'usuarios_suspendidos': 1,
  'hogares_registrados': 4,
  'alimentos_catalogo': 20,
  'propuestos_pendientes': 2,
  'solicitudes_abiertas': 5,
  'aprovechamiento': [
    for (var i = 5; i <= 10; i++)
      {
        'mes': '2026-${i.toString().padLeft(2, '0')}',
        'consumos': empty ? 0 : 3,
        'descartes': empty ? 0 : 1,
      },
  ],
};

class FakeDashboardRepository implements DashboardRepository {
  FakeDashboardRepository({this.empty = true});
  final bool empty;
  @override
  Future<DashboardData> cargar() async =>
      DashboardData.fromJson(dashboardJson(empty: empty));
}
