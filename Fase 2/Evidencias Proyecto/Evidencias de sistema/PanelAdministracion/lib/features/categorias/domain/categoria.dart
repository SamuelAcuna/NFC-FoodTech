class Categoria {
  const Categoria({
    required this.id,
    required this.nombre,
    this.parentId,
    this.conservacion,
    this.despensaDias,
    this.refrigeradorDias,
    this.congeladorDias,
    this.activa = true,
  });
  factory Categoria.fromJson(Map<String, dynamic> json) => Categoria(
    id: (json['id'] as num).toInt(),
    nombre: json['nombre'] as String,
    parentId: (json['parent_id'] as num?)?.toInt(),
    conservacion: json['temp_conservacion'] as String?,
    despensaDias: (json['vida_util_dias_ref'] as num?)?.toInt(),
    refrigeradorDias: (json['vida_util_refrigerado_dias'] as num?)?.toInt(),
    congeladorDias: (json['vida_util_congelado_dias'] as num?)?.toInt(),
    activa: json['activa'] as bool? ?? true,
  );
  final int id;
  final String nombre;
  final int? parentId;
  final String? conservacion;
  final int? despensaDias;
  final int? refrigeradorDias;
  final int? congeladorDias;
  final bool activa;
  String get conservacionLabel => switch (conservacion) {
    'AMBIENTE' => 'Ambiente',
    'REFRIGERADO' => 'Refrigerado',
    'CONGELADO' => 'Congelado',
    _ => 'Sin definir',
  };
}

String? validarDias(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final days = int.tryParse(text);
  if (!RegExp(r'^\d+$').hasMatch(text) ||
      days == null ||
      days < 1 ||
      days > 3650) {
    return 'Ingresa un entero de 1 a 3650 o deja vacío.';
  }
  return null;
}

int? diasDesdeTexto(String value) =>
    value.trim().isEmpty ? null : int.parse(value.trim());
String? validarNombre(String? value) {
  final length = value?.trim().runes.length ?? 0;
  return length < 2 || length > 60
      ? 'Ingresa un nombre de 2 a 60 caracteres.'
      : null;
}

List<Categoria> ordenarArbol(List<Categoria> categorias) {
  final sorted = [...categorias]
    ..sort((a, b) {
      final byName = a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      return byName == 0 ? a.id.compareTo(b.id) : byName;
    });
  final roots = sorted.where((c) => c.parentId == null);
  final result = <Categoria>[];
  for (final root in roots) {
    result.add(root);
    result.addAll(sorted.where((c) => c.parentId == root.id));
  }
  final ids = result.map((c) => c.id).toSet();
  // Conserva visibles datos huérfanos antiguos; el trigger valida las escrituras.
  result.addAll(sorted.where((c) => !ids.contains(c.id)));
  return result;
}
