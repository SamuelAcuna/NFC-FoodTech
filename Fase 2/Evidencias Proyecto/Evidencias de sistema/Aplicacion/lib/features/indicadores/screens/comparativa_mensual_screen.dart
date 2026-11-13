
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ComparativaMensualScreen extends StatefulWidget {
  final Map<String, dynamic> hogar;

  const ComparativaMensualScreen({super.key, required this.hogar});

  @override
  State<ComparativaMensualScreen> createState() =>
      _ComparativaMensualScreenState();
}

class _ResumenMes {
  final DateTime mes;

  int eventosConsumo = 0;
  int eventosDescarte = 0;

  final Map<String, double> consumo = {
    'g': 0,
    'ml': 0,
    'un': 0,
  };

  final Map<String, double> descarte = {
    'g': 0,
    'ml': 0,
    'un': 0,
  };

  _ResumenMes(this.mes);
}

class _ComparativaMensualScreenState
    extends State<ComparativaMensualScreen> {
  static const Color verde = Color(0xFF236B4A);
  static const Color fondo = Color(0xFFF3F7F3);

  bool get _modoOscuro => Theme.of(context).brightness == Brightness.dark;

  Color get _colorFondo =>
      _modoOscuro ? Theme.of(context).scaffoldBackgroundColor : fondo;

  Color get _colorSuperficie => _modoOscuro
      ? Theme.of(context).colorScheme.surfaceContainerLow
      : Colors.white;

  Color get _colorAcento =>
      _modoOscuro ? Theme.of(context).colorScheme.primary : verde;

  Color get _colorBorde => _modoOscuro
      ? Theme.of(context).colorScheme.outlineVariant
      : const Color(0xFFDCE8DE);

  Color get _colorTextoSecundario => _modoOscuro
      ? Theme.of(context).colorScheme.onSurfaceVariant
      : Colors.black54;

  Color get _colorError =>
      _modoOscuro ? Theme.of(context).colorScheme.error : Colors.red;

  Color get _colorTexto => _modoOscuro
      ? Theme.of(context).colorScheme.onSurface
      : Colors.black87;

  Color get _colorPista => _modoOscuro
      ? Theme.of(context).colorScheme.surfaceContainerHighest
      : const Color(0xFFE7EEE8);

  Color get _colorConsumo =>
      _modoOscuro ? Colors.blue.shade200 : azulConsumo;

  Color get _colorDescarte =>
      _modoOscuro ? Colors.deepOrange.shade200 : naranjaDescarte;

  static const Color azulConsumo = Color(0xFF1565C0);
  static const Color naranjaDescarte = Color(0xFFC45126);

  final _supabase = Supabase.instance.client;

  bool _cargando = true;
  String? _error;

  List<_ResumenMes> _meses = [];

  // Unidad seleccionada en el gráfico de descartes.
  String _unidadGrafico = 'g';

  static const List<String> _nombresMeses = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  @override
  void initState() {
    super.initState();
    _cargarComparativa();
  }

  // =====================================================
  // FORMATO DE DATOS
  // =====================================================

  double _numero(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  String _numeroTexto(double valor, {int decimales = 3}) {
    return valor
        .toStringAsFixed(decimales)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  String _cantidadTexto(double cantidad, String unidad) {
    if (unidad == 'g' && cantidad >= 1000) {
      return '${_numeroTexto(cantidad / 1000, decimales: 6)} kg';
    }

    if (unidad == 'ml' && cantidad >= 1000) {
      return '${_numeroTexto(cantidad / 1000, decimales: 6)} L';
    }

    return '${_numeroTexto(cantidad)} $unidad';
  }

  String _nombreMes(DateTime fecha) {
    return '${_nombresMeses[fecha.month - 1]} ${fecha.year}';
  }

  String _claveMes(DateTime fecha) {
    final mes = fecha.month.toString().padLeft(2, '0');

    return '${fecha.year}-$mes';
  }

  List<_ResumenMes> _crearMeses() {
    final ahora = DateTime.now();
    final resultado = <_ResumenMes>[];

    // Mes actual y cinco meses anteriores.
    for (var i = 0; i < 6; i++) {
      final mes = DateTime(ahora.year, ahora.month - i, 1);

      resultado.add(_ResumenMes(mes));
    }

    return resultado;
  }

  // =====================================================
  // CONSULTAR TODOS LOS ITEMS DEL HOGAR
  // =====================================================

  Future<List<Map<String, dynamic>>> _obtenerItems(
    String hogarId,
  ) async {
    final resultado = <Map<String, dynamic>>[];

    const tamanoPagina = 500;
    var desde = 0;

    while (true) {
      final respuesta = await _supabase
          .from('despensa_item')
          .select('id, alimento_id')
          .eq('hogar_id', hogarId)
          .order('id')
          .range(desde, desde + tamanoPagina - 1);

      resultado.addAll(
        respuesta.map(
          (dato) => Map<String, dynamic>.from(dato),
        ),
      );

      if (respuesta.length < tamanoPagina) {
        break;
      }

      desde += tamanoPagina;
    }

    return resultado;
  }

  // =====================================================
  // OBTENER UNIDADES DE LOS ALIMENTOS
  // =====================================================

  Future<Map<int, String>> _obtenerUnidades(
    List<Map<String, dynamic>> items,
  ) async {
    final ids = items
        .map((item) => (item['alimento_id'] as num).toInt())
        .toSet()
        .toList();

    final unidades = <int, String>{};

    const tamanoLote = 100;

    for (var inicio = 0; inicio < ids.length; inicio += tamanoLote) {
      final fin = inicio + tamanoLote < ids.length
          ? inicio + tamanoLote
          : ids.length;

      final lote = ids.sublist(inicio, fin);

      final respuesta = await _supabase
          .from('alimento')
          .select('id, unidad_base')
          .inFilter('id', lote);

      for (final alimento in respuesta) {
        final id = (alimento['id'] as num).toInt();

        unidades[id] =
            alimento['unidad_base']?.toString() ?? '';
      }
    }

    return unidades;
  }

  // =====================================================
  // OBTENER MOVIMIENTOS DEL PERIODO
  // =====================================================

  Future<List<Map<String, dynamic>>> _obtenerMovimientos(
    List<String> idsItems,
    DateTime fechaInicio,
  ) async {
    final resultado = <Map<String, dynamic>>[];

    const tamanoLote = 80;
    const tamanoPagina = 500;

    final fechaDesde = fechaInicio.toUtc().toIso8601String();

    for (var inicio = 0; inicio < idsItems.length; inicio += tamanoLote) {
      final fin = inicio + tamanoLote < idsItems.length
          ? inicio + tamanoLote
          : idsItems.length;

      final lote = idsItems.sublist(inicio, fin);

      var desde = 0;

      while (true) {
        final respuesta = await _supabase
            .from('movimiento')
            .select(
              'id, despensa_item_id, tipo, '
              'cantidad, fecha',
            )
            .inFilter('despensa_item_id', lote)
            .inFilter('tipo', ['CONSUMO', 'DESCARTE'])
            .gte('fecha', fechaDesde)
            .order('fecha', ascending: false)
            .order('id', ascending: false)
            .range(desde, desde + tamanoPagina - 1);

        resultado.addAll(
          respuesta.map(
            (dato) => Map<String, dynamic>.from(dato),
          ),
        );

        if (respuesta.length < tamanoPagina) {
          break;
        }

        desde += tamanoPagina;
      }
    }

    return resultado;
  }

  // =====================================================
  // CALCULAR COMPARATIVA MENSUAL
  // =====================================================

  Future<void> _cargarComparativa() async {
    if (!mounted) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final hogarId = widget.hogar['id']?.toString();

      if (hogarId == null || hogarId.isEmpty) {
        throw Exception('No hay un hogar seleccionado.');
      }

      final meses = _crearMeses();

      final mesesPorClave = <String, _ResumenMes>{
        for (final mes in meses) _claveMes(mes.mes): mes,
      };

      final items = await _obtenerItems(hogarId);

      if (items.isEmpty) {
        if (!mounted) return;

        setState(() {
          _meses = meses;
          _unidadGrafico = 'g';
          _cargando = false;
        });

        return;
      }

      final itemsPorId = <String, Map<String, dynamic>>{};

      for (final item in items) {
        final id = item['id']?.toString();

        if (id != null) {
          itemsPorId[id] = item;
        }
      }

      final unidadesPorAlimento = await _obtenerUnidades(items);

      // Primer día del mes más antiguo.
      final fechaInicio = meses.last.mes;

      final movimientos = await _obtenerMovimientos(
        itemsPorId.keys.toList(),
        fechaInicio,
      );

      for (final movimiento in movimientos) {
        final tipo = movimiento['tipo']?.toString();

        if (tipo != 'CONSUMO' && tipo != 'DESCARTE') {
          continue;
        }

        final fechaTexto = movimiento['fecha']?.toString();

        final fecha = fechaTexto == null
            ? null
            : DateTime.tryParse(fechaTexto)?.toLocal();

        if (fecha == null) continue;

        final resumen = mesesPorClave[_claveMes(fecha)];

        if (resumen == null) continue;

        final itemId =
            movimiento['despensa_item_id']?.toString();

        final item = itemsPorId[itemId];

        if (item == null) continue;

        final alimentoId =
            (item['alimento_id'] as num).toInt();

        final unidad = unidadesPorAlimento[alimentoId];

        if (unidad == null ||
            !resumen.consumo.containsKey(unidad)) {
          continue;
        }

        final cantidad = _numero(movimiento['cantidad']);

        if (cantidad <= 0) continue;

        if (tipo == 'CONSUMO') {
          resumen.eventosConsumo++;

          resumen.consumo[unidad] =
              (resumen.consumo[unidad] ?? 0) + cantidad;
        } else {
          resumen.eventosDescarte++;

          resumen.descarte[unidad] =
              (resumen.descarte[unidad] ?? 0) + cantidad;
        }
      }

      // Selecciona automáticamente una unidad
      // que tenga descartes registrados.
      final unidadInicial = ['g', 'ml', 'un'].firstWhere(
        (unidad) => meses.any(
          (mes) => (mes.descarte[unidad] ?? 0) > 0,
        ),
        orElse: () => 'g',
      );

      if (!mounted) return;

      setState(() {
        _meses = meses;
        _unidadGrafico = unidadInicial;
        _cargando = false;
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.message;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _cargando = false;
      });
    }
  }

  // =====================================================
  // INTERFAZ: FILAS DE CANTIDADES
  // =====================================================

  Widget _filaCantidad(
    String titulo,
    double cantidad,
    String unidad,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              titulo,
              style: TextStyle(color: _colorTexto),
            ),
          ),
          Text(
            _cantidadTexto(cantidad, unidad),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _grupoCantidades(
    String titulo,
    Map<String, double> cantidades,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        _filaCantidad(
          'Peso',
          cantidades['g'] ?? 0,
          'g',
        ),

        _filaCantidad(
          'Volumen',
          cantidades['ml'] ?? 0,
          'ml',
        ),

        _filaCantidad(
          'Unidades',
          cantidades['un'] ?? 0,
          'un',
        ),
      ],
    );
  }

  // =====================================================
  // GRÁFICOS MENSUALES SIN PAQUETES EXTERNOS
  // =====================================================

  Widget _barraGrafico({
    required String etiqueta,
    required double valor,
    required double maximo,
    required String valorTexto,
    required Color color,
  }) {
    final proporcion = maximo <= 0
        ? 0.0
        : valor / maximo;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 85,
            child: Text(
              etiqueta,
              style: const TextStyle(fontSize: 12),
            ),
          ),

          Expanded(
            child: LinearProgressIndicator(
              value: proporcion,
              minHeight: 12,
              color: color,
              backgroundColor: _colorPista,
              borderRadius: BorderRadius.circular(6),
            ),
          ),

          const SizedBox(width: 10),

          SizedBox(
            width: 80,
            child: Text(
              valorTexto,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // GRÁFICO 1: MOVIMIENTOS POR MES
  // =====================================================

  Widget _graficoEventos() {
    double maximo = 0;

    for (final mes in _meses) {
      if (mes.eventosConsumo > maximo) {
        maximo = mes.eventosConsumo.toDouble();
      }

      if (mes.eventosDescarte > maximo) {
        maximo = mes.eventosDescarte.toDouble();
      }
    }

    return Card(
      color: _colorSuperficie,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: _colorBorde,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Movimientos por mes',
              style: TextStyle(
                color: _colorAcento,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              'Comparación de eventos registrados. '
              'Cada barra utiliza la misma escala '
              'entre los seis meses.',
              style: TextStyle(
                fontSize: 12,
                color: _colorTextoSecundario,
              ),
            ),

            const SizedBox(height: 12),

            for (final mes in _meses) ...[
              Padding(
                padding: const EdgeInsets.only(
                  top: 8,
                  bottom: 3,
                ),
                child: Text(
                  _nombreMes(mes.mes),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              _barraGrafico(
                etiqueta: 'Consumos',
                valor: mes.eventosConsumo.toDouble(),
                maximo: maximo,
                valorTexto: '${mes.eventosConsumo}',
                color: _colorConsumo,
              ),

              _barraGrafico(
                etiqueta: 'Descartes',
                valor: mes.eventosDescarte.toDouble(),
                maximo: maximo,
                valorTexto: '${mes.eventosDescarte}',
                color: _colorDescarte,
              ),

              const Divider(height: 12),
            ],

            const SizedBox(height: 4),

            Text(
              'Los eventos no equivalen a cantidades: '
              'varios movimientos pueden corresponder '
              'a un mismo alimento.',
              style: TextStyle(
                fontSize: 12,
                color: _colorTextoSecundario,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // GRÁFICO 2: CANTIDAD DESCARTADA POR MES
  // =====================================================

  Widget _graficoCantidadesDescartadas() {
    double maximo = 0;

    for (final mes in _meses) {
      final cantidad = mes.descarte[_unidadGrafico] ?? 0;

      if (cantidad > maximo) {
        maximo = cantidad;
      }
    }

    return Card(
      color: _colorSuperficie,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: _colorBorde,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cantidad descartada por mes',
              style: TextStyle(
                color: _colorAcento,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              'Selecciona una unidad para comparar '
              'el desperdicio sin mezclar gramos, '
              'mililitros y unidades.',
              style: TextStyle(
                fontSize: 12,
                color: _colorTextoSecundario,
              ),
            ),

            const SizedBox(height: 8),

            Wrap(
              spacing: 8,
              children: [
                for (final unidad in ['g', 'ml', 'un'])
                  ChoiceChip(
                    label: Text(unidad),
                    selected: _unidadGrafico == unidad,
                    onSelected: (_) {
                      setState(() {
                        _unidadGrafico = unidad;
                      });
                    },
                  ),
              ],
            ),

            const SizedBox(height: 8),

            for (final mes in _meses)
              _barraGrafico(
                etiqueta:
                    '${_nombresMeses[mes.mes.month - 1].substring(0, 3)}. '
                    '${mes.mes.year}',
                valor: mes.descarte[_unidadGrafico] ?? 0,
                maximo: maximo,
                valorTexto: _cantidadTexto(
                  mes.descarte[_unidadGrafico] ?? 0,
                  _unidadGrafico,
                ),
                color: _colorDescarte,
              ),

            if (maximo == 0) ...[
              const SizedBox(height: 8),

              Text(
                'No hay descartes registrados '
                'en esta unidad durante los '
                'últimos seis meses.',
                style: TextStyle(
                  color: _colorTextoSecundario,
                  fontSize: 12,
                ),
              ),
            ],

            const SizedBox(height: 12),

            Text(
              'Se comparan solo cantidades de '
              'la misma unidad. La falta de '
              'registros no demuestra ausencia '
              'de desperdicio.',
              style: TextStyle(
                fontSize: 12,
                color: _colorTextoSecundario,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // INTERFAZ: TARJETAS MENSUALES
  // =====================================================

  Widget _tarjetaMes(
    _ResumenMes resumen,
    bool esMesActual,
  ) {
    final sinMovimientos =
        resumen.eventosConsumo == 0 &&
        resumen.eventosDescarte == 0;

    return Card(
      color: _colorSuperficie,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: _colorBorde,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _nombreMes(resumen.mes),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _colorAcento,
              ),
            ),

            if (esMesActual) ...[
              const SizedBox(height: 4),

              Text(
                'Mes en curso',
                style: TextStyle(
                  color: _colorTextoSecundario,
                  fontSize: 12,
                ),
              ),
            ],

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: Text(
                    'Consumos: ${resumen.eventosConsumo}',
                    style: TextStyle(
                      color: _colorConsumo,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                Expanded(
                  child: Text(
                    'Descartes: ${resumen.eventosDescarte}',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: _colorDescarte,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const Divider(height: 28),

            if (sinMovimientos)
              Text(
                'No hay consumos ni descartes '
                'registrados en este mes.',
                style: TextStyle(
                  color: _colorTextoSecundario,
                ),
              )
            else ...[
              _grupoCantidades(
                'Cantidad consumida',
                resumen.consumo,
                _colorConsumo,
              ),

              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 10),

              _grupoCantidades(
                'Cantidad descartada',
                resumen.descarte,
                _colorDescarte,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // =====================================================
  // PANTALLA PRINCIPAL
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final nombreHogar =
        widget.hogar['nombre']?.toString() ?? 'Hogar';

    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        backgroundColor: verde,
        foregroundColor: Colors.white,
        title: const Text('Comparativa mensual'),
        actions: [
          IconButton(
            tooltip: 'Actualizar datos',
            onPressed: _cargando
                ? null
                : _cargarComparativa,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: _colorError,
                          size: 42,
                        ),

                        const SizedBox(height: 12),

                        Text(
                          'No se pudo cargar la comparativa.\n'
                          '$_error',
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 12),

                        ElevatedButton(
                          onPressed: _cargarComparativa,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargarComparativa,
                  child: ListView(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'Hogar: $nombreHogar',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _colorAcento,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Consumos y descartes registrados '
                        'durante los últimos seis meses.',
                        style: TextStyle(
                          color: _colorTextoSecundario,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        'Las cantidades se muestran por '
                        'unidad de medida. Un mes sin '
                        'registros no significa que no '
                        'hubo desperdicio.',
                        style: TextStyle(
                          fontSize: 12,
                          color: _colorTextoSecundario,
                        ),
                      ),

                      const SizedBox(height: 20),

                      // GRÁFICO DE MOVIMIENTOS
                      _graficoEventos(),

                      const SizedBox(height: 12),

                      // GRÁFICO DE DESCARTES
                      _graficoCantidadesDescartadas(),

                      const SizedBox(height: 20),

                      // TARJETAS MENSUALES EXISTENTES
                      for (
                        var indice = 0;
                        indice < _meses.length;
                        indice++
                      )
                        _tarjetaMes(
                          _meses[indice],
                          indice == 0,
                        ),

                      const SizedBox(height: 12),

                      Text(
                        'Estos resultados describen '
                        'los movimientos registrados. '
                        'No demuestran por sí solos '
                        'una reducción causal '
                        'del desperdicio.',
                        style: TextStyle(
                          fontSize: 12,
                          color: _colorTextoSecundario,
                        ),
                      ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
    );
  }
}
