import 'package:admin/features/alimentos/data/alimentos_repository.dart';
import 'package:admin/features/alimentos/domain/alimento.dart';

class FakeAlimentosRepository implements AlimentosRepository {
  List<Alimento> items = [
    const Alimento(
      id: 1,
      nombre: 'Plátano',
      categoriaId: 1,
      unidadBase: 'un',
      esPerecible: true,
      activo: true,
    ),
    const Alimento(
      id: 2,
      nombre: 'Limón',
      categoriaId: 2,
      unidadBase: 'g',
      esPerecible: true,
      activo: true,
      vidaUtilDiasRef: 5,
    ),
    const Alimento(
      id: 3,
      nombre: 'Arroz',
      categoriaId: 3,
      unidadBase: 'g',
      esPerecible: false,
      activo: false,
    ),
  ];
  final saves = <Map<String, dynamic>>[];
  final toggles = <bool>[];
  int deletes = 0;
  Object? saveError;
  Object? deleteError;
  @override
  Future<List<Alimento>> listar() async => List.of(items);
  @override
  Future<void> guardar({
    int? id,
    required String nombre,
    required int categoriaId,
    required String unidadBase,
    required bool esPerecible,
    int? vidaUtilDiasRef,
  }) async {
    if (saveError != null) throw saveError!;
    saves.add({
      'id': id,
      'nombre': nombre,
      'categoria_id': categoriaId,
      'unidad_base': unidadBase,
      'es_perecible': esPerecible,
      'vida_util_dias_ref': vidaUtilDiasRef,
    });
    final current = id == null ? null : items.firstWhere((a) => a.id == id);
    final value = Alimento(
      id: id ?? 100 + saves.length,
      nombre: nombre,
      categoriaId: categoriaId,
      unidadBase: unidadBase,
      esPerecible: esPerecible,
      vidaUtilDiasRef: vidaUtilDiasRef,
      activo: current?.activo ?? true,
    );
    if (id == null) {
      items.add(value);
    } else {
      items = [
        for (final a in items)
          if (a.id == id) value else a,
      ];
    }
  }

  @override
  Future<void> cambiarEstado(int id, bool activo) async {
    toggles.add(activo);
    items = [
      for (final a in items)
        if (a.id != id)
          a
        else
          Alimento(
            id: a.id,
            nombre: a.nombre,
            categoriaId: a.categoriaId,
            unidadBase: a.unidadBase,
            esPerecible: a.esPerecible,
            vidaUtilDiasRef: a.vidaUtilDiasRef,
            activo: activo,
          ),
    ];
  }

  @override
  Future<void> eliminar(int id) async {
    if (deleteError != null) throw deleteError!;
    deletes++;
    items.removeWhere((a) => a.id == id);
  }
}
