import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/plan_avisos_locales.dart';
import 'coordinador_avisos.dart';

class DestinoAviso {
  final String usuarioId;
  final String hogarId;
  const DestinoAviso(this.usuarioId, this.hogarId);
}

class _AlmacenPreferencias implements AlmacenAvisos {
  final preferencias = SharedPreferencesAsync();
  static const clave = 'nfc_foodtech_agenda_android_v1';
  @override
  Future<String?> leer() => preferencias.getString(clave);
  @override
  Future<void> guardar(String valor) => preferencias.setString(clave, valor);
}

class _FuenteSupabase implements FuenteAvisos {
  final cliente = Supabase.instance.client;
  final cache = SharedPreferencesAsync();
  String _clave(String usuario, String campo) =>
      'nfc_foodtech_notif_${usuario}_$campo';
  @override
  Future<bool> silenciado(String usuarioId) async =>
      await cache.getBool(_clave(usuarioId, 'silencio')) ?? false;
  @override
  Future<String?> hogarActivo() async {
    final datos = await cliente
        .rpc('m14_listar_hogares')
        .timeout(const Duration(seconds: 15));
    if (datos is! List || datos.length > 1)
      throw StateError('No se pudo verificar el hogar para los avisos.');
    if (datos.isEmpty) return null;
    final id = datos.single['id'];
    if (id is! String || id.isEmpty)
      throw StateError('El hogar de los avisos no es válido.');
    return id;
  }

  @override
  Future<PreferenciasAvisos> preferencias(String usuarioId) async {
    var proxima = await cache.getBool(_clave(usuarioId, 'caducidad')) ?? true;
    var superada =
        await cache.getBool(_clave(usuarioId, 'fecha_superada')) ?? true;
    var dias = await cache.getInt(_clave(usuarioId, 'dias')) ?? 3;
    var hora = await cache.getString(_clave(usuarioId, 'hora')) ?? '09:00';
    final pendiente =
        await cache.getBool(_clave(usuarioId, 'pendiente_sync')) ?? false;
    if (!pendiente) {
      final filas = await cliente
          .from('preferencia_notificacion')
          .select('plantilla_id, habilitada, dias_anticipacion, hora_envio')
          .eq('perfil_id', usuarioId)
          .inFilter('plantilla_id', [2, 3, 4])
          .timeout(const Duration(seconds: 15));
      for (final fila in filas) {
        if (fila['plantilla_id'] == 2) {
          proxima = fila['habilitada'] as bool? ?? proxima;
          dias =
              int.tryParse(fila['dias_anticipacion']?.toString() ?? '') ?? dias;
          hora = fila['hora_envio']?.toString() ?? hora;
        }
        if (fila['plantilla_id'] == 3) {
          superada = fila['habilitada'] as bool? ?? superada;
          if (!filas.any(
            (f) => f['plantilla_id'] == 2 && f['hora_envio'] != null,
          )) {
            hora = fila['hora_envio']?.toString() ?? hora;
          }
        }
      }
      final porPlantilla = {
        for (final fila in filas) fila['plantilla_id']: fila,
      };
      hora =
          porPlantilla[2]?['hora_envio']?.toString() ??
          porPlantilla[3]?['hora_envio']?.toString() ??
          porPlantilla[4]?['hora_envio']?.toString() ??
          hora;
    }
    final partes = hora.split(':');
    return PreferenciasAvisos(
      proxima: proxima,
      superada: superada,
      silencio: await silenciado(usuarioId),
      dias: dias,
      hora: int.tryParse(partes.first) ?? 9,
      minuto: partes.length > 1 ? int.tryParse(partes[1]) ?? 0 : 0,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> ingresos(String hogarId) async {
    final usuario = cliente.auth.currentUser?.id;
    final resultado = <Map<String, dynamic>>[];
    Object? cursor;
    while (true) {
      if (cliente.auth.currentUser?.id != usuario)
        throw StateError('La sesión cambió durante la agenda.');
      var consulta = cliente
          .from('despensa_item')
          .select(
            'id, hogar_id, estado, cantidad_restante, fecha_vencimiento, vencimiento_estimado',
          )
          .eq('hogar_id', hogarId)
          .eq('estado', 'DISPONIBLE')
          .gt('cantidad_restante', 0);
      if (cursor != null) consulta = consulta.gt('id', cursor);
      final pagina = await consulta
          .order('id', ascending: true)
          .limit(400)
          .timeout(const Duration(seconds: 15));
      if (cliente.auth.currentUser?.id != usuario)
        throw StateError('La sesión cambió durante la agenda.');
      if (pagina.isEmpty) return resultado;
      resultado.addAll(pagina);
      final siguiente = pagina.last['id'] as Object;
      if (siguiente == cursor)
        throw StateError('No se pudo completar la agenda de avisos.');
      cursor = siguiente;
    }
  }
}

class ProgramadorAndroidAvisos implements ProgramadorAvisos {
  bool inicializado = false;
  final plugin = FlutterLocalNotificationsPlugin();
  AndroidFlutterLocalNotificationsPlugin get android => plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()!;
  static const canal = AndroidNotificationChannel(
    'caducidad_local_v1',
    'Caducidad de alimentos',
    description: 'Recordatorios locales de fechas de caducidad',
    importance: Importance.defaultImportance,
  );
  Future<void> inicializar(void Function(String?) recibir) async {
    final correcto = await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_aviso_alimentos'),
      ),
      onDidReceiveNotificationResponse: (respuesta) =>
          recibir(respuesta.payload),
    );
    if (correcto != true) throw StateError('Inicializacion rechazada');
    await android.createNotificationChannel(canal);
    inicializado = true;
    final inicio = await plugin.getNotificationAppLaunchDetails();
    if (inicio?.didNotificationLaunchApp == true)
      recibir(inicio?.notificationResponse?.payload);
  }

  @override
  Future<bool> permitido() async =>
      await android.areNotificationsEnabled() ?? false;
  @override
  Future<Set<int>> pendientes() async =>
      (await plugin.pendingNotificationRequests()).map((a) => a.id).toSet();
  @override
  Future<void> cancelar(int id) => plugin.cancel(id: id);
  @override
  Future<void> programar(int id, AvisoLocal aviso) => plugin.zonedSchedule(
    id: id,
    scheduledDate: aviso.fecha,
    title: aviso.titulo,
    body: aviso.cuerpo,
    payload: aviso.payload,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    notificationDetails: detalles,
  );

  static const detalles = NotificationDetails(
    android: AndroidNotificationDetails(
      'caducidad_local_v1',
      'Caducidad de alimentos',
      channelDescription: 'Recordatorios locales de fechas de caducidad',
      icon: 'ic_aviso_alimentos',
      visibility: NotificationVisibility.private,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );

  Future<void> publicarPruebaDebug() async {
    if (!kDebugMode) throw UnsupportedError('Solo debug');
    await plugin.show(
      id: 1600000000,
      title: 'Prueba inmediata NFC-FoodTech',
      body: 'Diagnostico de publicacion local Android.',
      notificationDetails: detalles,
    );
  }

  Future<DateTime> programarPruebaDebug() async {
    if (!kDebugMode) throw UnsupportedError('Solo debug');
    final fecha = tz.TZDateTime.from(
      DateTime.now().add(const Duration(minutes: 3)),
      zonaAvisosSantiago,
    );
    await plugin.zonedSchedule(
      id: 1600000001,
      scheduledDate: fecha,
      title: 'Prueba programada NFC-FoodTech',
      body: 'Diagnostico de alarma local Android.',
      notificationDetails: detalles,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
    return fecha;
  }
}

class NotificacionesLocales {
  NotificacionesLocales._();
  static final instancia = NotificacionesLocales._();
  final permiso = ValueNotifier<bool?>(null);
  final error = ValueNotifier<String?>(null);
  final destino = ValueNotifier<DestinoAviso?>(null);
  ProgramadorAndroidAvisos? _android;
  CoordinadorAvisos? _coordinador;
  StreamSubscription<AuthState>? _sesion;
  bool get disponible => _android != null;

  Future<void> inicializar() async {
    if (_coordinador != null ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android)
      return;
    try {
      final android = ProgramadorAndroidAvisos();
      await android.inicializar(_recibir);
      _anotarDebug("inicializacion OK");
      _android = android;
      _coordinador = CoordinadorAvisos(
        programador: android,
        almacen: _AlmacenPreferencias(),
        fuente: _FuenteSupabase(),
        usuarioActual: () => Supabase.instance.client.auth.currentUser?.id,
        diagnosticar: kDebugMode ? _anotarDebug : null,
        informarError: (e) {
          if (e != null) _anotarDebug("error ${_codigoError(e)}");
          error.value = e == null
              ? null
              : 'No se pudo actualizar la agenda local. Comprueba el permiso y la conexión; reintenta.';
        },
      );
      var usuario = Supabase.instance.client.auth.currentUser?.id;
      _sesion = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
        final actual = Supabase.instance.client.auth.currentUser?.id;
        if (actual != usuario) {
          usuario = actual;
          destino.value = null;
          unawaited(_coordinador!.invalidar(conservarUsuario: true));
        }
      });
      await _coordinador!.invalidar(conservarUsuario: true);
      await comprobarPermiso();
      if (usuario != null) unawaited(sincronizar());
    } catch (e) {
      _anotarDebug("inicializacion error ${_codigoError(e)}");
      error.value = 'No se pudieron inicializar los avisos Android.';
    }
  }

  void _recibir(String? payload) {
    try {
      final datos = jsonDecode(payload ?? '') as Map;
      if (datos['modulo'] == 'caducidad' &&
          datos['usuario'] is String &&
          datos['hogar'] is String) {
        destino.value = DestinoAviso(
          datos['usuario'] as String,
          datos['hogar'] as String,
        );
      }
    } catch (_) {}
  }

  Future<void> comprobarPermiso() async {
    try {
      final anterior = permiso.value;
      permiso.value = await _android?.permitido();
      if (anterior != null && permiso.value != anterior) {
        unawaited(_coordinador?.sincronizar() ?? Future<void>.value());
      }
    } catch (_) {
      permiso.value = null;
    }
  }

  Future<void> solicitarPermiso() async {
    try {
      await _android?.android.requestNotificationsPermission();
      await comprobarPermiso();
      await sincronizar();
    } catch (_) {
      error.value = 'No se pudo consultar el permiso de notificaciones.';
    }
  }

  void contextoVerificado(String usuarioId, String? hogarId) {
    if (_coordinador == null ||
        Supabase.instance.client.auth.currentUser?.id != usuarioId)
      return;
    if (hogarId == null) {
      unawaited(_coordinador!.invalidar());
    } else {
      unawaited(
        _coordinador!.sincronizar(
          hogarVerificado: hogarId,
          verificar: false,
          forzar: false,
        ),
      );
    }
  }

  Future<void> sincronizar() async {
    await comprobarPermiso();
    await _coordinador?.sincronizar();
  }

  Future<Set<int>> pendientes() async => await _android?.pendientes() ?? {};

  final _eventosDebug = <String>[];
  String _ultimoPlanDebug = 'Sin calculo observado en esta ejecucion.';
  String _preferenciasDebug = 'Sin lectura observada en esta ejecucion.';
  String _silencioDebug = 'Sin lectura observada en esta ejecucion.';
  DateTime? _pruebaDebug;

  String _codigoError(Object e) => e is PlatformException
      ? 'PlatformException:${e.code}'
      : '${e.runtimeType}';

  void _anotarDebug(String evento) {
    if (!kDebugMode) return;
    if (evento.startsWith('plan eventos=')) _ultimoPlanDebug = evento;
    if (evento.startsWith('preferencias ')) _preferenciasDebug = evento;
    if (evento.startsWith('silencio=')) _silencioDebug = evento;
    _eventosDebug.add('${DateTime.now().toUtc().toIso8601String()} $evento');
    if (_eventosDebug.length > 100) _eventosDebug.removeAt(0);
  }

  Future<String> publicarPruebaDebug({required bool programada}) async {
    if (!kDebugMode) throw UnsupportedError('Solo debug');
    final android = _android;
    if (android == null)
      return 'Plugin no inicializado. Inspecciona el estado.';
    try {
      if (programada) {
        _anotarDebug('prueba zonedSchedule inicio id=1600000001');
        _pruebaDebug = await android.programarPruebaDebug();
        _anotarDebug(
          'prueba zonedSchedule OK id=1600000001 UTC=${_pruebaDebug!.toUtc().toIso8601String()}',
        );
      } else {
        _anotarDebug('prueba show inicio id=1600000000');
        await android.publicarPruebaDebug();
        _anotarDebug('prueba show OK id=1600000000');
      }
      return 'Llamada completada; no demuestra entrega.\n${await inspeccionarDebug()}';
    } catch (e) {
      _anotarDebug('prueba error ${_codigoError(e)}');
      return 'Fallo ${_codigoError(e)}\n${await inspeccionarDebug()}';
    }
  }

  Future<String> inspeccionarDebug() async {
    if (!kDebugMode) throw UnsupportedError('Solo debug');
    final texto = StringBuffer();
    Future<void> leer(
      String etiqueta,
      Future<Object?> Function() consulta,
    ) async {
      try {
        texto.writeln('$etiqueta: ${await consulta()}');
      } catch (e) {
        texto.writeln('$etiqueta: ERROR ${_codigoError(e)}');
      }
    }

    texto.writeln('Inicializacion: ${_android?.inicializado ?? false}');
    texto.writeln('Zona de programacion: ${zonaAvisosSantiago.name}');
    texto.writeln('Ahora Santiago: ${tz.TZDateTime.now(zonaAvisosSantiago)}');
    texto.writeln('Ahora dispositivo: ${DateTime.now()}');
    texto.writeln('Modo: inexactAllowWhileIdle (sin alarmas exactas).');
    texto.writeln('Ultimo calculo: $_ultimoPlanDebug');
    texto.writeln('Ultimas preferencias leidas: $_preferenciasDebug');
    texto.writeln('Ultima lectura de silencio: $_silencioDebug');
    texto.writeln('Prueba en esta ejecucion: ${_pruebaDebug ?? "ninguna"}');
    final android = _android;
    if (android != null) {
      await leer('POST_NOTIFICATIONS / app habilitada', android.permitido);
      await leer('Canal Android caducidad_local_v1', () async {
        final canales = await android.android.getNotificationChannels();
        final propios = canales
            ?.where((c) => c.id == ProgramadorAndroidAvisos.canal.id)
            .toList();
        if (propios == null || propios.isEmpty) return 'ausente';
        final canal = propios.single;
        return 'importancia=${canal.importance.name}, sonido=${canal.playSound}';
      });
      await leer(
        'Pendientes del plugin (cache, NO prueba de alarma OS)',
        () async {
          final ids = (await android.pendientes()).toList()..sort();
          return 'cantidad=${ids.length}, IDs=$ids';
        },
      );
      await leer(
        'Publicadas actualmente segun Android (IDs)',
        () async => (await android.plugin.getActiveNotifications())
            .map((n) => n.id)
            .toList(),
      );
    }
    await leer(
      'Agenda propia persistida (NO equivale a pendientes Android)',
      () async => await _coordinador?.agendaDiagnostico() ?? [],
    );
    texto.writeln(
      'Eventos de esta ejecucion (hasta 100; cancelar OK confirma cancelacion):',
    );
    texto.write(_eventosDebug.join('\n'));
    return texto.toString();
  }

  Future<void> cerrar() async {
    await _sesion?.cancel();
  }
}
