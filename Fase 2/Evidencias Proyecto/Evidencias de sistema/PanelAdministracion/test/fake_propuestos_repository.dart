import 'package:admin/features/propuestos/data/propuestos_repository.dart';
import 'package:admin/features/propuestos/domain/propuesta.dart';

class FakePropuestosRepository implements PropuestosRepository {
  List<Propuesta> items = [
    Propuesta(
      id: 10,
      nombre: 'Plátano sugerido',
      categoriaId: 2,
      unidadBase: 'un',
      esPerecible: true,
      vidaUtilDiasRef: 5,
      hogarRef: 'hogar_abcdef',
      propuestoEn: DateTime(2026, 10, 19),
    ),
  ];
  final approvals = <Map<String, dynamic>>[];
  final rejections = <int>[];
  int countCalls = 0;
  int listCalls = 0;
  Object? approveError;
  Object? rejectError;
  Object? countError;
  @override
  Future<List<Propuesta>> listar() async {
    listCalls++;
    return List.of(items);
  }

  @override
  Future<int> contar() async {
    countCalls++;
    if (countError != null) throw countError!;
    return items.length;
  }

  @override
  Future<int> aprobar({
    required int id,
    required String nombre,
    required int categoriaId,
    required String unidadBase,
    required bool esPerecible,
    int? vidaUtilDiasRef,
  }) async {
    if (approveError != null) throw approveError!;
    approvals.add({
      'p_id': id,
      'p_nombre': nombre,
      'p_categoria_id': categoriaId,
      'p_unidad_base': unidadBase,
      'p_es_perecible': esPerecible,
      'p_vida_util_dias_ref': vidaUtilDiasRef,
    });
    items.removeWhere((p) => p.id == id);
    return id;
  }

  @override
  Future<void> rechazar(int id) async {
    if (rejectError != null) throw rejectError!;
    rejections.add(id);
    items.removeWhere((p) => p.id == id);
  }
}
