import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nfc_foodtech_app/shared/models/resumen_indicadores.dart';
import 'package:nfc_foodtech_app/features/indicadores/screens/indicadores_screen.dart';
import 'indicadores_calculos_test.dart' as datos;
import 'lectura_movimientos_test.dart' as soporte;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late soporte.Servidor servidor;
  late List<String> exportaciones;
  const canal = 'dev.flutter.pigeon.file_saver.FileSaverHostApi.saveAs';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    servidor = soporte.Servidor();
    exportaciones = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(canal, (mensaje) async {
          exportaciones.add(
            utf8.decode(
              mensaje!.buffer.asUint8List(
                mensaje.offsetInBytes,
                mensaje.lengthInBytes,
              ),
              allowMalformed: true,
            ),
          );
          return const StandardMessageCodec().encodeMessage(['reporte.csv']);
        });
    await Supabase.initialize(
      url: 'https://prueba.example.com',
      publishableKey: 'sb_publishable_prueba',
      httpClient: MockClient(servidor.atender),
      debug: false,
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(canal, null);
    await Supabase.instance.dispose();
  });

  Future<void> resolver(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  final casos = [
    (
      nombre: 'sin descartes',
      precios: <int?>[],
      titulo: 'Pérdida económica estimada',
      valor: r'$0',
      csv: '0',
      cobertura: 'No existen descartes registrados.',
    ),
    (
      nombre: 'precios completos',
      precios: <int?>[2000],
      titulo: 'Pérdida económica estimada',
      valor: r'$400',
      csv: '400',
      cobertura:
          'Calculado con 1 de 1 descartes con precio registrado y cantidad inicial válida.',
    ),
    (
      nombre: 'precios desconocidos',
      precios: <int?>[null],
      titulo: 'Pérdida económica estimada',
      valor: 'Sin datos de precio',
      csv: 'Sin datos de precio',
      cobertura:
          'Calculado con 0 de 1 descartes con precio registrado y cantidad inicial válida.',
    ),
    (
      nombre: 'precios parciales',
      precios: <int?>[2000, null],
      titulo: 'Subtotal conocido',
      valor: r'$400',
      csv: '400',
      cobertura:
          'Calculado con 1 de 2 descartes con precio registrado y cantidad inicial válida.',
    ),
    (
      nombre: 'precio cero conocido',
      precios: <int?>[0],
      titulo: 'Pérdida económica estimada',
      valor: r'$0',
      csv: '0',
      cobertura:
          'Calculado con 1 de 1 descartes con precio registrado y cantidad inicial válida.',
    ),
    (
      nombre: 'subtotal conocido cero',
      precios: <int?>[0, null],
      titulo: 'Subtotal conocido',
      valor: r'$0',
      csv: '0',
      cobertura:
          'Calculado con 1 de 2 descartes con precio registrado y cantidad inicial válida.',
    ),
  ];
  for (final caso in casos) {
    test('clasificación económica y CSV: ${caso.nombre}', () {
      final r = datos.calcular(
        [
          for (var i = 0; i < caso.precios.length; i++)
            datos.ingreso('$i', precio: caso.precios[i]),
        ],
        [
          for (var i = 0; i < caso.precios.length; i++)
            datos.movimiento('$i', '$i', 'DESCARTE', 200),
        ],
      );
      final p = PresentacionPerdidaEconomica(
        descartes: r.cantidadDescartes,
        descartesConPrecio: r.descartesConPrecio,
        costoConocido: r.costoConocido,
      );
      expect(p.titulo, caso.titulo);
      expect(p.valorCsv, caso.csv);
      expect(p.cobertura, caso.cobertura);
      expect(p.detalleCsv, contains('precios actuales'));
      expect(p.detalleCsv, contains('Puede cambiar al editar'));
      expect(
        p.valorClp == null,
        caso.precios.isNotEmpty && caso.precios.every((p) => p == null),
      );
    });
    for (final oscuro in [false, true]) {
      testWidgets('pantalla y archivo CSV: ${caso.nombre}, oscuro: $oscuro', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(1000, 1700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        servidor.tablas['despensa_item'] = [
          for (var i = 0; i < caso.precios.length; i++)
            datos.ingreso('$i', precio: caso.precios[i]),
        ];
        servidor.tablas['movimiento'] = [
          for (var i = 0; i < caso.precios.length; i++)
            datos.movimiento('$i', '$i', 'DESCARTE', 200),
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: oscuro ? Brightness.dark : Brightness.light,
            ),
            home: const IndicadoresScreen(hogar: {'id': 'hogar-a'}),
          ),
        );
        await resolver(tester);
        await tester.scrollUntilVisible(find.text(caso.titulo), 400);
        expect(find.text(caso.valor), findsOneWidget);
        expect(find.text(caso.cobertura), findsOneWidget);
        if (caso.valor == 'Sin datos de precio')
          expect(find.text(r'$0'), findsNothing);
        final boton = find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Exportar reporte CSV',
        );
        await tester.tap(boton);
        await resolver(tester);
        expect(exportaciones, hasLength(1));
        final archivo = exportaciones.single;
        expect(archivo, contains('Sección;Indicador;Valor;Unidad;Detalle'));
        expect(
          archivo,
          contains('"Costo";"${caso.titulo}";"${caso.csv}";"CLP";'),
        );
        expect(archivo, contains(caso.cobertura));
        expect(archivo, contains('precios actuales'));
        if (caso.csv == 'Sin datos de precio')
          expect(
            archivo,
            isNot(contains('"Pérdida económica estimada";"0";"CLP"')),
          );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('carga y fallo intermedio no muestran pérdida ni exportan', (
    tester,
  ) async {
    final pendiente = Completer<void>();
    servidor.pendiente = pendiente;
    servidor.fallar = true;
    servidor.tablas['movimiento'] = [
      for (var i = 0; i < 501; i++)
        {...datos.movimiento('$i', 'a', 'DESCARTE', 1), 'id': i},
    ];
    await tester.pumpWidget(
      const MaterialApp(home: IndicadoresScreen(hogar: {'id': 'hogar-a'})),
    );
    await resolver(tester);
    final boton = find.byWidgetPredicate(
      (w) => w is IconButton && w.tooltip == 'Exportar reporte CSV',
    );
    expect(tester.widget<IconButton>(boton).onPressed, isNull);
    expect(find.text('Pérdida económica estimada'), findsNothing);
    expect(exportaciones, isEmpty);
    pendiente.complete();
    await resolver(tester);
    expect(find.textContaining('No se completó la consulta'), findsOneWidget);
    expect(find.text(r'$0'), findsNothing);
    expect(tester.widget<IconButton>(boton).onPressed, isNull);
    expect(exportaciones, isEmpty);
  });
}
