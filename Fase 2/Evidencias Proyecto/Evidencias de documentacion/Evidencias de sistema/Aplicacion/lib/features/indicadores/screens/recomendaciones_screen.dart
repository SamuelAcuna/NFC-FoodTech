import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecomendacionesScreen extends StatefulWidget {
  final Map<String, dynamic> hogar;

  const RecomendacionesScreen({super.key, required this.hogar});

  @override
  State<RecomendacionesScreen> createState() => _RecomendacionesScreenState();
}

// =====================================================
// DATOS AGRUPADOS POR ALIMENTO
// =====================================================

class _ResumenAlimento {
  final int alimentoId;
  final String nombre;
  final String unidadBase;

  int eventosConsumo = 0;
  int eventosDescarte = 0;
  int descartesEvitables = 0;

  double cantidadConsumida = 0;
  double cantidadDescartada = 0;
  double cantidadDescarteEvitable = 0;

  _ResumenAlimento({
    required this.alimentoId,
    required this.nombre,
    required this.unidadBase,
  });

  int get totalEventos {
    return eventosConsumo + eventosDescarte;
  }

  double get cantidadGestionada {
    return cantidadConsumida + cantidadDescartada;
  }

  double get porcentajeDesperdicioEvitable {
    if (cantidadGestionada <= 0) return 0;

    return (cantidadDescarteEvitable / cantidadGestionada) * 100;
  }
}

// =====================================================
// RECOMENDACIÓN RESULTANTE
// =====================================================

class _Recomendacion {
  final String alimento;
  final String unidadBase;
  final String tipo;
  final String titulo;
  final String descripcion;
  final double porcentaje;
  final double cantidadDescartada;
  final int descartesEvitables;
  final int prioridad;

  _Recomendacion({
    required this.alimento,
    required this.unidadBase,
    required this.tipo,
    required this.titulo,
    required this.descripcion,
    required this.porcentaje,
    required this.cantidadDescartada,
    required this.descartesEvitables,
    required this.prioridad,
  });
}

class _RecomendacionesScreenState extends State<RecomendacionesScreen> {
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

  Color get _colorAdvertencia =>
      _modoOscuro ? Colors.deepOrange.shade200 : Colors.deepOrange;

  // Parámetros iniciales de las recomendaciones.
  static const int periodoDias = 90;
  static const int minimoMovimientos = 3;
  static const int minimoDescartesRecurrentes = 3;
  static const double umbralDesperdicio = 15.0;

  final _supabase = Supabase.instance.client;

  bool _cargando = true;
  String? _error;

  int _alimentosEvaluados = 0;
  int _alimentosConDatosInsuficientes = 0;
  int _movimientosEvaluados = 0;
  int _descartesEvitables = 0;

  List<_Recomendacion> _recomendaciones = [];

  @override
  void initState() {
    super.initState();
    _cargarRecomendaciones();
  }

  // =====================================================
  // FORMATO DE NÚMEROS Y CANTIDADES
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

  // =====================================================
  // OBTENER TODOS LOS INGRESOS DEL HOGAR
  // =====================================================

  Future<List<Map<String, dynamic>>> _obtenerItems(String hogarId) async {
    final resultado = <Map<String, dynamic>>[];

    const pagina = 500;
    var desde = 0;

    while (true) {
      final respuesta = await _supabase
          .from('despensa_item')
          .select('id, alimento_id')
          .eq('hogar_id', hogarId)
          .order('id')
          .range(desde, desde + pagina - 1);

      resultado.addAll(
        respuesta.map((dato) => Map<String, dynamic>.from(dato)),
      );

      if (respuesta.length < pagina) {
        break;
      }

      desde += pagina;
    }

    return resultado;
  }

  // =====================================================
  // OBTENER ALIMENTOS ASOCIADOS
  // =====================================================

  Future<Map<int, Map<String, dynamic>>> _obtenerAlimentos(
    List<Map<String, dynamic>> items,
  ) async {
    final ids = items
        .map((item) => (item['alimento_id'] as num).toInt())
        .toSet()
        .toList();

    final alimentos = <int, Map<String, dynamic>>{};

    const tamanoLote = 100;

    for (var inicio = 0; inicio < ids.length; inicio += tamanoLote) {
      final fin = inicio + tamanoLote < ids.length
          ? inicio + tamanoLote
          : ids.length;

      final lote = ids.sublist(inicio, fin);

      final respuesta = await _supabase
          .from('alimento')
          .select('id, nombre, unidad_base')
          .inFilter('id', lote);

      for (final dato in respuesta) {
        final alimento = Map<String, dynamic>.from(dato);

        final id = (alimento['id'] as num).toInt();

        alimentos[id] = alimento;
      }
    }

    return alimentos;
  }

  // =====================================================
  // OBTENER MOVIMIENTOS DE LOS ÚLTIMOS 90 DÍAS
  // =====================================================

  Future<List<Map<String, dynamic>>> _obtenerMovimientos(
    List<String> idsItems,
  ) async {
    final resultado = <Map<String, dynamic>>[];

    const tamanoLote = 80;
    const tamanoPagina = 500;

    final fechaDesde = DateTime.now()
        .subtract(const Duration(days: periodoDias))
        .toUtc()
        .toIso8601String();

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
              'id, despensa_item_id, tipo, cantidad, '
              'tipo_desperdicio_id, fecha',
            )
            .inFilter('despensa_item_id', lote)
            .inFilter('tipo', ['CONSUMO', 'DESCARTE'])
            .gte('fecha', fechaDesde)
            .order('fecha', ascending: false)
            .order('id', ascending: false)
            .range(desde, desde + tamanoPagina - 1);

        resultado.addAll(
          respuesta.map((dato) => Map<String, dynamic>.from(dato)),
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
  // CLASIFICACIÓN DE MOTIVOS DE DESCARTE
  // =====================================================

  Future<Map<int, bool>> _obtenerMotivos() async {
    final resultado = <int, bool>{};

    final respuesta = await _supabase
        .from('tipo_desperdicio')
        .select('id, es_evitable');

    for (final dato in respuesta) {
      final id = (dato['id'] as num).toInt();
      final evitable = dato['es_evitable'];

      if (evitable is bool) {
        resultado[id] = evitable;
      }
    }

    return resultado;
  }

  // =====================================================
  // PROCESAR REGLAS DE RECOMENDACIÓN
  // =====================================================

  List<_Recomendacion> _generarRecomendaciones(
    Iterable<_ResumenAlimento> resumenes,
  ) {
    final recomendaciones = <_Recomendacion>[];

    for (final resumen in resumenes) {
      // Evita recomendar con menos de 3 movimientos.
      if (resumen.totalEventos < minimoMovimientos) {
        continue;
      }

      if (resumen.descartesEvitables == 0) {
        continue;
      }

      final porcentaje = resumen.porcentajeDesperdicioEvitable;

      // REGLA 1: PROPORCIÓN.
      // Prioridad sobre recurrencia.
      if (porcentaje > umbralDesperdicio) {
        recomendaciones.add(
          _Recomendacion(
            alimento: resumen.nombre,
            unidadBase: resumen.unidadBase,
            tipo: 'PROPORCION',
            titulo: 'Revisa cuánto compras',
            descripcion:
                'En los últimos $periodoDias días, '
                'el ${_numeroTexto(porcentaje, decimales: 1)}% '
                'de la cantidad registrada como '
                'consumida o descartada de este alimento '
                'corresponde a descartes evitables. '
                'Podrías comprar una cantidad menor '
                'la próxima vez.',
            porcentaje: porcentaje,
            cantidadDescartada: resumen.cantidadDescarteEvitable,
            descartesEvitables: resumen.descartesEvitables,
            prioridad: 1,
          ),
        );

        continue;
      }

      // REGLA 2: RECURRENCIA.
      if (resumen.descartesEvitables >= minimoDescartesRecurrentes) {
        recomendaciones.add(
          _Recomendacion(
            alimento: resumen.nombre,
            unidadBase: resumen.unidadBase,
            tipo: 'RECURRENCIA',
            titulo: 'Compra con menor frecuencia',
            descripcion:
                'Este alimento se descartó de forma '
                'evitable ${resumen.descartesEvitables} '
                'veces durante los últimos $periodoDias días. '
                'Considera comprarlo en porciones '
                'más pequeñas o con menor frecuencia.',
            porcentaje: porcentaje,
            cantidadDescartada: resumen.cantidadDescarteEvitable,
            descartesEvitables: resumen.descartesEvitables,
            prioridad: 2,
          ),
        );
      }
    }

    recomendaciones.sort((a, b) {
      final orden = a.prioridad.compareTo(b.prioridad);

      if (orden != 0) return orden;

      final comparacionPorcentaje = b.porcentaje.compareTo(a.porcentaje);

      if (comparacionPorcentaje != 0) {
        return comparacionPorcentaje;
      }

      return a.alimento.compareTo(b.alimento);
    });

    return recomendaciones;
  }

  // =====================================================
  // CARGAR RECOMENDACIONES
  // =====================================================

  Future<void> _cargarRecomendaciones() async {
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

      final items = await _obtenerItems(hogarId);

      if (items.isEmpty) {
        if (!mounted) return;

        setState(() {
          _recomendaciones = [];
          _alimentosEvaluados = 0;
          _alimentosConDatosInsuficientes = 0;
          _movimientosEvaluados = 0;
          _descartesEvitables = 0;
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

      final alimentos = await _obtenerAlimentos(items);

      final motivos = await _obtenerMotivos();

      final movimientos = await _obtenerMovimientos(itemsPorId.keys.toList());

      final resumenes = <int, _ResumenAlimento>{};

      var movimientosEvaluados = 0;
      var descartesEvitables = 0;

      for (final movimiento in movimientos) {
        final tipo = movimiento['tipo']?.toString();

        if (tipo != 'CONSUMO' && tipo != 'DESCARTE') {
          continue;
        }

        final itemId = movimiento['despensa_item_id']?.toString();

        final item = itemsPorId[itemId];

        if (item == null) continue;

        final alimentoId = (item['alimento_id'] as num).toInt();

        final alimento = alimentos[alimentoId];

        if (alimento == null) continue;

        final unidad = alimento['unidad_base']?.toString() ?? '';

        if (unidad != 'g' && unidad != 'ml' && unidad != 'un') {
          continue;
        }

        final cantidad = _numero(movimiento['cantidad']);

        if (cantidad <= 0) continue;

        final resumen = resumenes.putIfAbsent(
          alimentoId,
          () => _ResumenAlimento(
            alimentoId: alimentoId,
            nombre: alimento['nombre']?.toString() ?? 'Alimento #$alimentoId',
            unidadBase: unidad,
          ),
        );

        movimientosEvaluados++;

        if (tipo == 'CONSUMO') {
          resumen.eventosConsumo++;
          resumen.cantidadConsumida += cantidad;
          continue;
        }

        // Movimiento de descarte.
        resumen.eventosDescarte++;
        resumen.cantidadDescartada += cantidad;

        final motivoId = (movimiento['tipo_desperdicio_id'] as num?)?.toInt();

        final esEvitable = motivoId == null ? null : motivos[motivoId];

        // Solo los descartes evitables generan
        // advertencias para ajustar compras.
        if (esEvitable == true) {
          resumen.descartesEvitables++;
          resumen.cantidadDescarteEvitable += cantidad;
          descartesEvitables++;
        }
      }

      final recomendaciones = _generarRecomendaciones(resumenes.values);

      final datosInsuficientes = resumenes.values
          .where((resumen) => resumen.totalEventos < minimoMovimientos)
          .length;

      if (!mounted) return;

      setState(() {
        _recomendaciones = recomendaciones;

        _alimentosEvaluados = resumenes.length;

        _alimentosConDatosInsuficientes = datosInsuficientes;

        _movimientosEvaluados = movimientosEvaluados;

        _descartesEvitables = descartesEvitables;

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
  // INTERFAZ PROVISIONAL
  // =====================================================

  Widget _tarjetaRecomendacion(_Recomendacion recomendacion) {
    final esProporcion = recomendacion.tipo == 'PROPORCION';

    return Card(
      color: _colorSuperficie,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _colorBorde),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  esProporcion ? Icons.trending_down : Icons.repeat,
                  color: esProporcion ? _colorAdvertencia : _colorAcento,
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    recomendacion.alimento,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            Text(
              recomendacion.titulo,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: _colorAcento,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              recomendacion.descripcion,
              style: TextStyle(color: _colorTexto),
            ),

            const Divider(height: 28),

            Text(
              'Descarte evitable registrado: '
              '${_cantidadTexto(recomendacion.cantidadDescartada, recomendacion.unidadBase)}',
            ),

            const SizedBox(height: 5),

            Text(
              'Eventos de descarte evitable: '
              '${recomendacion.descartesEvitables}',
            ),

            const SizedBox(height: 5),

            Text(
              'Proporción evitable registrada: '
              '${_numeroTexto(recomendacion.porcentaje, decimales: 1)}%',
            ),
          ],
        ),
      ),
    );
  }

  Widget _resumenGeneral() {
    return Card(
      color: _colorSuperficie,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Análisis del hogar',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
                color: _colorAcento,
              ),
            ),

            const SizedBox(height: 12),

            Text('Periodo analizado: últimos $periodoDias días'),

            const SizedBox(height: 6),

            Text('Alimentos evaluados: $_alimentosEvaluados'),

            const SizedBox(height: 6),

            Text(
              'Movimientos evaluados: '
              '$_movimientosEvaluados',
            ),

            const SizedBox(height: 6),

            Text('Descartes evitables: $_descartesEvitables'),

            const SizedBox(height: 6),

            Text(
              'Alimentos con historial insuficiente: '
              '$_alimentosConDatosInsuficientes',
            ),
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
    final nombreHogar = widget.hogar['nombre']?.toString() ?? 'Hogar';

    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        backgroundColor: verde,
        foregroundColor: Colors.white,
        title: const Text('Recomendaciones'),
        actions: [
          IconButton(
            tooltip: 'Actualizar recomendaciones',
            onPressed: _cargando ? null : _cargarRecomendaciones,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
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
                      'No se pudieron cargar las '
                      'recomendaciones.\n$_error',
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 12),

                    ElevatedButton(
                      onPressed: _cargarRecomendaciones,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _cargarRecomendaciones,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Hogar: $nombreHogar',
                    style: TextStyle(
                      color: _colorAcento,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'Sugerencias basadas en los '
                    'consumos y descartes registrados. '
                    'No se utiliza inteligencia artificial.',
                    style: TextStyle(color: _colorTextoSecundario),
                  ),

                  const SizedBox(height: 18),

                  _resumenGeneral(),

                  const SizedBox(height: 22),

                  Text(
                    'Sugerencias disponibles '
                    '(${_recomendaciones.length})',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _colorAcento,
                    ),
                  ),

                  const SizedBox(height: 14),

                  if (_recomendaciones.isEmpty)
                    Card(
                      color: _colorSuperficie,
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              size: 36,
                              color: _colorAcento,
                            ),

                            SizedBox(height: 12),

                            Text(
                              'Aún no hay recomendaciones '
                              'con suficiente evidencia.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),

                            SizedBox(height: 8),

                            Text(
                              'Sigue registrando consumos '
                              'y descartes del hogar. '
                              'No tener recomendaciones '
                              'no significa que no exista '
                              'desperdicio.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    for (final recomendacion in _recomendaciones)
                      _tarjetaRecomendacion(recomendacion),

                  const SizedBox(height: 20),

                  Text(
                    'Estas sugerencias son orientativas '
                    'y dependen de la información '
                    'registrada por los integrantes '
                    'del hogar. No representan '
                    'una medición exacta del consumo '
                    'ni del desperdicio real.',
                    style: TextStyle(fontSize: 12, color: _colorTextoSecundario),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}
