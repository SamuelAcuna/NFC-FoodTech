import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nfc_foodtech_app/features/compras/screens/lista_compras_screen.dart';
import 'package:nfc_foodtech_app/features/compras/widgets/estimacion_compra.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _pendiente(
  String id,
  int alimento,
  dynamic cantidad,
  String unidad, {
  String estado = 'PENDIENTE',
}) => {
  'id': id,
  'lista_id': 'lista-actual',
  'alimento_id': alimento,
  'cantidad': cantidad,
  'unidad': unidad,
  'estado': estado,
  'despensa_item_id': null,
};

Map<String, dynamic> _compra({
  String id = 'compra-1',
  int alimento = 1,
  dynamic cantidad = 1000,
  String unidad = 'g',
  dynamic precio = 4000,
  String? fecha = '2026-10-01T12:00:00Z',
  String hogar = 'hogar-a',
}) => {
  'id': id,
  'alimento_id': alimento,
  'cantidad': cantidad,
  'unidad': unidad,
  'precio_compra_clp': precio,
  'fecha_compra': fecha,
  'hogar_id': hogar,
  'estado': 'COMPRADO',
  'despensa_item_id': 'ingreso-$id',
};

const _unidades = {1: 'g', 2: 'ml', 3: 'un'};

EstimacionGasto _calcular(
  List<Map<String, dynamic>> compras, {
  List<Map<String, dynamic>>? items,
}) => calcularEstimacionCompra(
  hogarId: 'hogar-a',
  compras: compras,
  unidadesBase: _unidades,
  items: items ?? [_pendiente('pendiente-1', 1, 500, 'g')],
);

class _ServidorEstimacion {
  final List<Map<String, dynamic>> listas = [
    {
      'id': 'lista-actual',
      'hogar_id': 'hogar-a',
      'nombre': 'Semana',
      'estado': 'ABIERTA',
      'creada_en': '2026-10-28T12:00:00Z',
    },
  ];
  final Map<String, List<Map<String, dynamic>>> items = {
    'lista-actual': [_pendiente('pendiente-1', 1, 500, 'g')],
  };
  final Map<String, List<Map<String, dynamic>>> historial = {
    'lista-actual': [_compra()],
  };
  final List<http.Request> peticiones = [];
  bool fallaHistorial = false;
  Completer<http.Response>? historialPendiente;
  http.Response? respuestaRetardada;
  bool _consultaRetardada = false;
  int confirmaciones = 0;
  Map<String, dynamic>? parametrosCompra;

  http.Response responder(dynamic datos, http.Request solicitud) =>
      http.Response(
        jsonEncode(datos),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
        request: solicitud,
      );

  Set<String> _filtroIds(String? filtro) =>
      filtro == null || !filtro.startsWith('in.(')
      ? {}
      : filtro
            .substring(4, filtro.length - 1)
            .split(',')
            .map((id) => id.replaceAll('"', ''))
            .toSet();

  List<Map<String, dynamic>> _pagina(
    Iterable<Map<String, dynamic>> filas,
    Map<String, String> consulta, {
    String prefijo = '',
  }) => filas
      .skip(int.parse(consulta['${prefijo}offset'] ?? '0'))
      .take(int.parse(consulta['${prefijo}limit'] ?? '1000'))
      .toList();

  Future<http.Response> atender(http.Request solicitud) async {
    peticiones.add(solicitud);
    final consulta = solicitud.url.queryParameters;
    final ruta = solicitud.url.path;

    if (ruta == '/rest/v1/lista_compra') {
      final hogar = consulta['hogar_id']?.substring(3);
      final ids = _filtroIds(consulta['id']);
      final esHistorial = consulta['select']!.contains('lista_compra_item(');
      var seleccion = listas
          .where(
            (lista) =>
                lista['hogar_id'] == hogar &&
                (ids.isEmpty || ids.contains(lista['id'])),
          )
          .toList();

      if (esHistorial) {
        if (fallaHistorial) {
          return http.Response(
            jsonEncode({'message': 'Historial no disponible'}),
            400,
            request: solicitud,
            headers: {'content-type': 'application/json'},
          );
        }
        seleccion.sort(
          (a, b) => a['id'].toString().compareTo(b['id'].toString()),
        );
        final alimentos = _filtroIds(consulta['lista_compra_item.alimento_id']);
        final resultado = _pagina(seleccion, consulta).map((lista) {
          final compras = (historial[lista['id']] ?? [])
              .where(
                (compra) =>
                    compra['estado'] == 'COMPRADO' &&
                    alimentos.contains(compra['alimento_id'].toString()),
              )
              .toList();
          compras.sort((a, b) {
            final orden = (b['fecha_compra']?.toString() ?? '').compareTo(
              a['fecha_compra']?.toString() ?? '',
            );
            return orden != 0
                ? orden
                : b['id'].toString().compareTo(a['id'].toString());
          });
          return {
            ...lista,
            'lista_compra_item': _pagina(
              compras,
              consulta,
              prefijo: 'lista_compra_item.',
            ),
          };
        }).toList();
        final respuesta = responder(resultado, solicitud);
        if (historialPendiente != null && !_consultaRetardada) {
          _consultaRetardada = true;
          respuestaRetardada = respuesta;
          return historialPendiente!.future;
        }
        return respuesta;
      }

      if (consulta['id']?.startsWith('eq.') == true) {
        seleccion = seleccion
            .where((lista) => lista['id'] == consulta['id']!.substring(3))
            .toList();
      }
      return responder(seleccion, solicitud);
    }

    if (ruta == '/rest/v1/lista_compra_item') {
      final lista = consulta['lista_id']!.substring(3);
      var filas = items[lista] ?? [];
      if (consulta['id'] != null) {
        filas = filas
            .where((item) => item['id'] == consulta['id']!.substring(3))
            .toList();
      }
      return responder(_pagina(filas, consulta), solicitud);
    }

    if (ruta == '/rest/v1/alimento') {
      final filtro = consulta['id'];
      final ids = _filtroIds(filtro);
      return responder([
        for (final entrada in _unidades.entries)
          if ((ids.isEmpty || ids.contains(entrada.key.toString())) &&
              (filtro?.startsWith('eq.') != true ||
                  filtro!.substring(3) == entrada.key.toString()))
            {
              'id': entrada.key,
              'nombre': 'Alimento ${entrada.key}',
              'hogar_id': null,
              'unidad_base': entrada.value,
            },
      ], solicitud);
    }

    if (ruta == '/rest/v1/despensa_item') return responder([], solicitud);

    if (ruta == '/rest/v1/rpc/m27_confirmar_compra_item' &&
        solicitud.method == 'POST') {
      confirmaciones++;
      parametrosCompra = jsonDecode(solicitud.body) as Map<String, dynamic>;
      final producto = items.values
          .expand((lista) => lista)
          .firstWhere(
            (item) => item['id'] == parametrosCompra!['p_lista_item_id'],
          );
      producto['estado'] = 'COMPRADO';
      producto['despensa_item_id'] = 'ingreso-nuevo';
      return responder('ingreso-nuevo', solicitud);
    }

    throw StateError('Petición inesperada: $solicitud');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ServidorEstimacion servidor;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    servidor = _ServidorEstimacion();
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
        authFlowType: AuthFlowType.implicit,
      ),
    );
  });

  tearDown(() async => await Supabase.instance.dispose());

  for (final caso in [
    (
      alimento: 2,
      historica: 1.0,
      unidadHistorica: 'L',
      precio: 1000,
      deseada: 500.0,
      unidadDeseada: 'ml',
      importe: 500,
    ),
    (
      alimento: 2,
      historica: 1000.0,
      unidadHistorica: 'ml',
      precio: 1000,
      deseada: 0.25,
      unidadDeseada: 'l',
      importe: 250,
    ),
    (
      alimento: 1,
      historica: 1.0,
      unidadHistorica: 'kg',
      precio: 4000,
      deseada: 250.0,
      unidadDeseada: 'g',
      importe: 1000,
    ),
    (
      alimento: 1,
      historica: 1000.0,
      unidadHistorica: 'g',
      precio: 4000,
      deseada: 0.5,
      unidadDeseada: 'kg',
      importe: 2000,
    ),
    (
      alimento: 3,
      historica: 4.0,
      unidadHistorica: 'un',
      precio: 1000,
      deseada: 0.5,
      unidadDeseada: 'un',
      importe: 125,
    ),
  ]) {
    test(
      'estima ${caso.deseada} ${caso.unidadDeseada} desde ${caso.historica} ${caso.unidadHistorica}',
      () {
        final resultado = _calcular(
          [
            _compra(
              alimento: caso.alimento,
              cantidad: caso.historica,
              unidad: caso.unidadHistorica,
              precio: caso.precio,
            ),
          ],
          items: [
            _pendiente('p', caso.alimento, caso.deseada, caso.unidadDeseada),
          ],
        );
        expect(resultado.porItem['p']!.importeClp, caso.importe);
      },
    );
  }

  test('utiliza los 4000 históricos aunque el inventario indique 4500', () {
    final compra = {..._compra(), 'precio_clp': 4500};
    final resultado = _calcular(
      [compra],
      items: [_pendiente('p', 1, 1000, 'g')],
    );
    expect(resultado.totalConocido, 4000);
  });

  test('elige la referencia válida más reciente y excluye otros hogares', () {
    final resultado = _calcular([
      _compra(id: 'antigua', precio: 1000, fecha: '2026-09-01T12:00:00Z'),
      _compra(id: 'reciente', precio: 4000),
      _compra(
        id: 'ajena',
        precio: 9999,
        hogar: 'hogar-b',
        fecha: '2026-10-20T12:00:00Z',
      ),
      _compra(id: 'sin-precio', precio: null, fecha: '2026-10-25T12:00:00Z'),
    ]);
    expect(resultado.totalConocido, 2000);
    expect(
      resultado.porItem['pendiente-1']!.fechaReferencia,
      DateTime.utc(2026, 10, 1, 12),
    );
  });

  test('desempata por identificador sin depender del orden de respuesta', () {
    final a = _compra(id: 'a', precio: 1000);
    final b = _compra(id: 'b', precio: 4000);
    expect(_calcular([a, b]).totalConocido, 2000);
    expect(_calcular([b, a]).totalConocido, 2000);
  });

  for (final cambio in <Map<String, dynamic>>[
    {'precio_compra_clp': null},
    {'precio_compra_clp': -1},
    {'precio_compra_clp': 'NaN'},
    {'precio_compra_clp': 1.5},
    {'cantidad': 0},
    {'cantidad': -1},
    {'cantidad': 'Infinity'},
    {'unidad': 'L'},
    {'fecha_compra': null},
    {'fecha_compra': 'sin-fecha'},
    {'despensa_item_id': null},
    {'estado': 'PENDIENTE'},
  ]) {
    test('descarta histórico inválido: $cambio', () {
      final resultado = _calcular([
        {..._compra(), ...cambio},
      ]);
      expect(resultado.totalConocido, isNull);
      expect(resultado.sinEstimacion, 1);
    });
  }

  test('distingue referencia gratuita de precio desconocido', () {
    final resultado = _calcular(
      [_compra(precio: 0)],
      items: [
        _pendiente('gratis', 1, 500, 'g'),
        _pendiente('sin-precio', 2, 1, 'L'),
      ],
    );
    expect(resultado.porItem['gratis']!.importeClp, 0);
    expect(resultado.porItem.containsKey('sin-precio'), isFalse);
    expect(resultado.totalConocido, 0);
    expect(resultado.sinEstimacion, 1);
  });

  test(
    'suma importes redondeados por producto y excluye otras situaciones',
    () {
      final resultado = _calcular(
        [_compra(cantidad: 1, precio: 1)],
        items: [
          _pendiente('a', 1, 0.5, 'g'),
          _pendiente('b', 1, 0.5, 'g'),
          _pendiente('comprado', 1, 1000, 'g', estado: 'COMPRADO'),
          _pendiente('descartado', 1, 1000, 'g', estado: 'DESCARTADO'),
        ],
      );
      expect(resultado.totalConocido, 2);
      expect(resultado.pendientes, 2);
      expect(resultado.sinEstimacion, 0);
    },
  );

  test('no estima cantidades pendientes inválidas o incompatibles', () {
    for (final item in [
      _pendiente('p', 1, 0, 'g'),
      _pendiente('p', 1, 1, 'L'),
      _pendiente('p', 1, 'NaN', 'g'),
      _pendiente('p', 1, 1e308, 'kg'),
    ]) {
      expect(_calcular([_compra()], items: [item]).totalConocido, isNull);
    }
  });

  test('calcular no altera los datos de las compras', () {
    final compras = [_compra()];
    final antes = jsonEncode(compras);
    _calcular(compras);
    expect(jsonEncode(compras), antes);
  });

  Future<EstimacionGasto> consultar({List<Map<String, dynamic>>? items}) =>
      consultarEstimacionCompra(
        supabase: Supabase.instance.client,
        hogarId: 'hogar-a',
        items: items ?? servidor.items['lista-actual']!,
        unidadesBase: _unidades,
      );

  test(
    'consulta el historial en lectura y no solicita el precio del inventario',
    () async {
      final resultado = await consultar();
      expect(resultado.totalConocido, 2000);
      expect(servidor.peticiones, hasLength(1));
      expect(
        servidor.peticiones.every((peticion) => peticion.method == 'GET'),
        isTrue,
      );
      final consulta = servidor.peticiones.single.url.queryParameters;
      expect(consulta['hogar_id'], 'eq.hogar-a');
      expect(consulta['select'], contains('precio_compra_clp'));
      expect(consulta['lista_compra_item.alimento_id'], 'in.(1)');
      expect(
        consulta['lista_compra_item.order'],
        contains('fecha_compra.desc'),
      );
    },
  );

  test(
    'pagina las listas y encuentra referencias más allá de la primera página',
    () async {
      servidor.listas.clear();
      servidor.historial.clear();
      for (var i = 0; i < 101; i++) {
        final id = 'lista-${i.toString().padLeft(3, '0')}';
        servidor.listas.add({'id': id, 'hogar_id': 'hogar-a'});
      }
      servidor.historial['lista-100'] = [_compra()];
      expect((await consultar()).totalConocido, 2000);
      expect(servidor.peticiones, hasLength(2));
    },
  );

  test(
    'pagina el historial de cada lista hasta hallar una referencia válida',
    () async {
      servidor.historial['lista-actual'] = [
        for (var i = 0; i < 400; i++)
          _compra(
            id: 'invalida-$i',
            precio: null,
            fecha: '2026-10-20T12:00:00Z',
          ),
        _compra(id: 'valida'),
      ];
      expect((await consultar()).totalConocido, 2000);
      expect(servidor.peticiones, hasLength(2));
      expect(
        servidor
            .peticiones
            .last
            .url
            .queryParameters['lista_compra_item.offset'],
        '400',
      );
      expect(
        servidor.peticiones.last.url.queryParameters['id'],
        'in.("lista-actual")',
      );
    },
  );

  test('una lista de otro hogar no aporta referencias', () async {
    servidor.historial.clear();
    servidor.listas.add({'id': 'ajena', 'hogar_id': 'hogar-b'});
    servidor.historial['ajena'] = [_compra(hogar: 'hogar-b')];
    expect((await consultar()).totalConocido, isNull);
  });

  test('no consulta históricos cuando no hay productos pendientes', () async {
    final resultado = await consultar(
      items: [_pendiente('p', 1, 500, 'g', estado: 'COMPRADO')],
    );
    expect(resultado.pendientes, 0);
    expect(servidor.peticiones, isEmpty);
  });

  test(
    'varios pendientes del mismo alimento comparten la consulta histórica',
    () async {
      final resultado = await consultar(
        items: [_pendiente('a', 1, 500, 'g'), _pendiente('b', 1, 1, 'kg')],
      );
      expect(resultado.totalConocido, 6000);
      expect(servidor.peticiones, hasLength(1));
    },
  );

  test('agrupa los alimentos en lotes sin consultar uno por uno', () async {
    servidor.historial['lista-actual'] = [
      for (var id = 1; id <= 101; id++)
        _compra(id: 'compra-$id', alimento: id, precio: 1000),
    ];
    final resultado = await consultarEstimacionCompra(
      supabase: Supabase.instance.client,
      hogarId: 'hogar-a',
      items: [
        for (var id = 1; id <= 101; id++) _pendiente('p-$id', id, 500, 'g'),
      ],
      unidadesBase: {for (var id = 1; id <= 101; id++) id: 'g'},
    );
    expect(resultado.totalConocido, 50500);
    expect(servidor.peticiones, hasLength(2));
  });

  Future<void> resolverConsultas(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> abrirLista(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: ListaComprasScreen(hogar: {'id': 'hogar-a', 'nombre': 'Casa'}),
      ),
    );
    await resolverConsultas(tester);
  }

  testWidgets(
    'presenta importe, fecha, total parcial y productos sin referencia',
    (tester) async {
      servidor.items['lista-actual']!.add(_pendiente('sin-precio', 2, 1, 'L'));
      await abrirLista(tester);
      expect(find.textContaining('Estimación: \$2.000'), findsOneWidget);
      expect(find.textContaining('Referencia: 01/10/2026'), findsOneWidget);
      expect(find.text('Total estimado conocido'), findsOneWidget);
      expect(find.text('\$2.000'), findsOneWidget);
      expect(find.text('1 producto(s) sin estimación.'), findsOneWidget);
      expect(find.text('Sin estimación'), findsOneWidget);
    },
  );

  testWidgets('sin referencias no presenta un total de cero', (tester) async {
    servidor.historial.clear();
    await abrirLista(tester);
    expect(find.text('Sin estimación'), findsNWidgets(2));
    expect(find.text('\$0'), findsNothing);
  });

  testWidgets('el precio cero sí aparece como importe conocido', (
    tester,
  ) async {
    servidor.historial['lista-actual'] = [_compra(precio: 0)];
    await abrirLista(tester);
    expect(find.textContaining('Estimación: \$0'), findsOneWidget);
    expect(find.text('\$0'), findsOneWidget);
    expect(find.text('0 producto(s) sin estimación.'), findsOneWidget);
  });

  testWidgets('fallo del historial permite seguir abriendo la confirmación', (
    tester,
  ) async {
    servidor.fallaHistorial = true;
    await abrirLista(tester);
    expect(find.textContaining('Puedes seguir comprando'), findsOneWidget);
    final boton = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(boton.onPressed, isNotNull);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    expect(find.text('Confirmar compra'), findsOneWidget);
    expect(servidor.confirmaciones, 0);
  });

  testWidgets('historial lento no deshabilita los productos ni el agregado', (
    tester,
  ) async {
    servidor.historialPendiente = Completer<http.Response>();
    await abrirLista(tester);
    expect(find.text('Calculando estimación...'), findsNWidgets(2));
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged,
      isNotNull,
    );
    expect(
      tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed,
      isNotNull,
    );
    servidor.historialPendiente!.complete(servidor.respuestaRetardada!);
    await resolverConsultas(tester);
    expect(find.text('\$2.000'), findsOneWidget);
  });

  testWidgets('descarta la estimación tardía al seleccionar otra lista', (
    tester,
  ) async {
    servidor.historialPendiente = Completer<http.Response>();
    servidor.listas.add({
      'id': 'lista-otra',
      'hogar_id': 'hogar-a',
      'nombre': 'Otra',
      'estado': 'ABIERTA',
      'creada_en': '2026-10-27T12:00:00Z',
    });
    servidor.items['lista-otra'] = [
      {..._pendiente('p-otra', 1, 2000, 'g'), 'lista_id': 'lista-otra'},
    ];
    await abrirLista(tester);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Otra (ABIERTA)').last);
    await resolverConsultas(tester);
    expect(find.text('\$8.000'), findsOneWidget);
    servidor.historialPendiente!.complete(servidor.respuestaRetardada!);
    await resolverConsultas(tester);
    expect(find.text('\$8.000'), findsOneWidget);
    expect(find.text('\$2.000'), findsNothing);
  });

  testWidgets(
    'confirmar conserva el precio real y recalcula solo los pendientes',
    (tester) async {
      await abrirLista(tester);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      final confirmar = find.text('Confirmar e ingresar a despensa');
      await tester.scrollUntilVisible(
        confirmar,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), '2750');
      await tester.tap(confirmar);
      await resolverConsultas(tester);
      await tester.pumpAndSettle();
      await resolverConsultas(tester);
      expect(servidor.confirmaciones, 1);
      expect(servidor.parametrosCompra!['p_precio_clp'], 2750);
      expect(find.text('No hay productos pendientes.'), findsOneWidget);
      expect(find.textContaining('Estimación: '), findsNothing);
    },
  );
}
