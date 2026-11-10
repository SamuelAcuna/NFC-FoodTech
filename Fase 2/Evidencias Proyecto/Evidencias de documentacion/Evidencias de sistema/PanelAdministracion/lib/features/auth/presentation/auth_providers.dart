import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../data/auth_repository.dart';
import '../domain/admin_context.dart';

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authRepositoryProvider).onAuthStateChange,
);
final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  final controller = AuthController(ref.watch(authRepositoryProvider));
  ref.listen(authStateProvider, (_, next) {
    next.whenData(controller.onAuthEvent);
  });
  unawaited(controller.refresh());
  return controller;
});
final adminContextProvider = Provider<AdminContext?>(
  (ref) => ref.watch(authControllerProvider).contexto,
);
final puedeProvider = Provider<bool Function(String)>((ref) {
  final context = ref.watch(adminContextProvider);
  return (permiso) => context?.puede(permiso) ?? false;
});

class AuthController extends ChangeNotifier {
  AuthController(this.repository);
  final AuthRepository repository;
  AdminContext? contexto;
  List<String> factores = [];
  TotpEnrollment? enrollment;
  String? message;
  bool busy = false;
  bool ready = false;
  bool _disposed = false;
  int _revision = 0;
  String get aal => repository.nivelAal();
  bool get hasSession => repository.hasSession;
  bool get canEnter =>
      ready &&
      hasSession &&
      contexto?.tieneAcceso == true &&
      contexto?.aal == 'aal2' &&
      aal == 'aal2';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void onAuthEvent(AuthState event) {
    if (event.event == AuthChangeEvent.signedOut) {
      _revision++;
      contexto = null;
      factores = [];
      enrollment = null;
      ready = true;
      _notify();
    } else if (!busy) {
      unawaited(refresh());
    }
  }

  Future<void> _load(int revision) async {
    if (!hasSession) {
      contexto = null;
      factores = [];
      enrollment = null;
      ready = true;
      return;
    }
    final context = await repository.obtenerContexto();
    if (revision != _revision || _disposed) return;
    if (!context.tieneAcceso) {
      contexto = null;
      enrollment = null;
      factores = [];
      message = 'Tu cuenta no tiene acceso al panel de administración.';
      await repository.logout();
      ready = true;
      return;
    }
    final factors = await repository.listarFactores();
    // listFactors refresca el token; leer de nuevo el contexto con ese token.
    final refreshed = await repository.obtenerContexto();
    if (revision != _revision || _disposed) return;
    if (!refreshed.tieneAcceso) {
      contexto = null;
      message = 'Tu cuenta no tiene acceso al panel de administración.';
      await repository.logout();
      ready = true;
      return;
    }
    contexto = refreshed;
    factores = factors;
    ready = true;
  }

  Future<void> refresh() async {
    if (busy || _disposed) return;
    busy = true;
    ready = false;
    final revision = ++_revision;
    _notify();
    try {
      await _load(revision);
    } catch (error) {
      contexto = null;
      ready = true;
      message = AppError.message(error);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> login(String email, String password) => _run(() async {
    contexto = null;
    enrollment = null;
    ready = false;
    await repository.login(email, password);
    await _load(_revision);
  }, login: true);

  Future<void> enroll() => _run(() async {
    if (contexto?.tieneAcceso != true || !hasSession) return;
    enrollment ??= await repository.enrolarTotp();
  });

  Future<void> verify(String factorId, String code) => _run(() async {
    await repository.verificarTotp(factorId, code);
    enrollment = null;
    ready = false;
    await _load(_revision);
  }, mfa: true);

  Future<void> logout() => _run(() async {
    // Retira el acceso al shell antes de esperar la respuesta de red.
    contexto = null;
    enrollment = null;
    factores = [];
    ready = true;
    _notify();
    await repository.logout();
  });

  Future<void> _run(
    Future<void> Function() action, {
    bool login = false,
    bool mfa = false,
  }) async {
    if (busy || _disposed) return;
    busy = true;
    message = null;
    ++_revision;
    _notify();
    try {
      await action();
    } catch (error) {
      message = AppError.authMessage(error, login: login, mfa: mfa);
    } finally {
      busy = false;
      ready = true;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_revision;
    super.dispose();
  }
}
