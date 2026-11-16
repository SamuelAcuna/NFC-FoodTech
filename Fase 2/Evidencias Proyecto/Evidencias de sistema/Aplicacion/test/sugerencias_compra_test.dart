import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nfc_foodtech_app/features/compras/screens/sugerencias_compra_screen.dart';
import 'package:nfc_foodtech_app/shared/widgets/sugerencias_compra.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _ahora = DateTime.utc(2026, 10, 28, 12);

Map<String, dynamic> _item({
  String id = 'ingreso-1',
  int alimento = 1,
  dynamic stock = 100,
  String hogar = 'hogar-a',
  String estado = 'DISPONIBLE',
}) => {
  'id': id,
  'alimento_id': alimento,
  'hogar_id': hogar,
  'estado': estado,
  'cantidad_restante': stock,
};

Map<String, dynamic> _alimento({
  int id = 1,
  String unidad = 'g',
  String? hogar,
  bool activo = true,
}) => {
  'id': id,
  'nombre': 'Arroz $id',
  'unidad_base': unidad,
  'hogar_id': hogar,
  'activo': activo,
};

Map<String, dynamic> _movimiento({
  String id = 'mov-1',
  String item = 'ingreso-1',
  dynamic cantidad = 1500,
  String tipo = 'CONSUMO',
  DateTime? fecha,
}) => {
  'id': id,
  'despensa_item_id': item,
  'tipo': tipo,
  'cantidad': cantidad,
  'fecha': (fecha ?? _ahora.subtract(const Duration(days: 2)))
      .toIso8601String(),
};

List<Map<String, dynamic>> _consumos(DateTime ahora) => [
  _movimiento(fecha: ahora.subtract(const Duration(days: 2))),
  _movimiento(id: 'mov-2', fecha: ahora.subtract(const Duration(days: 4))),
];

ResultadoSugerenciasCompra _calcular({
  List<Map<String, dynamic>>? items,
  List<Map<String, dynamic>>? movimientos,
  List<Map<String, dynamic>>? alimentos,
  List<Map<String, dynamic>> itemsLista = const [],
}) => calcularSugerenciasCompra(
  hogarId: 'hogar-a',
  ahora: _ahora,
  items: items ?? [_item()],
  movimientos: movimientos ?? _consumos(_ahora),
  alimentos: alimentos ?? [_alimento()],
  itemsLista: itemsLista,
);

class _ServidorSugerencias {
  final items = <Map<String, dynamic>>[_item()];
  final alimentos = <Map<String, dynamic>>[_alimento()];
  final movimientos = _consumos(DateTime.now().toUtc());
  final pendientes = <Map<String, dynamic>>[];
  final solicitudes = <http.Request>[];
  bool listaAbierta = true;
  bool fallaLectura = false;
  bool rechazaAgregado = false;
  bool respuestaIncierta = false;
  int agregados = 0;

  Future<http.Response> atender(http.Request solicitud) async {
    solicitudes.add(solicitud);
    final q = solicitud.url.queryParameters;
    final ruta = solicitud.url.path;
    http.Response responder(dynamic datos, {int estado = 200}) => http.Response(
      jsonEncode(datos),
      estado,
      request: solicitud,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    if (ruta == '/auth/v1/token') {
      String codificar(Map<String, dynamic> dato) =>
          base64Url.encode(utf8.encode(jsonEncode(dato))).replaceAll('=', '');
      return responder({
        'access_token':
            '${codificar({'alg': 'HS256'})}.${codificar({'sub': 'usuario-1', 'exp': 4133980800})}.firma',
        'refresh_token': 'refresh-prueba',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'usuario-1',
          'aud': 'authenticated',
          'email': 'prueba@example.com',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-01-01T00:00:00Z',
        },
      });
    }
    if (solicitud.method == 'POST') {
      expectSync(ruta, '/rest/v1/lista_compra_item');
      agregados++;
      if (rechazaAgregado)
        return responder({
          'message': 'Compra rechazada',
          'code': '42501',
        }, estado: 403);
      pendientes.add({
        ...jsonDecode(solicitud.body) as Map<String, dynamic>,
        'id': 'nuevo-$agregados',
      });
      if (respuestaIncierta)
        return http.Response('respuesta incompleta', 200, request: solicitud);
      return http.Response('', 201, request: solicitud);
    }
    expectSync(solicitud.method, 'GET');
    if (fallaLectura)
      return responder({
        'message': 'Lectura fallida',
        'code': '42501',
      }, estado: 403);
    List<Map<String, dynamic>> paginar(Iterable<Map<String, dynamic>> filas) =>
        filas
            .skip(int.parse(q['offset'] ?? '0'))
            .take(int.parse(q['limit'] ?? '1000'))
            .toList();
    bool coincide(dynamic valor, String? filtro) {
      if (filtro == null) return true;
      if (filtro.startsWith('eq.'))
        return valor.toString() == filtro.substring(3);
      return filtro
          .substring(4, filtro.length - 1)
          .split(',')
          .map((id) => id.replaceAll('"', ''))
          .contains(valor.toString());
    }

    if (ruta == '/rest/v1/lista_compra') {
      expectSync(q['id'], 'eq.lista-1');
      expectSync(q['hogar_id'], 'eq.hogar-a');
      expectSync(q['estado'], 'eq.ABIERTA');
      return responder([
        if (listaAbierta)
          {'id': 'lista-1', 'hogar_id': 'hogar-a', 'estado': 'ABIERTA'},
      ]);
    }
    if (ruta == '/rest/v1/despensa_item') {
      expectSync(q['hogar_id'], 'eq.hogar-a');
      return responder(
        paginar(
          items.where(
            (i) =>
                i['hogar_id'] == 'hogar-a' &&
                coincide(i['alimento_id'], q['alimento_id']) &&
                coincide(i['estado'], q['estado']) &&
                (q['cantidad_restante'] == null ||
                    (i['cantidad_restante'] as num) > 0),
          ),
        ),
      );
    }
    if (ruta == '/rest/v1/lista_compra_item') {
      expectSync(q['lista_id'], 'eq.lista-1');
      expectSync(q['estado'], 'eq.PENDIENTE');
      return responder(
        paginar(
          pendientes.where(
            (i) =>
                i['estado'] == 'PENDIENTE' &&
                coincide(i['alimento_id'], q['alimento_id']),
          ),
        ),
      );
    }
    if (ruta == '/rest/v1/movimiento') {
      expectSync(q['tipo'], 'eq.CONSUMO');
      expectSync(
        solicitud.url.queryParametersAll['fecha']!.any(
          (f) => f.startsWith('gte.'),
        ),
        isTrue,
      );
      expectSync(
        solicitud.url.queryParametersAll['fecha']!.any(
          (f) => f.startsWith('lte.'),
        ),
        isTrue,
      );
      expectSync(q['order'], 'fecha.desc.nullslast,id.desc.nullslast');
      return responder(
        paginar(
          movimientos.where(
            (m) =>
                m['tipo'] == 'CONSUMO' &&
                coincide(m['despensa_item_id'], q['despensa_item_id']),
          ),
        ),
      );
    }
    if (ruta == '/rest/v1/alimento') {
      return responder(
        alimentos.where((a) => coincide(a['id'], q['id'])).toList(),
      );
    }
    throw StateError('Petición inesperada: $solicitud');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Cálculo R69', () {
    test('repone siete días a partir de treinta, restando el stock real', () {
      final s = _calcular().sugerencias.single;
      expect(s.consumido, 3000);
      expect(s.diasConsumo, 2);
      expect(s.objetivo, 700);
      expect(s.disponible, 100);
      expect(s.sugerido, 600);
    });
    test('dos eventos el mismo día no son suficientes', () {
      expect(
        _calcular(
          movimientos: [
            _movimiento(),
            _movimiento(id: 'otro'),
          ],
        ).sugerencias,
        isEmpty,
      );
    });
    test('descartes y ajustes no cuentan como consumo', () {
      expect(
        _calcular(
          movimientos: [
            _movimiento(),
            _movimiento(id: 'descarte', tipo: 'DESCARTE'),
            _movimiento(id: 'ajuste', tipo: 'AJUSTE'),
          ],
        ).sugerencias,
        isEmpty,
      );
    });
    test('sin historial no inventa sugerencias', () {
      expect(_calcular(movimientos: []).sugerencias, isEmpty);
    });
    test('excluye movimientos anteriores a treinta días y futuros', () {
      final r = _calcular(
        movimientos: [
          ..._consumos(_ahora),
          _movimiento(
            id: 'viejo',
            fecha: _ahora.subtract(const Duration(days: 31)),
          ),
          _movimiento(
            id: 'futuro',
            fecha: _ahora.add(const Duration(seconds: 1)),
          ),
        ],
      );
      expect(r.sugerencias.single.consumido, 3000);
    });
    test('incluye el límite de treinta días', () {
      expect(
        _calcular(
          movimientos: [
            _movimiento(),
            _movimiento(
              id: 'limite',
              fecha: _ahora.subtract(const Duration(days: 30)),
            ),
          ],
        ).sugerencias.single.diasConsumo,
        2,
      );
    });
    test('suma todos los ingresos disponibles del alimento', () {
      final s = _calcular(
        items: [
          _item(),
          _item(id: 'otro', stock: 200),
          _item(id: 'agotado', stock: 900, estado: 'AGOTADO'),
        ],
      ).sugerencias.single;
      expect(s.disponible, 300);
      expect(s.sugerido, 400);
    });
    test('el stock suficiente no genera sugerencia', () {
      expect(_calcular(items: [_item(stock: 700)]).sugerencias, isEmpty);
    });
    test('un ingreso agotado permite usar su historial de consumo', () {
      expect(
        _calcular(
          items: [_item(stock: 0, estado: 'AGOTADO')],
        ).sugerencias.single.sugerido,
        700,
      );
    });
    for (final invalido in [null, -1, 'NaN', 'Infinity', 'desconocido']) {
      test('stock inválido $invalido no se interpreta como cero', () {
        final r = _calcular(items: [_item(stock: invalido)]);
        expect(r.sugerencias, isEmpty);
        expect(r.registrosInvalidos, 1);
      });
    }
    test('ignora cantidades y fechas inválidas de consumo', () {
      final r = _calcular(
        movimientos: [
          ..._consumos(_ahora),
          _movimiento(id: 'negativo', cantidad: -20),
          _movimiento(id: 'nulo', cantidad: null),
          {..._movimiento(id: 'fecha'), 'fecha': 'inválida'},
          _movimiento(id: '', cantidad: 999),
        ],
      );
      expect(r.sugerencias.single.consumido, 3000);
      expect(r.registrosInvalidos, 4);
    });
    test('no duplica ingresos ni movimientos repetidos entre páginas', () {
      expect(
        _calcular(
          items: [_item(), _item()],
          movimientos: [..._consumos(_ahora), ..._consumos(_ahora)],
        ).sugerencias.single.sugerido,
        600,
      );
    });
    test('no mezcla inventario ni consumos de otro hogar', () {
      final r = _calcular(
        items: [
          _item(),
          _item(id: 'ajeno', hogar: 'hogar-b', stock: 9000),
        ],
        movimientos: [
          ..._consumos(_ahora),
          _movimiento(id: 'ajeno', item: 'ajeno', cantidad: 9999),
        ],
      );
      expect(r.sugerencias.single.sugerido, 600);
    });
    test('rechaza alimentos privados de otro hogar e inactivos', () {
      expect(
        _calcular(alimentos: [_alimento(hogar: 'hogar-b')]).sugerencias,
        isEmpty,
      );
      expect(
        _calcular(alimentos: [_alimento(activo: false)]).sugerencias,
        isEmpty,
      );
    });
    for (final unidad in ['g', 'ml', 'un']) {
      test('conserva la unidad base $unidad sin mezclar dimensiones', () {
        expect(
          _calcular(
            alimentos: [_alimento(unidad: unidad)],
          ).sugerencias.single.unidadBase,
          unidad,
        );
      });
    }
    test('unidad base desconocida no se convierte a unidades', () {
      expect(
        _calcular(alimentos: [_alimento(unidad: 'kg')]).sugerencias,
        isEmpty,
      );
    });
    test('PENDIENTE excluye pero COMPRADO permite volver a sugerir', () {
      expect(
        _calcular(
          itemsLista: [
            {'alimento_id': 1, 'estado': 'PENDIENTE'},
          ],
        ).sugerencias,
        isEmpty,
      );
      expect(
        _calcular(
          itemsLista: [
            {'alimento_id': 1, 'estado': 'COMPRADO'},
          ],
        ).sugerencias,
        hasLength(1),
      );
    });
    test('redondea a tres decimales y descarta cantidades fuera de rango', () {
      expect(
        _calcular(
          movimientos: [
            _movimiento(cantidad: 1),
            _movimiento(
              id: 'm2',
              cantidad: 1,
              fecha: _ahora.subtract(const Duration(days: 3)),
            ),
          ],
          items: [_item(stock: 0)],
        ).sugerencias.single.sugerido,
        0.467,
      );
      expect(
        _calcular(
          movimientos: [
            _movimiento(cantidad: 1e10),
            _movimiento(
              id: 'm2',
              cantidad: 1e10,
              fecha: _ahora.subtract(const Duration(days: 3)),
            ),
          ],
        ).sugerencias,
        isEmpty,
      );
    });
    test('prioriza menor cobertura de consumo', () {
      final r = _calcular(
        items: [
          _item(),
          _item(id: 'segundo', alimento: 2, stock: 0),
        ],
        alimentos: [
          _alimento(),
          _alimento(id: 2, unidad: 'ml'),
        ],
        movimientos: [
          ..._consumos(_ahora),
          _movimiento(id: 'm3', item: 'segundo'),
          _movimiento(
            id: 'm4',
            item: 'segundo',
            fecha: _ahora.subtract(const Duration(days: 5)),
          ),
        ],
      );
      expect(r.sugerencias.map((s) => s.alimentoId), [2, 1]);
    });
  });

  group('Consultas y aceptación R69', () {
    late _ServidorSugerencias servidor;
    late SupabaseClient cliente;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      servidor = _ServidorSugerencias();
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
      cliente = Supabase.instance.client;
    });
    tearDown(() async => Supabase.instance.dispose());

    Future<ResultadoSugerenciasCompra> consultar({int? alimento}) =>
        consultarSugerenciasCompra(
          supabase: cliente,
          hogarId: 'hogar-a',
          listaId: 'lista-1',
          alimentoId: alimento,
        );

    Future<void> estabilizar(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    Future<void> abrir(WidgetTester tester) async {
      await cliente.auth.signInWithPassword(
        email: 'prueba@example.com',
        password: 'prueba',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: SugerenciasCompraScreen(
            hogar: {'id': 'hogar-a', 'nombre': 'Casa'},
            listaId: 'lista-1',
          ),
        ),
      );
      await estabilizar(tester);
    }

    Future<void> dialogo(WidgetTester tester) async {
      await tester.ensureVisible(
        find.widgetWithText(ElevatedButton, 'Agregar'),
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> enviar(WidgetTester tester) async {
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Agregar a la lista'),
      );
      await estabilizar(tester);
    }

    test('valida hogar y lista abierta y solo realiza lecturas', () async {
      expect((await consultar()).sugerencias.single.sugerido, 600);
      expect(servidor.solicitudes.every((s) => s.method == 'GET'), isTrue);
    });
    test('lista cerrada bloquea antes de consultar inventario', () async {
      servidor.listaAbierta = false;
      await expectLater(consultar(), throwsStateError);
      expect(servidor.solicitudes, hasLength(1));
    });
    test('pagina todos los ingresos y divide movimientos por lotes', () async {
      servidor.items.addAll(
        List.generate(400, (i) => _item(id: 'extra-$i', stock: 1)),
      );
      expect((await consultar()).sugerencias.single.sugerido, 200);
      expect(
        servidor.solicitudes.where(
          (s) => s.url.path.endsWith('/despensa_item'),
        ),
        hasLength(2),
      );
      expect(
        servidor.solicitudes.where((s) => s.url.path.endsWith('/movimiento')),
        hasLength(6),
      );
    });
    test('pagina más de cuatrocientos consumos', () async {
      servidor.movimientos.clear();
      servidor.movimientos.addAll(
        List.generate(
          401,
          (i) => _movimiento(
            id: 'm-$i',
            cantidad: 10,
            fecha: DateTime.now().toUtc().subtract(
              Duration(days: i.isEven ? 2 : 4),
            ),
          ),
        ),
      );
      expect((await consultar()).sugerencias.single.consumido, 4010);
      expect(
        servidor.solicitudes.where((s) => s.url.path.endsWith('/movimiento')),
        hasLength(2),
      );
    });
    test('encuentra un pendiente después de la primera página', () async {
      servidor.pendientes.addAll(
        List.generate(
          400,
          (i) => {'id': 'p-$i', 'alimento_id': i + 2, 'estado': 'PENDIENTE'},
        ),
      );
      servidor.pendientes.add({
        'id': 'ultimo',
        'alimento_id': 1,
        'estado': 'PENDIENTE',
      });
      expect((await consultar()).sugerencias, isEmpty);
      expect(
        servidor.solicitudes.where(
          (s) => s.url.path.endsWith('/lista_compra_item'),
        ),
        hasLength(2),
      );
    });
    test(
      'revalidación focalizada consulta solo el alimento seleccionado',
      () async {
        await consultar(alimento: 1);
        for (final s in servidor.solicitudes.where(
          (s) =>
              s.url.path.endsWith('/despensa_item') ||
              s.url.path.endsWith('/lista_compra_item'),
        )) {
          expect(s.url.queryParameters['alimento_id'], 'eq.1');
        }
      },
    );
    test(
      'propaga error de lectura sin producir sugerencias parciales',
      () async {
        servidor.fallaLectura = true;
        await expectLater(consultar(), throwsA(isA<PostgrestException>()));
      },
    );
    testWidgets('explica consumo, stock, días y reposición', (tester) async {
      await abrir(tester);
      expect(find.text('Días con consumo registrado: 2'), findsOneWidget);
      expect(
        find.text('Objetivo orientativo para 7 días: 700 g'),
        findsOneWidget,
      );
      expect(find.text('Cantidad sugerida: 600 g'), findsOneWidget);
    });
    testWidgets('cancelar no agrega ni vuelve a consultar', (tester) async {
      await abrir(tester);
      final lecturas = servidor.solicitudes.length;
      await dialogo(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await estabilizar(tester);
      expect(servidor.agregados, 0);
      expect(servidor.solicitudes, hasLength(lecturas));
    });
    testWidgets('doble pulsación abre un diálogo y envía una sola vez', (
      tester,
    ) async {
      await abrir(tester);
      final agregar = tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Agregar'),
          )
          .onPressed!;
      agregar();
      agregar();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AlertDialog), findsOneWidget);
      final enviar = tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Agregar a la lista'),
          )
          .onPressed!;
      enviar();
      enviar();
      await estabilizar(tester);
      expect(servidor.agregados, 1);
      expect(servidor.pendientes.single['cantidad'], 600);
      expect(servidor.pendientes.single['unidad'], 'g');
      expect(servidor.pendientes.single['origen'], 'SUGERIDO_CONSUMO');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SugerenciasCompraScreen), findsOneWidget);
    });
    testWidgets(
      'stock ahora suficiente impide agregar una sugerencia obsoleta',
      (tester) async {
        await abrir(tester);
        await dialogo(tester);
        servidor.items[0]['cantidad_restante'] = 800;
        await enviar(tester);
        expect(servidor.agregados, 0);
        expect(
          find.textContaining('La sugerencia ya no aplica'),
          findsOneWidget,
        );
      },
    );
    testWidgets('stock cambiado exige revisar la cantidad actualizada', (
      tester,
    ) async {
      await abrir(tester);
      await dialogo(tester);
      servidor.items[0]['cantidad_restante'] = 200;
      await enviar(tester);
      expect(servidor.agregados, 0);
      expect(find.text('Cantidad sugerida: 500 g'), findsOneWidget);
    });
    testWidgets('pendiente creado por otro integrante impide agregar', (
      tester,
    ) async {
      await abrir(tester);
      await dialogo(tester);
      servidor.pendientes.add({
        'id': 'otro',
        'alimento_id': 1,
        'estado': 'PENDIENTE',
      });
      await enviar(tester);
      expect(servidor.agregados, 0);
      expect(
        find.textContaining('ya tiene un producto pendiente'),
        findsOneWidget,
      );
    });
    testWidgets('comprado anterior permite agregar un nuevo pendiente', (
      tester,
    ) async {
      servidor.pendientes.add({
        'id': 'anterior',
        'alimento_id': 1,
        'estado': 'COMPRADO',
      });
      await abrir(tester);
      await dialogo(tester);
      await enviar(tester);
      expect(servidor.agregados, 1);
    });
    testWidgets('lista cerrada mientras se decide impide insertar', (
      tester,
    ) async {
      await abrir(tester);
      await dialogo(tester);
      servidor.listaAbierta = false;
      await enviar(tester);
      expect(servidor.agregados, 0);
    });
    testWidgets('cantidad inválida conserva el diálogo sin enviar', (
      tester,
    ) async {
      await abrir(tester);
      await dialogo(tester);
      await tester.enterText(find.byType(TextField), '0');
      await enviar(tester);
      expect(find.text('La cantidad debe ser mayor que cero.'), findsOneWidget);
      expect(servidor.agregados, 0);
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await estabilizar(tester);
    });
    testWidgets('R70 permite cancelar sin insertar una compra innecesaria', (
      tester,
    ) async {
      servidor.items[0]['cantidad_restante'] = 600;
      await abrir(tester);
      await dialogo(tester);
      await enviar(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(servidor.agregados, 0);
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await estabilizar(tester);
      expect(servidor.agregados, 0);
    });
    testWidgets('revisa pendientes otra vez tras continuar en R70', (
      tester,
    ) async {
      servidor.items[0]['cantidad_restante'] = 600;
      await abrir(tester);
      await dialogo(tester);
      await enviar(tester);
      servidor.pendientes.add({
        'id': 'otro',
        'alimento_id': 1,
        'estado': 'PENDIENTE',
      });
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Continuar igualmente'),
      );
      await estabilizar(tester);
      expect(servidor.agregados, 0);
    });
    testWidgets('fallo de lectura muestra reintento y no realiza escrituras', (
      tester,
    ) async {
      servidor.fallaLectura = true;
      await abrir(tester);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(servidor.agregados, 0);
    });
    testWidgets('rechazo explícito del servidor muestra el error', (
      tester,
    ) async {
      servidor.rechazaAgregado = true;
      await abrir(tester);
      await dialogo(tester);
      await enviar(tester);
      expect(servidor.agregados, 1);
      expect(find.textContaining('Compra rechazada'), findsOneWidget);
      expect(find.textContaining('El servidor no confirmó'), findsNothing);
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Agregar'),
            )
            .onPressed,
        isNotNull,
      );
    });
    testWidgets('respuesta incierta no permite reenviar automáticamente', (
      tester,
    ) async {
      servidor.respuestaIncierta = true;
      await abrir(tester);
      await dialogo(tester);
      await enviar(tester);
      expect(servidor.agregados, 1);
      expect(find.textContaining('El servidor no confirmó'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Agregar'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Actualizar sugerencias'));
      await estabilizar(tester);
      expect(find.widgetWithText(ElevatedButton, 'Agregar'), findsNothing);
      expect(servidor.agregados, 1);
    });
  });
}
