import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nfc_foodtech_app/features/compras/screens/confirmar_compra_screen.dart';
import 'package:nfc_foodtech_app/features/compras/screens/lista_compras_screen.dart';
import 'package:nfc_foodtech_app/features/compras/widgets/advertencia_stock.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _ingreso(
  String id,
  dynamic cantidad, {
  String hogar = 'hogar-a',
  int alimento = 1,
  String estado = 'DISPONIBLE',
}) => {
  'id': id,
  'hogar_id': hogar,
  'alimento_id': alimento,
  'estado': estado,
  'cantidad_restante': cantidad,
};

class _ServidorCompras {
  String unidadBase = 'g';
  String? hogarAlimento;
  bool listaDisponible = true;
  bool fallaStock = false;
  int consultasStock = 0;
  int confirmaciones = 0;
  int agregados = 0;
  Map<String, dynamic>? parametrosCompra;
  Completer<http.Response>? compraPendiente;
  final List<Map<String, dynamic>> inventario = [];
  final List<http.Request> solicitudesStock = [];
  final List<Map<String, dynamic>> items = [];
  final List<String> peticiones = [];

  Map<String, dynamic> get producto => {
    'id': 'item-1',
    'lista_id': 'lista-1',
    'alimento_id': 1,
    'nombre_alimento': 'Arroz',
    'cantidad': 1,
    'unidad': 'kg',
    'estado': 'PENDIENTE',
    'despensa_item_id': null,
  };

  http.Response respuesta(dynamic datos, {http.Request? solicitud}) =>
      http.Response(
        jsonEncode(datos),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
        request:
            solicitud ??
            http.Request('GET', Uri.parse('https://prueba.example.com')),
      );

  Future<http.Response> atender(http.Request solicitud) async {
    final ruta = solicitud.url.path;
    final consulta = solicitud.url.queryParameters;
    peticiones.add(solicitud.url.toString());
    http.Response responder(dynamic datos) =>
        respuesta(datos, solicitud: solicitud);

    if (ruta == '/auth/v1/token') {
      String codificar(Map<String, dynamic> valor) =>
          base64Url.encode(utf8.encode(jsonEncode(valor))).replaceAll('=', '');
      final token =
          '${codificar({'alg': 'HS256'})}.'
          '${codificar({'sub': 'usuario-1', 'exp': 4133980800})}.firma';
      return responder({
        'access_token': token,
        'refresh_token': 'refresh-prueba',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'usuario-1',
          'aud': 'authenticated',
          'email': 'prueba@example.com',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-01-01T00:00:00Z',
        },
      });
    }

    if (ruta == '/rest/v1/alimento') {
      if (consulta['hogar_id'] == 'eq.hogar-a') return responder([]);
      return responder([
        {
          'id': 1,
          'nombre': 'Arroz',
          'unidad_base': unidadBase,
          'hogar_id': hogarAlimento,
        },
      ]);
    }

    if (ruta == '/rest/v1/despensa_item') {
      consultasStock++;
      solicitudesStock.add(solicitud);
      if (fallaStock) throw http.ClientException('Sin conexión');
      final desde = int.parse(consulta['offset']!);
      final limite = int.parse(consulta['limit']!);
      return responder(inventario.skip(desde).take(limite).toList());
    }

    if (ruta == '/rest/v1/lista_compra') {
      expect(consulta['hogar_id'], 'eq.hogar-a');
      return responder([
        if (listaDisponible)
          {'id': 'lista-1', 'nombre': 'Semana', 'estado': 'ABIERTA'},
      ]);
    }

    if (ruta == '/rest/v1/lista_compra_item') {
      if (solicitud.method == 'POST') {
        agregados++;
        items.add({
          ...jsonDecode(solicitud.body) as Map<String, dynamic>,
          'id': 'item-agregado',
        });
        return http.Response('', 201, request: solicitud);
      }
      expect(consulta['lista_id'], 'eq.lista-1');
      if (consulta.containsKey('id')) {
        final id = consulta['id']!.substring(3);
        return responder([
          if (id == producto['id']) producto,
          ...items.where((item) => item['id'] == id),
        ]);
      }
      return responder(items);
    }

    if (ruta == '/rest/v1/rpc/m27_confirmar_compra_item') {
      confirmaciones++;
      parametrosCompra = jsonDecode(solicitud.body) as Map<String, dynamic>;
      return compraPendiente == null
          ? responder('ingreso-1')
          : await compraPendiente!.future;
    }

    throw StateError('Petición no prevista en la prueba: $solicitud');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ServidorCompras servidor;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    servidor = _ServidorCompras();
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

  tearDown(() async {
    await Supabase.instance.dispose();
  });

  Future<StockCompra> consultar({dynamic cantidad = 1, String unidad = 'kg'}) {
    return consultarStockCompra(
      supabase: Supabase.instance.client,
      hogarId: 'hogar-a',
      alimentoId: 1,
      cantidad: cantidad,
      unidad: unidad,
    );
  }

  Future<void> resolverConsultas(WidgetTester tester) async {
    // El cliente HTTP procesa sus streams fuera del reloj de las animaciones.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    // Un diálogo puede mantener visible el indicador de la pantalla inferior.
    await tester.pump(const Duration(milliseconds: 500));
  }

  for (final caso in [
    (unidad: 'g', base: 'g', cantidad: 500, esperado: 500.0),
    (unidad: 'kg', base: 'g', cantidad: 0.5, esperado: 500.0),
    (unidad: 'ml', base: 'ml', cantidad: 500, esperado: 500.0),
    (unidad: 'L', base: 'ml', cantidad: 0.5, esperado: 500.0),
    (unidad: 'l', base: 'ml', cantidad: 2, esperado: 2000.0),
    (unidad: 'un', base: 'un', cantidad: 0.5, esperado: 0.5),
  ]) {
    test('convierte ${caso.cantidad} ${caso.unidad} a ${caso.base}', () {
      expect(
        cantidadCompraEnBase(caso.cantidad, caso.unidad, caso.base),
        caso.esperado,
      );
    });
  }

  test('no compara dimensiones incompatibles o unidades desconocidas', () {
    for (final par in [('kg', 'ml'), ('L', 'g'), ('un', 'g'), ('caja', 'un')]) {
      expect(cantidadCompraEnBase(1, par.$1, par.$2), isNull);
    }
  });

  test('rechaza cantidades inválidas, no finitas y desbordamientos', () {
    for (final cantidad in [
      null,
      'inválida',
      0,
      -1,
      double.nan,
      double.infinity,
    ]) {
      expect(cantidadCompraEnBase(cantidad, 'kg', 'g'), isNull);
    }
    expect(cantidadCompraEnBase(1e308, 'kg', 'g'), isNull);
  });

  for (final caso in [
    (stock: 1500, suficiente: true),
    (stock: 1000, suficiente: true),
    (stock: 999, suficiente: false),
    (stock: 0, suficiente: false),
  ]) {
    test('evalúa ${caso.stock} g frente a 1 kg', () async {
      servidor.inventario.add(_ingreso('ingreso-1', caso.stock));
      final stock = await consultar();
      expect(stock.suficiente, caso.suficiente);
    });
  }

  test('suma ingresos y excluye otros hogares, alimentos y estados', () async {
    servidor.inventario.addAll([
      _ingreso('a', 400),
      _ingreso('b', 600),
      _ingreso('c', 9000, hogar: 'hogar-b'),
      _ingreso('d', 9000, alimento: 2),
      _ingreso('e', 9000, estado: 'AGOTADO'),
    ]);
    final stock = await consultar();
    expect(stock.disponible, 1000);
    expect(stock.suficiente, isTrue);
    final filtros = servidor.solicitudesStock.single.url.queryParameters;
    expect(filtros['hogar_id'], 'eq.hogar-a');
    expect(filtros['alimento_id'], 'eq.1');
    expect(filtros['estado'], 'eq.DISPONIBLE');
    expect(filtros['cantidad_restante'], 'gt.0');
  });

  test('consulta todas las páginas de existencias', () async {
    servidor.inventario.addAll([
      for (var i = 0; i < 401; i++) _ingreso('ingreso-$i', 1),
    ]);
    final stock = await consultar(cantidad: 401, unidad: 'g');
    expect(stock.disponible, 401);
    expect(stock.suficiente, isTrue);
    expect(servidor.consultasStock, 2);
    expect(servidor.solicitudesStock.last.url.queryParameters['offset'], '400');
  });

  test('utiliza la unidad real y no permite alimentos de otro hogar', () async {
    servidor.unidadBase = 'ml';
    servidor.inventario.add(_ingreso('a', 1000));
    expect((await consultar()).suficiente, isNull);
    expect((await consultar(unidad: 'L')).suficiente, isTrue);
    servidor.hogarAlimento = 'hogar-b';
    expect((await consultar()).alimentoPermitido, isFalse);
  });

  test('stock inválido no equivale a stock cero', () async {
    servidor.inventario.add(_ingreso('a', 'inválida'));
    final stock = await consultar();
    expect(stock.disponible, isNull);
    expect(stock.suficiente, isNull);
  });

  test(
    'propaga el fallo de consulta para tratarlo como no verificado',
    () async {
      servidor.fallaStock = true;
      await expectLater(consultar(), throwsA(isA<http.ClientException>()));
    },
  );

  Future<void> abrirAviso(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => confirmarStockCompra(
                context: context,
                supabase: Supabase.instance.client,
                hogarId: 'hogar-a',
                alimentoId: 1,
                nombre: 'Arroz',
                cantidad: 1,
                unidad: 'kg',
              ),
              child: const Text('Consultar'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Consultar'));
    await resolverConsultas(tester);
  }

  testWidgets('muestra cantidades compatibles y permite cancelar', (
    tester,
  ) async {
    servidor.inventario.add(_ingreso('a', 1500));
    await abrirAviso(tester);
    expect(find.textContaining('Stock disponible: 1500 g'), findsOneWidget);
    expect(find.textContaining('deseas comprar: 1 kg'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(servidor.confirmaciones + servidor.agregados, 0);
  });

  testWidgets('fallo de red informa sin fingir stock cero', (tester) async {
    servidor.fallaStock = true;
    await abrirAviso(tester);
    await tester.pump(const Duration(seconds: 9));
    await resolverConsultas(tester);
    expect(find.text('No se pudo comprobar el stock'), findsOneWidget);
    expect(
      find.textContaining('Stock disponible: No disponible'),
      findsOneWidget,
    );
    expect(find.text('Continuar igualmente'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });

  testWidgets('no permite continuar con un alimento de otro hogar', (
    tester,
  ) async {
    servidor.hogarAlimento = 'hogar-b';
    await abrirAviso(tester);
    expect(find.text('Alimento no disponible para este hogar'), findsOneWidget);
    expect(find.text('Continuar igualmente'), findsNothing);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'unidades incompatibles permiten decidir sin afirmar suficiencia',
    (tester) async {
      servidor.unidadBase = 'ml';
      servidor.inventario.add(_ingreso('a', 1500));
      await abrirAviso(tester);
      expect(find.text('No se pudo comprobar el stock'), findsOneWidget);
      expect(find.textContaining('Stock disponible: 1500 ml'), findsOneWidget);
      await tester.tap(find.text('Continuar igualmente'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  Future<void> abrirConfirmacion(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ConfirmarCompraScreen(
                    hogar: const {'id': 'hogar-a'},
                    item: servidor.producto,
                    listaId: 'lista-1',
                  ),
                ),
              ),
              child: const Text('Abrir compra'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir compra'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Confirmar e ingresar a despensa'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ConfirmarCompraScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('cancelar al confirmar no ejecuta la RPC ni cierra la pantalla', (
    tester,
  ) async {
    servidor.inventario.add(_ingreso('a', 1000));
    await abrirConfirmacion(tester);
    await tester.tap(find.text('Confirmar e ingresar a despensa'));
    await resolverConsultas(tester);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(servidor.confirmaciones, 0);
    expect(find.byType(ConfirmarCompraScreen), findsOneWidget);
  });

  testWidgets('doble pulsación muestra un aviso y confirma una sola vez', (
    tester,
  ) async {
    servidor.inventario.add(_ingreso('a', 1000));
    await abrirConfirmacion(tester);
    await tester.enterText(find.byType(TextField), '1600');
    final confirmar = tester
        .widget<ElevatedButton>(
          find.widgetWithText(
            ElevatedButton,
            'Confirmar e ingresar a despensa',
          ),
        )
        .onPressed!;
    confirmar();
    confirmar();
    await resolverConsultas(tester);
    expect(servidor.consultasStock, 1, reason: servidor.peticiones.join('\n'));
    expect(find.byType(AlertDialog), findsOneWidget);
    final continuar = tester
        .widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Continuar igualmente'),
        )
        .onPressed!;
    continuar();
    continuar();
    await resolverConsultas(tester);
    expect(servidor.confirmaciones, 1);
    expect(servidor.parametrosCompra, {
      'p_lista_item_id': 'item-1',
      'p_ubicacion': 'DESPENSA',
      'p_fecha_vencimiento': null,
      'p_precio_clp': 1600,
    });
    expect(find.text('Abrir compra'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmación bloqueada mientras la RPC está pendiente', (
    tester,
  ) async {
    servidor.compraPendiente = Completer<http.Response>();
    await abrirConfirmacion(tester);
    await tester.tap(find.text('Confirmar e ingresar a despensa'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(servidor.confirmaciones, 1);
    expect(find.text('Registrando...'), findsOneWidget);
    final boton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Registrando...'),
    );
    expect(boton.onPressed, isNull);
    servidor.compraPendiente!.complete(servidor.respuesta('ingreso-1'));
    await tester.pumpAndSettle();
    expect(servidor.confirmaciones, 1);
  });

  testWidgets('lista fuera del hogar impide comprobar y confirmar', (
    tester,
  ) async {
    servidor.listaDisponible = false;
    await abrirConfirmacion(tester);
    await tester.tap(find.text('Confirmar e ingresar a despensa'));
    await resolverConsultas(tester);
    expect(servidor.consultasStock, 0);
    expect(servidor.confirmaciones, 0);
    expect(
      find.textContaining('La lista ya no está disponible'),
      findsOneWidget,
    );
  });

  Future<void> agregarDesdeFormulario(WidgetTester tester) async {
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'prueba@example.com',
      password: 'prueba-local',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: ListaComprasScreen(hogar: {'id': 'hogar-a', 'nombre': 'Casa'}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar alimento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arroz'));
    await tester.pumpAndSettle();
    final cantidad = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Cantidad',
    );
    await tester.enterText(cantidad, '1000');
    await tester.tap(find.text('Agregar a la lista').last);
    await resolverConsultas(tester);
  }

  for (final continuar in [false, true]) {
    testWidgets(
      'agregado manual con stock suficiente: ${continuar ? 'continuar' : 'cancelar'}',
      (tester) async {
        servidor.inventario.add(_ingreso('a', 1500));
        await agregarDesdeFormulario(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(servidor.consultasStock, 1);
        expect(servidor.agregados, 0);
        await tester.tap(
          find.text(continuar ? 'Continuar igualmente' : 'Cancelar'),
        );
        await resolverConsultas(tester);
        expect(servidor.agregados, continuar ? 1 : 0);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(ListaComprasScreen), findsOneWidget);
      },
    );
  }

  testWidgets('agregado manual y confirmación consultan stock por separado', (
    tester,
  ) async {
    await agregarDesdeFormulario(tester);
    expect(servidor.agregados, 1);
    expect(servidor.consultasStock, 1);
    servidor.inventario.add(_ingreso('a', 2000));
    final abrirCompra = tester
        .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
        .onChanged!;
    abrirCompra(true);
    abrirCompra(true);
    await tester.pumpAndSettle();
    expect(find.byType(ConfirmarCompraScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Confirmar e ingresar a despensa'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ConfirmarCompraScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Confirmar e ingresar a despensa'));
    await resolverConsultas(tester);
    expect(servidor.consultasStock, 2);
    expect(find.textContaining('Stock disponible: 2000 g'), findsOneWidget);
    expect(servidor.confirmaciones, 0);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });
}
