import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_foodtech_app/features/home/models/resumen_hogar.dart';
import 'package:nfc_foodtech_app/features/home/widgets/resumen_hogar_card.dart';

List<MesResumenHogar> resumen({
  int? precio = 2000,
  bool segundoSinPrecio = false,
  bool sinMovimientos = false,
}) {
  final ahora = DateTime(2026, 1, 20);
  return calcularResumenHogar(
    ahora: ahora,
    items: {
      'a': {'alimento_id': 1, 'cantidad_inicial': 1000, 'precio_clp': precio},
      'b': {
        'alimento_id': 2,
        'cantidad_inicial': 5,
        'precio_clp': segundoSinPrecio ? null : 1000,
      },
    },
    alimentos: {
      1: {'nombre': 'Arroz', 'unidad_base': 'g'},
      2: {'nombre': 'Huevos', 'unidad_base': 'un'},
    },
    movimientos: sinMovimientos
        ? []
        : [
            for (final mes in [11, 12, 1])
              {
                'despensa_item_id': 'a',
                'tipo': 'DESCARTE',
                'cantidad': 200,
                'fecha': DateTime(
                  mes == 1 ? 2026 : 2025,
                  mes,
                  10,
                ).toUtc().toIso8601String(),
              },
            if (segundoSinPrecio)
              {
                'despensa_item_id': 'b',
                'tipo': 'DESCARTE',
                'cantidad': 1,
                'fecha': ahora.toUtc().toIso8601String(),
              },
            {
              'despensa_item_id': 'a',
              'tipo': 'CONSUMO',
              'cantidad': 600,
              'fecha': ahora.toUtc().toIso8601String(),
            },
          ],
  );
}

void main() {
  test(
    'tres meses cruzan año y reutilizan pérdida proporcional sin incluir consumo',
    () {
      final meses = resumen();
      expect(meses.map((m) => m.mes), [
        DateTime(2025, 11),
        DateTime(2025, 12),
        DateTime(2026, 1),
      ]);
      expect(meses.map((m) => m.perdida.valorClp), [400, 400, 400]);
      expect(meses.last.perdida.descartes, 1);
    },
  );
  test(
    'precios desconocidos, parciales, cero y ausencia de descartes se distinguen',
    () {
      expect(resumen(precio: null).last.perdida.sinPrecios, isTrue);
      expect(resumen(segundoSinPrecio: true).last.perdida.parcial, isTrue);
      expect(resumen(segundoSinPrecio: true).last.perdida.valorClp, 400);
      expect(resumen(precio: 0).last.perdida.descartesConPrecio, 1);
      expect(resumen(precio: 0).last.perdida.valorClp, 0);
      expect(
        resumen(sinMovimientos: true).last.perdida.cobertura,
        'No existen descartes registrados.',
      );
    },
  );
  for (final oscuro in [false, true]) {
    for (final ancho in [320.0, 600.0]) {
      testWidgets('dos indicadores adaptables sin gráficos ($oscuro, $ancho)', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(ancho, 740));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        tester.binding.platformDispatcher.textScaleFactorTestValue =
            ancho == 320 ? 1.5 : 1;
        addTearDown(
          tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
        );
        var aperturas = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: oscuro ? Brightness.dark : Brightness.light,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ResumenHogarCard(
                  meses: resumen(segundoSinPrecio: true),
                  cargando: false,
                  error: false,
                  onReintentar: () {},
                  onAnalisis: () => aperturas++,
                ),
              ),
            ),
          ),
        );
        expect(find.textContaining('Subtotal conocido'), findsWidgets);
        expect(find.byType(FractionallySizedBox), findsNothing);
        expect(find.text('Porcentaje de desperdicio'), findsOneWidget);
        expect(find.text('Sin datos suficientes'), findsOneWidget);
        expect(find.text('Pérdida económica estimada'), findsOneWidget);
        final perdida = tester.getRect(
          find.byKey(const ValueKey('perdida-hogar')),
        );
        final porcentaje = tester.getRect(
          find.byKey(const ValueKey('porcentaje-desperdicio-hogar')),
        );
        if (ancho == 320) {
          expect(porcentaje.top, greaterThan(perdida.bottom));
        } else {
          expect(porcentaje.top, perdida.top);
          expect(porcentaje.left, greaterThan(perdida.right));
        }
        await tester.ensureVisible(find.text('Ver análisis completo'));
        await tester.tap(find.text('Ver análisis completo'));
        expect(aperturas, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'cero real sin descartes conserva la explicación y no inventa porcentaje',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ResumenHogarCard(
                meses: resumen(sinMovimientos: true),
                cargando: false,
                error: false,
                onReintentar: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text(r'$0 CLP'), findsOneWidget);
      expect(find.text('No existen descartes registrados.'), findsOneWidget);
      expect(find.text('Sin datos suficientes'), findsOneWidget);
      expect(find.text('0%'), findsNothing);
    },
  );
  testWidgets(
    'sin precios no se muestra cero y con precio cero se conserva valor conocido',
    (tester) async {
      Future<void> mostrar(int? precio) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ResumenHogarCard(
                  meses: resumen(precio: precio),
                  cargando: false,
                  error: false,
                  onReintentar: () {},
                ),
              ),
            ),
          ),
        );
      }

      await mostrar(null);
      expect(find.text('Sin datos de precio'), findsOneWidget);
      expect(find.text(r'$0 CLP'), findsNothing);
      await mostrar(0);
      expect(find.text(r'$0 CLP'), findsOneWidget);
      expect(find.textContaining('1 de 1 descartes'), findsOneWidget);
      await mostrar(62500);
      expect(find.text(r'$12.500 CLP'), findsOneWidget);
    },
  );
  testWidgets(
    'carga y ausencia de hogar no presentan importes ni porcentajes',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResumenHogarCard(
              meses: resumen(),
              cargando: true,
              error: false,
              onReintentar: () {},
            ),
          ),
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('400 CLP'), findsNothing);
      expect(find.text('Sin datos suficientes'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResumenHogarCard(
              meses: null,
              cargando: false,
              error: false,
              onReintentar: () {},
            ),
          ),
        ),
      );
      expect(
        find.text('Crea un hogar o únete para ver su resumen.'),
        findsOneWidget,
      );
      expect(find.text(r'$0 CLP'), findsNothing);
      expect(
        find.byKey(const ValueKey('porcentaje-desperdicio-hogar')),
        findsNothing,
      );
    },
  );
  testWidgets('error oculta cifras anteriores y permite reintentar', (
    tester,
  ) async {
    var reintentos = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResumenHogarCard(
            meses: resumen(),
            cargando: false,
            error: true,
            onReintentar: () => reintentos++,
          ),
        ),
      ),
    );
    expect(find.textContaining('400 CLP'), findsNothing);
    expect(find.byType(FractionallySizedBox), findsNothing);
    expect(find.text('Sin datos suficientes'), findsNothing);
    await tester.tap(find.text('Reintentar análisis'));
    expect(reintentos, 1);
  });
}
