class Administrador {
  Administrador.fromJson(Map<String, dynamic> j)
    : id = j['perfil_id'] as String,
      email = j['email'] as String? ?? '—',
      nombre = j['nombre'] as String?,
      apellido = j['apellido'] as String?,
      estado = j['estado_cuenta'] as String,
      roles = List<String>.from(j['roles'] as List),
      mfa = j['mfa_activo'] as bool;
  final String id, email, estado;
  final String? nombre, apellido;
  final List<String> roles;
  final bool mfa;
  String get etiqueta {
    final name = [
      nombre,
      apellido,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
    return name.isEmpty ? email : name;
  }

  String get iniciales => etiqueta
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .take(2)
      .map((s) => s[0].toUpperCase())
      .join();
}

class RolAdministrativo {
  RolAdministrativo({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.permisos,
  });
  final int id;
  final String codigo, nombre;
  final List<String> permisos;
}

class AdministradoresData {
  AdministradoresData(this.administradores, this.roles);
  final List<Administrador> administradores;
  final List<RolAdministrativo> roles;
}
