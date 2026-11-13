import 'package:intl/intl.dart';
import 'package:admin/features/auditoria/domain/registro_auditoria.dart';
import 'package:admin/features/auditoria/data/auditoria_repository.dart';
import 'package:admin/features/auditoria/presentation/auditoria_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_auditoria_repository.dart';

RegistroAuditoria row(
  String entity,
  String action, {
  Map<String, dynamic>? before,
  Map<String, dynamic>? after,
  String id = '1',
}) => RegistroAuditoria.fromJson({
  'id': id,
  'fecha': '2026-10-20T15:00:00Z',
  'entidad': entity,
  'entidad_id': id,
  'accion': action,
  'antes': before,
  'despues': after,
});
void main() {
  setUpAll(() => initializeDateFormatting('es_CL'));
  test('acciones y diferencias minimizan campos técnicos', () {
    for (final e in ['categoria', 'alimento']) {
      for (final a in ['INSERT', 'UPDATE', 'DELETE']) {
        final r = row(
          e,
          a,
          before: a == 'INSERT' ? null : {'nombre': 'Pan'},
          after: a == 'DELETE' ? null : {'nombre': 'Pan nuevo'},
        );
        expect(r.texto, contains(e == 'categoria' ? 'categoría' : 'alimento'));
      }
    }
    expect(
      row('alimento', 'APROBAR', after: {'nombre': 'Pan'}).texto,
      'Aprobó producto «Pan»',
    );
    expect(
      row('alimento', 'RECHAZAR', after: {'nombre': 'Pan'}).texto,
      'Rechazó producto «Pan»',
    );
    for (final active in [true, false]) {
      final r = row(
        'alimento',
        'UPDATE',
        before: {'nombre': 'Pan', 'activo': !active, 'updated_at': 'a'},
        after: {'nombre': 'Pan', 'activo': active, 'updated_at': 'b'},
      );
      expect(r.camposCambiados, ['activo']);
      expect(r.texto, startsWith(active ? 'Reactivó' : 'Dio de baja'));
    }
    expect(
      row('parametro', 'UPDATE', after: {'clave': 'x'}).texto,
      'Modificó parámetro «x»',
    );
    for (final e in ['rol', 'rol_permiso', 'perfil_rol']) {
      for (final a in ['INSERT', 'UPDATE', 'DELETE']) {
        expect(row(e, a, id: 'a:1').texto, contains('$e a:1'));
      }
    }
    for (final a in ['SUSPENDER', 'REACTIVAR']) {
      expect(
        row('perfil', a, after: {'email': 'u@test'}).texto,
        contains('«u@test»'),
      );
    }
    for (final op in ['ASIGNAR', 'RESPONDER', 'CERRAR']) {
      expect(
        row(
          'solicitud_soporte',
          'UPDATE',
          after: {'operacion': op, 'asunto': 'Ayuda'},
        ).texto,
        contains('la solicitud «Ayuda»'),
      );
    }
    expect(row('otra', 'UPDATE').texto, 'UPDATE en otra #1');
    final winter = DateTime.utc(2026, 7, 1, 12);
    expect(
      fechaChile(winter),
      DateFormat('dd-MM-yyyy HH:mm', 'es_CL').format(winter.toLocal()),
    );
    final summer = DateTime.utc(2026, 10, 1, 12);
    expect(
      fechaChile(summer),
      DateFormat('dd-MM-yyyy HH:mm', 'es_CL').format(summer.toLocal()),
    );
    expect(
      fechaChile(summer, time: false),
      DateFormat('dd-MM-yyyy', 'es_CL').format(summer.toLocal()),
    );
  });
  testWidgets('página falsa pagina, filtra y abre diferencias', (tester) async {
    final repo = FakeAuditoriaRepository()
      ..rows = List.generate(
        51,
        (i) => row(
          'categoria',
          'INSERT',
          after: {'nombre': 'Prueba $i'},
          id: '$i',
        ),
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [auditoriaRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: Scaffold(body: AuditoriaPage())),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.calls.single['offset'], 0);
    await tester.ensureVisible(find.text('Ver').first);
    await tester.tap(find.text('Ver').first);
    await tester.pumpAndSettle();
    expect(find.text('Después'), findsOneWidget);
    expect(find.text('Prueba 0'), findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Cargar más'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Cargar más'));
    await tester.pumpAndSettle();
    expect(repo.calls.last['offset'], 50);
  });
}
