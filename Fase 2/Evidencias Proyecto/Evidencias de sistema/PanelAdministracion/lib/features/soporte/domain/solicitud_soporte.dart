class SolicitudSoporte {
  SolicitudSoporte.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      tipo = j['tipo'] as String,
      asunto = j['asunto'] as String,
      mensaje = j['mensaje'] as String,
      estado = j['estado'] as String,
      prioridad = (j['prioridad'] as num).toInt(),
      email = j['solicitante_email'] as String? ?? '—',
      hogar = j['hogar_ref'] as String?,
      fecha = DateTime.parse(j['solicitado_en'] as String),
      agente = j['asignado_a'] as String?,
      agenteEmail = j['asignado_email'] as String?,
      respuesta = j['respuesta'] as String?,
      respondidoEmail = j['respondido_email'] as String?,
      respondidoEn = j['respondido_en'] == null
          ? null
          : DateTime.parse(j['respondido_en'] as String),
      cerradoEn = j['cerrado_en'] == null
          ? null
          : DateTime.parse(j['cerrado_en'] as String),
      total = (j['total'] as num).toInt();
  final String id, tipo, asunto, mensaje, estado, email;
  final String? hogar, agente, agenteEmail, respuesta, respondidoEmail;
  final DateTime fecha;
  final DateTime? respondidoEn, cerradoEn;
  final int prioridad, total;
  String get tipoTexto =>
      {
        'CONSULTA': 'Consulta',
        'ERROR': 'Error',
        'SUGERENCIA': 'Sugerencia',
      }[tipo] ??
      tipo;
  String get estadoTexto =>
      {
        'PENDIENTE': 'Pendiente',
        'ASIGNADA': 'Asignada',
        'RESPONDIDA': 'Respondida',
        'CERRADA': 'Cerrada',
      }[estado] ??
      estado;
}

class AgenteSoporte {
  AgenteSoporte.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      email = j['email'] as String? ?? '—';
  final String id, email;
}
