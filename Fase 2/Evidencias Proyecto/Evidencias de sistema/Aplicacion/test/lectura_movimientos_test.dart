import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nfc_foodtech_app/shared/services/lectura_movimientos.dart';
import 'package:nfc_foodtech_app/shared/widgets/acceso_hogar.dart';
import 'package:nfc_foodtech_app/features/indicadores/screens/indicadores_screen.dart';
import 'package:nfc_foodtech_app/features/inventario/screens/historial_movimientos_screen.dart';
import 'indicadores_calculos_test.dart' as datos;

class Servidor {
  final tablas = <String, List<Map<String, dynamic>>>{
    'despensa_item': [datos.ingreso('a')],
    'movimiento': [],
    'alimento': [
      {'id': 1, 'nombre': 'Arroz', 'unidad_base': 'g', 'categoria_id': 1},
    ],
    'categoria': [
      {'id': 1, 'nombre': 'Prueba'},
    ],
    'tipo_desperdicio': [
      {'id': 1, 'nombre': 'Evitable', 'es_evitable': true},
    ],
  };
  final consultas = <Uri>[];
  bool fallar = false;
  bool repetir = false;
  Completer<void>? pendiente;
  bool membresia = true;

  Future<http.Response> atender(http.Request req) async {
    consultas.add(req.url);
    final tabla = req.url.pathSegments.last;
    http.Response responder(Object datos, [int status = 200]) => http.Response(
      jsonEncode(datos),
      status,
      headers: {'content-type': 'application/json'},
      request: req,
    );
    if (tabla == 'historial_traslados_hogar') return responder([]);
    if (tabla == 'token') {
      final email = (jsonDecode(req.body) as Map)['email'];
      final id = email == 'otra@example.com' ? 'usuario-2' : 'usuario-1';
      String codificar(Map<String, dynamic> v) =>
          base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
      return responder({
        'access_token':
            '${codificar({'alg': 'HS256'})}.${codificar({'sub': id, 'exp': 4133980800})}.firma',
        'refresh_token': 'local-$id',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': id,
          'aud': 'authenticated',
          'email': email,
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-01-01T00:00:00Z',
        },
      });
    }
    if (tabla == 'm14_listar_hogares')
      return responder(
        membresia
            ? [
                {'id': 'hogar-a'},
              ]
            : [],
      );
    final parametros = req.url.queryParameters;
    final cursor = parametros['id'];
    if (tabla == 'movimiento' && cursor != null) {
      final espera = pendiente;
      pendiente = null;
      if (espera != null) await espera.future;
      if (fallar)
        return responder({
          'message': 'Página intermedia no disponible',
          'code': '08006',
        }, 400);
    }
    var filas = List<Map<String, dynamic>>.from(tablas[tabla] ?? []);
    final filtro = parametros['despensa_item_id'];
    if (filtro != null) {
      final ids = filtro
          .substring(4, filtro.length - 1)
          .replaceAll('"', '')
          .split(',');
      filas = filas.where((f) => ids.contains(f['despensa_item_id'])).toList();
    }
    for (final cursor in req.url.queryParametersAll['id'] ?? <String>[]) {
      if (cursor.startsWith('gt.') && !repetir) {
        final valor = cursor.substring(3);
        filas = filas
            .where(
              (f) => f['id'] is int
                  ? (f['id'] as int) > int.parse(valor)
                  : f['id'].toString().compareTo(valor) > 0,
            )
            .toList();
      }
      if (cursor.startsWith('in.')) {
        final ids = cursor.substring(4, cursor.length - 1).split(',');
        filas = filas.where((f) => ids.contains(f['id'].toString())).toList();
      }
    }
    filas.sort(
      (a, b) => a['id'] is int
          ? (a['id'] as int).compareTo(b['id'] as int)
          : a['id'].toString().compareTo(b['id'].toString()),
    );
    if ((parametros['order'] ?? '').contains('.desc')) {
      filas = filas.reversed.toList();
    }
    return responder(
      filas.take(int.parse(parametros['limit'] ?? '1000')).toList(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Servidor servidor;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    servidor = Servidor();
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
  tearDown(() async => Supabase.instance.dispose());

  test(
    'más de 1000 ingresos conservan hogar, orden único y todos los estados',
    () async {
      servidor.tablas['despensa_item'] = List.generate(
        1201,
        (i) => datos.ingreso('item${i.toString().padLeft(5, '0')}'),
      );
      final lector = LecturaMovimientos(Supabase.instance.client, () => true);
      final items = await lector.leer(
        'despensa_item',
        'id, alimento_id',
        hogarId: 'hogar-a',
      );
      expect(items.length, 1201);
      expect(items.map((i) => i['id']).toSet().length, 1201);
      expect(servidor.consultas.length, 4);
      for (final uri in servidor.consultas) {
        expect(uri.queryParameters['hogar_id'], 'eq.hogar-a');
        expect(uri.queryParameters['order'], startsWith('id.asc'));
        expect(uri.queryParameters.containsKey('offset'), isFalse);
        expect(uri.queryParameters.containsKey('estado'), isFalse);
      }
    },
  );

  test(
    '1201 movimientos paginados equivalen al conjunto completo y a otras páginas',
    () async {
      final todos = List.generate(
        1201,
        (i) => {
          ...datos.movimiento('$i', 'a', i.isEven ? 'CONSUMO' : 'DESCARTE', 1),
          'id': i,
        },
      );
      servidor.tablas['movimiento'] = todos;
      final completo = datos.calcular([datos.ingreso('a')], todos);
      for (final pagina in [500, 137]) {
        final lector = LecturaMovimientos(
          Supabase.instance.client,
          () => true,
          tamanoPagina: pagina,
        );
        final filas = await lector.leer(
          'movimiento',
          'id, despensa_item_id, tipo, cantidad, fecha',
          columnaIds: 'despensa_item_id',
          ids: ['a'],
        );
        final r = datos.calcular([datos.ingreso('a')], filas);
        expect(filas.length, 1201);
        expect(r.consumido, completo.consumido);
        expect(r.descartado, completo.descartado);
        expect(r.aprovechamientoMes, completo.aprovechamientoMes);
        expect(r.costoConocido, completo.costoConocido);
        expect(r.cantidadConsumos, completo.cantidadConsumos);
        expect(r.cantidadDescartes, completo.cantidadDescartes);
      }
    },
  );

  test('error intermedio descarta la lectura completa', () async {
    servidor.tablas['movimiento'] = List.generate(
      1001,
      (i) => {'id': i, 'despensa_item_id': 'a'},
    );
    servidor.fallar = true;
    await expectLater(
      LecturaMovimientos(
        Supabase.instance.client,
        () => true,
      ).leer('movimiento', 'id', columnaIds: 'despensa_item_id', ids: ['a']),
      throwsA(isA<PostgrestException>()),
    );
  });

  test(
    'páginas repetidas se rechazan sin duplicar totales ni entrar en bucle',
    () async {
      servidor.repetir = true;
      servidor.tablas['movimiento'] = [
        {'id': 1},
      ];
      await expectLater(
        LecturaMovimientos(
          Supabase.instance.client,
          () => true,
        ).leer('movimiento', 'id'),
        throwsStateError,
      );
      expect(servidor.consultas.length, 2);
    },
  );

  test(
    'invalidación durante una consulta descarta la respuesta y detiene páginas',
    () async {
      servidor.tablas['movimiento'] = List.generate(1001, (i) => {'id': i});
      final pendiente = Completer<void>();
      servidor.pendiente = pendiente;
      var vigente = true;
      final consulta = LecturaMovimientos(
        Supabase.instance.client,
        () => vigente,
      ).leer('movimiento', 'id');
      final expectativa = expectLater(
        consulta,
        throwsA(isA<LecturaCancelada>()),
      );
      while (servidor.pendiente != null) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      vigente = false;
      pendiente.complete();
      await expectativa;
      expect(servidor.consultas.length, 2);
    },
  );

  test('catálogo en lotes conserva simultáneamente filtro y cursor', () async {
    servidor.tablas['alimento'] = List.generate(250, (i) => {'id': i});
    final filas = await LecturaMovimientos(Supabase.instance.client, () => true)
        .leer(
          'alimento',
          'id',
          columnaIds: 'id',
          ids: List.generate(230, (i) => i),
        );
    expect(filas.length, 230);
    expect(filas.map((f) => f['id']).toSet().length, 230);
  });

  for (final cambioCuenta in [false, true]) {
    testWidgets(
      'página pendiente no publica tras ${cambioCuenta ? 'cambio de cuenta' : 'expulsión'}',
      (tester) async {
        await Supabase.instance.client.auth.signInWithPassword(
          email: 'prueba@example.com',
          password: 'local',
        );
        servidor.tablas['movimiento'] = List.generate(
          1001,
          (i) => {...datos.movimiento('$i', 'a', 'CONSUMO', 1), 'id': i},
        );
        final pendiente = Completer<void>();
        servidor.pendiente = pendiente;
        Future<void> resolver() async {
          for (var i = 0; i < 8; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }
        }

        final navegador = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navegador,
            home: const Scaffold(body: Text('Inicio seguro')),
          ),
        );
        navegador.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const AccesoHogar(
              hogarId: 'hogar-a',
              child: IndicadoresScreen(hogar: {'id': 'hogar-a'}),
            ),
          ),
        );
        await resolver();
        expect(servidor.pendiente, isNull);
        if (cambioCuenta) {
          await tester.runAsync(
            () => Supabase.instance.client.auth.signInWithPassword(
              email: 'otra@example.com',
              password: 'local',
            ),
          );
        } else {
          servidor.membresia = false;
        }
        pendiente.complete();
        await resolver();
        expect(find.text('Inicio seguro'), findsOneWidget);
        expect(find.byType(IndicadoresScreen), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Historial muestra más de 1000 movimientos con fechas iguales', (
    tester,
  ) async {
    servidor.tablas['movimiento'] = List.generate(
      1201,
      (i) => {...datos.movimiento('$i', 'a', 'CONSUMO', 1), 'id': i},
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: HistorialMovimientosScreen(hogar: {'id': 'hogar-a'}),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('1201'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final historial in [false, true]) {
    testWidgets(
      'fallo intermedio bloquea resultados y exportación (historial: $historial)',
      (tester) async {
        servidor.tablas['movimiento'] = List.generate(
          1001,
          (i) => {...datos.movimiento('$i', 'a', 'CONSUMO', 1), 'id': i},
        );
        servidor.fallar = true;
        await tester.pumpWidget(
          MaterialApp(
            home: historial
                ? const HistorialMovimientosScreen(hogar: {'id': 'hogar-a'})
                : const IndicadoresScreen(hogar: {'id': 'hogar-a'}),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          find.textContaining('No se completó la consulta'),
          findsOneWidget,
        );
        expect(find.text('Promedio de aprovechamiento'), findsNothing);
        if (!historial) {
          expect(
            tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is IconButton &&
                        widget.tooltip == 'Exportar reporte CSV',
                  ),
                )
                .onPressed,
            isNull,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
