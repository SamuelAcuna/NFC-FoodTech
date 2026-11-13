import 'package:admin/features/categorias/data/categorias_repository.dart';
import 'package:admin/features/categorias/domain/categoria.dart';

class FakeCategoriasRepository implements CategoriasRepository {
  List<Categoria> items = [
    const Categoria(id: 1, nombre: 'Frutas'),
    const Categoria(
      id: 2,
      nombre: 'Cítricos',
      parentId: 1,
      conservacion: 'REFRIGERADO',
    ),
    const Categoria(id: 3, nombre: 'Verduras', activa: false),
  ];
  Map<int, int>? counts;
  Object? deleteError;
  Object? saveError;
  int saves = 0;
  int deletes = 0;
  int durationSaves = 0;
  @override
  Future<List<Categoria>> listar() async => List.of(items);
  @override
  Future<Map<int, int>?> contarAlimentos() async => counts;
  @override
  Future<void> guardar({
    int? id,
    required String nombre,
    int? parentId,
    String? conservacion,
  }) async {
    if (saveError != null) throw saveError!;
    saves++;
    if (id == null) {
      items.add(
        Categoria(
          id: 100 + saves,
          nombre: nombre,
          parentId: parentId,
          conservacion: conservacion,
        ),
      );
    } else {
      final c = items.firstWhere((c) => c.id == id);
      items = [
        for (final item in items)
          if (item.id != id)
            item
          else
            Categoria(
              id: id,
              nombre: nombre,
              parentId: parentId,
              conservacion: conservacion,
              activa: c.activa,
              despensaDias: c.despensaDias,
              refrigeradorDias: c.refrigeradorDias,
              congeladorDias: c.congeladorDias,
            ),
      ];
    }
  }

  @override
  Future<void> cambiarEstado(int id, bool activa) async {
    items = [
      for (final c in items)
        if (c.id != id)
          c
        else
          Categoria(
            id: c.id,
            nombre: c.nombre,
            parentId: c.parentId,
            conservacion: c.conservacion,
            activa: activa,
            despensaDias: c.despensaDias,
            refrigeradorDias: c.refrigeradorDias,
            congeladorDias: c.congeladorDias,
          ),
    ];
  }

  @override
  Future<void> eliminar(int id) async {
    if (deleteError != null) throw deleteError!;
    deletes++;
    items.removeWhere((c) => c.id == id);
  }

  @override
  Future<void> guardarDuraciones(
    int id, {
    int? despensa,
    int? refrigerador,
    int? congelador,
  }) async {
    durationSaves++;
    items = [
      for (final c in items)
        if (c.id != id)
          c
        else
          Categoria(
            id: c.id,
            nombre: c.nombre,
            parentId: c.parentId,
            conservacion: c.conservacion,
            activa: c.activa,
            despensaDias: despensa,
            refrigeradorDias: refrigerador,
            congeladorDias: congelador,
          ),
    ];
  }
}
