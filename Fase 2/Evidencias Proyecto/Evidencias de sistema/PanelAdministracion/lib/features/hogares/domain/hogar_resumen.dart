class HogarResumen {
  HogarResumen.fromJson(Map<String, dynamic> j)
    : ref = j['hogar_ref'] as String,
      nombre = j['nombre'] as String,
      comuna = j['comuna'] as String?,
      region = j['region'] as String?,
      integrantes = j['integrantes'] as int,
      invitados = j['invitados'] as int,
      adultos = j['adultos'] as int?,
      menores = j['menores'] as int?,
      creado = DateTime.parse(j['creado_en'] as String),
      movimientos = j['movimientos_30d'] as int,
      ultimo = j['ultimo_movimiento'] == null
          ? null
          : DateTime.parse(j['ultimo_movimiento'] as String),
      productos = j['productos_disponibles'] as int,
      nivel = j['nivel_actividad'] as String,
      total = j['total'] as int;
  final String ref, nombre, nivel;
  final String? comuna, region;
  final int integrantes, invitados, movimientos, productos, total;
  final int? adultos, menores;
  final DateTime creado;
  final DateTime? ultimo;
}
