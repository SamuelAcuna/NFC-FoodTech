import 'dart:convert';

const parametroMessages = {
  'El parámetro no existe.',
  'El valor debe ser un número entero.',
  'El valor debe ser un número decimal.',
  'El valor debe ser verdadero o falso.',
  'El valor debe ser JSON válido.',
  'El texto debe tener entre 1 y 200 caracteres.',
  'El valor está fuera del rango permitido.',
  'La hora debe tener formato HH:MM.',
  'Los canales deben ser una lista no vacía de PUSH, EMAIL o IN_APP.',
};
const systemKeys = {
  'notif.vencimiento.dias_anticipacion': 'Anticipación de vencimiento',
  'hogar.max_miembros': 'Máximo de miembros por hogar',
  'hogar.invitacion_vigencia_horas': 'Vigencia de invitación',
  'notif.hora_envio': 'Hora de envío',
};
const notificationKeys = {
  'notif.vencimiento.habilitada': 'Aviso de vencimiento próximo',
  'notif.lista_compra.habilitada': 'Sugerencias de lista de compras',
  'notif.resumen_semanal.habilitado': 'Resumen semanal',
};
String channelKey(String key) =>
    '${key.substring(0, key.lastIndexOf('.'))}.canales';
final contractKeys = {
  ...systemKeys.keys,
  ...notificationKeys.keys,
  ...notificationKeys.keys.map(channelKey),
};
const parameterHelp = {
  'notif.vencimiento.dias_anticipacion': 'Entre 0 y 30 días',
  'hogar.max_miembros': 'Entre 1 y 20 miembros',
  'hogar.invitacion_vigencia_horas': 'Entre 1 y 720 horas',
  'notif.hora_envio': 'HH:MM, formato de 24 horas',
};

class Parametro {
  Parametro.fromJson(Map<String, dynamic> j)
    : clave = j['clave'] as String,
      valor = j['valor'] as String,
      tipo = j['tipo_dato'] as String,
      descripcion = j['descripcion'] as String?,
      actualizado = DateTime.parse(j['actualizado_en'] as String);
  final String clave, valor, tipo;
  final String? descripcion;
  final DateTime actualizado;
}

String? validateParametro(String key, String type, String raw) {
  final v = raw.trim();
  if (type == 'ENTERO' && !RegExp(r'^-?[0-9]+$').hasMatch(v)) {
    return 'El valor debe ser un número entero.';
  }
  if (type == 'DECIMAL' && !RegExp(r'^-?[0-9]+(\.[0-9]+)?$').hasMatch(v)) {
    return 'El valor debe ser un número decimal.';
  }
  if (type == 'BOOLEANO' && v != 'true' && v != 'false') {
    return 'El valor debe ser verdadero o falso.';
  }
  if (type == 'TEXTO' && (v.isEmpty || v.runes.length > 200)) {
    return 'El texto debe tener entre 1 y 200 caracteres.';
  }
  dynamic json;
  if (type == 'JSON') {
    try {
      json = jsonDecode(v);
    } catch (_) {
      {
        return 'El valor debe ser JSON válido.';
      }
    }
  }
  final range = switch (key) {
    'notif.vencimiento.dias_anticipacion' => (0, 30),
    'hogar.max_miembros' => (1, 20),
    'hogar.invitacion_vigencia_horas' => (1, 720),
    _ => (null, null),
  };
  if (range.$1 != null) {
    final n = BigInt.tryParse(v);
    if (n == null || n < BigInt.from(range.$1!) || n > BigInt.from(range.$2!)) {
      return 'El valor está fuera del rango permitido.';
    }
  }
  if (key == 'notif.hora_envio' &&
      !RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(v)) {
    return 'La hora debe tener formato HH:MM.';
  }
  if (key.endsWith('.canales') &&
      (json is! List ||
          json.isEmpty ||
          json.any((e) => !['PUSH', 'EMAIL', 'IN_APP'].contains(e)) ||
          json.toSet().length != json.length)) {
    return 'Los canales deben ser una lista no vacía de PUSH, EMAIL o IN_APP.';
  }
  return null;
}

String normalizeParametro(String type, String value) =>
    type == 'JSON' ? jsonEncode(jsonDecode(value.trim())) : value.trim();
