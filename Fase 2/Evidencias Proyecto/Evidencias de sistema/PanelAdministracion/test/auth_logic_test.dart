import 'dart:async';

import 'package:admin/core/errors/app_error.dart';
import 'package:admin/core/router/auth_redirect.dart';
import 'package:admin/features/auth/domain/admin_context.dart';
import 'package:admin/features/auth/presentation/auth_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_auth_repository.dart';

void main() {
  group('AdminContext unit tests', () {
    test(
      'Contexto RPC, conjuntos inmutables y permisos solo con acceso aal2',
      () {
        final c = AdminContext.fromJson({
          'tiene_rol': true,
          'aal': 'aal2',
          'estado_cuenta': 'ACTIVA',
          'roles': ['ADMIN', 'ADMIN'],
          'permisos': ['USUARIOS_VER', 'USUARIOS_VER'],
        });
        expect(c.roles, {'ADMIN'});
        expect(c.permisos.length, 1);
        expect(c.puede('USUARIOS_VER'), isTrue);
        expect(c.puede('OTRO'), isFalse);
        expect(() => c.permisos.add('OTRO'), throwsUnsupportedError);
        expect(adminContext(aal: 'aal1').puede('USUARIOS_VER'), isFalse);
        expect(adminContext(state: 'SUSPENDIDA').puede('USUARIOS_VER'), isFalse);
        expect(adminContext(role: false).puede('USUARIOS_VER'), isFalse);
        expect(AdminContext.fromJson({}).tieneAcceso, isFalse);
      },
    );

    test('fromJson maneja campos ausentes, nulos o con tipos inesperados', () {
      final vacio = AdminContext.fromJson({});
      expect(vacio.tieneRol, isFalse);
      expect(vacio.aal, '');
      expect(vacio.estadoCuenta, '');
      expect(vacio.roles, isEmpty);
      expect(vacio.permisos, isEmpty);
      expect(vacio.tieneAcceso, isFalse);
      expect(vacio.nombreRol, '');

      final conNulos = AdminContext.fromJson({
        'tiene_rol': null,
        'aal': null,
        'estado_cuenta': null,
        'roles': null,
        'permisos': null,
      });
      expect(conNulos.tieneRol, isFalse);
      expect(conNulos.aal, '');
      expect(conNulos.estadoCuenta, '');
      expect(conNulos.roles, isEmpty);
      expect(conNulos.permisos, isEmpty);
    });

    test('nombreRol formatea nombres conocidos y roles personalizados', () {
      expect(adminContext(roles: {'ADMIN'}).nombreRol, 'Administrador');
      expect(
        adminContext(roles: {'EDITOR_CATALOGO'}).nombreRol,
        'Editor de catálogo',
      );
      expect(adminContext(roles: {'SOPORTE'}).nombreRol, 'Soporte');
      expect(adminContext(roles: {'AUDITOR_EXTERNO'}).nombreRol, 'AUDITOR_EXTERNO');
      expect(
        adminContext(roles: {'ADMIN', 'SOPORTE'}).nombreRol,
        'Administrador, Soporte',
      );
    });
  });

  group('resolverRedireccion - Punto 3 de la spec', () {
    test('3.1: Sin sesión redirige siempre a /login (salvo si ya está en /login)', () {
      expect(resolverRedireccion(false, '', [], null, '/'), '/login');
      expect(resolverRedireccion(false, '', [], null, '/catalogo'), '/login');
      expect(resolverRedireccion(false, '', [], null, '/mfa/verificar'), '/login');
      expect(resolverRedireccion(false, '', [], null, '/mfa/enrolar'), '/login');
      expect(resolverRedireccion(false, '', [], null, '/login'), isNull);
    });

    test('3.2: Sesión aal1 redirige a /mfa/enrolar si no tiene factores TOTP verificados', () {
      final ctxAal1 = adminContext(aal: 'aal1');
      expect(resolverRedireccion(true, 'aal1', [], ctxAal1, '/'), '/mfa/enrolar');
      expect(resolverRedireccion(true, 'aal1', [], ctxAal1, '/catalogo'), '/mfa/enrolar');
      expect(resolverRedireccion(true, 'aal1', [], ctxAal1, '/login'), '/mfa/enrolar');
      expect(resolverRedireccion(true, 'aal1', [], ctxAal1, '/mfa/enrolar'), isNull);
    });

    test('3.2: Sesión aal1 redirige a /mfa/verificar si tiene factor TOTP verificado', () {
      final ctxAal1 = adminContext(aal: 'aal1');
      final factores = ['factor-totp-1'];
      expect(resolverRedireccion(true, 'aal1', factores, ctxAal1, '/'), '/mfa/verificar');
      expect(resolverRedireccion(true, 'aal1', factores, ctxAal1, '/catalogo'), '/mfa/verificar');
      expect(resolverRedireccion(true, 'aal1', factores, ctxAal1, '/login'), '/mfa/verificar');
      expect(resolverRedireccion(true, 'aal1', factores, ctxAal1, '/mfa/verificar'), isNull);
    });

    test('3.3: Sesión aal2 sin rol o estado_cuenta distinto de ACTIVA redirige a /login', () {
      final sinRol = adminContext(role: false);
      final suspendida = adminContext(state: 'SUSPENDIDA');
      final baneada = adminContext(state: 'BANEADA');
      expect(resolverRedireccion(true, 'aal2', ['f1'], sinRol, '/'), '/login');
      expect(resolverRedireccion(true, 'aal2', ['f1'], suspendida, '/catalogo'), '/login');
      expect(resolverRedireccion(true, 'aal2', ['f1'], baneada, '/'), '/login');
      expect(resolverRedireccion(true, 'aal2', ['f1'], null, '/'), '/login');
    });

    test('3.4: Sesión aal2 con rol que intenta ir a /login o /mfa/* se redirige a /', () {
      final adminValido = adminContext(aal: 'aal2');
      expect(resolverRedireccion(true, 'aal2', ['f1'], adminValido, '/login'), '/');
      expect(resolverRedireccion(true, 'aal2', ['f1'], adminValido, '/mfa/enrolar'), '/');
      expect(resolverRedireccion(true, 'aal2', ['f1'], adminValido, '/mfa/verificar'), '/');
    });

    test('3.4: Sesión aal2 con rol en rutas del shell se mantiene (retorna null)', () {
      final adminValido = adminContext(aal: 'aal2');
      expect(resolverRedireccion(true, 'aal2', ['f1'], adminValido, '/'), isNull);
      expect(resolverRedireccion(true, 'aal2', ['f1'], adminValido, '/catalogo'), isNull);
      expect(resolverRedireccion(true, 'aal2', ['f1'], adminValido, '/usuarios'), isNull);
      expect(resolverRedireccion(true, 'aal2', ['f1'], adminValido, '/soporte'), isNull);
    });
  });
  test('Redirect: sin sesión, denegado, aal1, aal2, rutas profundas', () {
    for (final route in ['/', '/catalogo', '/mfa/enrolar', '/mfa/verificar']) {
      expect(resolverRedireccion(false, '', [], null, route), '/login');
      expect(
        resolverRedireccion(true, 'aal2', [], adminContext(role: false), route),
        '/login',
      );
      expect(
        resolverRedireccion(
          true,
          'aal2',
          [],
          adminContext(state: 'BANEADA'),
          route,
        ),
        '/login',
      );
    }
    expect(resolverRedireccion(false, '', [], null, '/login'), isNull);
    for (final factors in [
      <String>[],
      ['verified'],
    ]) {
      final target = factors.isEmpty ? '/mfa/enrolar' : '/mfa/verificar';
      for (final route in ['/', '/catalogo', '/login']) {
        expect(
          resolverRedireccion(
            true,
            'aal1',
            factors,
            adminContext(aal: 'aal1'),
            route,
          ),
          target,
        );
      }
      expect(
        resolverRedireccion(
          true,
          'aal1',
          factors,
          adminContext(aal: 'aal1'),
          target,
        ),
        isNull,
      );
    }
    for (final route in ['/login', '/mfa/enrolar', '/mfa/verificar']) {
      expect(
        resolverRedireccion(true, 'aal2', ['factor'], adminContext(), route),
        '/',
      );
    }
    expect(
      resolverRedireccion(
        true,
        'aal2',
        ['factor'],
        adminContext(),
        '/catalogo',
      ),
      isNull,
    );
    expect(
      resolverRedireccion(
        true,
        'aal1',
        ['factor'],
        adminContext(),
        '/catalogo',
      ),
      '/mfa/verificar',
    );
    expect(
      resolverRedireccion(
        true,
        'aal2',
        ['factor'],
        adminContext(aal: 'aal1'),
        '/catalogo',
      ),
      '/mfa/verificar',
    );
  });
  test(
    'Controlador expulsa sin rol y suspendidos antes de habilitar shell',
    () async {
      for (final context in [
        adminContext(role: false),
        adminContext(state: 'SUSPENDIDA'),
      ]) {
        final repo = FakeAuthRepository()..contextOverride = context;
        final controller = AuthController(repo);
        await controller.refresh();
        expect(controller.canEnter, isFalse);
        expect(repo.logouts, 1);
        expect(
          controller.message,
          'Tu cuenta no tiene acceso al panel de administración.',
        );
        controller.dispose();
        await repo.events.close();
      }
    },
  );
  test(
    'Login, enrolamiento, verificación y logout recargan contexto',
    () async {
      final repo = FakeAuthRepository(hasSession: false, level: 'aal1')
        ..factors = [];
      final controller = AuthController(repo);
      await controller.refresh();
      expect(controller.canEnter, isFalse);
      await controller.login('admin@example.test', 'password');
      expect(controller.contexto?.aal, 'aal1');
      expect(controller.canEnter, isFalse);
      await controller.enroll();
      await controller.enroll();
      expect(repo.enrollments, 1);
      expect(controller.enrollment?.secret, 'TEST-SECRET');
      await controller.verify('new-factor', '123456');
      expect(controller.contexto?.aal, 'aal2');
      expect(controller.canEnter, isTrue);
      expect(controller.enrollment, isNull);
      await controller.logout();
      expect(controller.canEnter, isFalse);
      expect(controller.contexto, isNull);
      controller.dispose();
      await repo.events.close();
    },
  );
  test(
    'Código incorrecto no eleva sesión y nunca publica detalle crudo',
    () async {
      final repo = FakeAuthRepository(level: 'aal1')
        ..verifyError = const AuthException(
          'SECRET BACKEND',
          code: 'mfa_verification_failed',
        );
      final controller = AuthController(repo);
      await controller.refresh();
      await controller.verify('factor', '000000');
      expect(controller.canEnter, isFalse);
      expect(
        controller.message,
        'Código incorrecto o vencido, intenta de nuevo.',
      );
      controller.dispose();
      await repo.events.close();
    },
  );
  test('Sesión restaurada aal2 y evento signedOut retiran contexto', () async {
    final repo = FakeAuthRepository();
    final controller = AuthController(repo);
    await controller.refresh();
    expect(controller.canEnter, isTrue);
    repo.hasSession = false;
    controller.onAuthEvent(const AuthState(AuthChangeEvent.signedOut, null));
    expect(controller.contexto, isNull);
    expect(controller.canEnter, isFalse);
    controller.dispose();
    await repo.events.close();
  });
  test('Errores de credenciales, red y genéricos están saneados', () {
    expect(
      AppError.authMessage(
        const AuthException('raw', code: 'invalid_credentials'),
      ),
      'Correo o contraseña incorrectos.',
    );
    for (final error in [
      ClientException('host secreto'),
      TimeoutException('raw'),
      AuthRetryableFetchException(message: 'raw'),
    ]) {
      expect(
        AppError.authMessage(error),
        'No se pudo conectar. Revisa tu conexión.',
      );
    }
    expect(AppError.authMessage(Exception('raw')), isNot(contains('raw')));
  });
}
