import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum EstadoM08 {
  inicial,
  revisando,
  lista,
  bloqueada,
  procesando,
  simulada,
  desconocido,
  error,
  sesionCambiada,
}

class M08EliminacionLocal extends ChangeNotifier {
  final String? Function() usuarioActual;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  invocar;
  final Future<String?> Function(String) leer;
  final Future<void> Function(String, String) guardar;
  final Duration espera;
  final String? _usuario;
  int _version = 0;
  bool _cerrado = false;
  EstadoM08 estado = EstadoM08.inicial;
  Map<String, dynamic>? revision;
  Map<String, dynamic> autenticacion = {};
  Map<String, dynamic>? _solicitud;
  bool pendiente = false;
  String mensaje = 'La eliminacion real permanece deshabilitada.';

  M08EliminacionLocal({
    required this.usuarioActual,
    required this.invocar,
    required this.leer,
    required this.guardar,
    this.espera = const Duration(seconds: 25),
  }) : _usuario = usuarioActual();

  factory M08EliminacionLocal.supabase() {
    final cliente = Supabase.instance.client;
    final preferencias = SharedPreferencesAsync();
    return M08EliminacionLocal(
      usuarioActual: () => cliente.auth.currentUser?.id,
      invocar: (nombre, datos) async {
        final respuesta = await cliente.functions.invoke(nombre, body: datos);
        if (respuesta.status != 200 || respuesta.data is! Map)
          throw StateError('Respuesta no confirmada');
        return Map<String, dynamic>.from(respuesta.data as Map);
      },
      leer: preferencias.getString,
      guardar: preferencias.setString,
    );
  }

  bool get ocupado =>
      estado == EstadoM08.revisando || estado == EstadoM08.procesando;
  bool get puedeSimular => !ocupado && !pendiente && estado == EstadoM08.lista;
  String get _clave => 'nfc_m08_solicitud_$_usuario';

  void cambioSesion() {
    if (_cerrado || usuarioActual() == _usuario) return;
    _version++;
    revision = null;
    autenticacion = {};
    _solicitud = null;
    pendiente = false;
    estado = EstadoM08.sesionCambiada;
    mensaje = 'La sesion cambio. Vuelve a abrir esta pantalla.';
    notifyListeners();
  }

  bool _vigente(int version) {
    if (_cerrado || version != _version) return false;
    if (_usuario == null || usuarioActual() != _usuario) {
      cambioSesion();
      return false;
    }
    return true;
  }

  void _validar(Map<String, dynamic> datos, String modo) {
    if (datos['borrado_real_habilitado'] != false || datos['modo'] != modo) {
      throw StateError('Contrato de simulacion no confirmado');
    }
  }

  Future<void> revisar() async {
    if (ocupado || !_vigente(_version)) return;
    final version = ++_version;
    estado = EstadoM08.revisando;
    revision = null;
    autenticacion = {};
    notifyListeners();
    try {
      final texto = await leer(_clave);
      if (!_vigente(version)) return;
      if (texto != null) {
        final datos = Map<String, dynamic>.from(jsonDecode(texto) as Map);
        if (datos['solicitud'] is! String || datos['recibo'] is! String)
          throw StateError('Recibo invalido');
        _solicitud = {
          'solicitud': datos['solicitud'],
          'recibo': datos['recibo'],
        };
        pendiente = datos['pendiente'] != false;
      }
      final datos = await invocar(
        'm08-preflight-cuenta-local',
        {},
      ).timeout(espera);
      if (!_vigente(version)) return;
      _validar(datos, 'SOLO_REVISION');
      final informe = Map<String, dynamic>.from(datos['revision'] as Map);
      if (informe['apto'] is! bool ||
          informe['bloqueos'] is! List ||
          informe['resumen'] is! Map)
        throw StateError('Revision invalida');
      revision = informe;
      autenticacion = Map<String, dynamic>.from(datos['autenticacion'] as Map);
      estado = informe['apto'] == true ? EstadoM08.lista : EstadoM08.bloqueada;
      mensaje = pendiente
          ? 'Hay un recibo guardado. Consulta su estado antes de otra simulacion.'
          : 'Revision completada. El borrado real sigue deshabilitado.';
    } catch (_) {
      if (!_vigente(version)) return;
      estado = EstadoM08.error;
      mensaje =
          'No se pudo revisar. El backend local debe desplegarse y validarse antes de usar este flujo.';
    }
    if (_vigente(version)) notifyListeners();
  }

  Map<String, dynamic> _nuevaSolicitud() {
    final azar = Random.secure();
    final bytes = List.generate(16, (_) => azar.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return {
      'solicitud':
          '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}',
      'recibo': List.generate(
        32,
        (_) => azar.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
    };
  }

  Future<void> simular({
    required String confirmacion,
    String contrasena = '',
    String codigo = '',
  }) async {
    if (!puedeSimular || !_vigente(_version)) return;
    if (confirmacion != 'ELIMINAR') {
      mensaje = 'Escribe exactamente ELIMINAR.';
      notifyListeners();
      return;
    }
    final version = ++_version;
    estado = EstadoM08.procesando;
    notifyListeners();
    bool enviada = false;
    try {
      _solicitud = _nuevaSolicitud();
      await guardar(_clave, jsonEncode(_solicitud));
      if (!_vigente(version)) return;
      pendiente = true;
      enviada = true;
      final datos = await invocar('m08-confirmar-cuenta-local', {
        ..._solicitud!,
        'accion': 'SIMULAR',
        'confirmacion': confirmacion,
        'contrasena': contrasena,
        'codigo': codigo,
      }).timeout(espera);
      if (!_vigente(version)) return;
      await _aplicarEstado(datos);
    } catch (_) {
      if (!_vigente(version)) return;
      estado = enviada ? EstadoM08.desconocido : EstadoM08.error;
      mensaje = enviada
          ? 'Resultado desconocido. Consulta el estado con el recibo guardado; no repitas la solicitud.'
          : 'No se pudo guardar el recibo. No se envio la solicitud.';
    }
    if (_vigente(version)) notifyListeners();
  }

  Future<void> _aplicarEstado(Map<String, dynamic> datos) async {
    _validar(datos, 'SIMULACION_SEGURA');
    final resultado = datos['estado'];
    if (![
      'RECIBIDA',
      'SIMULADA',
      'BLOQUEADA',
      'RECHAZADA',
      'ERROR',
      'EXPIRADA',
    ].contains(resultado))
      throw StateError('Estado no reconocido');
    pendiente = resultado == 'RECIBIDA';
    estado = resultado == 'SIMULADA'
        ? EstadoM08.simulada
        : pendiente
        ? EstadoM08.desconocido
        : EstadoM08.bloqueada;
    mensaje = resultado == 'SIMULADA'
        ? 'Identidad verificada y simulacion registrada. No se elimino ninguna cuenta.'
        : 'Estado: $resultado. ${_mensajeCodigo(datos['codigo'])}';
    if (datos['bloqueos'] is List && revision != null) {
      revision = {...revision!, 'apto': false, 'bloqueos': datos['bloqueos']};
    }
    if (!pendiente && _solicitud != null) {
      await guardar(_clave, jsonEncode({..._solicitud!, 'pendiente': false}));
    }
  }

  String _mensajeCodigo(Object? codigo) => switch (codigo) {
    'VERIFICANDO' => 'El servidor aun esta verificando.',
    'REQUISITOS_PENDIENTES' ||
    'REQUISITOS_CAMBIARON' => 'Vuelve a revisar los requisitos.',
    'OTRA_SOLICITUD_EN_CURSO' =>
      'Existe otra solicitud en curso; espera antes de continuar.',
    'PLAZO_AGOTADO' => 'La simulacion expiro; no habilita un borrado.',
    'CONTRASENA_REQUERIDA' || 'VERIFICACION_AUTH_RECHAZADA' =>
      'No se pudo verificar la identidad con Auth.',
    'TOTP_REQUERIDO' => 'Se necesita un codigo TOTP vigente.',
    'TOTP_SESION_RECIENTE_REQUERIDO' =>
      'Verifica TOTP de esta sesion y vuelve a revisar los requisitos.',
    _ => 'No se autoriza ningun borrado. Revisa el estado antes de continuar.',
  };

  Future<void> consultarEstado() async {
    if (ocupado || _solicitud == null || !_vigente(_version)) return;
    final version = ++_version;
    estado = EstadoM08.procesando;
    notifyListeners();
    try {
      final datos = await invocar('m08-confirmar-cuenta-local', {
        ..._solicitud!,
        'accion': 'ESTADO',
      }).timeout(espera);
      if (!_vigente(version)) return;
      await _aplicarEstado(datos);
    } catch (_) {
      if (!_vigente(version)) return;
      estado = EstadoM08.desconocido;
      mensaje =
          'No se pudo recuperar el resultado. Conserva el recibo y no repitas la solicitud.';
    }
    if (_vigente(version)) notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    _version++;
    super.dispose();
  }
}
