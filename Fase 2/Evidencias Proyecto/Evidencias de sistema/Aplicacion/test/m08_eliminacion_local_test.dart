import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_foodtech_app/services/m08_eliminacion_local.dart';

Map<String, dynamic> informe({
  bool apto = true,
  bool google = false,
  String? bloqueo,
}) => {
  'modo': 'SOLO_REVISION',
  'borrado_real_habilitado': false,
  'revision': {
    'apto': apto,
    'bloqueos': bloqueo == null
        ? []
        : [
            {'codigo': bloqueo, 'mensaje': 'Resuelve el requisito.'},
          ],
    'resumen': {'membresias_removidas': 1},
    'consecuencias': ['Se conservan datos compartidos.'],
  },
  'autenticacion': {
    'contrasena': !google,
    'requiere_totp': google,
    'totp_en_sesion': google,
    'disponible': true,
  },
};
Map<String, dynamic> resultado(String estado) => {
  'modo': 'SIMULACION_SEGURA',
  'borrado_real_habilitado': false,
  'estado': estado,
  'codigo': estado == 'SIMULADA' ? 'BORRADO_DESHABILITADO' : 'VERIFICANDO',
};

void main() {
  late M08EliminacionLocal control;
  late String? usuario;
  late Map<String, String> cache;
  late List<(String, Map<String, dynamic>)> llamadas;
  late Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  responder;
  setUp(() {
    usuario = 'usuario-a';
    cache = {};
    llamadas = [];
    responder = (nombre, datos) async => nombre == 'm08-preflight-cuenta-local'
        ? informe()
        : resultado('SIMULADA');
    control = M08EliminacionLocal(
      usuarioActual: () => usuario,
      invocar: (nombre, datos) {
        llamadas.add((nombre, datos));
        return responder(nombre, datos);
      },
      leer: (clave) async => cache[clave],
      guardar: (clave, datos) async {
        cache[clave] = datos;
      },
      espera: const Duration(milliseconds: 40),
    );
  });
  tearDown(() => control.dispose());

  test(
    'correo sin hogar revisa y simula sin UUID objetivo ni cierre de sesión',
    () async {
      await control.revisar();
      expect(control.puedeSimular, true);
      await control.simular(
        confirmacion: 'ELIMINAR',
        contrasena: 'clave-no-persistir',
      );
      expect(control.estado, EstadoM08.simulada);
      expect(usuario, 'usuario-a');
      final datos = llamadas.last.$2;
      expect(datos['accion'], 'SIMULAR');
      expect(datos.containsKey('usuario_id'), false);
      expect(jsonEncode(cache), isNot(contains('clave-no-persistir')));
      expect(datos['recibo'], matches(RegExp(r'^[0-9a-f]{64}$')));
    },
  );
  test(
    'Google reutiliza estado y verificación TOTP sin exigir contraseña',
    () async {
      responder = (nombre, datos) async =>
          nombre == 'm08-preflight-cuenta-local'
          ? informe(google: true)
          : resultado('SIMULADA');
      await control.revisar();
      expect(control.autenticacion['contrasena'], false);
      await control.simular(confirmacion: 'ELIMINAR');
      expect(control.estado, EstadoM08.simulada);
    },
  );
  for (final bloqueo in [
    'MEMBRESIA_ACTIVA',
    'CREADOR_HOGAR',
    'CREADOR_SIN_RELEVO',
    'CUENTA_NO_ACTIVA',
    'REFERENCIA_BLOQUEANTE',
  ]) {
    test('$bloqueo se muestra y no habilita simulación', () async {
      responder = (_, _) async => informe(apto: false, bloqueo: bloqueo);
      await control.revisar();
      expect(control.estado, EstadoM08.bloqueada);
      expect(control.revision!['bloqueos'], isNotEmpty);
      await control.simular(confirmacion: 'ELIMINAR');
      expect(llamadas, hasLength(1));
    });
  }
  test('membresía histórica informada no equivale a activa', () async {
    await control.revisar();
    expect(control.revision!['resumen']['membresias_removidas'], 1);
    expect(control.puedeSimular, true);
  });
  test(
    'error de servidor no se interpreta como ausencia de dependencias',
    () async {
      responder = (_, _) async => throw StateError('Servidor no disponible');
      await control.revisar();
      expect(control.estado, EstadoM08.error);
      expect(control.revision, null);
      expect(control.puedeSimular, false);
    },
  );
  test(
    'timeout guarda recibo, bloquea reenvío y consulta mismo identificador',
    () async {
      await control.revisar();
      responder = (_, datos) => datos['accion'] == 'ESTADO'
          ? Future.value(resultado('SIMULADA'))
          : Completer<Map<String, dynamic>>().future;
      await control.simular(confirmacion: 'ELIMINAR');
      expect(control.estado, EstadoM08.desconocido);
      expect(control.pendiente, true);
      final id = llamadas.last.$2['solicitud'];
      await control.simular(confirmacion: 'ELIMINAR');
      expect(llamadas, hasLength(2));
      await control.consultarEstado();
      expect(llamadas.last.$2['solicitud'], id);
      expect(control.estado, EstadoM08.simulada);
    },
  );
  test(
    'doble pulsación comparte protección de procesamiento y envía una solicitud',
    () async {
      await control.revisar();
      final respuesta = Completer<Map<String, dynamic>>();
      responder = (_, _) => respuesta.future;
      final primera = control.simular(confirmacion: 'ELIMINAR');
      final segunda = control.simular(confirmacion: 'ELIMINAR');
      await Future<void>.delayed(Duration.zero);
      respuesta.complete(resultado('SIMULADA'));
      await Future.wait([primera, segunda]);
      expect(llamadas, hasLength(2));
    },
  );
  test(
    'cambio de usuario durante confirmación descarta respuesta y conserva nueva sesión',
    () async {
      await control.revisar();
      final respuesta = Completer<Map<String, dynamic>>();
      responder = (_, _) => respuesta.future;
      final operacion = control.simular(confirmacion: 'ELIMINAR');
      await Future<void>.delayed(Duration.zero);
      usuario = 'usuario-b';
      control.cambioSesion();
      respuesta.complete(resultado('SIMULADA'));
      await operacion;
      expect(control.estado, EstadoM08.sesionCambiada);
      expect(usuario, 'usuario-b');
      expect(control.revision, null);
    },
  );
  test('cambio de usuario durante revisión no publica datos viejos', () async {
    final respuesta = Completer<Map<String, dynamic>>();
    responder = (_, _) => respuesta.future;
    final operacion = control.revisar();
    await Future<void>.delayed(Duration.zero);
    usuario = 'usuario-b';
    respuesta.complete(informe());
    await operacion;
    expect(control.estado, EstadoM08.sesionCambiada);
    expect(control.revision, null);
  });
  test(
    'contrato que habilita borrado real se rechaza sin tratarlo como éxito',
    () async {
      await control.revisar();
      responder = (_, _) async => {
        ...resultado('SIMULADA'),
        'borrado_real_habilitado': true,
      };
      await control.simular(confirmacion: 'ELIMINAR');
      expect(control.estado, EstadoM08.desconocido);
      expect(usuario, 'usuario-a');
    },
  );
  test(
    'recibo sobrevive a recreación del controlador y no se duplica tras reiniciar',
    () async {
      await control.revisar();
      responder = (_, _) => Completer<Map<String, dynamic>>().future;
      await control.simular(confirmacion: 'ELIMINAR');
      final otro = M08EliminacionLocal(
        usuarioActual: () => usuario,
        invocar: (nombre, datos) async => nombre == 'm08-preflight-cuenta-local'
            ? informe()
            : resultado('SIMULADA'),
        leer: (clave) async => cache[clave],
        guardar: (clave, datos) async {
          cache[clave] = datos;
        },
      );
      await otro.revisar();
      expect(otro.pendiente, true);
      expect(otro.puedeSimular, false);
      await otro.consultarEstado();
      await otro.revisar();
      expect(otro.puedeSimular, true);
      otro.dispose();
    },
  );
}
