import 'dart:convert';
import 'package:timezone/data/latest.dart' as datos;
import 'package:timezone/timezone.dart' as tz;

bool _zonaInicializada = false;
tz.Location get zonaAvisosSantiago {
  if (!_zonaInicializada) {
    datos.initializeTimeZones();
    _zonaInicializada = true;
  }
  return tz.getLocation('America/Santiago');
}

class PreferenciasAvisos {
  final bool proxima;
  final bool superada;
  final bool silencio;
  final int dias;
  final int hora;
  final int minuto;

  const PreferenciasAvisos({
    this.proxima = true,
    this.superada = true,
    this.silencio = false,
    this.dias = 3,
    this.hora = 9,
    this.minuto = 0,
  });
}

class AvisoLocal {
  final String usuarioId;
  final String hogarId;
  final String ingresoId;
  final String tipo;
  final bool estimada;
  final String huella;
  final tz.TZDateTime fecha;

  const AvisoLocal({
    required this.usuarioId,
    required this.hogarId,
    required this.ingresoId,
    required this.tipo,
    required this.estimada,
    required this.huella,
    required this.fecha,
  });

  String get clave => jsonEncode([usuarioId, hogarId, ingresoId, tipo]);
  String get titulo => tipo == 'PROXIMA'
      ? (estimada
            ? 'Fecha estimada de caducidad próxima'
            : 'Fecha de caducidad próxima')
      : (estimada ? 'Fecha estimada superada' : 'Fecha de caducidad superada');
  String get cuerpo => 'Revisa las alertas de caducidad en NFC-FoodTech.';
  String get payload => jsonEncode({
    'modulo': 'caducidad',
    'usuario': usuarioId,
    'hogar': hogarId,
  });
}

List<AvisoLocal> planificarAvisos({
  required String usuarioId,
  required String hogarId,
  required List<Map<String, dynamic>> ingresos,
  required PreferenciasAvisos preferencias,
  required DateTime ahora,
}) {
  if (usuarioId.isEmpty || hogarId.isEmpty || preferencias.silencio) return [];
  if (![1, 2, 3, 5, 7].contains(preferencias.dias) ||
      preferencias.hora < 0 ||
      preferencias.hora > 23 ||
      preferencias.minuto < 0 ||
      preferencias.minuto > 59) {
    throw ArgumentError('Preferencias de avisos inválidas.');
  }
  final zona = zonaAvisosSantiago;
  final actual = tz.TZDateTime.from(ahora, zona);
  final hoy = DateTime.utc(actual.year, actual.month, actual.day);
  final resultado = <AvisoLocal>[];
  final vistos = <String>{};
  for (final ingreso in ingresos) {
    if (ingreso['hogar_id'] != hogarId || ingreso['estado'] != 'DISPONIBLE')
      continue;
    final cantidad = num.tryParse(
      ingreso['cantidad_restante']?.toString() ?? '',
    );
    if (cantidad == null || !cantidad.isFinite || cantidad <= 0) continue;
    final id = ingreso['id']?.toString();
    if (id == null || id.isEmpty || !vistos.add(id)) continue;
    final texto = ingreso['fecha_vencimiento']?.toString() ?? '';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(texto)) continue;
    final civil = DateTime.tryParse('${texto}T00:00:00Z');
    if (civil == null || civil.toIso8601String().substring(0, 10) != texto)
      continue;
    final estimada = ingreso['vencimiento_estimado'] == true;
    for (final tipo in ['PROXIMA', 'SUPERADA']) {
      if (tipo == 'PROXIMA' && (!preferencias.proxima || civil.isBefore(hoy)))
        continue;
      if (tipo == 'SUPERADA' && !preferencias.superada) continue;
      final dia = civil.day + (tipo == 'PROXIMA' ? -preferencias.dias : 1);
      var fecha = tz.TZDateTime(
        zona,
        civil.year,
        civil.month,
        dia,
        preferencias.hora,
        preferencias.minuto,
      );
      if (!fecha.isAfter(actual)) {
        fecha = tz.TZDateTime(
          zona,
          actual.year,
          actual.month,
          actual.day,
          preferencias.hora,
          preferencias.minuto,
        );
        if (!fecha.isAfter(actual)) {
          fecha = tz.TZDateTime(
            zona,
            actual.year,
            actual.month,
            actual.day + 1,
            preferencias.hora,
            preferencias.minuto,
          );
        }
      }
      if (tipo == 'PROXIMA' &&
          DateTime.utc(fecha.year, fecha.month, fecha.day).isAfter(civil))
        continue;
      resultado.add(
        AvisoLocal(
          usuarioId: usuarioId,
          hogarId: hogarId,
          ingresoId: id,
          tipo: tipo,
          estimada: estimada,
          fecha: fecha,
          huella: jsonEncode([
            texto,
            estimada,
            tipo,
            tipo == 'PROXIMA' ? preferencias.dias : null,
            preferencias.hora,
            preferencias.minuto,
          ]),
        ),
      );
    }
  }
  resultado.sort((a, b) {
    final comparacion = a.fecha.compareTo(b.fecha);
    return comparacion != 0 ? comparacion : a.clave.compareTo(b.clave);
  });
  return resultado;
}
