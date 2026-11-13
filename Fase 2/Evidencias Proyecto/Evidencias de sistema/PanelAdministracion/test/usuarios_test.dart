import 'package:admin/features/usuarios/data/usuarios_repository.dart';
import 'package:admin/features/usuarios/domain/usuario_admin.dart';
import 'package:admin/features/usuarios/presentation/usuarios_page.dart';
import 'package:admin/features/auth/data/auth_repository.dart';
import 'package:admin/features/auth/presentation/auth_providers.dart';
import 'package:admin/core/errors/app_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_auth_repository.dart';
import 'fake_usuarios_repository.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_CL'));
  test('modelo y errores permitidos', () {
    final u = UsuarioAdmin.fromJson({
      'id': 'x',
      'email': 'u@test',
      'estado_cuenta': 'ACTIVA',
      'registrado_en': '2026-10-20T12:00:00Z',
      'es_administrador': false,
      'total': 1,
    });
    expect(u.etiqueta, 'u@test');
    expect(u.acceso, isNull);
    expect(
      AppError.usuarioMessage(
        const PostgrestException(message: 'Estado no válido.', code: 'P0001'),
      ),
      'Estado no válido.',
    );
    expect(
      AppError.usuarioMessage(
        const PostgrestException(message: 'SQL secreto', code: 'P0001'),
      ),
      isNot(contains('secreto')),
    );
  });
  testWidgets('debounce y motivo obligatorio con repositorio falso', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeUsuariosRepository()
      ..rows = [
        UsuarioAdmin.fromJson({
          'id': 'otro',
          'email': 'u@test',
          'nombre': 'Ana',
          'apellido': 'Pérez',
          'estado_cuenta': 'ACTIVA',
          'registrado_en': '2026-10-20T12:00:00Z',
          'es_administrador': false,
          'total': 1,
        }),
      ];
    final auth = FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          adminContextProvider.overrideWithValue(adminContext()),
          usuariosRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: Scaffold(body: UsuariosPage())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Ana');
    await tester.pump(const Duration(milliseconds: 299));
    expect(repo.calls.length, 1);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(repo.calls.last['busqueda'], 'Ana');
    await tester.tap(find.text('Suspender'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(repo.changes, isEmpty);
    expect(
      find.text('Ingresa un motivo entre 5 y 500 caracteres.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextFormField).last, 'Motivo válido');
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(repo.changes.single, ['otro', 'SUSPENDIDA', 'Motivo válido']);
  });
}
