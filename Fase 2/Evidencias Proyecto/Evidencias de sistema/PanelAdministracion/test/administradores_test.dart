import 'package:admin/features/auth/data/auth_repository.dart';
import 'package:admin/features/administradores/domain/administrador.dart';

import 'fake_auth_repository.dart';

import 'package:admin/features/administradores/data/administradores_repository.dart';
import 'package:admin/features/administradores/presentation/administradores_page.dart';
import 'package:admin/core/errors/app_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_administradores_repository.dart';

void main() {
  test('solo errores de negocio permitidos', () {
    expect(
      AppError.administradorMessage(
        const PostgrestException(
          message: 'El usuario ya tiene ese rol.',
          code: 'P0001',
        ),
      ),
      'El usuario ya tiene ese rol.',
    );
    expect(
      AppError.administradorMessage(
        const PostgrestException(message: 'secreto', code: 'P0001'),
      ),
      isNot(contains('secreto')),
    );
  });
  testWidgets('roles desde repositorio y confirmación al quitar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeAdministradoresRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          administradoresRepositoryProvider.overrideWithValue(repo),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        ],
        child: const MaterialApp(home: Scaffold(body: AdministradoresPage())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Activo'), findsOneWidget);
    expect(find.text('Permisos administrativos por rol'), findsOneWidget);
    expect(find.text('Gestionar catálogo'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(repo.operations, isEmpty);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(repo.operations.single, ['QUITAR', 'a', 'ADMIN']);
    await tester.tap(find.text('Nuevo administrador'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asignar rol'));
    await tester.pumpAndSettle();
    expect(find.text('Ingresa un correo.'), findsOneWidget);
    expect(repo.operations.length, 1);
    await tester.enterText(find.byType(TextFormField), 'nuevo@test');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editor de catálogo').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asignar rol'));
    await tester.pumpAndSettle();
    expect(repo.operations.last, ['ASIGNAR', 'nuevo@test', 'EDITOR_CATALOGO']);
  });
  test('nuevo mensaje de roles propios en lista cerrada', () {
    expect(
      AppError.administradorMessage(
        const PostgrestException(
          message: 'No puedes quitarte tus propios roles.',
          code: 'P0001',
        ),
      ),
      'No puedes quitarte tus propios roles.',
    );
    expect(
      AppError.administradorMessage(
        const PostgrestException(
          message: 'No puedes quitarte tu propio rol de administrador.',
          code: 'P0001',
        ),
      ),
      isNot('No puedes quitarte tu propio rol de administrador.'),
    );
  });
  testWidgets('fila propia no permite quitar ninguno de sus roles', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    final repo = FakeAdministradoresRepository()
      ..admins = [
        Administrador.fromJson({
          'perfil_id': auth.userId,
          'email': 'propio@test',
          'estado_cuenta': 'ACTIVA',
          'roles': ['ADMIN', 'EDITOR_CATALOGO'],
          'mfa_activo': true,
        }),
      ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          administradoresRepositoryProvider.overrideWithValue(repo),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: const MaterialApp(home: Scaffold(body: AdministradoresPage())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsNWidgets(2));
    for (final chip in tester.widgetList<InputChip>(find.byType(InputChip))) {
      expect(chip.onDeleted, isNull);
    }
    expect(find.byIcon(Icons.close), findsNothing);
  });
}
