import 'package:admin/features/soporte/data/soporte_repository.dart';
import 'package:admin/features/soporte/domain/solicitud_soporte.dart';
import 'package:admin/features/soporte/presentation/soporte_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_soporte_repository.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_CL'));
  testWidgets('soporte conserva total al agotar una página exacta', (
    tester,
  ) async {
    final repo = FakeSoporteRepository()
      ..rows = List.generate(
        50,
        (i) => SolicitudSoporte.fromJson({
          'id': 's$i',
          'tipo': 'CONSULTA',
          'asunto': 'Solicitud $i',
          'mensaje': 'Prueba',
          'estado': 'PENDIENTE',
          'prioridad': 1,
          'solicitante_email': 'u@test',
          'solicitado_en': '2026-10-20T12:00:00Z',
          'total': 50,
        }),
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [soporteRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: Scaffold(body: SoportePage())),
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
    expect(find.text('Solicitudes de soporte (50)'), findsOneWidget);
    expect(find.text('Cargar más'), findsNothing);
  });
}
