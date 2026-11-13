import 'package:admin/features/soporte/data/soporte_repository.dart';
import 'package:admin/features/soporte/domain/solicitud_soporte.dart';
import 'package:admin/features/soporte/presentation/soporte_page.dart';
import 'package:admin/core/errors/app_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_soporte_repository.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_CL'));
  test('errores cerrados y modelo', () {
    expect(
      AppError.soporteMessage(
        const PostgrestException(
          message: 'La solicitud está cerrada.',
          code: 'P0001',
        ),
      ),
      'La solicitud está cerrada.',
    );
    expect(
      AppError.soporteMessage(
        const PostgrestException(message: 'detalle SQL', code: 'P0001'),
      ),
      isNot(contains('SQL')),
    );
  });
  testWidgets('filtro y respuesta validada sin base real', (tester) async {
    final repo = FakeSoporteRepository()
      ..rows = [
        SolicitudSoporte.fromJson({
          'id': 's',
          'tipo': 'CONSULTA',
          'asunto': 'Ayuda de prueba',
          'mensaje': 'Mensaje completo privado',
          'estado': 'PENDIENTE',
          'prioridad': 1,
          'solicitante_email': 'u@test',
          'solicitado_en': '2026-10-20T12:00:00Z',
          'total': 1,
        }),
      ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [soporteRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: Scaffold(body: SoportePage())),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.calls.single, 'ABIERTAS');
    await tester.tap(find.text('Respondidas'));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'RESPONDIDA');
    await tester.tap(find.text('Ayuda de prueba'));
    await tester.pumpAndSettle();
    expect(find.text('Mensaje completo privado'), findsOneWidget);
    await tester.tap(find.text('Responder'));
    await tester.pumpAndSettle();
    expect(repo.operations, isEmpty);
    await tester.enterText(find.byType(TextFormField), 'Respuesta de prueba');
    await tester.tap(find.text('Responder'));
    await tester.pumpAndSettle();
    expect(repo.operations.single, ['RESPONDER', 's', 'Respuesta de prueba']);
    expect(find.text('Comunicados'), findsNothing);
    expect(find.text('Eliminación de cuenta'), findsNothing);
  });
}
