import 'dart:async';

import 'package:admin/features/auth/data/auth_repository.dart';
import 'package:admin/features/auth/domain/admin_context.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const allPermissions = {
  'CATEGORIAS_GESTIONAR',
  'CATALOGO_GESTIONAR',
  'PROPUESTOS_REVISAR',
  'PARAMETROS_GESTIONAR',
  'USUARIOS_VER',
  'USUARIOS_SUSPENDER',
  'HOGARES_VER',
  'SOPORTE_GESTIONAR',
  'ROLES_GESTIONAR',
  'AUDITORIA_VER',
  'REPORTES_VER',
};
AdminContext adminContext({
  String aal = 'aal2',
  bool role = true,
  String state = 'ACTIVA',
  Set<String> roles = const {'ADMIN'},
  Set<String> permissions = allPermissions,
}) => AdminContext(
  tieneRol: role,
  aal: aal,
  estadoCuenta: state,
  roles: roles,
  permisos: permissions,
);

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.hasSession = true, this.level = 'aal2'});
  @override
  bool hasSession;
  @override
  String? get userId =>
      hasSession ? '00000000-0000-0000-0000-000000000004' : null;
  String level;
  AdminContext? contextOverride;
  List<String> factors = ['factor-1'];
  Object? loginError;
  Object? verifyError;
  Completer<void>? loginWait;
  Completer<void>? verifyWait;
  int logins = 0;
  int logouts = 0;
  int verifications = 0;
  int enrollments = 0;
  final events = StreamController<AuthState>.broadcast();
  @override
  String get userLabel => 'Admin Demo';
  @override
  Stream<AuthState> get onAuthStateChange => events.stream;
  @override
  Future<void> login(String email, String password) async {
    logins++;
    await loginWait?.future;
    if (loginError != null) throw loginError!;
    hasSession = true;
  }

  @override
  Future<void> logout() async {
    logouts++;
    hasSession = false;
  }

  @override
  Future<AdminContext> obtenerContexto() async =>
      contextOverride ?? adminContext(aal: level);
  @override
  Future<List<String>> listarFactores() async => factors;
  @override
  Future<TotpEnrollment> enrolarTotp() async {
    enrollments++;
    return const TotpEnrollment(
      factorId: 'new-factor',
      secret: 'TEST-SECRET',
      qrCode: '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect width="20" height="20"/></svg>',
    );
  }

  @override
  Future<void> verificarTotp(String factorId, String code) async {
    verifications++;
    await verifyWait?.future;
    if (verifyError != null) throw verifyError!;
    level = 'aal2';
    factors = [factorId];
  }

  @override
  String nivelAal() => level;
}
