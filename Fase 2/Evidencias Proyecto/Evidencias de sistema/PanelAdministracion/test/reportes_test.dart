import 'dart:convert';

import 'package:admin/features/reportes/domain/reporte.dart';
import 'package:admin/features/reportes/domain/reporte_csv.dart';
import 'package:admin/features/reportes/data/reportes_repository.dart';
import 'package:admin/features/reportes/presentation/reportes_page.dart';
import 'package:admin/features/auth/presentation/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_auth_repository.dart';

class FakeReportes implements ReportesRepository {
  final calls = <String>[];
  @override
  Future<List<UsoPeriodo>> uso(String d, String h, String g) async {
    calls.add('$d/$h/$g');
    return [
      UsoPeriodo.fromJson({
        'periodo': '2026-10-01',
        'altas': 2,
        'usuarios_activos': 3,
        'retencion_pct': 33.3,
        'productos_registrados': 4,
        'alertas_emitidas': 5,
      }),
    ];
  }

  @override
  Future<List<DesperdicioPeriodo>> desperdicio(
    String d,
    String h,
    String g,
  ) async => [];
}

void main() {
  setUpAll(() => initializeDateFormatting('es_CL'));
  test(
    'CSV exacto con BOM, encabezados, punto y coma, coma decimal y escapado',
    () {
      final row = UsoPeriodo.fromJson({
        'periodo': '2026-10-01',
        'altas': 2,
        'usuarios_activos': 3,
        'retencion_pct': 33.3,
        'productos_registrados': 4,
        'alertas_emitidas': 5,
      });
      final bytes = usoCsv([row], 'MES');
      expect(bytes.take(3), [239, 187, 191]);
      expect(
        utf8.decode(bytes),
        'Período;Altas;Usuarios activos;Retención (%);Productos registrados;Alertas emitidas\r\noct 2026;2;3;33,3;4;5\r\n',
      );
      final waste = DesperdicioPeriodo.fromJson({
        'periodo': '2026-10-05',
        'categoria': 'Fruta; "otra"',
        'descartes': 7,
        'hogares': 3,
      });
      expect(
        utf8.decode(desperdicioCsv([waste], 'SEMANA')),
        'Período;Categoría;Registros de descarte;Hogares\r\nSem. 05-10-2026;"Fruta; ""otra""";7;3\r\n',
      );
      expect(porcentaje(null), '—');
      expect(porcentaje(33.3), '33,3%');
      expect(
        validateReporte(DateTime(2026, 2), DateTime(2026, 1), 'MES'),
        'El rango de fechas no es válido.',
      );
      expect(
        validateReporte(DateTime(2024), DateTime(2024, 12, 31), 'MES'),
        isNull,
      );
      expect(
        validateReporte(DateTime(2024), DateTime(2025, 1, 1), 'MES'),
        'El rango no puede superar 366 días.',
      );
      expect(
        validateReporte(DateTime(2026, 1), DateTime(2026, 2), 'DIA'),
        'La agrupación no es válida.',
      );
      expect(csvCell('normal'), 'normal');
      expect(csvCell('con;puntoycoma'), '"con;puntoycoma"');
      expect(csvCell('con"comillas"'), '"con""comillas"""');
      expect(csvCell('con\nsalto'), '"con\nsalto"');
    },
  );
  testWidgets('genera dos tablas, privacidad y vacío', (t) async {
    t.view.physicalSize = const Size(1600, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final repo = FakeReportes();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          adminContextProvider.overrideWithValue(adminContext()),
          reportesRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: Scaffold(body: ReportesPage())),
      ),
    );
    await t.tap(find.text('Generar'));
    await t.pumpAndSettle();
    expect(repo.calls.length, 1);
    expect(find.text('33,3%'), findsOneWidget);
    expect(find.text('No hay datos en el rango seleccionado.'), findsOneWidget);
    expect(
      find.text(
        'Se omiten los grupos con menos de 3 hogares para resguardar la privacidad. Se cuentan registros, no cantidades.',
      ),
      findsOneWidget,
    );
    expect(find.text('Exportar CSV'), findsNWidgets(2));
  });
  testWidgets('pantalla sin permiso REPORTES_VER', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          adminContextProvider.overrideWithValue(
            adminContext(permissions: {}),
          ),
          reportesRepositoryProvider.overrideWithValue(FakeReportes()),
        ],
        child: const MaterialApp(home: Scaffold(body: ReportesPage())),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.text('No tienes permisos para acceder a reportes.'),
      findsOneWidget,
    );
  });
}
