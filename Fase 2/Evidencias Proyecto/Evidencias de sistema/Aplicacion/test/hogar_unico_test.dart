import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nfc_foodtech_app/features/inventario/screens/catalogo_alimentos_screen.dart';
import 'package:nfc_foodtech_app/features/alertas/screens/notificaciones_screen.dart';
import 'package:nfc_foodtech_app/features/inventario/screens/registro_multiple_screen.dart';
import 'package:nfc_foodtech_app/features/home/screens/home_screen.dart';
import 'package:nfc_foodtech_app/features/inventario/screens/inventario_screen.dart';
import 'package:nfc_foodtech_app/features/indicadores/screens/indicadores_screen.dart';
import 'package:nfc_foodtech_app/features/configuracion/screens/ayuda_screen.dart';
import 'package:nfc_foodtech_app/features/alertas/screens/alertas_caducidad_screen.dart';
import 'package:nfc_foodtech_app/services/notificaciones_locales.dart';
import 'package:nfc_foodtech_app/features/compras/screens/lista_compras_screen.dart';
import 'package:nfc_foodtech_app/features/hogar/screens/seleccionar_hogar_screen.dart';
import 'package:nfc_foodtech_app/features/perfil/screens/perfil_screen.dart';
import 'package:nfc_foodtech_app/features/configuracion/screens/configuracion_screen.dart';
import 'package:nfc_foodtech_app/features/auth/screens/cambiar_contrasena_screen.dart';
import 'package:nfc_foodtech_app/features/perfil/screens/desactivar_cuenta_screen.dart';
import 'package:nfc_foodtech_app/screens/eliminar_cuenta_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _hogar = <String, dynamic>{
  'id': 'hogar-a',
  'nombre': 'Casa de prueba',
  'rol': 'ADMIN',
  'adultos': 2,
  'menores': 1,
};

final class _PreferenciasAsyncSimuladas extends SharedPreferencesAsyncPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Esta prueba solo consulta la apariencia en memoria.',
  );
}

class _ServidorHogares {
  List<dynamic> hogares = [];
  bool fallar = false;
  int lecturas = 0;
  Completer<List<dynamic>>? pendiente;
  final acciones = <Map<String, dynamic>>[];
  final consultas = <Uri>[];
  int escriturasLista = 0;
  List<dynamic> resumen = [];
  bool fallarResumen = false;
  List<Map<String, dynamic>> notificaciones = [];
  bool fallarNotificaciones = false;
  Completer<List<Map<String, dynamic>>>? avisoPendiente;
  bool catalogoConAlimento = false;
  Completer<List<dynamic>>? resumenPendiente;
  final consultasResumen = <Uri>[];
  final solicitudes = <Uri>[];
  bool datosAnalisis = false;
  bool fallarAnalisis = false;
  Completer<List<Map<String, dynamic>>>? analisisPendiente;

  Map<String, dynamic> get ingresoAnalisis => {
    'id': 'ingreso-a',
    'alimento_id': 1,
    'cantidad_inicial': 1000,
    'precio_clp': 2000,
  };

  Future<http.Response> atender(http.Request req) async {
    solicitudes.add(req.url);
    http.Response responder(dynamic datos, {int status = 200}) => http.Response(
      jsonEncode(datos),
      status,
      request: req,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    final ruta = req.url.path;
    if (ruta == '/rest/v1/despensa_item' &&
        req.url.queryParameters['select'] ==
            'id,alimento_id,cantidad_inicial,precio_clp') {
      final espera = analisisPendiente;
      analisisPendiente = null;
      if (espera != null) return responder(await espera.future);
      if (fallarAnalisis)
        return responder({'message': 'Sin conexión'}, status: 500);
      return responder(
        datosAnalisis && !req.url.queryParameters.containsKey('id')
            ? [ingresoAnalisis]
            : [],
      );
    }
    if (ruta == '/rest/v1/movimiento') {
      return responder(
        datosAnalisis && !req.url.queryParameters.containsKey('id')
            ? [
                {
                  'id': 1,
                  'despensa_item_id': 'ingreso-a',
                  'tipo': 'DESCARTE',
                  'cantidad': 200,
                  'fecha': DateTime.now().toUtc().toIso8601String(),
                },
              ]
            : [],
      );
    }
    if (ruta == '/rest/v1/alimento' &&
        req.url.queryParameters['select'] ==
            'id,nombre,unidad_base,categoria_id') {
      return responder(
        datosAnalisis &&
                !(req.url.queryParameters['id'] ?? '').startsWith('gt.')
            ? [
                {
                  'id': 1,
                  'nombre': 'Arroz',
                  'unidad_base': 'g',
                  'categoria_id': 1,
                },
              ]
            : [],
      );
    }
    if (ruta == '/auth/v1/token') {
      final email = (jsonDecode(req.body) as Map)['email'];
      final id = email == 'otra@example.com' ? 'usuario-2' : 'usuario-1';
      String codificar(Map<String, dynamic> valor) =>
          base64Url.encode(utf8.encode(jsonEncode(valor))).replaceAll('=', '');
      return responder({
        'access_token':
            '${codificar({'alg': 'HS256'})}.${codificar({'sub': id, 'exp': 4133980800})}.firma',
        'refresh_token': 'refresh-$id',
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
    if (ruta == '/rest/v1/notificacion') {
      final espera = avisoPendiente;
      avisoPendiente = null;
      if (espera != null) return responder(await espera.future);
      if (fallarNotificaciones)
        return responder({'message': 'Sin conexión'}, status: 500);
      return responder(notificaciones.take(3).toList());
    }
    if (ruta == '/rest/v1/plantilla_notificacion')
      return responder([
        {
          'id': 2,
          'titulo_tpl': 'Aviso {alimento}',
          'cuerpo_tpl': 'Quedan {{ dias }} días.',
        },
      ]);
    if (ruta == '/rest/v1/rpc/m28_sincronizar_alertas') return responder({});
    if (ruta == '/rest/v1/rpc/m19_registrar_multiples') {
      resumen = [
        {'alimento_id': 1},
      ];
      return responder(1);
    }
    if (ruta == '/rest/v1/alimento' && catalogoConAlimento)
      return responder([
        {
          'id': 1,
          'nombre': 'Manzana',
          'unidad_base': 'g',
          'estado': 'APROBADO',
          'hogar_id': null,
          'categoria_id': 1,
        },
      ]);
    if (ruta == '/rest/v1/categoria' && catalogoConAlimento)
      return responder([
        {'id': 1, 'nombre': 'Frutas', 'parent_id': null, 'activa': true},
      ]);
    if (ruta == '/rest/v1/perfil') return responder({'nombre': 'Prueba'});
    if (ruta == '/rest/v1/lista_compra') {
      if (req.method == 'POST') {
        escriturasLista++;
        return responder({'id': 'lista-a'});
      }
      return responder([]);
    }
    if (ruta == '/rest/v1/rpc/m14_listar_hogares') {
      lecturas++;
      final espera = pendiente;
      pendiente = null;
      if (espera != null) return responder(await espera.future);
      if (fallar)
        return responder({
          'code': '08006',
          'message': 'Sin conexión',
        }, status: 400);
      return responder(hogares);
    }
    if (ruta == '/rest/v1/rpc/m15_guardar_hogar') {
      final body = Map<String, dynamic>.from(jsonDecode(req.body) as Map);
      hogares = [
        {..._hogar, 'nombre': body['p_nombre']},
      ];
      return responder('hogar-a');
    }
    if (ruta == '/rest/v1/rpc/m17_unirse_hogar') {
      hogares = [
        {..._hogar, 'rol': 'MIEMBRO'},
      ];
      return responder({
        'exito': true,
        'hogar_id': 'hogar-a',
        'rol': 'MIEMBRO',
      });
    }
    if (ruta == '/rest/v1/rpc/m16_listar_miembros') {
      return responder([
        {
          'perfil_id': 'usuario-1',
          'nombre': 'Prueba',
          'rol': hogares.single['rol'],
          'es_creador': false,
        },
        {
          'perfil_id': 'usuario-otro',
          'nombre': 'Integrante',
          'rol': 'MIEMBRO',
          'es_creador': false,
        },
      ]);
    }
    if (ruta == '/rest/v1/rpc/m16_gestionar_miembro') {
      final body = Map<String, dynamic>.from(jsonDecode(req.body) as Map);
      acciones.add(body);
      if (body['p_accion'] == 'ABANDONAR') hogares = [];
      if (body['p_accion'] == 'TRANSFERIR')
        hogares = [
          {..._hogar, 'rol': 'MIEMBRO'},
        ];
      return responder(null);
    }
    if (ruta == '/rest/v1/despensa_item' &&
        req.url.queryParameters['select'] == 'alimento_id') {
      consultasResumen.add(req.url);
      final espera = resumenPendiente;
      resumenPendiente = null;
      if (espera != null) return responder(await espera.future);
      if (fallarResumen)
        return responder({'message': 'Sin conexión'}, status: 500);
      final inicio = int.parse(req.url.queryParameters['offset'] ?? '0');
      return responder(resumen.skip(inicio).take(1000).toList());
    }
    if ([
      '/rest/v1/despensa_item',
      '/rest/v1/categoria',
      '/rest/v1/alimento',
      '/rest/v1/tipo_desperdicio',
    ].contains(ruta)) {
      consultas.add(req.url);
      return responder([]);
    }
    throw StateError('Solicitud inesperada: ${req.method} ${req.url}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ServidorHogares servidor;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance = _PreferenciasAsyncSimuladas();
    servidor = _ServidorHogares();
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
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'prueba@example.com',
      password: 'prueba-local',
    );
  });
  tearDown(() async {
    NotificacionesLocales.instancia.destino.value = null;
    await Supabase.instance.dispose();
  });

  Future<void> resolver(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  Future<void> abrir(
    WidgetTester tester, {
    bool gestion = false,
    bool oscuro = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: HomeScreen.verde,
            brightness: oscuro ? Brightness.dark : Brightness.light,
          ),
        ),
        home: gestion ? const SeleccionarHogarScreen() : const HomeScreen(),
      ),
    );
    await resolver(tester);
  }

  Future<void> pulsar(WidgetTester tester, String texto) async {
    if (find.byType(NavigationBar).evaluate().isNotEmpty) {
      final destino = switch (texto) {
        'Mi inventario' || 'Registrar consumo' => 'Inventario',
        'Lista de compras' => 'Compras',
        'Alertas de caducidad' => 'Alertas',
        _ => null,
      };
      if (destino != null && find.text(texto).evaluate().isEmpty ||
          texto == 'Mi inventario' ||
          texto == 'Registrar consumo') {
        await tester.tap(find.text(destino!));
        await resolver(tester);
        return;
      }
      if (texto == 'Mi perfil' && find.text(texto).evaluate().isEmpty) {
        await tester.tap(find.byTooltip('Mi perfil'));
        await resolver(tester);
        return;
      }
      if (texto == 'Mi hogar') {
        await tester.tap(find.text('Inicio'));
        await resolver(tester);
        texto = 'Mi hogar: ${servidor.hogares.single['nombre']}';
      }
      if (texto == 'Análisis' ||
          texto == 'Crear hogar' ||
          texto == 'Unirse mediante código') {
        if (tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex !=
            0) {
          await tester.tap(find.text('Inicio'));
          await resolver(tester);
        }
      }
      if (texto == 'Análisis') texto = 'Ver análisis completo';
      if (texto == 'Registrar alimentos') texto = 'Registrar alimento';
    }

    final textos = find.text(texto);
    final botones = find.ancestor(
      of: textos,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is ButtonStyleButton || widget is FloatingActionButton,
      ),
    );
    final finder = botones.evaluate().isEmpty ? textos.last : botones.last;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await resolver(tester);
  }

  Future<void> reanudar(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await resolver(tester);
  }

  for (final oscuro in [false, true]) {
    testWidgets(
      'cinco pestanas conservan hogar, barra y flecha Atras ($oscuro)',
      (tester) async {
        servidor.hogares = [_hogar];
        await abrir(tester, oscuro: oscuro);
        expect(find.byType(NavigationDestination), findsNWidgets(5));
        expect(find.text('Por revisar'), findsNothing);
        expect(find.text('Mi inventario'), findsNothing);
        expect(
          find.text('No tienes notificaciones recientes.'),
          findsOneWidget,
        );
        for (final entrada in <String, Type>{
          'Mi inventario': InventarioScreen,
          'Lista de compras': ListaComprasScreen,
          'Alertas de caducidad': AlertasCaducidadScreen,
        }.entries) {
          await pulsar(tester, entrada.key);
          expect(
            (tester.widget(find.byType(entrada.value)) as dynamic).hogar,
            _hogar,
          );
          expect(find.byType(NavigationBar), findsOneWidget);
          await tester.tap(find.byType(BackButton));
          await resolver(tester);
          expect(
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            0,
          );
        }
        await tester.tap(find.text('Ajustes'));
        await resolver(tester);
        for (final texto in [
          'Mi perfil',
          'Apariencia',
          'Ayuda y preguntas frecuentes',
          'Cerrar sesión',
        ]) {
          expect(find.text(texto), findsOneWidget);
        }
        expect(find.byType(ConfiguracionScreen), findsOneWidget);
        expect(find.widgetWithText(AppBar, 'Configuración'), findsOneWidget);
        expect(find.text('Indicadores y análisis'), findsNothing);
        await tester.binding.handlePopRoute();
        await resolver(tester);
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          0,
        );
      },
    );

    testWidgets(
      'perfil y configuracion conservan seguridad sin eliminacion ($oscuro)',
      (tester) async {
        servidor.hogares = [_hogar];
        await abrir(tester, oscuro: oscuro);
        await pulsar(tester, 'Mi perfil');
        expect(find.byType(PerfilScreen), findsOneWidget);
        expect(find.text('Eliminar cuenta definitivamente'), findsNothing);
        await pulsar(tester, 'Cambiar contraseña');
        expect(find.byType(CambiarContrasenaScreen), findsOneWidget);
        await tester.pageBack();
        await resolver(tester);
        await pulsar(tester, 'Desactivar cuenta');
        expect(find.byType(DesactivarCuentaScreen), findsOneWidget);
        await tester.pageBack();
        await resolver(tester);
        await tester.pageBack();
        await resolver(tester);
        await pulsar(tester, 'Ajustes');
        expect(find.byType(ConfiguracionScreen), findsOneWidget);
        expect(find.textContaining('Eliminar cuenta'), findsNothing);
        expect(find.text('Cambiar contraseña'), findsOneWidget);
        await pulsar(tester, 'Mi perfil');
        expect(find.byType(PerfilScreen), findsOneWidget);
        expect(find.text('Eliminar cuenta definitivamente'), findsNothing);
        expect(tester.takeException(), isNull);
        expect(
          servidor.solicitudes.where((u) => u.path.contains('/functions/')),
          isEmpty,
        );
      },
    );

    testWidgets('Home compacto sin desbordes en pantalla estrecha ($oscuro)', (
      tester,
    ) async {
      servidor.hogares = [_hogar];
      await abrir(tester, oscuro: oscuro);
      await tester.binding.setSurfaceSize(const Size(320, 740));
      tester.binding.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      await tester.pump();
      for (final etiqueta in [
        'Inventario',
        'Compras',
        'Alertas',
        'Ajustes',
        'Inicio',
      ]) {
        await tester.tap(find.text(etiqueta));
        await resolver(tester);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets(
    'resumen usa datos reales, filtros temporales y cache entre pestañas',
    (tester) async {
      servidor.hogares = [_hogar];
      servidor.datosAnalisis = true;
      await abrir(tester);
      expect(find.byTooltip('Mi perfil'), findsOneWidget);
      expect(find.byTooltip('Notificaciones'), findsOneWidget);
      expect(find.text('Resumen de tu hogar'), findsOneWidget);
      expect(find.textContaining('400 CLP'), findsWidgets);
      final consulta = servidor.solicitudes.firstWhere(
        (u) => u.path == '/rest/v1/movimiento',
      );
      expect(consulta.queryParameters['tipo'], 'in.("CONSUMO","DESCARTE")');
      expect(consulta.queryParametersAll['fecha']!.length, 2);
      final lecturas = servidor.solicitudes
          .where((u) => u.path == '/rest/v1/movimiento')
          .length;
      await pulsar(tester, 'Ajustes');
      expect(find.byType(ConfiguracionScreen), findsOneWidget);
      expect(find.text('Ver análisis completo'), findsNothing);
      await pulsar(tester, 'Inicio');
      expect(
        servidor.solicitudes
            .where((u) => u.path == '/rest/v1/movimiento')
            .length,
        lecturas,
      );
      await pulsar(tester, 'Mi inventario');
      final actualizar = tester
          .widget<InventarioScreen>(find.byType(InventarioScreen))
          .onDatosActualizados!;
      await pulsar(tester, 'Inicio');
      actualizar();
      await resolver(tester);
      expect(find.textContaining('400 CLP'), findsWidgets);
      await pulsar(tester, 'Análisis');
      expect(find.byType(IndicadoresScreen), findsOneWidget);
    },
  );

  testWidgets(
    'fallo económico permite reintentar sin presentar cero definitivo',
    (tester) async {
      servidor.hogares = [_hogar];
      servidor.fallarAnalisis = true;
      await abrir(tester);
      expect(
        find.text('No se pudo cargar el resumen económico.'),
        findsOneWidget,
      );
      expect(find.textContaining('0 CLP'), findsNothing);
      servidor.fallarAnalisis = false;
      servidor.datosAnalisis = true;
      await pulsar(tester, 'Reintentar análisis');
      expect(find.textContaining('400 CLP'), findsWidgets);
    },
  );

  testWidgets(
    'respuesta económica pendiente no restaura datos de otra cuenta',
    (tester) async {
      servidor.hogares = [_hogar];
      servidor.datosAnalisis = true;
      final pendiente = Completer<List<Map<String, dynamic>>>();
      servidor.analisisPendiente = pendiente;
      await abrir(tester);
      servidor.hogares = [];
      servidor.datosAnalisis = false;
      await Supabase.instance.client.auth.signInWithPassword(
        email: 'otra@example.com',
        password: 'prueba-local',
      );
      await resolver(tester);
      pendiente.complete([servidor.ingresoAnalisis]);
      await resolver(tester);
      expect(find.textContaining('400 CLP'), findsNothing);
      expect(
        find.text('Crea un hogar o únete para ver su resumen.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'apertura directa de eliminacion no habilita acciones ni llama al backend',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: EliminarCuentaScreen()));
      await resolver(tester);
      expect(
        find.text('La eliminación definitiva de cuentas no está disponible.'),
        findsOneWidget,
      );
      expect(find.text('Revisar requisitos'), findsNothing);
      expect(find.text('Simular confirmacion segura'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(
        servidor.solicitudes.where((u) => u.path.contains('/functions/')),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'notificaciones recientes reales limitadas y filtradas por usuario',
    (tester) async {
      servidor.hogares = [_hogar];
      servidor.notificaciones = List.generate(
        4,
        (i) => {
          'id': 'n$i',
          'plantilla_id': 2,
          'datos': {'alimento': 'Fruta $i', 'dias': 2},
          'estado': 'PENDIENTE',
          'created_at': '2026-11-06T12:00:00Z',
        },
      );
      await abrir(tester);
      for (final i in [0, 1, 2]) {
        expect(find.text('Aviso Fruta $i'), findsOneWidget);
      }
      expect(find.text('Aviso Fruta 3'), findsNothing);
      final consulta = servidor.solicitudes
          .singleWhere((u) => u.path == '/rest/v1/notificacion')
          .queryParameters;
      expect(consulta['limit'], '3');
      expect(consulta['perfil_id'], 'eq.usuario-1');
      expect(consulta['order'], 'created_at.desc.nullslast,id.desc.nullslast');
      expect(consulta['estado'], 'neq.CANCELADA');
      await pulsar(tester, 'Ver todas');
      expect(find.byType(NotificacionesScreen), findsOneWidget);
      await tester.pageBack();
      await resolver(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
    },
  );

  testWidgets(
    'notificaciones pendientes de cuenta anterior no aparecen al cambiar usuario',
    (tester) async {
      servidor.hogares = [_hogar];
      final pendiente = Completer<List<Map<String, dynamic>>>();
      servidor.avisoPendiente = pendiente;
      await abrir(tester);
      await tester.runAsync(
        () => Supabase.instance.client.auth.signInWithPassword(
          email: 'otra@example.com',
          password: 'prueba-local',
        ),
      );
      await resolver(tester);
      pendiente.complete([
        {
          'id': 'vieja',
          'plantilla_id': 2,
          'datos': {'alimento': 'Dato anterior'},
          'estado': 'PENDIENTE',
        },
      ]);
      await resolver(tester);
      expect(find.text('Aviso Dato anterior'), findsNothing);
      expect(find.text('No tienes notificaciones recientes.'), findsOneWidget);
    },
  );

  testWidgets(
    'error de notificaciones permite reintentar sin fingir estado vacio',
    (tester) async {
      servidor.fallarNotificaciones = true;
      await abrir(tester);
      expect(
        find.text('No se pudieron cargar las notificaciones.'),
        findsOneWidget,
      );
      expect(find.text('No tienes notificaciones recientes.'), findsNothing);
      servidor.fallarNotificaciones = false;
      await pulsar(tester, 'Reintentar notificaciones');
      expect(find.text('No tienes notificaciones recientes.'), findsOneWidget);
    },
  );

  testWidgets(
    'pestanas conservan filtros y Atras Android distingue subruta y raiz',
    (tester) async {
      servidor.hogares = [_hogar];
      await abrir(tester);
      await pulsar(tester, 'Mi inventario');
      final estado = tester.state(find.byType(InventarioScreen));
      await tester.enterText(find.byType(TextField).first, 'arroz');
      await tester.pump();
      await tester.tap(find.text('Compras'));
      await resolver(tester);
      await tester.tap(find.text('Inventario'));
      await resolver(tester);
      expect(tester.state(find.byType(InventarioScreen)), same(estado));
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'arroz',
      );
      await tester.tap(find.byTooltip('Lista de compras'));
      await resolver(tester);
      await tester.binding.handlePopRoute();
      await resolver(tester);
      expect(find.byType(ListaComprasScreen), findsNothing);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      await tester.binding.handlePopRoute();
      await resolver(tester);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
    },
  );

  testWidgets(
    'registro rapido reutiliza seleccion manual y actualiza contador',
    (tester) async {
      servidor.hogares = [_hogar];
      servidor.catalogoConAlimento = true;
      await abrir(tester);
      await pulsar(tester, 'Registrar alimentos');
      expect(find.byType(CatalogoAlimentosScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Manzana');
      await tester.pump();
      await pulsar(tester, 'Manzana');
      await pulsar(tester, 'Continuar con 1 alimentos');
      expect(find.byType(RegistroMultipleScreen), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '100');
      await pulsar(tester, 'Guardar 1 alimentos');
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(CatalogoAlimentosScreen), findsNothing);
      expect(find.text('1'), findsOneWidget);
    },
  );

  testWidgets(
    'seleccionar pestaña mientras carga el hogar no deja una pantalla vacía',
    (tester) async {
      final pendiente = Completer<List<dynamic>>();
      servidor.pendiente = pendiente;
      await abrir(tester);
      await tester.tap(find.text('Inventario'));
      await resolver(tester);
      servidor.hogares = [_hogar];
      pendiente.complete([_hogar]);
      await resolver(tester);
      expect(find.byType(InventarioScreen), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('toque de aviso abre alertas solo con sesión y hogar vigentes', (
    tester,
  ) async {
    servidor.hogares = [_hogar];
    await abrir(tester);
    NotificacionesLocales.instancia.destino.value = const DestinoAviso(
      'usuario-1',
      'hogar-a',
    );
    await resolver(tester);
    expect(find.byType(AlertasCaducidadScreen), findsOneWidget);
    expect(
      tester
          .widget<AlertasCaducidadScreen>(find.byType(AlertasCaducidadScreen))
          .hogar,
      _hogar,
    );
    await tester.pageBack();
    await resolver(tester);
    expect(find.text('Mi hogar: Casa de prueba'), findsOneWidget);
  });

  for (final caso in [
    'otra cuenta',
    'expulsado',
    'otro hogar',
    'sin conexión',
  ]) {
    testWidgets('toque de aviso no abre contexto antiguo: $caso', (
      tester,
    ) async {
      servidor.hogares = [_hogar];
      await abrir(tester);
      if (caso == 'expulsado') servidor.hogares = [];
      if (caso == 'otro hogar')
        servidor.hogares = [
          {..._hogar, 'id': 'hogar-b'},
        ];
      if (caso == 'sin conexión') servidor.fallar = true;
      NotificacionesLocales.instancia.destino.value = DestinoAviso(
        caso == 'otra cuenta' ? 'usuario-otro' : 'usuario-1',
        'hogar-a',
      );
      await resolver(tester);
      expect(find.byType(AlertasCaducidadScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  }

  for (final oscuro in [false, true]) {
    testWidgets('accesos reales del Home conservan hogar y Atrás ($oscuro)', (
      tester,
    ) async {
      servidor.hogares = [_hogar];
      await abrir(tester, oscuro: oscuro);
      await pulsar(tester, 'Registrar consumo');
      expect(
        tester.widget<InventarioScreen>(find.byType(InventarioScreen)).hogar,
        _hogar,
      );
      expect(find.byType(CatalogoAlimentosScreen), findsNothing);
      await tester.pageBack();
      await resolver(tester);
      await pulsar(tester, 'Análisis');
      expect(
        tester.widget<IndicadoresScreen>(find.byType(IndicadoresScreen)).hogar,
        _hogar,
      );
      await tester.pageBack();
      await resolver(tester);
      expect(find.text('Mi hogar: Casa de prueba'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'indicadores abiertos desde Inventario vuelven a Inventario con su flecha',
    (tester) async {
      servidor.hogares = [_hogar];
      await abrir(tester);
      await pulsar(tester, 'Mi inventario');
      await tester.tap(find.byTooltip('Ver indicadores del hogar'));
      await resolver(tester);
      expect(find.byType(IndicadoresScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await resolver(tester);
      expect(find.byType(IndicadoresScreen), findsNothing);
      expect(find.byType(InventarioScreen), findsOneWidget);
    },
  );

  testWidgets('Análisis respeta expulsión y cierre de rutas protegidas', (
    tester,
  ) async {
    servidor.hogares = [_hogar];
    await abrir(tester);
    await pulsar(tester, 'Análisis');
    servidor.hogares = [];
    await reanudar(tester);
    expect(find.byType(IndicadoresScreen), findsNothing);
    expect(find.text('Todavía no perteneces a ningún hogar.'), findsOneWidget);
  });

  testWidgets('sin hogar mantiene cinco pestanas y bloquea registro', (
    tester,
  ) async {
    await abrir(tester);
    expect(servidor.consultasResumen, isEmpty);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Registrar alimento'),
          )
          .onPressed,
      isNull,
    );
    for (final etiqueta in ['Inventario', 'Compras', 'Alertas']) {
      await tester.tap(find.text(etiqueta));
      await resolver(tester);
      expect(
        find.text('Todavía no perteneces a ningún hogar.'),
        findsOneWidget,
      );
    }
  });

  testWidgets('resumen distingue cero real y alimentos distintos disponibles', (
    tester,
  ) async {
    servidor.hogares = [_hogar];
    await abrir(tester);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Sin datos'), findsNothing);
    servidor.resumen = [
      {'alimento_id': 1},
      {'alimento_id': 1},
      {'alimento_id': 2},
    ];
    await reanudar(tester);
    expect(find.text('2'), findsOneWidget);
    final consulta = servidor.consultasResumen.last.queryParameters;
    expect(consulta['hogar_id'], 'eq.hogar-a');
    expect(consulta['estado'], 'eq.DISPONIBLE');
    expect(consulta['cantidad_restante'], 'gt.0');
    final consultas = servidor.consultasResumen.length;
    await tester.pump();
    expect(servidor.consultasResumen.length, consultas);
  });

  testWidgets('resumen pagina y no informa totales truncados', (tester) async {
    servidor.hogares = [_hogar];
    servidor.resumen = List.generate(1001, (i) => {'alimento_id': i});
    await abrir(tester);
    expect(find.text('1001'), findsOneWidget);
    expect(servidor.consultasResumen.length, 2);
  });

  testWidgets(
    'error del resumen permite reintento sin confundirse con cero o sin hogar',
    (tester) async {
      servidor.hogares = [_hogar];
      servidor.fallarResumen = true;
      await abrir(tester);
      expect(find.text('Error'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.text('Mi hogar: Casa de prueba'), findsOneWidget);
      servidor.fallarResumen = false;
      await pulsar(tester, 'Reintentar resumen');
      expect(find.text('0'), findsOneWidget);
      expect(find.text('Error'), findsNothing);
    },
  );

  testWidgets('resumen descarta datos pendientes tras cambio de cuenta', (
    tester,
  ) async {
    servidor.hogares = [_hogar];
    final pendiente = Completer<List<dynamic>>();
    servidor.resumenPendiente = pendiente;
    await abrir(tester);
    expect(find.text('…'), findsOneWidget);
    servidor.hogares = [];
    await tester.runAsync(
      () => Supabase.instance.client.auth.signInWithPassword(
        email: 'otra@example.com',
        password: 'prueba-local',
      ),
    );
    await resolver(tester);
    pendiente.complete([
      {'alimento_id': 1},
    ]);
    await resolver(tester);
    expect(find.text('Sin datos'), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });

  testWidgets(
    'resumen se actualiza al volver de Inventario sin consulta extra al entrar',
    (tester) async {
      servidor.hogares = [_hogar];
      await abrir(tester);
      expect(servidor.consultasResumen.length, 1);
      await pulsar(tester, 'Registrar consumo');
      expect(servidor.consultasResumen.length, 1);
      servidor.resumen = [
        {'alimento_id': 4},
      ];
      await tester.pageBack();
      await resolver(tester);
      expect(find.text('1'), findsOneWidget);
      expect(servidor.consultasResumen.length, 2);
    },
  );

  testWidgets('ayuda describe consumo implementado y acceso desde Inventario', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AyudaScreen()));
    await tester.enterText(
      find.byType(TextField),
      '¿Cómo registro el consumo?',
    );
    await tester.pumpAndSettle();
    final pregunta = find.byKey(const ValueKey('¿Cómo registro el consumo?'));
    await tester.ensureVisible(pregunta);
    await tester.tap(pregunta);
    await tester.pumpAndSettle();
    expect(find.textContaining('utiliza Consumir'), findsOneWidget);
    expect(find.textContaining('próxima etapa'), findsNothing);
  });

  for (final oscuro in [false, true]) {
    final tema = oscuro ? 'oscuro' : 'claro';
    testWidgets(
      'sin hogar ofrece gestion desde Inicio y bloquea registro ($tema)',
      (tester) async {
        await abrir(tester, oscuro: oscuro);
        expect(
          find.text('Todavía no perteneces a ningún hogar.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Registrar alimento'),
              )
              .onPressed,
          isNull,
        );
        expect(find.text('Crear hogar'), findsOneWidget);
        expect(find.text('Unirse mediante código'), findsOneWidget);
        await pulsar(tester, 'Mi inventario');
        expect(find.byType(InventarioScreen), findsNothing);
      },
    );

    testWidgets(
      'un hogar se carga sin selección y conserva mapa de inventario ($tema)',
      (tester) async {
        servidor.hogares = [_hogar];
        await abrir(tester, oscuro: oscuro);
        expect(find.text('Mi hogar: Casa de prueba'), findsOneWidget);
        expect(find.text('Seleccionar hogar'), findsNothing);
        await pulsar(tester, 'Mi inventario');
        expect(
          tester.widget<InventarioScreen>(find.byType(InventarioScreen)).hogar,
          _hogar,
        );
        expect(
          servidor.consultas
              .where((uri) => uri.path.endsWith('despensa_item'))
              .first
              .queryParameters['hogar_id'],
          'eq.hogar-a',
        );
      },
    );

    testWidgets(
      'error de consulta no se interpreta como ausencia y permite reintento ($tema)',
      (tester) async {
        servidor.fallar = true;
        await abrir(tester, oscuro: oscuro);
        expect(
          find.text('No se pudo consultar tu hogar. Reintenta.'),
          findsOneWidget,
        );
        expect(find.text('Crear hogar'), findsNothing);
        servidor.fallar = false;
        servidor.hogares = [_hogar];
        await pulsar(tester, 'Reintentar');
        expect(find.text('Mi hogar: Casa de prueba'), findsOneWidget);
      },
    );

    testWidgets(
      'Mi hogar conserva gestión y oculta creación y selección ($tema)',
      (tester) async {
        servidor.hogares = [_hogar];
        await abrir(tester, gestion: true, oscuro: oscuro);
        expect(find.text('Miembros'), findsOneWidget);
        expect(find.text('Editar'), findsOneWidget);
        expect(find.text('Invitar'), findsOneWidget);
        expect(find.text('Crear hogar'), findsNothing);
        expect(find.byTooltip('Unirse a un hogar'), findsNothing);
        expect(find.text('Seleccionar hogar'), findsNothing);
      },
    );
  }

  testWidgets('catálogo recibe el mapa completo del único hogar', (
    tester,
  ) async {
    servidor.hogares = [_hogar];
    await abrir(tester);
    await pulsar(tester, 'Registrar alimentos');
    expect(
      tester
          .widget<CatalogoAlimentosScreen>(find.byType(CatalogoAlimentosScreen))
          .hogar,
      _hogar,
    );
    expect(
      servidor.consultas.any(
        (uri) =>
            uri.path.endsWith('alimento') &&
            uri.queryParameters['hogar_id'] == 'eq.hogar-a',
      ),
      isTrue,
    );
  });

  for (final gestion in [false, true]) {
    for (final crear in [true, false]) {
      testWidgets(
        'Recarga tras ${crear ? 'crear' : 'unirse'} (gestión: $gestion)',
        (tester) async {
          await abrir(tester, gestion: gestion);
          final antes = servidor.lecturas;
          if (gestion && !crear) {
            await tester.tap(find.byTooltip('Unirse a un hogar'));
            await resolver(tester);
          } else {
            await pulsar(
              tester,
              crear ? 'Crear hogar' : 'Unirse mediante código',
            );
          }
          await tester.enterText(
            find.byType(TextField).first,
            crear ? 'Casa nueva' : 'A1B2C3D4E5F60708',
          );
          await pulsar(tester, crear ? 'Crear hogar' : 'Unirse al hogar');
          final nombre = crear ? 'Casa nueva' : 'Casa de prueba';
          expect(
            find.text(gestion ? nombre : 'Mi hogar: $nombre'),
            findsOneWidget,
          );
          expect(servidor.lecturas, greaterThan(antes));
          expect(find.text('Crear hogar'), findsNothing);
          expect(find.text('Unirse mediante código'), findsNothing);
        },
      );
    }
  }

  testWidgets(
    'abandono actualiza Mi hogar y limpia el hogar del Home al volver',
    (tester) async {
      servidor.hogares = [
        {..._hogar, 'rol': 'MIEMBRO'},
      ];
      await abrir(tester);
      await pulsar(tester, 'Mi hogar');
      await pulsar(tester, 'Miembros');
      await pulsar(tester, 'Abandonar hogar');
      await pulsar(tester, 'Confirmar');
      expect(servidor.acciones.single['p_accion'], 'ABANDONAR');
      expect(servidor.acciones.single['p_hogar_id'], 'hogar-a');
      expect(find.text('Crear hogar'), findsOneWidget);
      await tester.pageBack();
      await resolver(tester);
      expect(
        find.text('Todavía no perteneces a ningún hogar.'),
        findsOneWidget,
      );
      expect(find.text('Mi hogar: Casa de prueba'), findsNothing);
    },
  );

  testWidgets('transferencia refresca los permisos visibles de Mi hogar', (
    tester,
  ) async {
    servidor.hogares = [_hogar];
    await abrir(tester);
    await pulsar(tester, 'Mi hogar');
    await pulsar(tester, 'Miembros');
    await tester.tap(find.byTooltip('Administrar integrante'));
    await resolver(tester);
    await pulsar(tester, 'Transferir administración');
    await pulsar(tester, 'Confirmar');
    expect(servidor.acciones.single['p_accion'], 'TRANSFERIR');
    expect(servidor.acciones.single['p_perfil_id'], 'usuario-otro');
    await tester.pageBack();
    await resolver(tester);
    expect(find.text('Editar'), findsNothing);
    expect(find.text('Invitar'), findsNothing);
    expect(find.text('Miembros'), findsOneWidget);
  });

  testWidgets(
    'verifica nuevamente antes de abrir un hogar que dejó de pertenecer',
    (tester) async {
      servidor.hogares = [_hogar];
      await abrir(tester);
      servidor.hogares = [];
      await pulsar(tester, 'Mi inventario');
      expect(find.byType(InventarioScreen), findsNothing);
      expect(
        find.text('Todavía no perteneces a ningún hogar.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('error de red al entrar a pestana bloquea y permite reintentar', (
    tester,
  ) async {
    servidor.hogares = [_hogar];
    await abrir(tester);
    servidor.fallar = true;
    await pulsar(tester, 'Mi inventario');
    expect(find.byType(InventarioScreen), findsNothing);
    expect(
      find.text(
        'No se pudo verificar el acceso al hogar. Comprueba tu conexión.',
      ),
      findsOneWidget,
    );
    servidor.fallar = false;
    await pulsar(tester, 'Reintentar acceso');
    expect(find.byType(InventarioScreen), findsOneWidget);
  });

  for (final gestion in [false, true]) {
    testWidgets(
      'rechaza hogares múltiples sin elegir el primero (gestión: $gestion)',
      (tester) async {
        servidor.hogares = [
          _hogar,
          {..._hogar, 'id': 'hogar-b'},
        ];
        await abrir(tester, gestion: gestion);
        expect(
          find.text('Se encontró más de un hogar activo. Contacta a soporte.'),
          findsOneWidget,
        );
        expect(find.text('Crear hogar'), findsNothing);
        expect(find.text('Casa de prueba'), findsNothing);
      },
    );

    testWidgets(
      'respuesta anterior no restaura un hogar tras recarga (gestión: $gestion)',
      (tester) async {
        servidor.hogares = [_hogar];
        await abrir(tester, gestion: gestion);
        final pendiente = Completer<List<dynamic>>();
        servidor.pendiente = pendiente;
        await reanudar(tester);
        expect(
          find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
              find.byType(CircularProgressIndicator).evaluate().isNotEmpty,
          isTrue,
        );
        servidor.hogares = [];
        await reanudar(tester);
        pendiente.complete([_hogar]);
        await resolver(tester);
        expect(
          find.text(
            gestion ? 'Crear hogar' : 'Todavía no perteneces a ningún hogar.',
          ),
          findsOneWidget,
        );
        expect(find.text('Mi hogar: Casa de prueba'), findsNothing);
        expect(find.text('Casa de prueba'), findsNothing);
      },
    );
  }

  testWidgets('cambio de cuenta invalida una consulta pendiente', (
    tester,
  ) async {
    await abrir(tester);
    final pendiente = Completer<List<dynamic>>();
    servidor.pendiente = pendiente;
    await reanudar(tester);
    servidor.hogares = [
      {..._hogar, 'id': 'hogar-b', 'nombre': 'Otra casa'},
    ];
    await tester.runAsync(() async {
      await Supabase.instance.client.auth.signInWithPassword(
        email: 'otra@example.com',
        password: 'prueba-local',
      );
    });
    await resolver(tester);
    pendiente.complete([_hogar]);
    await resolver(tester);
    expect(find.text('Mi hogar: Otra casa'), findsOneWidget);
    expect(find.text('Mi hogar: Casa de prueba'), findsNothing);
  });

  for (final oscuro in [false, true]) {
    testWidgets(
      'sesión activa mantiene Inventario y navegación secundaria ($oscuro)',
      (tester) async {
        servidor.hogares = [_hogar];
        await abrir(tester, oscuro: oscuro);
        await pulsar(tester, 'Mi inventario');
        expect(find.text('Mi inventario'), findsOneWidget);
        final antes = servidor.lecturas;
        await tester.tap(find.byTooltip('Lista de compras'));
        await resolver(tester);
        expect(find.byType(ListaComprasScreen), findsOneWidget);
        expect(servidor.lecturas, greaterThan(antes));
        await tester.pageBack();
        await resolver(tester);
        expect(find.text('Mi inventario'), findsOneWidget);
        await tester.pageBack();
        await resolver(tester);
        expect(find.byType(InventarioScreen), findsNothing);
        expect(find.text('Mi hogar: Casa de prueba'), findsOneWidget);
      },
    );

    testWidgets(
      'expulsión con Inventario abierto regresa al Home al reanudar ($oscuro)',
      (tester) async {
        servidor.hogares = [_hogar];
        await abrir(tester, oscuro: oscuro);
        await pulsar(tester, 'Mi inventario');
        servidor.hogares = [];
        await reanudar(tester);
        await resolver(tester);
        expect(find.byType(InventarioScreen), findsNothing);
        expect(
          find.text('Todavía no perteneces a ningún hogar.'),
          findsOneWidget,
        );
        await pulsar(tester, 'Mi inventario');
        expect(find.byType(InventarioScreen), findsNothing);
      },
    );
  }

  testWidgets('expulsión en primer plano se detecta al abrir una subpantalla', (
    tester,
  ) async {
    servidor.hogares = [_hogar];
    await abrir(tester);
    await pulsar(tester, 'Mi inventario');
    servidor.hogares = [];
    await tester.tap(find.byTooltip('Lista de compras'));
    await resolver(tester);
    expect(find.byType(ListaComprasScreen), findsNothing);
    expect(find.byType(InventarioScreen), findsNothing);
    expect(find.text('Todavía no perteneces a ningún hogar.'), findsOneWidget);
  });

  testWidgets('expulsión cierra subpantalla y diálogo sin enviar escrituras', (
    tester,
  ) async {
    servidor.hogares = [_hogar];
    await abrir(tester);
    await pulsar(tester, 'Mi inventario');
    await tester.tap(find.byTooltip('Lista de compras'));
    await resolver(tester);
    await pulsar(tester, 'Crear primera lista');
    await resolver(tester);
    await tester.enterText(find.byType(TextField), 'Compra de prueba');
    servidor.hogares = [];
    await reanudar(tester);
    await resolver(tester);
    expect(find.byType(ListaComprasScreen), findsNothing);
    expect(find.byType(InventarioScreen), findsNothing);
    expect(find.text('Compra de prueba'), findsNothing);
    expect(servidor.escriturasLista, 0);
    expect(find.text('Todavía no perteneces a ningún hogar.'), findsOneWidget);
  });

  testWidgets(
    'red caída bloquea el flujo sin expulsar y reintento recupera acceso',
    (tester) async {
      servidor.hogares = [_hogar];
      await abrir(tester);
      await pulsar(tester, 'Mi inventario');
      servidor.fallar = true;
      await reanudar(tester);
      expect(
        find.text(
          'No se pudo verificar el acceso al hogar. Comprueba tu conexión.',
        ),
        findsOneWidget,
      );
      expect(find.text('Todavía no perteneces a ningún hogar.'), findsNothing);
      expect(find.byType(InventarioScreen), findsOneWidget);
      servidor.fallar = false;
      await pulsar(tester, 'Reintentar acceso');
      expect(
        find.text(
          'No se pudo verificar el acceso al hogar. Comprueba tu conexión.',
        ),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Lista de compras'));
      await resolver(tester);
      expect(find.byType(ListaComprasScreen), findsOneWidget);
    },
  );

  testWidgets(
    'confirmar tras expulsión comprueba membresía y no crea la lista',
    (tester) async {
      servidor.hogares = [_hogar];
      await abrir(tester);
      await pulsar(tester, 'Mi inventario');
      await tester.tap(find.byTooltip('Lista de compras'));
      await resolver(tester);
      await pulsar(tester, 'Crear primera lista');
      await resolver(tester);
      await tester.enterText(find.byType(TextField), 'Compra de prueba');
      servidor.hogares = [];
      await pulsar(tester, 'Crear');
      await resolver(tester);
      expect(servidor.escriturasLista, 0);
      expect(find.byType(ListaComprasScreen), findsNothing);
      expect(
        find.text('Todavía no perteneces a ningún hogar.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'cambio de cuenta durante validación no restaura el flujo anterior',
    (tester) async {
      servidor.hogares = [_hogar];
      await abrir(tester);
      await pulsar(tester, 'Mi inventario');
      final pendiente = Completer<List<dynamic>>();
      servidor.pendiente = pendiente;
      await reanudar(tester);
      servidor.hogares = [
        {..._hogar, 'id': 'hogar-b', 'nombre': 'Otra casa'},
      ];
      await tester.runAsync(() async {
        await Supabase.instance.client.auth.signInWithPassword(
          email: 'otra@example.com',
          password: 'prueba-local',
        );
      });
      await resolver(tester);
      pendiente.complete([_hogar]);
      await resolver(tester);
      expect(find.byType(InventarioScreen), findsNothing);
      expect(find.text('Mi hogar: Otra casa'), findsOneWidget);
      expect(find.text('Mi hogar: Casa de prueba'), findsNothing);
    },
  );

  testWidgets('reanudar y navegar comparten la misma consulta de acceso', (
    tester,
  ) async {
    servidor.hogares = [_hogar];
    await abrir(tester);
    await pulsar(tester, 'Mi inventario');
    final pendiente = Completer<List<dynamic>>();
    servidor.pendiente = pendiente;
    final antes = servidor.lecturas;
    await reanudar(tester);
    await reanudar(tester);
    expect(servidor.lecturas, antes + 1);
    pendiente.complete([_hogar]);
    await resolver(tester);
    expect(find.byType(InventarioScreen), findsOneWidget);
  });
}
