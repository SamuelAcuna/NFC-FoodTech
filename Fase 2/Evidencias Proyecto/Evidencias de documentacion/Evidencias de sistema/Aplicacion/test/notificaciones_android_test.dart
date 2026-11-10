import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nfc_foodtech_app/models/plan_avisos_locales.dart';
import 'package:nfc_foodtech_app/services/notificaciones_locales.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canal = MethodChannel('dexterous.com/flutter/local_notifications');
  final llamadas = <MethodCall>[];
  var inicializacionCorrecta = true;
  var fallaProgramacion = false;
  late ProgramadorAndroidAvisos android;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    llamadas.clear();
    inicializacionCorrecta = true;
    fallaProgramacion = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, (llamada) async {
          llamadas.add(llamada);
          switch (llamada.method) {
            case 'initialize':
              return inicializacionCorrecta;
            case 'getNotificationAppLaunchDetails':
              return {'notificationLaunchedApp': false};
            case 'areNotificationsEnabled':
              return true;
            case 'pendingNotificationRequests':
              return [
                {'id': 1600000001},
              ];
            case 'zonedSchedule':
              if (fallaProgramacion) {
                throw PlatformException(code: 'schedule_failure');
              }
              return null;
            default:
              return null;
          }
        });
    android = ProgramadorAndroidAvisos();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, null);
  });

  test('inicializa icono y canal; no acepta inicializacion falsa', () async {
    inicializacionCorrecta = false;
    await expectLater(android.inicializar((_) {}), throwsStateError);
    expect(android.inicializado, false);
    inicializacionCorrecta = true;
    await android.inicializar((_) {});
    expect(android.inicializado, true);
    expect(
      (llamadas.first.arguments as Map)['defaultIcon'],
      'ic_aviso_alimentos',
    );
    expect(llamadas.any((l) => l.method == 'createNotificationChannel'), true);
  });

  test('publicacion inmediata y programada comparten canal e icono', () async {
    await android.inicializar((_) {});
    await android.publicarPruebaDebug();
    final antes = DateTime.now();
    final fecha = await android.programarPruebaDebug();
    expect(fecha.difference(antes).inSeconds, inInclusiveRange(179, 181));
    final inmediata =
        llamadas.singleWhere((l) => l.method == 'show').arguments as Map;
    final programada =
        llamadas.singleWhere((l) => l.method == 'zonedSchedule').arguments
            as Map;
    for (final datos in [inmediata, programada]) {
      final detalles = datos['platformSpecifics'] as Map;
      expect(detalles['channelId'], 'caducidad_local_v1');
      expect(detalles['icon'], 'ic_aviso_alimentos');
      expect(datos['payload'], '');
    }
    expect(programada['timeZoneName'], 'America/Santiago');
    expect(
      (programada['platformSpecifics'] as Map)['scheduleMode'],
      'inexactAllowWhileIdle',
    );
    expect(llamadas.any((l) => l.method.contains('ExactAlarms')), false);
    expect(await android.pendientes(), {1600000001});
  });

  test(
    'el plan real alcanza zonedSchedule con su fecha futura Santiago',
    () async {
      await android.inicializar((_) {});
      final hoy = tz.TZDateTime.now(zonaAvisosSantiago);
      final fecha = tz.TZDateTime(
        zonaAvisosSantiago,
        hoy.year,
        hoy.month,
        hoy.day + 2,
        9,
      );
      final aviso = AvisoLocal(
        usuarioId: 'u',
        hogarId: 'h',
        ingresoId: 'i',
        tipo: 'PROXIMA',
        estimada: true,
        fecha: fecha,
        huella: 'x',
      );
      await android.programar(1700000000, aviso);
      final datos =
          llamadas.singleWhere((l) => l.method == 'zonedSchedule').arguments
              as Map;
      expect(datos['id'], 1700000000);
      expect(datos['timeZoneName'], 'America/Santiago');
      expect(
        datos['scheduledDateTime'],
        startsWith(fecha.toIso8601String().substring(0, 19)),
      );
    },
  );

  test(
    'errores nativos de programacion se propagan; no hay exito falso',
    () async {
      await android.inicializar((_) {});
      fallaProgramacion = true;
      await expectLater(
        android.programarPruebaDebug(),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
