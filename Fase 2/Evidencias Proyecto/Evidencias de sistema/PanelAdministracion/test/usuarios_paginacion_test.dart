import 'package:admin/features/usuarios/data/usuarios_repository.dart';
import 'package:admin/features/usuarios/domain/usuario_admin.dart';
import 'package:admin/features/usuarios/presentation/usuarios_page.dart';
import 'package:admin/features/auth/data/auth_repository.dart';
import 'package:admin/features/auth/presentation/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_auth_repository.dart';
import 'fake_usuarios_repository.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_CL'));
  testWidgets('usuarios conserva total al agotar una página exacta', (
    tester,
  ) async {
    final repo = FakeUsuariosRepository()
      ..rows = List.generate(
        50,
        (i) => UsuarioAdmin.fromJson({
          'id': 'u$i',
          'email': 'u$i@test',
          'estado_cuenta': 'ACTIVA',
          'registrado_en': '2026-10-20T12:00:00Z',
          'es_administrador': false,
          'total': 50,
        }),
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          usuariosRepositoryProvider.overrideWithValue(repo),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          adminContextProvider.overrideWithValue(adminContext()),
        ],
        child: const MaterialApp(home: Scaffold(body: UsuariosPage())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Cargar más'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Cargar más'));
    await tester.pumpAndSettle();
    expect(repo.calls.last['offset'], 50);
    expect(find.text('Usuarios (50)'), findsOneWidget);
    expect(find.text('Cargar más'), findsNothing);
  });
}
