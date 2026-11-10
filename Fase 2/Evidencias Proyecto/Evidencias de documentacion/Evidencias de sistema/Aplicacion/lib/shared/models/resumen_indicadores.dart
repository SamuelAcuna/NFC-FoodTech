class PresentacionPerdidaEconomica {
  final int descartes;
  final int descartesConPrecio;
  final double costoConocido;

  const PresentacionPerdidaEconomica({
    required this.descartes,
    required this.descartesConPrecio,
    required this.costoConocido,
  });

  bool get sinPrecios => descartes > 0 && descartesConPrecio == 0;
  bool get parcial => descartesConPrecio > 0 && descartesConPrecio < descartes;
  int? get valorClp => sinPrecios ? null : costoConocido.round();
  String get titulo =>
      parcial ? 'Subtotal conocido' : 'Pérdida económica estimada';
  String get valorCsv => valorClp?.toString() ?? 'Sin datos de precio';
  String get cobertura => descartes == 0
      ? 'No existen descartes registrados.'
      : 'Calculado con $descartesConPrecio de $descartes descartes con precio registrado y cantidad inicial válida.';

  static const criterioValoracion =
      'Estimación proporcional a la cantidad inicial y a los precios actuales '
      'de los ingresos. Puede cambiar al editar esos precios. '
      'No representa una pérdida total exacta si faltan precios.';

  String get detalleCsv => '$cobertura $criterioValoracion';
}

class ResumenIndicadores {
  final Map<String, double> consumido;
  final Map<String, double> descartado;
  final int cantidadConsumos;
  final int cantidadDescartes;
  final int descartesEvitables;
  final int descartesNoEvitables;
  final int descartesSinClasificar;
  final int descartesConPrecio;
  final double costoConocido;
  final List<Map<String, dynamic>> rankingAlimentos;
  final int cantidadConsumosMes;
  final int cantidadDescartesMes;
  final int ingresosEvaluados;
  final double? aprovechamientoMes;
  final Map<String, double?> aprovechamientoPorUnidad;
  final List<Map<String, dynamic>> rankingCategorias;

  ResumenIndicadores({
    required this.consumido,
    required this.descartado,
    required this.cantidadConsumos,
    required this.cantidadDescartes,
    required this.descartesEvitables,
    required this.descartesNoEvitables,
    required this.descartesSinClasificar,
    required this.descartesConPrecio,
    required this.costoConocido,
    required this.rankingAlimentos,
    required this.cantidadConsumosMes,
    required this.cantidadDescartesMes,
    required this.ingresosEvaluados,
    required this.aprovechamientoMes,
    required this.aprovechamientoPorUnidad,
    required this.rankingCategorias,
  });
}

double _numero(dynamic valor) {
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor?.toString() ?? "") ?? 0;
}

double? _calcularPorcentaje(double consumido, double descartado) {
  final total = consumido + descartado;

  if (total <= 0) return null;

  return (consumido / total) * 100;
}

ResumenIndicadores calcularIndicadores({
  required Map<String, Map<String, dynamic>> itemsPorId,
  required List<Map<String, dynamic>> movimientos,
  required Map<int, Map<String, dynamic>> alimentosPorId,
  required Map<int, String> categoriasPorId,
  required Map<int, bool> motivosPorId,
  required DateTime ahora,
}) {
  final consumido = <String, double>{'g': 0, 'ml': 0, 'un': 0};

  final descartado = <String, double>{'g': 0, 'ml': 0, 'un': 0};

  final rankingPorAlimento = <int, Map<String, dynamic>>{};

  final rankingPorCategoria = <int, Map<String, dynamic>>{};

  var cantidadConsumos = 0;
  var cantidadDescartes = 0;

  var descartesEvitables = 0;
  var descartesNoEvitables = 0;
  var descartesSinClasificar = 0;
  var descartesConPrecio = 0;

  double costoConocido = 0;

  // -------------------------------------------------
  // 7. ACUMULADORES R59: MES ACTUAL
  // -------------------------------------------------

  final consumidoMes = <String, double>{'g': 0, 'ml': 0, 'un': 0};

  final descartadoMes = <String, double>{'g': 0, 'ml': 0, 'un': 0};

  // Por cada ingreso se calcula su proporción
  // consumida respecto de lo consumido+descartado.
  //
  // Cada ingreso mantiene una única unidad base.
  // Así evitamos sumar g + ml + un.
  final salidasMesPorItem = <String, Map<String, double>>{};

  var cantidadConsumosMes = 0;
  var cantidadDescartesMes = 0;

  // -------------------------------------------------
  // 8. PROCESAR MOVIMIENTOS
  // -------------------------------------------------

  for (final movimiento in movimientos) {
    final tipo = movimiento['tipo']?.toString();

    if (tipo != 'CONSUMO' && tipo != 'DESCARTE') {
      continue;
    }

    final itemId = movimiento['despensa_item_id']?.toString();

    final item = itemsPorId[itemId];

    if (item == null || itemId == null) {
      continue;
    }

    final alimentoId = (item['alimento_id'] as num).toInt();

    final alimento = alimentosPorId[alimentoId];

    if (alimento == null) {
      continue;
    }

    final unidad = alimento['unidad_base']?.toString() ?? '';

    if (!consumido.containsKey(unidad)) {
      continue;
    }

    final cantidad = _numero(movimiento['cantidad']);

    if (cantidad <= 0) continue;

    // ---------------------------------------------
    // DETERMINAR SI ES DEL MES ACTUAL
    // ---------------------------------------------

    final fechaMovimiento = DateTime.tryParse(
      movimiento['fecha']?.toString() ?? '',
    )?.toLocal();

    final esDelMes =
        fechaMovimiento != null &&
        fechaMovimiento.year == ahora.year &&
        fechaMovimiento.month == ahora.month;

    if (esDelMes) {
      final salidaItem = salidasMesPorItem.putIfAbsent(
        itemId,
        () => <String, double>{'consumido': 0, 'descartado': 0},
      );

      if (tipo == 'CONSUMO') {
        cantidadConsumosMes++;

        consumidoMes[unidad] = (consumidoMes[unidad] ?? 0) + cantidad;

        salidaItem['consumido'] = (salidaItem['consumido'] ?? 0) + cantidad;
      } else {
        cantidadDescartesMes++;

        descartadoMes[unidad] = (descartadoMes[unidad] ?? 0) + cantidad;

        salidaItem['descartado'] = (salidaItem['descartado'] ?? 0) + cantidad;
      }
    }

    // ---------------------------------------------
    // CONSUMO HISTÓRICO
    // ---------------------------------------------

    if (tipo == 'CONSUMO') {
      cantidadConsumos++;

      consumido[unidad] = (consumido[unidad] ?? 0) + cantidad;

      continue;
    }

    // ---------------------------------------------
    // DESCARTE HISTÓRICO
    // ---------------------------------------------

    cantidadDescartes++;

    descartado[unidad] = (descartado[unidad] ?? 0) + cantidad;

    final motivoId = (movimiento['tipo_desperdicio_id'] as num?)?.toInt();

    final esEvitable = motivoId == null ? null : motivosPorId[motivoId];

    if (esEvitable == true) {
      descartesEvitables++;
    } else if (esEvitable == false) {
      descartesNoEvitables++;
    } else {
      descartesSinClasificar++;
    }

    // ---------------------------------------------
    // RANKING EXISTENTE: POR ALIMENTO
    // ---------------------------------------------

    final resumenAlimento = rankingPorAlimento.putIfAbsent(
      alimentoId,
      () => <String, dynamic>{
        'nombre': alimento['nombre']?.toString() ?? 'Alimento',
        'unidad': unidad,
        'cantidad': 0.0,
        'eventos': 0,
      },
    );

    resumenAlimento['cantidad'] =
        _numero(resumenAlimento['cantidad']) + cantidad;

    resumenAlimento['eventos'] = (resumenAlimento['eventos'] as int) + 1;

    // ---------------------------------------------
    // R61: RANKING POR CATEGORÍA
    // ---------------------------------------------

    final categoriaId = (alimento['categoria_id'] as num?)?.toInt();

    final idCategoria = categoriaId ?? -1;

    final nombreCategoria = categoriaId == null
        ? 'Sin categoría'
        : categoriasPorId[categoriaId] ?? 'Sin categoría';

    final resumenCategoria = rankingPorCategoria.putIfAbsent(
      idCategoria,
      () => <String, dynamic>{
        'nombre': nombreCategoria,
        'eventos': 0,
        'cantidades': <String, double>{'g': 0, 'ml': 0, 'un': 0},
      },
    );

    resumenCategoria['eventos'] = (resumenCategoria['eventos'] as int) + 1;

    final cantidadesCategoria =
        resumenCategoria['cantidades'] as Map<String, double>;

    cantidadesCategoria[unidad] = (cantidadesCategoria[unidad] ?? 0) + cantidad;

    // ---------------------------------------------
    // ESTIMACIÓN ECONÓMICA EXISTENTE
    // ---------------------------------------------

    final precioValor = item['precio_clp'];
    final inicial = _numero(item['cantidad_inicial']);

    if (precioValor != null && inicial > 0) {
      final precio = _numero(precioValor);

      if (precio >= 0) {
        costoConocido += precio * (cantidad / inicial);

        descartesConPrecio++;
      }
    }
  }

  // -------------------------------------------------
  // 9. R59: APROVECHAMIENTO POR UNIDAD
  // -------------------------------------------------

  final aprovechamientoPorUnidad = <String, double?>{
    'g': null,
    'ml': null,
    'un': null,
  };

  for (final unidad in ['g', 'ml', 'un']) {
    aprovechamientoPorUnidad[unidad] = _calcularPorcentaje(
      consumidoMes[unidad] ?? 0,
      descartadoMes[unidad] ?? 0,
    );
  }

  // -------------------------------------------------
  // 10. R59: PROMEDIO ENTRE INGRESOS
  // -------------------------------------------------

  // Una tasa por ingreso. Luego promedio simple.
  // Se evita sumar cantidades incompatibles.
  //
  // Este indicador representa el aprovechamiento
  // de salidas registradas, no de todo el stock.
  double sumaPorcentajes = 0;
  var ingresosEvaluados = 0;

  for (final salida in salidasMesPorItem.values) {
    final porcentaje = _calcularPorcentaje(
      salida['consumido'] ?? 0,
      salida['descartado'] ?? 0,
    );

    if (porcentaje == null) {
      continue;
    }

    sumaPorcentajes += porcentaje;
    ingresosEvaluados++;
  }

  final aprovechamientoMes = ingresosEvaluados == 0
      ? null
      : sumaPorcentajes / ingresosEvaluados;

  // -------------------------------------------------
  // 11. ORDENAR RANKING POR ALIMENTO
  // -------------------------------------------------

  final rankingAlimentos = rankingPorAlimento.values.toList();

  rankingAlimentos.sort((a, b) {
    final comparacion = (b['eventos'] as int).compareTo(a['eventos'] as int);

    if (comparacion != 0) {
      return comparacion;
    }

    return a['nombre'].toString().compareTo(b['nombre'].toString());
  });

  // -------------------------------------------------
  // 12. R61: ORDENAR RANKING POR CATEGORÍA
  // -------------------------------------------------

  // Se ordena por eventos de descarte.
  // No se suman g, ml y un.
  final rankingCategorias = rankingPorCategoria.values.toList();

  rankingCategorias.sort((a, b) {
    final comparacion = (b['eventos'] as int).compareTo(a['eventos'] as int);

    if (comparacion != 0) {
      return comparacion;
    }

    return a['nombre'].toString().compareTo(b['nombre'].toString());
  });

  return ResumenIndicadores(
    consumido: consumido,
    descartado: descartado,
    cantidadConsumos: cantidadConsumos,
    cantidadDescartes: cantidadDescartes,
    descartesEvitables: descartesEvitables,
    descartesNoEvitables: descartesNoEvitables,
    descartesSinClasificar: descartesSinClasificar,
    descartesConPrecio: descartesConPrecio,
    costoConocido: costoConocido,
    rankingAlimentos: rankingAlimentos,
    cantidadConsumosMes: cantidadConsumosMes,
    cantidadDescartesMes: cantidadDescartesMes,
    ingresosEvaluados: ingresosEvaluados,
    aprovechamientoMes: aprovechamientoMes,
    aprovechamientoPorUnidad: aprovechamientoPorUnidad,
    rankingCategorias: rankingCategorias,
  );
}
