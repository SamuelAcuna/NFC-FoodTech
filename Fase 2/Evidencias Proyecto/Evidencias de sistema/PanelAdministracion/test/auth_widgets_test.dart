import 'package:admin/features/dashboard/data/dashboard_repository.dart';
import 'fake_dashboard_repository.dart';
import 'package:admin/features/propuestos/data/propuestos_repository.dart';
import 'fake_propuestos_repository.dart';
import 'package:admin/features/alimentos/data/alimentos_repository.dart';
import 'package:admin/features/categorias/data/categorias_repository.dart';
import 'fake_alimentos_repository.dart';
import 'fake_categorias_repository.dart';
import 'dart:async';

import 'package:admin/app.dart';
import 'package:admin/core/widgets/admin_shell.dart';
import 'package:admin/features/auth/data/auth_repository.dart';
import 'package:admin/features/auth/presentation/auth_providers.dart';
import 'package:admin/features/auth/presentation/login_page.dart';
import 'package:admin/features/auth/presentation/mfa_enroll_page.dart';
import 'package:admin/features/auth/presentation/mfa_verify_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_auth_repository.dart';

Widget app(FakeAuthRepository repo, {Widget? page}) => ProviderScope(
  overrides: [
    dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),authRepositoryProvider.overrideWithValue(repo),
    alimentosRepositoryProvider.overrideWithValue(FakeAlimentosRepository()),
        propuestosRepositoryProvider.overrideWithValue(FakePropuestosRepository()),
    categoriasRepositoryProvider.overrideWithValue(FakeCategoriasRepository()),],
  child: page == null ? const AdminApp() : MaterialApp(home: page),
);

void main() {
  testWidgets('Login valida correo y contraseña; spinner evita doble llamada', (
    tester,
  ) async {
    final repo = FakeAuthRepository(hasSession: false)
      ..loginWait = Completer<void>();
    addTearDown(repo.events.close);
    await tester.pumpWidget(app(repo, page: const LoginPage()));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));
    await tester.tap(find.text('Acceder al panel'));
    await tester.pump();
    expect(find.text('Ingresa un correo válido.'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña.'), findsOneWidget);
    expect(repo.logins, 0);
    await tester.enterText(
      find.byType(TextFormField).first,
      'admin@example.test',
    );
    await tester.enterText(find.byType(TextFormField).last, 'password');
    await tester.tap(find.text('Acceder al panel'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(repo.logins, 1);
    repo.loginWait!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Login rechaza formatos de correo inválidos y muestra error del controlador', (
    tester,
  ) async {
    final repo = FakeAuthRepository(hasSession: false)
      ..loginError = const AuthException(
        'Invalid login credentials',
        code: 'invalid_credentials',
      );
    addTearDown(repo.events.close);
    await tester.pumpWidget(app(repo, page: const LoginPage()));
    await tester.pumpAndSettle();

    // Probar correo sin dominio completo
    await tester.enterText(find.byType(TextFormField).first, 'admin@invalido');
    await tester.enterText(find.byType(TextFormField).last, 'pass123');
    await tester.tap(find.text('Acceder al panel'));
    await tester.pump();
    expect(find.text('Ingresa un correo válido.'), findsOneWidget);
    expect(repo.logins, 0);

    // Corregir a formato válido pero con credenciales erróneas
    await tester.enterText(find.byType(TextFormField).first, 'admin@dominio.cl');
    await tester.tap(find.text('Acceder al panel'));
    await tester.pumpAndSettle();
    expect(repo.logins, 1);
    expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
  });

  testWidgets('MFA spinner deshabilita botón durante llamada y muestra error si falla', (
    tester,
  ) async {
    final repo = FakeAuthRepository(level: 'aal1')
      ..verifyWait = Completer<void>()
      ..verifyError = const AuthException(
        'Code expired',
        code: 'mfa_verification_failed',
      );
    addTearDown(repo.events.close);
    await tester.pumpWidget(app(repo, page: const MfaVerifyPage()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('Verificar y entrar'));
    await tester.pump();

    // Spinner activo y botón deshabilitado
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(repo.verifications, 1);

    repo.verifyWait!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('Código incorrecto o vencido, intenta de nuevo.'),
      findsOneWidget,
    );
  });

  testWidgets('MFA permite cerrar sesión y ejecuta logout', (tester) async {
    final repo = FakeAuthRepository(level: 'aal1');
    addTearDown(repo.events.close);
    await tester.pumpWidget(app(repo, page: const MfaVerifyPage()));
    await tester.pumpAndSettle();

    expect(find.text('Cerrar sesión'), findsOneWidget);
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(repo.logouts, 1);
  });

  testWidgets('MFA rechaza código corto y verifica seis dígitos', (
    tester,
  ) async {
    final repo = FakeAuthRepository(level: 'aal1');
    addTearDown(repo.events.close);
    await tester.pumpWidget(app(repo, page: const MfaVerifyPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '12345');
    await tester.tap(find.text('Verificar y entrar'));
    await tester.pump();
    expect(find.text('Ingresa un código de 6 dígitos.'), findsOneWidget);
    expect(repo.verifications, 0);
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('Verificar y entrar'));
    await tester.pumpAndSettle();
    expect(repo.verifications, 1);
    expect(repo.level, 'aal2');
  });
  testWidgets('Guard nunca muestra shell a cuenta sin rol', (tester) async {
    final repo = FakeAuthRepository()
      ..contextOverride = adminContext(role: false);
    addTearDown(repo.events.close);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    expect(find.byType(AdminShell), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(
      find.text('Tu cuenta no tiene acceso al panel de administración.'),
      findsOneWidget,
    );
    expect(repo.logouts, 1);
  });
  testWidgets('URL catálogo aal1 obliga MFA y logout impide volver al shell', (
    tester,
  ) async {
    final repo = FakeAuthRepository(level: 'aal1');
    addTearDown(repo.events.close);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(MfaVerifyPage)));
    router.go('/catalogo');
    await tester.pumpAndSettle();
    expect(find.byType(MfaVerifyPage), findsOneWidget);
    expect(find.byType(AdminShell), findsNothing);
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('Verificar y entrar'));
    await tester.pumpAndSettle();
    expect(find.byType(AdminShell), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    router.go('/catalogo');
    await tester.pumpAndSettle();
    expect(find.byType(AdminShell), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
  });
  testWidgets(
    'EDITOR_CATALOGO oculta menú no autorizado y muestra usuario real',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeAuthRepository()
        ..contextOverride = adminContext(
          roles: {'EDITOR_CATALOGO'},
          permissions: {
            'CATEGORIAS_GESTIONAR',
            'CATALOGO_GESTIONAR',
            'PROPUESTOS_REVISAR',
            'PARAMETROS_GESTIONAR',
          },
        );
      addTearDown(repo.events.close);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      for (final title in [
        'Usuarios y hogares',
        'Soporte',
        'Administradores',
        'Auditoría y monitoreo',
      ]) {
        expect(find.text(title), findsNothing);
      }
      expect(find.text('Catálogo'), findsOneWidget);
      expect(find.text('Admin Demo'), findsOneWidget);
      expect(find.text('Editor de catálogo'), findsOneWidget);
    },
  );
  for (final width in [500.0, 1200.0]) {
    testWidgets('Enrolamiento QR, secreto y diseño sin KPIs a $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeAuthRepository(level: 'aal1')..factors = [];
      addTearDown(repo.events.close);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      expect(find.byType(MfaEnrollPage), findsOneWidget);
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.text('TEST-SECRET'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(
        find.text('Panel de administración de la plataforma'),
        width < 900 ? findsNothing : findsOneWidget,
      );
      expect(find.text('Hogares activos'), findsNothing);
      expect(find.text('Disponibilidad'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Provider puede se actualiza con logout', (tester) async {
    final repo = FakeAuthRepository();
    addTearDown(repo.events.close);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdminShell)),
    );
    expect(container.read(puedeProvider)('ROLES_GESTIONAR'), isTrue);
    await container.read(authControllerProvider).logout();
    await tester.pumpAndSettle();
    expect(container.read(puedeProvider)('ROLES_GESTIONAR'), isFalse);
  });
}
