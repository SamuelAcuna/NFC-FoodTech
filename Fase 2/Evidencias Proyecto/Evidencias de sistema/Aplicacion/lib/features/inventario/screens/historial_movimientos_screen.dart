import 'package:nfc_foodtech_app/shared/services/lectura_movimientos.dart';
import 'package:nfc_foodtech_app/shared/widgets/acceso_hogar.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistorialMovimientosScreen extends StatefulWidget {
  final Map<String, dynamic> hogar;

  const HistorialMovimientosScreen({super.key, required this.hogar});

  @override
  State<HistorialMovimientosScreen> createState() =>
      _HistorialMovimientosScreenState();
}

class _HistorialMovimientosScreenState
    extends State<HistorialMovimientosScreen> {
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

  Color get _colorTexto =>
      _modoOscuro ? Theme.of(context).colorScheme.onSurface : Colors.black87;

  final _supabase = Supabase.instance.client;
  final _buscadorController = TextEditingController();

  List<Map<String, dynamic>> _movimientos = [];

  String _filtro = 'TODOS';
  String _busqueda = '';
  String? _error;
  bool _cargando = true;
  int _revisionCarga = 0;

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  @override
  void dispose() {
    _revisionCarga++;
    _buscadorController.dispose();
    super.dispose();
  }

  // =====================================================
  // FORMATO DE CANTIDADES
  // =====================================================

  double _numero(dynamic valor) {
    if (valor is num) return valor.toDouble();

    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  String _formatearNumero(double valor, {int decimales = 3}) {
    return valor
        .toStringAsFixed(decimales)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  String _formatearCantidad(dynamic valor, String unidadBase) {
    final cantidad = _numero(valor);

    if (unidadBase == 'g' && cantidad >= 1000) {
      return '${_formatearNumero(cantidad / 1000, decimales: 6)} kg';
    }

    if (unidadBase == 'ml' && cantidad >= 1000) {
      return '${_formatearNumero(cantidad / 1000, decimales: 6)} L';
    }

    return '${_formatearNumero(cantidad)} $unidadBase';
  }

  String _textoCantidad(Map<String, dynamic> movimiento) {
    final tipo = movimiento['tipo']?.toString() ?? '';
    final unidad = movimiento['unidad_base']?.toString() ?? 'un';

    if (tipo == 'TRASLADO') {
      return '';
    }

    if (tipo == 'AJUSTE') {
      final deltaValor = movimiento['ajuste_delta'];

      if (deltaValor == null) {
        return 'Ajuste: ${_formatearCantidad(movimiento['cantidad'], unidad)}';
      }

      final delta = _numero(deltaValor);
      final magnitud = _formatearCantidad(delta.abs(), unidad);

      return delta < 0 ? '-$magnitud' : '+$magnitud';
    }

    final cantidad = _formatearCantidad(movimiento['cantidad'], unidad);

    if (tipo == 'INGRESO') {
      return '+$cantidad';
    }

    return '-$cantidad';
  }

  // =====================================================
  // FORMATO DE FECHAS
  // =====================================================

  DateTime? _fechaMovimiento(dynamic valor) {
    if (valor == null) return null;

    return DateTime.tryParse(valor.toString())?.toLocal();
  }

  String _formatearFechaHora(dynamic valor) {
    final fecha = _fechaMovimiento(valor);

    if (fecha == null) {
      return 'Fecha no disponible';
    }

    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    final hora = fecha.hour.toString().padLeft(2, '0');
    final minuto = fecha.minute.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year} · $hora:$minuto';
  }

  String _formatearFecha(dynamic valor) {
    if (valor == null) return 'Sin fecha';

    final fecha = DateTime.tryParse(valor.toString());

    if (fecha == null) return 'Sin fecha';

    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year}';
  }

  String _nombreUbicacion(dynamic valor) {
    switch (valor?.toString()) {
      case 'DESPENSA':
        return 'Despensa';

      case 'REFRIGERADOR':
        return 'Refrigerador';

      case 'CONGELADOR':
        return 'Congelador';

      default:
        return 'Sin ubicación';
    }
  }

  Map<String, dynamic> _mapaJson(dynamic valor) {
    if (valor is Map) {
      return Map<String, dynamic>.from(valor);
    }

    return <String, dynamic>{};
  }

  // =====================================================
  // CONSULTAR HISTORIAL EN SUPABASE
  // =====================================================

  Future<void> _cargarHistorial() async {
    if (!mounted) return;

    final revision = ++_revisionCarga;
    final usuarioId = _supabase.auth.currentUser?.id;
    bool vigente() =>
        mounted &&
        revision == _revisionCarga &&
        _supabase.auth.currentUser?.id == usuarioId;
    final lectura = LecturaMovimientos(_supabase, vigente);

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final hogarId = widget.hogar['id']?.toString();

      if (hogarId == null || hogarId.isEmpty) {
        throw Exception('No hay un hogar seleccionado.');
      }

      if (!await AccesoHogar.verificar(context)) {
        throw StateError('No se pudo confirmar el acceso al hogar.');
      }
      lectura.comprobar();

      // -------------------------------------------------
      // 1. OBTENER ÍTEMS DEL HOGAR
      // -------------------------------------------------

      // No filtramos por estado porque necesitamos
      // también ingresos AGOTADOS y DESECHADOS.
      final respuestaItems = await lectura.leer(
        'despensa_item',
        'id, alimento_id',
        hogarId: hogarId,
      );

      final itemsPorId = <String, Map<String, dynamic>>{};

      for (final dato in respuestaItems) {
        final item = Map<String, dynamic>.from(dato);
        final id = item['id']?.toString();

        if (id != null) {
          itemsPorId[id] = item;
        }
      }

      if (itemsPorId.isEmpty) {
        if (!await AccesoHogar.verificar(context)) {
          throw StateError('No se pudo confirmar el acceso al hogar.');
        }
        lectura.comprobar();
        setState(() {
          _movimientos = [];
          _cargando = false;
        });

        return;
      }

      // -------------------------------------------------
      // 2. MOVIMIENTOS TRADICIONALES
      // -------------------------------------------------

      final idsItems = itemsPorId.keys.toList();
      final movimientos = await lectura.leer(
        'movimiento',
        'id, despensa_item_id, tipo, cantidad, ajuste_delta, tipo_desperdicio_id, registrado_por, fecha',
        columnaIds: 'despensa_item_id',
        ids: idsItems,
      );

      // -------------------------------------------------
      // 3. R42: CONSULTAR TRASLADOS AUDITADOS
      // -------------------------------------------------

      final respuestaTraslados = await _supabase
          .rpc('historial_traslados_hogar', params: {'p_hogar_id': hogarId})
          .timeout(const Duration(seconds: 15));
      lectura.comprobar();

      final traslados = <Map<String, dynamic>>[];

      for (final dato in respuestaTraslados as List) {
        traslados.add(Map<String, dynamic>.from(dato as Map));
      }

      // -------------------------------------------------
      // 4. OBTENER NOMBRES Y UNIDADES
      // -------------------------------------------------

      final idsAlimentos = itemsPorId.values
          .map((item) => (item['alimento_id'] as num).toInt())
          .toSet()
          .toList();

      final alimentosPorId = <int, Map<String, dynamic>>{};

      if (idsAlimentos.isNotEmpty) {
        final respuestaAlimentos = await lectura.leer(
          'alimento',
          'id, nombre, unidad_base',
          columnaIds: 'id',
          ids: idsAlimentos,
        );

        for (final dato in respuestaAlimentos) {
          final alimento = Map<String, dynamic>.from(dato);

          final id = (alimento['id'] as num).toInt();

          alimentosPorId[id] = alimento;
        }
      }

      // -------------------------------------------------
      // 5. OBTENER MOTIVOS DE DESCARTE
      // -------------------------------------------------

      final motivosPorId = <int, String>{};

      final respuestaMotivos = await lectura.leer(
        'tipo_desperdicio',
        'id, nombre',
      );

      for (final motivo in respuestaMotivos) {
        final id = (motivo['id'] as num).toInt();

        motivosPorId[id] = motivo['nombre']?.toString() ?? 'Motivo desconocido';
      }

      // -------------------------------------------------
      // 6. COMBINAR MOVIMIENTOS NORMALES
      // -------------------------------------------------

      final historial = <Map<String, dynamic>>[];

      for (final movimiento in movimientos) {
        final itemId = movimiento['despensa_item_id']?.toString();

        final item = itemsPorId[itemId];

        if (item == null) continue;

        final alimentoId = (item['alimento_id'] as num).toInt();

        final alimento = alimentosPorId[alimentoId];

        final motivoId = (movimiento['tipo_desperdicio_id'] as num?)?.toInt();

        historial.add({
          ...movimiento,
          'nombre_alimento':
              alimento?['nombre']?.toString() ?? 'Alimento #$alimentoId',
          'unidad_base': alimento?['unidad_base']?.toString() ?? 'un',
          'nombre_motivo': motivoId == null
              ? null
              : motivosPorId[motivoId] ?? 'Motivo #$motivoId',
        });
      }

      // -------------------------------------------------
      // 7. R42: INCORPORAR TRASLADOS
      // -------------------------------------------------

      for (final traslado in traslados) {
        final itemId = traslado['despensa_item_id']?.toString();

        final item = itemsPorId[itemId];

        if (item == null) continue;

        final alimentoId = (item['alimento_id'] as num).toInt();

        final alimento = alimentosPorId[alimentoId];

        historial.add({
          'id': traslado['traslado_id'],
          'despensa_item_id': itemId,
          'tipo': 'TRASLADO',
          'cantidad': null,
          'ajuste_delta': null,
          'tipo_desperdicio_id': null,
          'registrado_por': traslado['registrado_por'],
          'fecha': traslado['fecha'],
          'antes': _mapaJson(traslado['antes']),
          'despues': _mapaJson(traslado['despues']),
          'nombre_alimento':
              alimento?['nombre']?.toString() ?? 'Alimento #$alimentoId',
          'unidad_base': alimento?['unidad_base']?.toString() ?? 'un',
          'nombre_motivo': null,
        });
      }

      // -------------------------------------------------
      // 8. ORDENAR CRONOLÓGICAMENTE
      // -------------------------------------------------

      historial.sort((a, b) {
        final fechaA = DateTime.tryParse(a['fecha']?.toString() ?? '');

        final fechaB = DateTime.tryParse(b['fecha']?.toString() ?? '');

        if (fechaA == null && fechaB == null) return 0;
        if (fechaA == null) return 1;
        if (fechaB == null) return -1;

        final comparacion = fechaB.compareTo(fechaA);
        return comparacion != 0
            ? comparacion
            : b['id'].toString().compareTo(a['id'].toString());
      });

      lectura.comprobar();
      if (!await AccesoHogar.verificar(context)) {
        throw StateError('No se pudo confirmar el acceso al hogar.');
      }
      lectura.comprobar();

      setState(() {
        _movimientos = historial;
        _cargando = false;
      });
    } on PostgrestException catch (error) {
      if (!vigente()) return;

      setState(() {
        _error = 'No se completó la consulta. Reintenta. ${error.message}';
        _cargando = false;
      });
    } catch (error) {
      if (!vigente()) return;

      setState(() {
        _error = 'No se completó la consulta. Reintenta. $error';
        _cargando = false;
      });
    }
  }

  // =====================================================
  // FILTROS DEL HISTORIAL
  // =====================================================

  List<Map<String, dynamic>> _movimientosVisibles() {
    final consulta = _busqueda.trim().toLowerCase();

    return _movimientos.where((movimiento) {
      final tipo = movimiento['tipo']?.toString() ?? '';

      if (_filtro != 'TODOS' && tipo != _filtro) {
        return false;
      }

      if (consulta.isEmpty) return true;

      final nombre =
          movimiento['nombre_alimento']?.toString().toLowerCase() ?? '';

      final motivo =
          movimiento['nombre_motivo']?.toString().toLowerCase() ?? '';

      final antes = _mapaJson(movimiento['antes']);

      final despues = _mapaJson(movimiento['despues']);

      final ubicacionAnterior = _nombreUbicacion(
        antes['ubicacion'],
      ).toLowerCase();

      final ubicacionNueva = _nombreUbicacion(
        despues['ubicacion'],
      ).toLowerCase();

      return nombre.contains(consulta) ||
          motivo.contains(consulta) ||
          ubicacionAnterior.contains(consulta) ||
          ubicacionNueva.contains(consulta);
    }).toList();
  }

  Widget _chipFiltro(String etiqueta, String valor) {
    final seleccionado = _filtro == valor;

    return ChoiceChip(
      label: Text(etiqueta),
      selected: seleccionado,
      selectedColor: _modoOscuro
          ? Theme.of(context).colorScheme.primaryContainer
          : const Color(0xFFDCEFE3),
      checkmarkColor: _modoOscuro ? _colorAcento : null,
      labelStyle: TextStyle(
        color: seleccionado
            ? (_modoOscuro
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : verde)
            : _colorTexto,
        fontWeight: seleccionado ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) {
        setState(() {
          _filtro = valor;
        });
      },
    );
  }

  // =====================================================
  // APARIENCIA SEGÚN TIPO DE MOVIMIENTO
  // =====================================================

  String _tituloTipo(String tipo) {
    switch (tipo) {
      case 'INGRESO':
        return 'Ingreso';

      case 'CONSUMO':
        return 'Consumo';

      case 'DESCARTE':
        return 'Descarte';

      case 'AJUSTE':
        return 'Ajuste';

      case 'TRASLADO':
        return 'Traslado';

      default:
        return tipo;
    }
  }

  IconData _iconoTipo(String tipo) {
    switch (tipo) {
      case 'INGRESO':
        return Icons.add_circle_outline;

      case 'CONSUMO':
        return Icons.restaurant_outlined;

      case 'DESCARTE':
        return Icons.delete_outline;

      case 'AJUSTE':
        return Icons.tune;

      case 'TRASLADO':
        return Icons.swap_horiz;

      default:
        return Icons.history;
    }
  }

  Color _colorTipo(String tipo) {
    switch (tipo) {
      case 'INGRESO':
        return _colorAcento;

      case 'CONSUMO':
        return _modoOscuro ? Colors.blue.shade200 : const Color(0xFF1565C0);

      case 'DESCARTE':
        return _modoOscuro
            ? Colors.deepOrange.shade200
            : const Color(0xFFC45126);

      case 'AJUSTE':
        return _modoOscuro ? Colors.brown.shade200 : const Color(0xFF795548);

      case 'TRASLADO':
        return _modoOscuro ? Colors.purple.shade200 : const Color(0xFF6A1B9A);

      default:
        return _modoOscuro
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : Colors.blueGrey;
    }
  }

  // =====================================================
  // R42: INFORMACIÓN DEL TRASLADO
  // =====================================================

  Widget _detalleTraslado(Map<String, dynamic> movimiento) {
    final antes = _mapaJson(movimiento['antes']);

    final despues = _mapaJson(movimiento['despues']);

    final origen = _nombreUbicacion(antes['ubicacion']);

    final destino = _nombreUbicacion(despues['ubicacion']);

    final fechaAnterior = antes['fecha_vencimiento'];

    final fechaNueva = despues['fecha_vencimiento'];

    final cambioFecha = fechaAnterior?.toString() != fechaNueva?.toString();

    final inicioCongelacion = despues['fecha_inicio_congelacion'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _modoOscuro
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : const Color(0xFFF1ECF7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.swap_horiz, color: _colorTipo('TRASLADO')),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Text(
                      '$origen → $destino',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),

              if (cambioFecha) ...[
                const SizedBox(height: 10),

                Text(
                  'Fecha anterior: '
                  '${_formatearFecha(fechaAnterior)}',
                  style: const TextStyle(fontSize: 13),
                ),

                Text(
                  'Fecha referencial nueva: '
                  '${_formatearFecha(fechaNueva)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],

              if (inicioCongelacion != null && destino == 'Congelador') ...[
                const SizedBox(height: 7),

                Text(
                  'Congelado desde: '
                  '${_formatearFecha(inicioCongelacion)}',
                  style: TextStyle(fontSize: 12, color: _colorTextoSecundario),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // =====================================================
  // TARJETA DE MOVIMIENTO
  // =====================================================

  Widget _tarjetaMovimiento(Map<String, dynamic> movimiento) {
    final tipo = movimiento['tipo']?.toString() ?? '';

    final nombre = movimiento['nombre_alimento']?.toString() ?? 'Alimento';

    final motivo = movimiento['nombre_motivo']?.toString();

    final color = _colorTipo(tipo);

    return Card(
      color: _colorSuperficie,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: _colorBorde),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.10),
                  child: Icon(_iconoTipo(tipo), color: color),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        _formatearFechaHora(movimiento['fecha']),
                        style: TextStyle(
                          fontSize: 12,
                          color: _colorTextoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _tituloTipo(tipo),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),

                const Spacer(),

                if (tipo != 'TRASLADO')
                  Flexible(
                    child: Text(
                      _textoCantidad(movimiento),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
              ],
            ),

            // ------------------------------------------
            // DETALLE DE TRASLADO
            // ------------------------------------------
            if (tipo == 'TRASLADO') _detalleTraslado(movimiento),

            // ------------------------------------------
            // MOTIVO DE DESCARTE
            // ------------------------------------------
            if (tipo == 'DESCARTE' && motivo != null) ...[
              const SizedBox(height: 12),

              Text(
                'Motivo: $motivo',
                style: TextStyle(color: _colorTexto, fontSize: 13),
              ),
            ],

            if (tipo == 'CONSUMO') ...[
              const SizedBox(height: 8),

              Text(
                'No contabilizado como desperdicio.',
                style: TextStyle(color: _colorTextoSecundario, fontSize: 12),
              ),
            ],

            if (tipo == 'AJUSTE') ...[
              const SizedBox(height: 8),

              Text(
                'Corrección de inventario. '
                'No contabilizada como consumo '
                'ni desperdicio.',
                style: TextStyle(color: _colorTextoSecundario, fontSize: 12),
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
    final nombreHogar = widget.hogar['nombre']?.toString() ?? 'Hogar';

    final visibles = _movimientosVisibles();

    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        backgroundColor: verde,
        foregroundColor: Colors.white,
        title: const Text('Historial'),
        actions: [
          IconButton(
            tooltip: 'Actualizar historial',
            onPressed: _cargando ? null : _cargarHistorial,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _colorSuperficie,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hogar: $nombreHogar',
                  style: TextStyle(
                    color: _colorAcento,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  '${_movimientos.length} '
                  'movimientos cargados',
                  style: TextStyle(color: _colorTextoSecundario),
                ),

                const SizedBox(height: 12),

                TextField(
                  controller: _buscadorController,
                  onChanged: (valor) {
                    setState(() {
                      _busqueda = valor;
                    });
                  },
                  decoration: InputDecoration(
                    hintText:
                        'Buscar alimento, motivo '
                        'o ubicación...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: _colorFondo,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chipFiltro('Todos', 'TODOS'),

                      const SizedBox(width: 7),

                      _chipFiltro('Ingresos', 'INGRESO'),

                      const SizedBox(width: 7),

                      _chipFiltro('Consumos', 'CONSUMO'),

                      const SizedBox(width: 7),

                      _chipFiltro('Descartes', 'DESCARTE'),

                      const SizedBox(width: 7),

                      _chipFiltro('Ajustes', 'AJUSTE'),

                      const SizedBox(width: 7),

                      _chipFiltro('Traslados', 'TRASLADO'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _cargando
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
                            size: 42,
                            color: _colorError,
                          ),

                          const SizedBox(height: 12),

                          Text(
                            'No se pudo cargar '
                            'el historial.\n$_error',
                            textAlign: TextAlign.center,
                          ),

                          const SizedBox(height: 12),

                          ElevatedButton(
                            onPressed: _cargarHistorial,
                            child: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  )
                : visibles.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _movimientos.isEmpty
                            ? 'Todavía no hay '
                                  'movimientos '
                                  'visibles en este hogar.'
                            : 'No encontramos '
                                  'movimientos '
                                  'para este filtro.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _colorTextoSecundario),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: visibles.length,
                    itemBuilder: (context, indice) {
                      return _tarjetaMovimiento(visibles[indice]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
