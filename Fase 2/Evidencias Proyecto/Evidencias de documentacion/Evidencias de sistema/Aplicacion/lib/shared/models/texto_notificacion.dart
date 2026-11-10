String completarTextoNotificacion(String texto, dynamic datos) {
  final valores = datos is Map ? datos : const {};
  final patron = RegExp(r'\{\{\s*([a-zA-Z0-9_]+)\s*\}\}|\{([a-zA-Z0-9_]+)\}');
  return texto.replaceAllMapped(patron, (coincidencia) {
    final clave = coincidencia.group(1) ?? coincidencia.group(2);
    if (clave == null) return coincidencia.group(0) ?? '';
    final valor = valores[clave];
    return valor == null || valor.toString().isEmpty
        ? '(dato no disponible)'
        : valor.toString();
  });
}
