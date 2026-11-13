class AdminContext {
  AdminContext({
    required this.tieneRol,
    required this.aal,
    required this.estadoCuenta,
    required Set<String> roles,
    required Set<String> permisos,
  }) : roles = Set.unmodifiable(roles),
       permisos = Set.unmodifiable(permisos);

  factory AdminContext.fromJson(Map<String, dynamic> json) => AdminContext(
    tieneRol: json['tiene_rol'] == true,
    aal: json['aal'] as String? ?? '',
    estadoCuenta: json['estado_cuenta'] as String? ?? '',
    roles: (json['roles'] as List? ?? []).cast<String>().toSet(),
    permisos: (json['permisos'] as List? ?? []).cast<String>().toSet(),
  );

  final bool tieneRol;
  final String aal;
  final String estadoCuenta;
  final Set<String> roles;
  final Set<String> permisos;
  bool get tieneAcceso => tieneRol && estadoCuenta == 'ACTIVA';
  bool puede(String permiso) =>
      tieneAcceso && aal == 'aal2' && permisos.contains(permiso);
  String get nombreRol => roles
      .map(
        (rol) => switch (rol) {
          'ADMIN' => 'Administrador',
          'EDITOR_CATALOGO' => 'Editor de catálogo',
          'SOPORTE' => 'Soporte',
          _ => rol,
        },
      )
      .join(', ');
}

class TotpEnrollment {
  const TotpEnrollment({
    required this.factorId,
    required this.qrCode,
    required this.secret,
  });
  final String factorId;
  final String qrCode;
  final String secret;
}
