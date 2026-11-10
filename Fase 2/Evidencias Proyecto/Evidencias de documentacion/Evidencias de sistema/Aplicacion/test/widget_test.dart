import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_foodtech_app/shared/models/busqueda.dart';

void main() {
  test('interpreta un producto encontrado', () {
    final r = BusquedaCodigo.fromJson({
      'encontrado': true,
      'codigo': '3017620422003',
      'tipo_codigo': 'EAN13',
      'producto': {
        'codigo': '3017620422003',
        'tipo_codigo': 'EAN13',
        'nombre': 'Nutella',
        'marca_texto': 'Ferrero',
        'tipo_medida': 'PESO',
        'cantidad_neta': 400,
        'unidad_neta': 'g',
      },
    });
    expect(r.encontrado, isTrue);
    expect(r.producto!.nombre, 'Nutella');
    expect(r.producto!.contenido, '400 g');
  });

  test('interpreta un codigo no encontrado', () {
    final r = BusquedaCodigo.fromJson({
      'encontrado': false,
      'codigo': '2000000000008',
      'tipo_codigo': 'INTERNO',
      'motivo': 'Codigo interno de tienda',
    });
    expect(r.encontrado, isFalse);
    expect(r.producto, isNull);
    expect(r.tipoCodigo, 'INTERNO');
  });

  test('formatea cantidades con decimales', () {
    const p = ProductoSugerido(codigo: '1', tipoCodigo: 'EAN13', cantidadNeta: 1.5, unidadNeta: 'l');
    expect(p.contenido, '1,5 l');
  });
}
