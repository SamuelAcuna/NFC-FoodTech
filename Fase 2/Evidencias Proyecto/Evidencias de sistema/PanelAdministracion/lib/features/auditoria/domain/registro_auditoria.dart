import 'dart:convert';

class RegistroAuditoria {
  RegistroAuditoria.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      fecha = DateTime.parse(json['fecha'] as String),
      actor = json['actor_email'] as String?,
      entidad = json['entidad'] as String,
      entidadId = json['entidad_id'] as String,
      accion = json['accion'] as String,
      antes = json['antes'] == null
          ? null
          : Map<String, dynamic>.from(json['antes'] as Map),
      despues = json['despues'] == null
          ? null
          : Map<String, dynamic>.from(json['despues'] as Map),
      motivo = json['motivo'] as String?;
  final String id, entidad, entidadId, accion;
  final DateTime fecha;
  final String? actor, motivo;
  final Map<String, dynamic>? antes, despues;

  List<String> get camposCambiados =>
      ({...?antes?.keys, ...?despues?.keys}
            ..removeAll(['created_at', 'updated_at']))
          .where(
            (k) =>
                antes == null ||
                despues == null ||
                jsonEncode(antes?[k]) != jsonEncode(despues?[k]),
          )
          .toList()
        ..sort();

  String get texto {
    final values = despues ?? antes ?? {};
    final name = values['nombre'] ?? '';
    final verb = {
      'INSERT': 'Creó',
      'UPDATE': 'Editó',
      'DELETE': 'Eliminó',
    }[accion];
    if (entidad == 'perfil' && ['SUSPENDER', 'REACTIVAR'].contains(accion)) {
      return '${accion == 'SUSPENDER' ? 'Suspendió' : 'Reactivó'} la cuenta de «${values['email']}»';
    }
    if (entidad == 'solicitud_soporte' && accion == 'UPDATE') {
      final op = {
        'ASIGNAR': 'Asignó',
        'RESPONDER': 'Respondió',
        'CERRAR': 'Cerró',
      }[values['operacion']];
      if (op != null) return '$op la solicitud «${values['asunto']}»';
    }
    if (entidad == 'alimento') {
      if (accion == 'APROBAR') return 'Aprobó producto «$name»';
      if (accion == 'RECHAZAR') return 'Rechazó producto «$name»';
      if (accion == 'UPDATE' &&
          camposCambiados.length == 1 &&
          camposCambiados.single == 'activo') {
        return '${values['activo'] == true ? 'Reactivó' : 'Dio de baja'} alimento «$name»';
      }
    }
    if (verb != null && ['categoria', 'alimento'].contains(entidad)) {
      return '$verb ${entidad == 'categoria' ? 'categoría' : 'alimento'} «$name»';
    }
    if (entidad == 'parametro' && accion == 'UPDATE') {
      return 'Modificó parámetro «${values['clave']}»';
    }
    if (['rol', 'rol_permiso', 'perfil_rol'].contains(entidad) &&
        verb != null) {
      final operation = entidad == 'rol'
          ? verb
          : {'INSERT': 'Asignó', 'UPDATE': 'Editó', 'DELETE': 'Quitó'}[accion];
      return '$operation ${entidad == 'rol_permiso' ? 'permiso de rol' : 'rol'} ($entidad $entidadId)';
    }
    return '$accion en $entidad #$entidadId';
  }
}
