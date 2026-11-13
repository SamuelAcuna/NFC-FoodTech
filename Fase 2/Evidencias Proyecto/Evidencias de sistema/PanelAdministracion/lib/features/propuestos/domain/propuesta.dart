import '../../alimentos/domain/alimento.dart';

class Propuesta {
  const Propuesta({
    required this.id,
    required this.nombre,
    required this.categoriaId,
    required this.unidadBase,
    required this.esPerecible,
    this.vidaUtilDiasRef,
    required this.hogarRef,
    required this.propuestoEn,
  });
  factory Propuesta.fromJson(Map<String, dynamic> json) => Propuesta(
    id: (json['id'] as num).toInt(),
    nombre: json['nombre'] as String,
    categoriaId: (json['categoria_id'] as num).toInt(),
    unidadBase: json['unidad_base'] as String,
    esPerecible: json['es_perecible'] as bool,
    vidaUtilDiasRef: (json['vida_util_dias_ref'] as num?)?.toInt(),
    hogarRef: json['hogar_ref'] as String,
    propuestoEn: DateTime.parse(json['propuesto_en'] as String),
  );
  final int id;
  final String nombre;
  final int categoriaId;
  final String unidadBase;
  final bool esPerecible;
  final int? vidaUtilDiasRef;
  final String hogarRef;
  final DateTime propuestoEn;
  Alimento get editable => Alimento(
    id: id,
    nombre: nombre,
    categoriaId: categoriaId,
    unidadBase: unidadBase,
    esPerecible: esPerecible,
    vidaUtilDiasRef: vidaUtilDiasRef,
    activo: true,
  );
}

List<Propuesta> filtrarPropuestas(
  List<Propuesta> propuestas,
  String busqueda,
) => propuestas
    .where(
      (p) =>
          normalizarBusqueda(p.nombre).contains(normalizarBusqueda(busqueda)),
    )
    .toList();
