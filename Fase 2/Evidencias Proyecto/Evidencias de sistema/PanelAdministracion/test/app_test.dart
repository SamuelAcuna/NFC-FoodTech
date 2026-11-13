import 'package:admin/features/administradores/data/administradores_repository.dart';

import 'fake_administradores_repository.dart';

import 'package:admin/features/dashboard/data/dashboard_repository.dart';

import 'fake_dashboard_repository.dart';

import 'package:admin/features/soporte/data/soporte_repository.dart';

import 'fake_soporte_repository.dart';

import 'package:admin/features/usuarios/data/usuarios_repository.dart';

import 'fake_usuarios_repository.dart';

import 'package:admin/features/auditoria/data/auditoria_repository.dart';

import 'fake_auditoria_repository.dart';

import 'package:intl/date_symbol_data_local.dart';
import 'package:admin/features/propuestos/data/propuestos_repository.dart';

import 'fake_propuestos_repository.dart';

import 'package:admin/features/alimentos/data/alimentos_repository.dart';
import 'package:admin/features/categorias/data/categorias_repository.dart';

import 'fake_alimentos_repository.dart';
import 'fake_categorias_repository.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:admin/features/auth/data/auth_repository.dart';

import 'fake_auth_repository.dart';

import 'package:admin/app.dart';
import 'package:admin/core/config/env.dart';
import 'package:admin/core/widgets/admin_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_CL'));
  testWidgets('sin defines muestra un error legible', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: AdminApp(configurationError: Env.configurationError),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Error de configuración'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final width in [500.0, 800.0, 1200.0]) {
    testWidgets('menú y navegación a ancho $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            administradoresRepositoryProvider.overrideWithValue(
              FakeAdministradoresRepository(),
            ),
            dashboardRepositoryProvider.overrideWithValue(
              FakeDashboardRepository(),
            ),
            soporteRepositoryProvider.overrideWithValue(
              FakeSoporteRepository(),
            ),
            usuariosRepositoryProvider.overrideWithValue(
              FakeUsuariosRepository(),
            ),
            auditoriaRepositoryProvider.overrideWithValue(
              FakeAuditoriaRepository(),
            ),
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
            propuestosRepositoryProvider.overrideWithValue(
              FakePropuestosRepository(),
            ),
            alimentosRepositoryProvider.overrideWithValue(
              FakeAlimentosRepository(),
            ),
            categoriasRepositoryProvider.overrideWithValue(
              FakeCategoriasRepository(),
            ),
          ],
          child: const AdminApp(),
        ),
      );
      await tester.pumpAndSettle();
      if (width < 600) {
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).drawer,
          isA<Drawer>(),
        );
      } else {
        if (width < 1024) {
          expect(find.byType(NavigationRail), findsOneWidget);
        }
        final key = width >= 1024 ? 'expanded-sidebar' : 'collapsed-sidebar';
        expect(find.byKey(ValueKey(key)), findsOneWidget);
        expect(
          tester.getSize(find.byKey(ValueKey(key))).width,
          width >= 1024 ? 240 : 72,
        );
      }
      for (final item in adminDestinations) {
        if (width < 600) {
          await tester.tap(find.byIcon(Icons.menu));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byIcon(item.icon));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text(item.title),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    });
  }
}
