/// Respuesta de GET /productos/buscar/{codigo} del servicio de integraciones.
class BusquedaCodigo {
  const BusquedaCodigo({
    required this.encontrado,
    required this.codigo,
    required this.tipoCodigo,
    this.motivo,
    this.producto,
  });

  factory BusquedaCodigo.fromJson(Map<String, dynamic> json) {
    final producto = json['producto'];
    return BusquedaCodigo(
      encontrado: json['encontrado'] as bool? ?? false,
      codigo: json['codigo'] as String? ?? '',
      tipoCodigo: json['tipo_codigo'] as String? ?? '',
      motivo: json['motivo'] as String?,
      producto: producto is Map<String, dynamic>
          ? ProductoSugerido.fromJson(producto)
          : null,
    );
  }

  final bool encontrado;
  final String codigo;
  final String tipoCodigo;
  final String? motivo;
  final ProductoSugerido? producto;
}

/// Producto de Open Food Facts ya traducido a los campos de la tabla `producto`.
class ProductoSugerido {
  const ProductoSugerido({
    required this.codigo,
    required this.tipoCodigo,
    this.nombre,
    this.marca,
    this.tipoMedida,
    this.cantidadNeta,
    this.unidadNeta,
    this.imagenUrl,
  });

  factory ProductoSugerido.fromJson(Map<String, dynamic> json) {
    return ProductoSugerido(
      codigo: json['codigo'] as String? ?? '',
      tipoCodigo: json['tipo_codigo'] as String? ?? '',
      nombre: json['nombre'] as String?,
      marca: json['marca_texto'] as String?,
      tipoMedida: json['tipo_medida'] as String?,
      cantidadNeta: (json['cantidad_neta'] as num?)?.toDouble(),
      unidadNeta: json['unidad_neta'] as String?,
      imagenUrl: json['imagen_url'] as String?,
    );
  }

  final String codigo;
  final String tipoCodigo;
  final String? nombre;
  final String? marca;
  final String? tipoMedida;
  final double? cantidadNeta;
  final String? unidadNeta;
  final String? imagenUrl;

  /// "400 g", "1 l", etc. Null si Open Food Facts no trae la cantidad.
  String? get contenido {
    final cantidad = cantidadNeta;
    final unidad = unidadNeta;
    if (cantidad == null || unidad == null) return null;
    final texto = cantidad == cantidad.roundToDouble()
        ? cantidad.toStringAsFixed(0)
        : cantidad.toString().replaceAll('.', ',');
    return '$texto $unidad';
  }
}
