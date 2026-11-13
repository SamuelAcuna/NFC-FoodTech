class UsuarioAdmin {
  UsuarioAdmin.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      email = j['email'] as String? ?? '—',
      nombre = j['nombre'] as String?,
      apellido = j['apellido'] as String?,
      estado = j['estado_cuenta'] as String,
      hogar = j['hogar_nombre'] as String?,
      rolHogar = j['rol_hogar'] as String?,
      registro = DateTime.parse(j['registrado_en'] as String),
      acceso = j['ultimo_acceso'] == null
          ? null
          : DateTime.parse(j['ultimo_acceso'] as String),
      esAdministrador = j['es_administrador'] as bool,
      total = (j['total'] as num).toInt();
  final String id, email, estado;
  final String? nombre, apellido, hogar, rolHogar;
  final DateTime registro;
  final DateTime? acceso;
  final bool esAdministrador;
  final int total;
  String get etiqueta =>
      [nombre, apellido]
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .join(' ')
          .trim()
          .isEmpty
      ? email
      : [
          nombre,
          apellido,
        ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
  String get iniciales => etiqueta
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .take(2)
      .map((s) => s[0].toUpperCase())
      .join();
}
