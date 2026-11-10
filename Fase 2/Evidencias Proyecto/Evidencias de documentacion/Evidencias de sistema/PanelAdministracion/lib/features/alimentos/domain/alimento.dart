import '../../categorias/domain/categoria.dart';

class Alimento {
  const Alimento({
    required this.id,
    required this.nombre,
    required this.categoriaId,
    this.vidaUtilDiasRef,
    required this.unidadBase,
    required this.esPerecible,
    required this.activo,
  });
  factory Alimento.fromJson(Map<String, dynamic> json) => Alimento(
    id: (json['id'] as num).toInt(),
    nombre: json['nombre'] as String,
    categoriaId: (json['categoria_id'] as num).toInt(),
    vidaUtilDiasRef: (json['vida_util_dias_ref'] as num?)?.toInt(),
    unidadBase: json['unidad_base'] as String,
    esPerecible: json['es_perecible'] as bool,
    activo: json['activo'] as bool,
  );
  final int id;
  final String nombre;
  final int categoriaId;
  final int? vidaUtilDiasRef;
  final String unidadBase;
  final bool esPerecible;
  final bool activo;
  String get unidadLabel => switch (unidadBase) {
    'g' => 'Gramo',
    'ml' => 'Mililitro',
    'un' => 'Unidad',
    _ => unidadBase,
  };
}

String normalizarBusqueda(String text) {
  const accents = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  return text
      .toLowerCase()
      .split('')
      .map((c) => accents[c] ?? c)
      .join()
      .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
      .trim();
}

String? validarNombreAlimento(String? text) {
  final length = text?.trim().runes.length ?? 0;
  return length < 2 || length > 80
      ? 'Ingresa un nombre de 2 a 80 caracteres.'
      : null;
}

String nombreCategoria(int id, List<Categoria> categorias) {
  final byId = {for (final c in categorias) c.id: c};
  final c = byId[id];
  if (c == null) return 'Categoría no disponible';
  final parent = byId[c.parentId];
  return parent == null ? c.nombre : '${parent.nombre} › ${c.nombre}';
}

List<Alimento> filtrarAlimentos(
  List<Alimento> alimentos,
  List<Categoria> categorias, {
  String busqueda = '',
  int? categoriaId,
  bool? activo = true,
}) {
  final ids = {
    ?categoriaId,
    for (final c in categorias)
      if (c.parentId == categoriaId && categoriaId != null) c.id,
  };
  final query = normalizarBusqueda(busqueda);
  return alimentos
      .where(
        (a) =>
            normalizarBusqueda(a.nombre).contains(query) &&
            (categoriaId == null || ids.contains(a.categoriaId)) &&
            (activo == null || a.activo == activo),
      )
      .toList();
}
