import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nfc_foodtech_app/features/inventario/screens/movimiento_alimento_screen.dart';
import 'package:nfc_foodtech_app/features/inventario/widgets/reposicion_automatica.dart';
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
  'cantidad_restante': cantidad,
  'estado': estado,
};

Map<String, dynamic> _lista(String id, {String hogar = 'hogar-a'}) => {
  'id': id,
  'nombre': id,
  'hogar_id': hogar,
  'estado': 'ABIERTA',
};

class _ServidorReposicion {
  final ingresos = <Map<String, dynamic>>[_ingreso('ingreso-1', 1500)];
  final listas = <Map<String, dynamic>>[_lista('lista-1')];
  final productos = <Map<String, dynamic>>[];
  final movimientos = <Map<String, dynamic>>[
    {
      'id': 'anterior',
      'despensa_item_id': 'ingreso-1',
      'tipo': 'CONSUMO',
      'cantidad': 1500,
      'fecha': DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 3))
          .toIso8601String(),
    },
  ];
  final solicitudes = <http.Request>[];
  int consumos = 0;
  int inserciones = 0;
  int lecturasStock = 0;
  String unidad = 'g';
  String? hogarAlimento;
  bool rechazarConsumo = false;
  bool consumoIncierto = false;
  bool insercionIncierta = false;
  bool rechazarInsercion = false;
  bool fallarStock = false;
  bool fallarListas = false;
  Completer<void>? pausaConsumo;
  Completer<void>? pausaInsercion;
  void Function(int)? alConsultarStock;
  void Function()? alConsultarPendienteFinal;
  void Function(int)? alValidarLista;
  int validacionesLista = 0;

  Future<http.Response> atender(http.Request solicitud) async {
    solicitudes.add(solicitud);
    final ruta = solicitud.url.path;
    final q = solicitud.url.queryParameters;
    http.Response responder(dynamic datos, {int estado = 200}) => http.Response(
      jsonEncode(datos),
      estado,
      request: solicitud,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    http.Response rechazar(String mensaje) =>
        responder({'code': '42501', 'message': mensaje}, estado: 403);
    bool coincide(dynamic valor, String? filtro) {
      if (filtro == null) return true;
      if (filtro.startsWith('eq.'))
        return valor.toString() == filtro.substring(3);
      return filtro
          .substring(4, filtro.length - 1)
          .split(',')
          .map((v) => v.replaceAll('"', ''))
          .contains(valor.toString());
    }

    List<Map<String, dynamic>> paginar(Iterable<Map<String, dynamic>> filas) =>
        filas
            .skip(int.parse(q['offset'] ?? '0'))
            .take(int.parse(q['limit'] ?? '1000'))
            .toList();

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
    if (ruta == '/rest/v1/rpc/registrar_movimiento_despensa') {
      expectSync(solicitud.method, 'POST');
      consumos++;
      if (pausaConsumo != null) await pausaConsumo!.future;
      if (rechazarConsumo) return rechazar('Consumo rechazado');
      final datos = jsonDecode(solicitud.body) as Map<String, dynamic>;
      final ingreso = ingresos.singleWhere(
        (i) => i['id'] == datos['p_despensa_item_id'],
      );
      final cantidad = (datos['p_cantidad'] as num).toDouble();
      ingreso['cantidad_restante'] =
          (ingreso['cantidad_restante'] as num) - cantidad;
      if (ingreso['cantidad_restante'] == 0) ingreso['estado'] = 'AGOTADO';
      movimientos.add({
        'id': 'nuevo-$consumos',
        'despensa_item_id': ingreso['id'],
        'tipo': datos['p_tipo'],
        'cantidad': cantidad,
        'fecha': DateTime.now().toUtc().toIso8601String(),
      });
      if (consumoIncierto)
        return http.Response('respuesta incompleta', 200, request: solicitud);
      return responder(null);
    }
    if (ruta == '/rest/v1/lista_compra_item' && solicitud.method == 'POST') {
      inserciones++;
      if (pausaInsercion != null) await pausaInsercion!.future;
      if (rechazarInsercion) return rechazar('Inserción rechazada');
      productos.add({
        ...jsonDecode(solicitud.body) as Map<String, dynamic>,
        'id': 'producto-$inserciones',
      });
      if (insercionIncierta)
        return http.Response('respuesta incompleta', 200, request: solicitud);
      return http.Response('', 201, request: solicitud);
    }
    expectSync(solicitud.method, 'GET');
    if (ruta == '/rest/v1/tipo_desperdicio')
      return responder([
        {'id': 1, 'nombre': 'Deterioro'},
      ]);
    if (ruta == '/rest/v1/despensa_item') {
      expectSync(q['hogar_id'], 'eq.hogar-a');
      if (!q.containsKey('id')) {
        lecturasStock++;
        alConsultarStock?.call(lecturasStock);
        if (fallarStock) return rechazar('Stock no disponible');
        expectSync(q['alimento_id'], 'eq.1');
      }
      return responder(
        paginar(
          ingresos.where(
            (i) =>
                coincide(i['id'], q['id']) &&
                coincide(i['hogar_id'], q['hogar_id']) &&
                coincide(i['alimento_id'], q['alimento_id']),
          ),
        ),
      );
    }
    if (ruta == '/rest/v1/lista_compra') {
      expectSync(q['hogar_id'], 'eq.hogar-a');
      expectSync(q['estado'], 'eq.ABIERTA');
      if (q.containsKey('id')) alValidarLista?.call(++validacionesLista);
      if (fallarListas) return rechazar('Listas no disponibles');
      return responder(
        paginar(
          listas.where(
            (l) =>
                coincide(l['id'], q['id']) &&
                coincide(l['hogar_id'], q['hogar_id']) &&
                l['estado'] == 'ABIERTA',
          ),
        ),
      );
    }
    if (ruta == '/rest/v1/lista_compra_item') {
      expectSync(q['estado'], 'eq.PENDIENTE');
      expectSync(q['alimento_id'], 'eq.1');
      if (q['limit'] == '1') alConsultarPendienteFinal?.call();
      return responder(
        paginar(
          productos.where(
            (p) =>
                p['estado'] == 'PENDIENTE' &&
                coincide(p['lista_id'], q['lista_id']) &&
                coincide(p['alimento_id'], q['alimento_id']),
          ),
        ),
      );
    }
    if (ruta == '/rest/v1/movimiento') {
      expectSync(q['tipo'], 'eq.CONSUMO');
      final fechas = solicitud.url.queryParametersAll['fecha']!;
      final inicio = DateTime.parse(
        fechas.singleWhere((f) => f.startsWith('gte.')).substring(4),
      );
      final fin = DateTime.parse(
        fechas.singleWhere((f) => f.startsWith('lte.')).substring(4),
      );
      return responder(
        paginar(
          movimientos.where((m) {
            final fecha = DateTime.tryParse(m['fecha']?.toString() ?? '');
            return coincide(m['despensa_item_id'], q['despensa_item_id']) &&
                m['tipo'] == 'CONSUMO' &&
                (fecha == null ||
                    (!fecha.isBefore(inicio) && !fecha.isAfter(fin)));
          }),
        ),
      );
    }
    if (ruta == '/rest/v1/alimento')
      return responder([
        {
          'id': 1,
          'nombre': 'Arroz',
          'unidad_base': unidad,
          'activo': true,
          'hogar_id': hogarAlimento,
        },
      ]);
    throw StateError('Solicitud inesperada: $solicitud');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ServidorReposicion servidor;
  late SupabaseClient cliente;
  late ReposicionAutomatica operacion;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    servidor = _ServidorReposicion();
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
    await cliente.auth.signInWithPassword(
      email: 'prueba@example.com',
      password: 'prueba',
    );
    operacion = ReposicionAutomatica(supabase: cliente);
  });
  tearDown(() async => Supabase.instance.dispose());

  Future<ResultadoMovimientoAlimento> registrar({
    double cantidad = 1500,
    String tipo = 'CONSUMO',
    Future<String?> Function(List<Map<String, dynamic>>)? seleccionar,
  }) => operacion.registrar(
    hogarId: 'hogar-a',
    ingresoId: 'ingreso-1',
    tipo: tipo,
    cantidad: cantidad,
    motivoDescarte: tipo == 'DESCARTE' ? 1 : null,
    seleccionarLista:
        seleccionar ??
        (_) async => throw StateError('No debe solicitar selección'),
  );

  test('consumo parcial conserva el stock y no agrega', () async {
    final r = await registrar(cantidad: 500);
    expect(r.registrado, isTrue);
    expect(r.mensaje, contains('todavía existe stock'));
    expect(servidor.inserciones, 0);
    expect(servidor.lecturasStock, 1);
  });
  test(
    'agotamiento habitual incluye consumo actual y repone siete días',
    () async {
      final r = await registrar();
      expect(r.registrado, isTrue);
      expect(r.mensaje, startsWith('Consumo registrado. Reposición agregada'));
      expect(servidor.productos.single['cantidad'], 700);
      expect(servidor.productos.single['unidad'], 'g');
      expect(servidor.consumos, 1);
      expect(servidor.inserciones, 1);
    },
  );
  test(
    'otro ingreso con stock, incluso en otra ubicación, impide reponer',
    () async {
      servidor.ingresos.add({
        ..._ingreso('otro', 50),
        'ubicacion': 'CONGELADOR',
      });
      expect((await registrar()).mensaje, contains('todavía existe stock'));
      expect(servidor.inserciones, 0);
    },
  );
  test('stock posterior a mil ingresos no se omite por paginación', () async {
    servidor.ingresos.addAll(
      List.generate(1000, (i) => _ingreso('extra-$i', 0, estado: 'AGOTADO')),
    );
    servidor.ingresos.add(_ingreso('ultimo', 20));
    expect((await registrar()).mensaje, contains('todavía existe stock'));
    expect(servidor.lecturasStock, 3);
    expect(servidor.inserciones, 0);
  });
  test('un solo día de consumo no basta', () async {
    servidor.movimientos.clear();
    expect(
      (await registrar()).mensaje,
      contains('no hay historial habitual válido'),
    );
    expect(servidor.inserciones, 0);
  });
  test('dos consumos en el mismo día no bastan', () async {
    servidor.movimientos[0]['fecha'] = DateTime.now().toUtc().toIso8601String();
    expect(
      (await registrar()).mensaje,
      contains('no hay historial habitual válido'),
    );
  });
  test(
    'consumo de hace más de treinta días no acredita habitualidad',
    () async {
      servidor.movimientos[0]['fecha'] = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 31))
          .toIso8601String();
      expect(
        (await registrar()).mensaje,
        contains('no hay historial habitual válido'),
      );
    },
  );
  test('descarte no consulta listas, historial ni stock para R66', () async {
    final r = await registrar(tipo: 'DESCARTE');
    expect(r.mensaje, 'Descarte registrado.');
    expect(servidor.consumos, 1);
    expect(servidor.lecturasStock, 0);
    expect(servidor.inserciones, 0);
  });
  test('ajustes no se procesan por esta operación', () async {
    final r = await registrar(tipo: 'AJUSTE');
    expect(r.registrado, isFalse);
    expect(servidor.consumos, 0);
    expect(servidor.inserciones, 0);
  });
  test('un descarte previo no acredita consumo habitual', () async {
    servidor.movimientos[0]['tipo'] = 'DESCARTE';
    expect(
      (await registrar()).mensaje,
      contains('no hay historial habitual válido'),
    );
  });
  test('sin lista conserva consumo y no crea listas', () async {
    servidor.listas.clear();
    final r = await registrar();
    expect(r.registrado, isTrue);
    expect(r.mensaje, contains('no hay una lista abierta'));
    expect(servidor.inserciones, 0);
  });
  test('varias listas requieren selección explícita', () async {
    servidor.listas.add(_lista('lista-2'));
    var selecciones = 0;
    await registrar(
      seleccionar: (listas) async {
        selecciones++;
        expect(listas, hasLength(2));
        return 'lista-2';
      },
    );
    expect(selecciones, 1);
    expect(servidor.productos.single['lista_id'], 'lista-2');
  });
  test('cancelar selección conserva consumo sin reposición', () async {
    servidor.listas.add(_lista('lista-2'));
    final r = await registrar(seleccionar: (_) async => null);
    expect(r.registrado, isTrue);
    expect(r.mensaje, contains('no se seleccionó una lista'));
    expect(servidor.inserciones, 0);
  });
  test('lista ajena no aparece entre opciones ni recibe productos', () async {
    servidor.listas[0] = _lista('ajena', hogar: 'hogar-b');
    expect((await registrar()).mensaje, contains('no hay una lista abierta'));
    expect(servidor.inserciones, 0);
  });
  test(
    'selección fuera de las opciones conserva consumo sin agregar',
    () async {
      servidor.listas.add(_lista('lista-2'));
      final r = await registrar(seleccionar: (_) async => 'lista-ajena');
      expect(r.registrado, isTrue);
      expect(r.mensaje, contains('no pertenece'));
      expect(servidor.inserciones, 0);
    },
  );
  test('pendiente existente impide duplicación', () async {
    servidor.productos.add({
      'id': 'anterior',
      'lista_id': 'lista-1',
      'alimento_id': 1,
      'estado': 'PENDIENTE',
    });
    expect(
      (await registrar()).mensaje,
      contains('ya existe un producto pendiente'),
    );
    expect(servidor.inserciones, 0);
  });
  test('COMPRADO anterior permite nueva reposición', () async {
    servidor.productos.add({
      'id': 'anterior',
      'lista_id': 'lista-1',
      'alimento_id': 1,
      'estado': 'COMPRADO',
    });
    await registrar();
    expect(servidor.inserciones, 1);
  });
  test(
    'pendiente en otra lista no impide reponer en la seleccionada',
    () async {
      servidor.productos.add({
        'id': 'ajeno',
        'lista_id': 'lista-otra',
        'alimento_id': 1,
        'estado': 'PENDIENTE',
      });
      await registrar();
      expect(servidor.inserciones, 1);
    },
  );
  test('cambio de stock antes de insertar omite reposición', () async {
    servidor.alConsultarStock = (numero) {
      if (numero == 3) servidor.ingresos.add(_ingreso('nuevo-stock', 25));
    };
    final r = await registrar();
    expect(r.registrado, isTrue);
    expect(r.mensaje, contains('existencias cambiaron'));
    expect(servidor.inserciones, 0);
  });
  test('pendiente creado durante el flujo impide inserción final', () async {
    servidor.alConsultarPendienteFinal = () => servidor.productos.add({
      'id': 'otro',
      'lista_id': 'lista-1',
      'alimento_id': 1,
      'estado': 'PENDIENTE',
    });
    expect(
      (await registrar()).mensaje,
      contains('ya existe un producto pendiente'),
    );
    expect(servidor.inserciones, 0);
  });
  test('lista cerrada antes del insert conserva consumo', () async {
    servidor.alValidarLista = (numero) {
      if (numero == 2) servidor.listas[0]['estado'] = 'CERRADA';
    };
    final r = await registrar();
    expect(r.registrado, isTrue);
    expect(r.mensaje, contains('Reposición omitida'));
    expect(servidor.inserciones, 0);
  });
  for (final invalido in [null, -1, 'NaN', 'Infinity']) {
    test('stock inválido $invalido no equivale a cero', () async {
      servidor.ingresos.add(_ingreso('invalido', invalido));
      final r = await registrar();
      expect(r.registrado, isTrue);
      expect(r.mensaje, contains('Reposición omitida'));
      expect(servidor.inserciones, 0);
    });
  }
  test('stock de otro hogar no se suma', () async {
    servidor.ingresos.add(_ingreso('ajeno', 8000, hogar: 'hogar-b'));
    await registrar();
    expect(servidor.inserciones, 1);
  });
  test('ingreso de otro hogar impide enviar el consumo', () async {
    servidor.ingresos[0]['hogar_id'] = 'hogar-b';
    expect((await registrar()).registrado, isFalse);
    expect(servidor.consumos, 0);
  });
  test('alimento privado ajeno no recibe reposición', () async {
    servidor.hogarAlimento = 'hogar-b';
    final r = await registrar();
    expect(r.registrado, isTrue);
    expect(servidor.inserciones, 0);
  });
  for (final unidad in ['g', 'ml', 'un']) {
    test('reposicion usa cantidad normalizada en $unidad', () async {
      servidor.unidad = unidad;
      await registrar();
      expect(servidor.productos.single['unidad'], unidad);
      expect(servidor.productos.single['cantidad'], 700);
    });
  }
  test('unidad base incompatible impide reposición', () async {
    servidor.unidad = 'kg';
    await registrar();
    expect(servidor.inserciones, 0);
  });
  test('consultas fallidas conservan consumo registrado', () async {
    servidor.fallarStock = true;
    final r = await registrar();
    expect(r.registrado, isTrue);
    expect(r.mensaje, contains('Stock no disponible'));
    expect(servidor.inserciones, 0);
  });
  test('fallo al consultar listas conserva consumo', () async {
    servidor.fallarListas = true;
    final r = await registrar();
    expect(r.registrado, isTrue);
    expect(r.mensaje, contains('Listas no disponibles'));
  });
  test('rechazo explícito de inserción no se presenta como incierto', () async {
    servidor.rechazarInsercion = true;
    final r = await registrar();
    expect(r.registrado, isTrue);
    expect(r.mensaje, contains('Reposición omitida: Inserción rechazada'));
    expect(r.mensaje, isNot(contains('no confirmada')));
    await registrar();
    expect(servidor.consumos, 1);
    expect(servidor.inserciones, 1);
  });
  test(
    'inserción incierta no se reenvía, incluso si el pendiente se elimina',
    () async {
      servidor.insercionIncierta = true;
      final r = await registrar();
      expect(r.registrado, isTrue);
      expect(r.mensaje, contains('Reposición no confirmada'));
      servidor.productos.clear();
      await registrar();
      expect(servidor.consumos, 1);
      expect(servidor.inserciones, 1);
    },
  );
  test('consumo incierto no activa R66 ni permite reenviar', () async {
    servidor.consumoIncierto = true;
    final r = await registrar();
    expect(r.registrado, isFalse);
    expect(r.incierto, isTrue);
    await registrar();
    expect(servidor.consumos, 1);
    expect(servidor.lecturasStock, 0);
    expect(servidor.inserciones, 0);
  });
  test('rechazo del consumo no activa R66', () async {
    servidor.rechazarConsumo = true;
    final r = await registrar();
    expect(r.registrado, isFalse);
    expect(r.incierto, isFalse);
    expect(r.mensaje, contains('Consumo rechazado'));
    expect(servidor.lecturasStock, 0);
  });
  test('solicitudes locales concurrentes comparten una operación', () async {
    servidor.pausaConsumo = Completer<void>();
    final primero = registrar();
    final segundo = registrar();
    expect(identical(primero, segundo), isTrue);
    servidor.pausaConsumo!.complete();
    await Future.wait([primero, segundo]);
    expect(servidor.consumos, 1);
    expect(servidor.inserciones, 1);
  });
  test(
    'no reincorpora tras eliminar pendiente sin nuevo agotamiento',
    () async {
      await registrar();
      servidor.productos.clear();
      await registrar();
      expect(servidor.consumos, 1);
      expect(servidor.inserciones, 1);
    },
  );

  Future<void> estabilizar(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  Future<void> abrirPantalla(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                final r = await Navigator.of(context)
                    .push<ResultadoMovimientoAlimento>(
                      MaterialPageRoute(
                        builder: (_) => MovimientoAlimentoScreen(
                          registro: Map.of(servidor.ingresos[0]),
                          hogarId: 'hogar-a',
                          nombreAlimento: 'Arroz',
                          unidadBase: 'g',
                        ),
                      ),
                    );
                if (context.mounted && r != null)
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(r.mensaje)));
              },
              child: const Text('Abrir movimiento'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir movimiento'));
    await estabilizar(tester);
  }

  Future<Finder> botonConfirmar(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), '1500');
    final boton = find.widgetWithText(ElevatedButton, 'Confirmar consumo');
    await tester.scrollUntilVisible(
      boton,
      250,
      scrollable: find
          .descendant(
            of: find.byType(MovimientoAlimentoScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    return boton;
  }

  testWidgets('abrir, recargar y cerrar pantalla no ejecuta R66', (
    tester,
  ) async {
    await abrirPantalla(tester);
    await tester.pump();
    expect(servidor.consumos, 0);
    expect(servidor.inserciones, 0);
    await tester.pageBack();
    await estabilizar(tester);
    await abrirPantalla(tester);
    expect(servidor.consumos, 0);
    expect(servidor.inserciones, 0);
  });
  testWidgets(
    'doble pulsación confirma e incorpora una sola vez y vuelve una pantalla',
    (tester) async {
      await abrirPantalla(tester);
      final boton = await botonConfirmar(tester);
      final confirmar = tester.widget<ElevatedButton>(boton).onPressed!;
      confirmar();
      confirmar();
      await estabilizar(tester);
      expect(servidor.consumos, 1);
      expect(servidor.inserciones, 1);
      expect(find.byType(MovimientoAlimentoScreen), findsNothing);
      expect(find.text('Abrir movimiento'), findsOneWidget);
      expect(
        find.textContaining('Consumo registrado. Reposición agregada'),
        findsOneWidget,
      );
    },
  );
  testWidgets('varias listas muestran selector y cancelar conserva consumo', (
    tester,
  ) async {
    servidor.listas.add(_lista('lista-2'));
    await abrirPantalla(tester);
    await tester.tap(await botonConfirmar(tester));
    await estabilizar(tester);
    expect(find.byType(SimpleDialog), findsOneWidget);
    expect(find.text('lista-1'), findsOneWidget);
    expect(find.text('lista-2'), findsOneWidget);
    await tester.tap(find.text('Continuar sin reposición'));
    await estabilizar(tester);
    expect(servidor.consumos, 1);
    expect(servidor.inserciones, 0);
    expect(
      find.textContaining('Consumo registrado. Reposición omitida'),
      findsOneWidget,
    );
  });
  testWidgets(
    'resultado incierto deshabilita confirmación y no activa reposición',
    (tester) async {
      servidor.consumoIncierto = true;
      await abrirPantalla(tester);
      await tester.tap(await botonConfirmar(tester));
      await estabilizar(tester);
      expect(servidor.consumos, 1);
      expect(servidor.inserciones, 0);
      expect(find.byType(MovimientoAlimentoScreen), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Confirmar consumo'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'timeout de consumo no se reenvía aunque el servidor termine después',
    (tester) async {
      servidor.pausaConsumo = Completer<void>();
      await abrirPantalla(tester);
      await tester.tap(await botonConfirmar(tester));
      await estabilizar(tester);
      expect(servidor.consumos, 1);
      await tester.pump(const Duration(seconds: 9));
      await estabilizar(tester);
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Confirmar consumo'),
            )
            .onPressed,
        isNull,
      );
      expect(servidor.inserciones, 0);
      servidor.pausaConsumo!.complete();
      await estabilizar(tester);
      expect(servidor.consumos, 1);
      expect(servidor.inserciones, 0);
    },
  );

  testWidgets('timeout de inserción conserva consumo y no vuelve a enviar', (
    tester,
  ) async {
    servidor.pausaInsercion = Completer<void>();
    await abrirPantalla(tester);
    await tester.tap(await botonConfirmar(tester));
    await estabilizar(tester);
    expect(servidor.inserciones, 1);
    await tester.pump(const Duration(seconds: 9));
    await estabilizar(tester);
    expect(
      find.textContaining('Consumo registrado. Reposición no confirmada'),
      findsOneWidget,
    );
    expect(servidor.consumos, 1);
    servidor.pausaInsercion!.complete();
    await estabilizar(tester);
    expect(servidor.inserciones, 1);
  });

  testWidgets(
    'doble selección de lista incorpora una vez en el destino elegido',
    (tester) async {
      servidor.listas.add(_lista('lista-2'));
      await abrirPantalla(tester);
      await tester.tap(await botonConfirmar(tester));
      await estabilizar(tester);
      final elegir = tester
          .widget<SimpleDialogOption>(
            find.ancestor(
              of: find.text('lista-2'),
              matching: find.byType(SimpleDialogOption),
            ),
          )
          .onPressed!;
      elegir();
      elegir();
      await estabilizar(tester);
      expect(servidor.consumos, 1);
      expect(servidor.inserciones, 1);
      expect(servidor.productos.single['lista_id'], 'lista-2');
    },
  );
}
