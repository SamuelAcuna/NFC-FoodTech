import 'package:admin/features/dashboard/data/dashboard_repository.dart';
import 'package:admin/features/dashboard/domain/dashboard_data.dart';
import 'package:admin/features/dashboard/presentation/dashboard_page.dart';
import 'package:admin/features/auth/presentation/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_repository.dart';
import 'fake_dashboard_repository.dart';

void main() {
  test('porcentaje por registros y meses españoles', () {
    final d = DashboardData.fromJson(dashboardJson(empty: false));
    expect(d.meses.first.porcentaje, .75);
    expect(d.meses.first.etiqueta, 'May');
    expect(
      DashboardData.fromJson(dashboardJson()).meses.first.porcentaje,
      isNull,
    );
  });
  for (final allowed in [true, false]) {
    testWidgets('KPIs, vacíos y enlaces según permisos $allowed', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardRepositoryProvider.overrideWithValue(
              FakeDashboardRepository(),
            ),
            adminContextProvider.overrideWithValue(
              adminContext(permissions: allowed ? allPermissions : {}),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: DashboardPage())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hogares registrados'), findsOneWidget);
      expect(find.text('3 activos en 30 días'), findsOneWidget);
      expect(
        find.text('Aún no hay registros de consumo o descarte.'),
        findsOneWidget,
      );
      expect(
        find.text('Revisar ahora →'),
        allowed ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Ver soporte →'),
        allowed ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Generar reporte administrativo →'),
        allowed ? findsOneWidget : findsNothing,
      );
      expect(find.text('—'), findsNWidgets(6));
    });
  }
}
