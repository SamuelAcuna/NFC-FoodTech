import 'dart:convert';
import '../models/plan_avisos_locales.dart';

abstract interface class ProgramadorAvisos {
  Future<bool> permitido();
  Future<Set<int>> pendientes();
  Future<void> programar(int id, AvisoLocal aviso);
  Future<void> cancelar(int id);
}

abstract interface class AlmacenAvisos {
  Future<String?> leer();
  Future<void> guardar(String valor);
}

abstract interface class FuenteAvisos {
  Future<String?> hogarActivo();
  Future<PreferenciasAvisos> preferencias(String usuarioId);
  Future<bool> silenciado(String usuarioId);
  Future<List<Map<String, dynamic>>> ingresos(String hogarId);
}

class CoordinadorAvisos {
  final ProgramadorAvisos programador;
  final AlmacenAvisos almacen;
  final FuenteAvisos fuente;
  final String? Function() usuarioActual;
  final DateTime Function() ahora;
  final void Function(Object?)? informarError;
  final void Function(String)? diagnosticar;
  Map<String, dynamic>? _registro;
  Future<void> _cola = Future.value();
  Future<void>? _enCurso;
  ({String usuario, String? hogar, bool verificar})? _pendiente;
  int _revision = 0;
  String? _contexto;
  DateTime? _ultimaCarga;

  CoordinadorAvisos({
    required this.programador,
    required this.almacen,
    required this.fuente,
    required this.usuarioActual,
    DateTime Function()? ahora,
    this.informarError,
    this.diagnosticar,
  }) : ahora = ahora ?? DateTime.now;

  Future<void> _serializar(Future<void> Function() accion) {
    final siguiente = _cola.then((_) => accion());
    _cola = siguiente.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return siguiente;
  }

  Future<Map<String, dynamic>> _datos() async {
    if (_registro != null) return _registro!;
    final texto = await almacen.leer();
    final registro = texto == null
        ? <String, dynamic>{
            'siguiente': 1700000000,
            'avisos': <String, dynamic>{},
          }
        : Map<String, dynamic>.from(jsonDecode(texto) as Map);
    if (registro['avisos'] is! Map || registro['siguiente'] is! int) {
      throw StateError('No se pudo leer el registro de avisos locales.');
    }
    _registro = registro;
    return registro;
  }

  Future<List<Map<String, Object?>>> agendaDiagnostico() async {
    var resultado = <Map<String, Object?>>[];
    await _serializar(() async {
      final texto = await almacen.leer();
      if (texto == null) return;
      final registro = jsonDecode(texto) as Map;
      resultado = [
        for (final fila in (registro['avisos'] as Map).values.cast<Map>())
          {
            'id': fila['id'],
            'fecha': fila['fecha'],
            'activa': fila['activa'],
            'registrada': fila['registrada'],
          },
      ];
    });
    return resultado;
  }

  Future<void> _cancelar(int id, String motivo) async {
    diagnosticar?.call('cancelar inicio id=$id motivo=$motivo');
    await programador.cancelar(id);
    diagnosticar?.call('cancelar OK id=$id motivo=$motivo');
  }

  Future<void> invalidar({
    String? hogarConservado,
    bool conservarUsuario = false,
  }) async {
    _revision++;
    _pendiente = null;
    _contexto = null;
    _ultimaCarga = null;
    final usuario = usuarioActual();
    try {
      await _serializar(() async {
        final registro = await _datos();
        for (final valor in (registro['avisos'] as Map).values) {
          final fila = valor as Map;
          final conservar =
              conservarUsuario &&
              fila['usuario'] == usuario &&
              (hogarConservado == null || fila['hogar'] == hogarConservado);
          if (!conservar && fila['activa'] == true) {
            await _cancelar(fila['id'] as int, 'invalidacion');
            fila['activa'] = false;
          }
        }
        await almacen.guardar(jsonEncode(registro));
      });
    } catch (error) {
      informarError?.call(error);
    }
  }

  Future<void> sincronizar({
    String? hogarVerificado,
    bool verificar = true,
    bool forzar = true,
  }) {
    final usuario = usuarioActual();
    if (usuario == null) return invalidar();
    if (!forzar && !verificar && _contexto == '$usuario/$hogarVerificado') {
      if (_enCurso != null) return _enCurso!;
      if (_ultimaCarga != null &&
          ahora().difference(_ultimaCarga!) < const Duration(seconds: 30))
        return Future.value();
    }
    _revision++;
    _pendiente = (
      usuario: usuario,
      hogar: hogarVerificado,
      verificar: verificar,
    );
    return _enCurso ??= _procesar().whenComplete(() => _enCurso = null);
  }

  Future<void> _procesar() async {
    while (_pendiente != null) {
      final solicitud = _pendiente!;
      _pendiente = null;
      final revision = _revision;
      bool vigente() =>
          revision == _revision && usuarioActual() == solicitud.usuario;
      try {
        diagnosticar?.call('sincronizacion inicio');
        final silencio = await fuente.silenciado(solicitud.usuario);
        diagnosticar?.call('silencio=$silencio');
        if (!vigente()) continue;
        if (silencio) {
          await _serializar(() async {
            if (!vigente()) return;
            final registro = await _datos();
            for (final fila in (registro['avisos'] as Map).values.cast<Map>()) {
              if (fila['activa'] == true) {
                await _cancelar(fila['id'] as int, 'silencio');
                fila['activa'] = false;
              }
            }
            await almacen.guardar(jsonEncode(registro));
          });
          if (vigente()) informarError?.call(null);
          continue;
        }
        final hogar = solicitud.verificar
            ? await fuente.hogarActivo()
            : solicitud.hogar;
        if (!vigente()) continue;
        _contexto = '${solicitud.usuario}/$hogar';
        await _serializar(() async {
          if (!vigente()) return;
          final registro = await _datos();
          for (final fila in (registro['avisos'] as Map).values.cast<Map>()) {
            if ((fila['usuario'] != solicitud.usuario ||
                    fila['hogar'] != hogar) &&
                fila['activa'] == true) {
              await _cancelar(fila['id'] as int, 'cambio_contexto');
              fila['activa'] = false;
            }
          }
          await almacen.guardar(jsonEncode(registro));
        });
        if (!vigente()) continue;
        final permitido = await programador.permitido();
        diagnosticar?.call('hogar_activo=${hogar != null} permiso=$permitido');
        if (!vigente()) continue;
        List<AvisoLocal> plan = [];
        if (hogar != null && !silencio && permitido) {
          final preferencias = await fuente.preferencias(solicitud.usuario);
          diagnosticar?.call(
            'preferencias proxima=${preferencias.proxima} '
            'superada=${preferencias.superada} silencio=${preferencias.silencio} '
            'dias=${preferencias.dias} hora=${preferencias.hora}:${preferencias.minuto}',
          );
          if (!vigente()) continue;
          final ingresos = await fuente.ingresos(hogar);
          diagnosticar?.call('ingresos_leidos=${ingresos.length}');
          if (!vigente()) continue;
          plan = planificarAvisos(
            usuarioId: solicitud.usuario,
            hogarId: hogar,
            ingresos: ingresos,
            preferencias: preferencias,
            ahora: ahora(),
          );
        }
        diagnosticar?.call(
          'plan eventos=${plan.length} proxima_UTC='
          '${plan.isEmpty ? "ninguna" : plan.first.fecha.toUtc().toIso8601String()}',
        );
        await _serializar(() async {
          if (!vigente()) return;
          final registro = await _datos();
          final filas = registro['avisos'] as Map;
          final pendientes = await programador.pendientes();
          if (!vigente()) return;
          final claves = plan.map((a) => a.clave).toSet();
          for (final entrada in filas.entries) {
            final fila = entrada.value as Map;
            if (!claves.contains(entrada.key) && fila['activa'] == true) {
              await _cancelar(fila['id'] as int, 'fuera_del_plan');
              fila['activa'] = false;
            }
            if (!vigente()) return;
          }
          for (final aviso in plan) {
            if (!vigente()) return;
            final anterior = filas[aviso.clave] as Map?;
            if (anterior != null && anterior['huella'] == aviso.huella) {
              final fecha = DateTime.parse(anterior['fecha'] as String);
              if (anterior['activa'] == true &&
                  pendientes.contains(anterior['id']))
                continue;
              if (!fecha.isAfter(ahora()) && anterior['registrada'] != false)
                continue;
            }
            final int id;
            if (anterior != null) {
              id = anterior['id'] as int;
              await _cancelar(id, 'reprogramacion');
            } else {
              var siguiente = registro['siguiente'] as int;
              while (pendientes.contains(siguiente)) {
                siguiente++;
              }
              if (siguiente >= 2147483647)
                throw StateError('Se agotaron los identificadores de avisos.');
              id = siguiente;
              registro['siguiente'] = siguiente + 1;
            }
            filas[aviso.clave] = {
              'id': id,
              'usuario': aviso.usuarioId,
              'hogar': aviso.hogarId,
              'huella': aviso.huella,
              'fecha': aviso.fecha.toUtc().toIso8601String(),
              'activa': true,
              'registrada': false,
            };
            await almacen.guardar(jsonEncode(registro));
            if (!vigente()) return;
            diagnosticar?.call(
              'zonedSchedule inicio id=$id UTC=${aviso.fecha.toUtc().toIso8601String()}',
            );
            await programador.programar(id, aviso);
            (filas[aviso.clave] as Map)['registrada'] = true;
            diagnosticar?.call('zonedSchedule OK id=$id');
          }
          await almacen.guardar(jsonEncode(registro));
        });
        if (vigente()) {
          _ultimaCarga = ahora();
          informarError?.call(null);
        }
      } catch (error) {
        diagnosticar?.call('sincronizacion error tipo=${error.runtimeType}');
        if (vigente()) informarError?.call(error);
      }
    }
  }
}
