import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_foodtech_app/shared/models/resumen_indicadores.dart';

final ahora = DateTime(2026, 11, 15);

Map<String, dynamic> ingreso(
  String id, {
  int alimento = 1,
  double inicial = 1000,
  int? precio = 2000,
}) => {
  'id': id,
  'alimento_id': alimento,
  'cantidad_inicial': inicial,
  'precio_clp': precio,
};

Map<String, dynamic> movimiento(
  String id,
  String item,
  String tipo,
  double cantidad, {
  DateTime? fecha,
}) => {
  'id': id,
  'despensa_item_id': item,
  'tipo': tipo,
  'cantidad': cantidad,
  'fecha': (fecha ?? ahora).toUtc().toIso8601String(),
  'tipo_desperdicio_id': 1,
};

ResumenIndicadores calcular(
  List<Map<String, dynamic>> items,
  List<Map<String, dynamic>> movimientos,
) => calcularIndicadores(
  itemsPorId: {for (final item in items) item['id'] as String: item},
  movimientos: movimientos,
  alimentosPorId: {
    1: {'nombre': 'Arroz', 'unidad_base': 'g', 'categoria_id': 1},
    2: {'nombre': 'Leche', 'unidad_base': 'ml', 'categoria_id': 1},
    3: {'nombre': 'Huevos', 'unidad_base': 'un', 'categoria_id': 1},
  },
  categoriasPorId: {1: 'Prueba'},
  motivosPorId: {1: true},
  ahora: ahora,
);

void main() {
  test('600 g consumidos y 200 g descartados: 75% y 400 CLP', () {
    final r = calcular(
      [ingreso('a')],
      [
        movimiento('1', 'a', 'CONSUMO', 600),
        movimiento('2', 'a', 'DESCARTE', 200),
      ],
    );
    expect(r.aprovechamientoMes, 75);
    expect(r.aprovechamientoPorUnidad['g'], 75);
    expect(r.costoConocido, 400);
    expect(r.consumido['g'], 600);
    expect(r.descartado['g'], 200);
  });
  test('ingresos del mismo alimento conservan precio y peso propios', () {
    final r = calcular(
      [ingreso('a'), ingreso('b', inicial: 100, precio: 1000)],
      [
        movimiento('1', 'a', 'CONSUMO', 600),
        movimiento('2', 'a', 'DESCARTE', 200),
        movimiento('3', 'b', 'DESCARTE', 100),
      ],
    );
    expect(r.aprovechamientoMes, 37.5);
    expect(r.aprovechamientoPorUnidad['g'], closeTo(100 * 600 / 900, 1e-10));
    expect(r.costoConocido, 1400);
    expect(r.rankingAlimentos.single['eventos'], 2);
    expect(r.rankingAlimentos.single['cantidad'], 300);
  });
  test('precio desconocido y cero conservan cobertura distinta', () {
    for (final precio in <int?>[null, 0]) {
      final r = calcular(
        [ingreso('a', precio: precio)],
        [movimiento('1', 'a', 'DESCARTE', 200)],
      );
      expect(r.costoConocido, 0);
      expect(r.descartesConPrecio, precio == null ? 0 : 1);
      expect(r.cantidadDescartes, 1);
    }
  });
  for (final tipo in ['CONSUMO', 'DESCARTE']) {
    test('$tipo total', () {
      final r = calcular([ingreso('a')], [movimiento('1', 'a', tipo, 1000)]);
      expect(r.aprovechamientoMes, tipo == 'CONSUMO' ? 100 : 0);
      expect(r.costoConocido, tipo == 'CONSUMO' ? 0 : 2000);
    });
  }
  test('ingresos sin movimientos no participan del promedio', () {
    final vacio = calcular([ingreso('a')], []);
    expect(vacio.aprovechamientoMes, isNull);
    expect(vacio.ingresosEvaluados, 0);
    expect(vacio.aprovechamientoPorUnidad.values, everyElement(isNull));
    final r = calcular(
      [ingreso('a'), ingreso('b')],
      [movimiento('1', 'a', 'CONSUMO', 100)],
    );
    expect(r.aprovechamientoMes, 100);
    expect(r.ingresosEvaluados, 1);
  });
  test('g ml y un permanecen separados y las categorías cuentan eventos', () {
    final r = calcular(
      [ingreso('a'), ingreso('b', alimento: 2), ingreso('c', alimento: 3)],
      [
        movimiento('1', 'a', 'CONSUMO', 600),
        movimiento('2', 'a', 'DESCARTE', 200),
        movimiento('3', 'b', 'CONSUMO', 300),
        movimiento('4', 'b', 'DESCARTE', 100),
        movimiento('5', 'c', 'CONSUMO', 1),
        movimiento('6', 'c', 'DESCARTE', 1),
      ],
    );
    expect(r.consumido, {'g': 600.0, 'ml': 300.0, 'un': 1.0});
    expect(r.descartado, {'g': 200.0, 'ml': 100.0, 'un': 1.0});
    expect(r.aprovechamientoPorUnidad, {'g': 75.0, 'ml': 75.0, 'un': 50.0});
    expect(r.aprovechamientoMes, closeTo(200 / 3, 1e-10));
    expect(r.rankingCategorias.single['eventos'], 3);
  });
  test(
    'meses diferentes no se mezclan en aprovechamiento; histórico sí acumula',
    () {
      final r = calcular(
        [ingreso('a')],
        [
          movimiento('1', 'a', 'CONSUMO', 600, fecha: DateTime(2026, 10, 15)),
          movimiento('2', 'a', 'DESCARTE', 200),
        ],
      );
      expect(r.aprovechamientoMes, 0);
      expect(r.cantidadConsumosMes, 0);
      expect(r.cantidadDescartesMes, 1);
      expect(r.consumido['g'], 600);
      expect(r.costoConocido, 400);
    },
  );
  test('ajustes, traslados, cero y NULL no alteran fórmulas', () {
    final r = calcular(
      [ingreso('a')],
      [
        movimiento('1', 'a', 'AJUSTE', 100),
        movimiento('2', 'a', 'TRASLADO', 100),
        movimiento('3', 'a', 'CONSUMO', 0),
        {...movimiento('4', 'a', 'DESCARTE', 1), 'cantidad': null},
      ],
    );
    expect(r.aprovechamientoMes, isNull);
    expect(r.cantidadConsumos + r.cantidadDescartes, 0);
  });
  test('redondeo económico se mantiene después de sumar proporciones', () {
    final r = calcular(
      [ingreso('a', inicial: 3, precio: 1000)],
      [for (var i = 0; i < 3; i++) movimiento('$i', 'a', 'DESCARTE', 1)],
    );
    expect(r.costoConocido.round(), 1000);
  });
}
