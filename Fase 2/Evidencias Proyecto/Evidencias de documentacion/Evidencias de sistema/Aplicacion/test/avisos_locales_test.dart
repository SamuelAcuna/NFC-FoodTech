import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:nfc_foodtech_app/models/plan_avisos_locales.dart';
import 'package:nfc_foodtech_app/services/coordinador_avisos.dart';

Map<String, dynamic> ingreso({
  String fecha = '2026-11-10',
  bool estimada = true,
  String hogar = 'hogar-a',
  num cantidad = 100,
  String estado = 'DISPONIBLE',
}) => {
  'id': 'ingreso-a',
  'hogar_id': hogar,
  'fecha_vencimiento': fecha,
  'vencimiento_estimado': estimada,
  'cantidad_restante': cantidad,
  'estado': estado,
};

class ProgramadorSimulado implements ProgramadorAvisos {
  bool permiso = true;
  final programadas = <int, AvisoLocal>{};
  final canceladas = <int>[];
  final idsAjenos = <int>{7};
  int llamadas = 0;
  bool fallarProgramacion = false;
  @override
  Future<bool> permitido() async => permiso;
  @override
  Future<Set<int>> pendientes() async => {...programadas.keys, ...idsAjenos};
  @override
  Future<void> programar(int id, AvisoLocal aviso) async {
    llamadas++;
    if (fallarProgramacion) throw StateError('Fallo nativo simulado');
    programadas[id] = aviso;
  }

  @override
  Future<void> cancelar(int id) async {
    canceladas.add(id);
    programadas.remove(id);
    idsAjenos.remove(id);
  }
}

class AlmacenSimulado implements AlmacenAvisos {
  String? contenido;
  @override
  Future<String?> leer() async => contenido;
  @override
  Future<void> guardar(String valor) async {
    contenido = valor;
  }
}

class FuenteSimulada implements FuenteAvisos {
  String? hogar = 'hogar-a';
  bool fallar = false;
  bool fallarInventario = false;
  int consultas = 0;
  Completer<void>? espera;
  PreferenciasAvisos ajustes = const PreferenciasAvisos();
  List<Map<String, dynamic>> items = [ingreso()];
  @override
  Future<String?> hogarActivo() async {
    if (fallar) throw StateError('Sin conexión');
    return hogar;
  }

  @override
  Future<bool> silenciado(String usuarioId) async => ajustes.silencio;
  @override
  Future<PreferenciasAvisos> preferencias(String usuarioId) async => ajustes;
  @override
  Future<List<Map<String, dynamic>>> ingresos(String hogarId) async {
    consultas++;
    final pendiente = espera;
    espera = null;
    if (pendiente != null) await pendiente.future;
    if (fallar || fallarInventario) throw StateError('Sin conexión');
    return items;
  }
}

void main() {
  List<AvisoLocal> plan({
    List<Map<String, dynamic>>? items,
    PreferenciasAvisos ajustes = const PreferenciasAvisos(),
    DateTime? ahora,
    String usuario = 'usuario-a',
    String hogar = 'hogar-a',
  }) => planificarAvisos(
    usuarioId: usuario,
    hogarId: hogar,
    ingresos: items ?? [ingreso()],
    preferencias: ajustes,
    ahora: ahora ?? DateTime.utc(2026, 11, 5),
  );

  test('anticipación y hora civil de Santiago para fecha estimada', () {
    final aviso = plan().firstWhere((a) => a.tipo == 'PROXIMA');
    expect(aviso.fecha.year, 2026);
    expect(aviso.fecha.month, 11);
    expect(aviso.fecha.day, 7);
    expect(aviso.fecha.hour, 9);
    expect(aviso.fecha.toUtc(), DateTime.utc(2026, 11, 7, 12));
    expect(aviso.titulo, contains('estimada'));
  });
  test('fecha manual conserva nombre y no se trata como timestamp UTC', () {
    final avisos = plan(items: [ingreso(estimada: false)]);
    expect(avisos.first.titulo, 'Fecha de caducidad próxima');
    expect(avisos.last.titulo, 'Fecha de caducidad superada');
    expect(avisos.first.fecha.day, 7);
  });
  test(
    'vence mañana con anticipacion de un dia programa hoy si la hora es futura',
    () {
      final aviso = plan(
        items: [ingreso(fecha: '2026-11-06')],
        ajustes: const PreferenciasAvisos(dias: 1, hora: 16, minuto: 30),
        ahora: tz.TZDateTime(zonaAvisosSantiago, 2026, 11, 5, 16),
      ).firstWhere((a) => a.tipo == 'PROXIMA');
      expect(
        aviso.fecha,
        tz.TZDateTime(zonaAvisosSantiago, 2026, 11, 5, 16, 30),
      );
      expect(aviso.fecha.toUtc(), DateTime.utc(2026, 11, 5, 19, 30));
    },
  );
  test('fecha superada usa siguiente hora preferida y no programa próxima', () {
    final avisos = plan(
      items: [ingreso(fecha: '2026-11-01')],
      ahora: DateTime.utc(2026, 11, 5, 13),
    );
    expect(avisos, hasLength(1));
    expect(avisos.single.tipo, 'SUPERADA');
    expect(avisos.single.fecha.day, 6);
    expect(avisos.single.fecha.hour, 9);
  });
  test('si la hora de hoy no pasó se conserva para aviso atrasado', () {
    final avisos = plan(
      items: [ingreso(fecha: '2026-11-01')],
      ahora: DateTime.utc(2026, 11, 5, 10),
    );
    expect(avisos.single.fecha.day, 5);
    expect(avisos.single.fecha.hour, 9);
  });
  test('hora próxima pasada no produce aviso próximo después de caducar', () {
    final avisos = plan(
      items: [ingreso(fecha: '2026-11-05')],
      ahora: DateTime.utc(2026, 11, 5, 13),
    );
    expect(avisos.map((a) => a.tipo), ['SUPERADA']);
  });
  test('preferencias deshabilitadas y silencio no programan', () {
    expect(
      plan(ajustes: const PreferenciasAvisos(proxima: false, superada: false)),
      isEmpty,
    );
    expect(plan(ajustes: const PreferenciasAvisos(silencio: true)), isEmpty);
    expect(
      plan(ajustes: const PreferenciasAvisos(proxima: false)).single.tipo,
      'SUPERADA',
    );
  });
  test('agotados, descartados, otro hogar y fechas inválidas quedan fuera', () {
    for (final item in [
      ingreso(cantidad: 0),
      ingreso(estado: 'DESECHADO'),
      ingreso(hogar: 'otro'),
      ingreso(fecha: '2026-02-30'),
      ingreso(fecha: ''),
      {...ingreso(), 'fecha_vencimiento': null},
    ]) {
      expect(plan(items: [item]), isEmpty);
    }
  });
  test('cambio de fecha actualiza huella sin cambiar identidad', () {
    final anterior = plan().first;
    final nuevo = plan(items: [ingreso(fecha: '2026-11-12')]).first;
    expect(nuevo.clave, anterior.clave);
    expect(nuevo.huella, isNot(anterior.huella));
    expect(nuevo.fecha.day, 9);
  });
  test('usuarios y hogares diferentes no comparten identidad', () {
    expect(plan(usuario: 'otro').first.clave, isNot(plan().first.clave));
    expect(
      plan(
        hogar: 'otro',
        items: [ingreso(hogar: 'otro')],
      ).first.clave,
      isNot(plan().first.clave),
    );
  });
  test('repetición de ingresos no duplica avisos ni expone datos privados', () {
    final avisos = plan(
      items: [
        ingreso(),
        {...ingreso(), 'nombre': 'Secreto'},
      ],
    );
    expect(avisos.length, 2);
    for (final a in avisos) {
      expect(a.cuerpo, isNot(contains('Secreto')));
      expect(a.cuerpo, isNot(contains('hogar-a')));
    }
  });
  test('medianoche UTC no adelanta el día civil de Santiago', () {
    final aviso = plan(
      items: [ingreso(fecha: '2026-11-06')],
      ajustes: const PreferenciasAvisos(dias: 1),
      ahora: DateTime.utc(2026, 11, 6, 1, 30),
    ).firstWhere((a) => a.tipo == 'PROXIMA');
    expect(aviso.fecha.day, 6);
    expect(aviso.fecha.hour, 9);
    expect(aviso.fecha.isAfter(DateTime.utc(2026, 11, 6, 1, 30)), isTrue);
  });
  test('hora inexistente en salto estacional se normaliza hacia adelante', () {
    final aviso = plan(
      items: [ingreso(fecha: '2026-09-07')],
      ajustes: const PreferenciasAvisos(dias: 1, hora: 0, minuto: 30),
      ahora: DateTime.utc(2026, 9, 5),
    ).firstWhere((a) => a.tipo == 'PROXIMA');
    expect(aviso.fecha.day, 6);
    expect(aviso.fecha.hour, 1);
    expect(aviso.fecha.minute, 30);
  });
  test('Santiago aplica verano e invierno mediante IANA', () {
    final verano = plan(
      items: [ingreso(fecha: '2026-01-10')],
      ahora: DateTime.utc(2026, 1, 1),
    ).first;
    final invierno = plan(
      items: [ingreso(fecha: '2026-07-10')],
      ahora: DateTime.utc(2026, 7, 1),
    ).first;
    expect(verano.fecha.timeZoneOffset, const Duration(hours: -3));
    expect(invierno.fecha.timeZoneOffset, const Duration(hours: -4));
    expect(verano.fecha.hour, 9);
    expect(invierno.fecha.hour, 9);
  });
  test(
    'cruce estacional conserva día y hora civil con jornadas de 23 y 25 horas',
    () {
      final zona = zonaAvisosSantiago;
      final primavera = plan(
        items: [ingreso(fecha: '2026-09-07')],
        ajustes: const PreferenciasAvisos(dias: 1),
        ahora: tz.TZDateTime(zona, 2026, 9, 5, 10),
      ).first;
      expect(primavera.fecha.hour, 9);
      expect(
        primavera.fecha.difference(tz.TZDateTime(zona, 2026, 9, 5, 9)).inHours,
        23,
      );
      final otono = plan(
        items: [ingreso(fecha: '2026-04-06')],
        ajustes: const PreferenciasAvisos(dias: 1),
        ahora: tz.TZDateTime(zona, 2026, 4, 4, 10),
      ).first;
      expect(otono.fecha.hour, 9);
      expect(
        otono.fecha.difference(tz.TZDateTime(zona, 2026, 4, 4, 9)).inHours,
        25,
      );
    },
  );

  group('reconciliación sin canales nativos', () {
    late ProgramadorSimulado nativo;
    late AlmacenSimulado almacen;
    late FuenteSimulada fuente;
    late CoordinadorAvisos servicio;
    late String? usuario;
    late DateTime fecha;
    late List<String> eventos;
    Object? error;
    setUp(() {
      nativo = ProgramadorSimulado();
      almacen = AlmacenSimulado();
      fuente = FuenteSimulada();
      usuario = 'usuario-a';
      fecha = DateTime.utc(2026, 11, 5);
      error = null;
      eventos = [];
      servicio = CoordinadorAvisos(
        programador: nativo,
        almacen: almacen,
        fuente: fuente,
        usuarioActual: () => usuario,
        ahora: () => fecha,
        informarError: (e) => error = e,
        diagnosticar: eventos.add,
      );
    });
    test(
      'diagnostico separa agenda persistida de pendientes y no expone contexto',
      () async {
        await servicio.sincronizar();
        final antes = nativo.llamadas;
        final agenda = await servicio.agendaDiagnostico();
        expect(agenda, hasLength(2));
        expect(agenda.every((f) => f['registrada'] == true), true);
        expect(jsonEncode(agenda), isNot(contains('usuario-a')));
        expect(jsonEncode(agenda), isNot(contains('hogar-a')));
        expect(eventos.join(), isNot(contains('ingreso-a')));
        await servicio.sincronizar();
        expect(nativo.llamadas, antes);
        expect(eventos.where((e) => e.startsWith('cancelar OK')), isEmpty);
        fuente.ajustes = const PreferenciasAvisos(silencio: true);
        await servicio.sincronizar();
        expect(eventos.where((e) => e.contains('motivo=silencio')), isNotEmpty);
        expect(nativo.programadas, isEmpty);
      },
    );
    test(
      'registro persistido sin programacion exitosa puede reintentarse aun pasada la fecha',
      () async {
        nativo.fallarProgramacion = true;
        await servicio.sincronizar();
        expect(error, isA<StateError>());
        expect(nativo.programadas, isEmpty);
        expect(
          (await servicio.agendaDiagnostico()).single['registrada'],
          false,
        );
        fecha = DateTime.utc(2026, 11, 9, 18);
        nativo.fallarProgramacion = false;
        await servicio.sincronizar();
        expect(error, isNull);
        expect(nativo.programadas, hasLength(2));
        expect(
          nativo.programadas.values.every((a) => a.fecha.isAfter(fecha)),
          true,
        );
      },
    );
    test(
      'sincronización repetida y reinicio del servicio conservan identificadores',
      () async {
        await servicio.sincronizar();
        final ids = nativo.programadas.keys.toSet();
        await servicio.sincronizar();
        servicio = CoordinadorAvisos(
          programador: nativo,
          almacen: almacen,
          fuente: fuente,
          usuarioActual: () => usuario,
          ahora: () => fecha,
        );
        await servicio.sincronizar();
        expect(nativo.programadas.keys.toSet(), ids);
        expect(nativo.llamadas, 2);
        expect(nativo.idsAjenos, {7});
      },
    );
    test(
      'cambio de fecha cancela y reemplaza con los mismos identificadores',
      () async {
        await servicio.sincronizar();
        final ids = nativo.programadas.keys.toSet();
        fuente.items = [ingreso(fecha: '2026-11-12')];
        await servicio.sincronizar();
        expect(nativo.programadas.keys.toSet(), ids);
        expect(nativo.canceladas.toSet(), ids);
        expect(nativo.programadas.values.first.fecha.day, 9);
      },
    );
    test(
      'consumo total, descarte y deshabilitación cancelan solo avisos propios',
      () async {
        await servicio.sincronizar();
        fuente.items = [ingreso(cantidad: 0)];
        await servicio.sincronizar();
        expect(nativo.programadas, isEmpty);
        expect(nativo.idsAjenos, {7});
        fuente.items = [ingreso()];
        fuente.ajustes = const PreferenciasAvisos(superada: false);
        await servicio.sincronizar();
        expect(nativo.programadas.values.single.tipo, 'PROXIMA');
      },
    );
    test(
      'silencio local cancela incluso si la siguiente lectura de inventario falla',
      () async {
        await servicio.sincronizar();
        fuente.ajustes = const PreferenciasAvisos(silencio: true);
        fuente.fallar = true;
        await servicio.sincronizar();
        expect(nativo.programadas, isEmpty);
        expect(error, isNull);
      },
    );
    test(
      'error de red conserva agenda y permite recuperar sincronización',
      () async {
        await servicio.sincronizar();
        final ids = nativo.programadas.keys.toSet();
        fuente.fallar = true;
        await servicio.sincronizar();
        expect(error, isNotNull);
        expect(nativo.programadas.keys.toSet(), ids);
        fuente.fallar = false;
        fuente.items = [];
        await servicio.sincronizar();
        expect(error, isNull);
        expect(nativo.programadas, isEmpty);
      },
    );
    test(
      'fallo de inventario tras verificar membresía conserva alarmas',
      () async {
        await servicio.sincronizar();
        final ids = nativo.programadas.keys.toSet();
        fuente.fallarInventario = true;
        await servicio.sincronizar();
        expect(error, isNotNull);
        expect(nativo.programadas.keys.toSet(), ids);
        expect(nativo.canceladas, isEmpty);
      },
    );
    test(
      'sin permiso no se programa y concederlo permite reconciliar',
      () async {
        nativo.permiso = false;
        await servicio.sincronizar();
        expect(nativo.programadas, isEmpty);
        nativo.permiso = true;
        await servicio.sincronizar();
        expect(nativo.programadas.length, 2);
      },
    );
    test(
      'expulsión confirmada cancela y cambio de hogar no conserva agenda anterior',
      () async {
        await servicio.sincronizar();
        fuente.hogar = null;
        await servicio.sincronizar();
        expect(nativo.programadas, isEmpty);
        fuente.hogar = 'hogar-b';
        fuente.items = [ingreso(hogar: 'hogar-b')];
        await servicio.sincronizar();
        expect(
          nativo.programadas.values.every((a) => a.hogarId == 'hogar-b'),
          isTrue,
        );
      },
    );
    test(
      'cierre de sesión y nuevo usuario no reutilizan identificadores',
      () async {
        await servicio.sincronizar();
        final ids = nativo.programadas.keys.toSet();
        usuario = null;
        await servicio.invalidar();
        expect(nativo.programadas, isEmpty);
        usuario = 'usuario-b';
        await servicio.sincronizar();
        expect(nativo.programadas.keys.toSet().intersection(ids), isEmpty);
        expect(jsonDecode(almacen.contenido!)['avisos'], hasLength(4));
      },
    );
    test(
      'consulta antigua no programa después de un cambio de cuenta',
      () async {
        final espera = Completer<void>();
        fuente.espera = espera;
        final tarea = servicio.sincronizar();
        await Future<void>.delayed(Duration.zero);
        usuario = 'usuario-b';
        await servicio.invalidar(conservarUsuario: true);
        espera.complete();
        await tarea;
        expect(nativo.programadas, isEmpty);
        await servicio.sincronizar();
        expect(
          nativo.programadas.values.every((a) => a.usuarioId == 'usuario-b'),
          isTrue,
        );
      },
    );
    test('peticiones simultáneas se agrupan y no duplican avisos', () async {
      final espera = Completer<void>();
      fuente.espera = espera;
      final primera = servicio.sincronizar();
      await Future<void>.delayed(Duration.zero);
      final segunda = servicio.sincronizar();
      espera.complete();
      await Future.wait([primera, segunda]);
      expect(nativo.programadas.length, 2);
      expect(nativo.llamadas, 2);
    });
    test('aviso pasado no se reproduce cada día al sincronizar', () async {
      fuente.items = [ingreso(fecha: '2026-11-01')];
      await servicio.sincronizar();
      expect(nativo.llamadas, 1);
      nativo.programadas.clear();
      fecha = DateTime.utc(2026, 11, 8, 16);
      await servicio.sincronizar();
      expect(nativo.llamadas, 1);
      expect(nativo.programadas, isEmpty);
    });
  });
}
