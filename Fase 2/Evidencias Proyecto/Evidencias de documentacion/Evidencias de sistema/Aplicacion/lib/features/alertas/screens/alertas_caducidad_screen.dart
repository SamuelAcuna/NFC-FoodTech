import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nfc_foodtech_app/shared/widgets/acceso_hogar.dart';

class AlertasCaducidadScreen extends StatefulWidget {
  final Map<String, dynamic> hogar;

  const AlertasCaducidadScreen({super.key, required this.hogar});

  @override
  State<AlertasCaducidadScreen> createState() => AlertasCaducidadScreenState();
}

class _AlertaCaducidad {
  final String itemId;
  final String nombreAlimento;
  final String unidadBase;
  final double cantidadRestante;
  final String ubicacion;
  final DateTime fecha;
  final int diasRestantes;
  final bool esEstimada;

  const _AlertaCaducidad({
    required this.itemId,
    required this.nombreAlimento,
    required this.unidadBase,
    required this.cantidadRestante,
    required this.ubicacion,
    required this.fecha,
    required this.diasRestantes,
    required this.esEstimada,
  });
}

class AlertasCaducidadScreenState extends State<AlertasCaducidadScreen> {
  Future<void> actualizarDatos() async {
    if (await AccesoHogar.verificar(context) && mounted) await _cargarAlertas();
  }

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

  final _supabase = Supabase.instance.client;

  List<_AlertaCaducidad> _alertas = [];

  bool _cargando = true;
  String? _error;

  int _sinFecha = 0;
  int _diasAnticipacion = 7;

  String _filtro = 'TODOS';

  @override
  void initState() {
    super.initState();
    _cargarAlertas();
  }

  // =====================================================
  // NÚMEROS Y CANTIDADES
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

  String _cantidadTexto(double cantidad, String unidadBase) {
    if (unidadBase == 'g' && cantidad >= 1000) {
      return '${_numeroTexto(cantidad / 1000, decimales: 6)} kg';
    }

    if (unidadBase == 'ml' && cantidad >= 1000) {
      return '${_numeroTexto(cantidad / 1000, decimales: 6)} L';
    }

    return '${_numeroTexto(cantidad)} $unidadBase';
  }

  // =====================================================
  // FECHAS
  // =====================================================

  DateTime? _leerFecha(dynamic valor) {
    if (valor == null) return null;

    final texto = valor.toString();

    // despensa_item.fecha_vencimiento es de tipo DATE.
    // Tomamos año, mes y día sin depender de la zona
    // horaria del timestamp.
    final partes = texto.split('-');

    if (partes.length != 3) return null;

    final anio = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    final dia = int.tryParse(
      partes[2].substring(0, partes[2].length >= 2 ? 2 : partes[2].length),
    );

    if (anio == null || mes == null || dia == null) {
      return null;
    }

    final fecha = DateTime.utc(anio, mes, dia);

    if (fecha.year != anio || fecha.month != mes || fecha.day != dia) {
      return null;
    }

    return fecha;
  }

  DateTime _hoy() {
    final ahora = DateTime.now();

    // UTC únicamente para comparar días calendario.
    // El día se toma de la hora local del dispositivo.
    return DateTime.utc(ahora.year, ahora.month, ahora.day);
  }

  int _diasHasta(DateTime fecha) {
    return fecha.difference(_hoy()).inDays;
  }

  String _fechaTexto(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year}';
  }

  // =====================================================
  // OBTENER INVENTARIO ACTIVO
  // =====================================================

  Future<List<Map<String, dynamic>>> _obtenerInventario(String hogarId) async {
    final resultado = <Map<String, dynamic>>[];

    const tamanoPagina = 400;
    var desde = 0;

    while (true) {
      final respuesta = await _supabase
          .from('despensa_item')
          .select(
            'id, alimento_id, cantidad_restante, '
            'fecha_vencimiento, vencimiento_estimado, '
            'ubicacion',
          )
          .eq('hogar_id', hogarId)
          .eq('estado', 'DISPONIBLE')
          .gt('cantidad_restante', 0)
          .order('id')
          .range(desde, desde + tamanoPagina - 1);

      resultado.addAll(
        respuesta.map((dato) => Map<String, dynamic>.from(dato)),
      );

      if (respuesta.length < tamanoPagina) {
        break;
      }

      desde += tamanoPagina;
    }

    return resultado;
  }

  // =====================================================
  // OBTENER NOMBRES Y UNIDADES
  // =====================================================

  Future<Map<int, Map<String, dynamic>>> _obtenerAlimentos(
    List<Map<String, dynamic>> inventario,
  ) async {
    final ids = inventario
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
  // CARGAR ALERTAS
  // =====================================================

  Future<void> _cargarAlertas() async {
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

      final inventario = await _obtenerInventario(hogarId);

      final alimentos = await _obtenerAlimentos(inventario);

      final alertas = <_AlertaCaducidad>[];
      var sinFecha = 0;

      for (final item in inventario) {
        final fecha = _leerFecha(item['fecha_vencimiento']);

        // No generamos una fecha ficticia.
        if (fecha == null) {
          sinFecha++;
          continue;
        }

        final alimentoId = (item['alimento_id'] as num).toInt();

        final alimento = alimentos[alimentoId];

        final cantidad = _numero(item['cantidad_restante']);

        if (cantidad <= 0) continue;

        alertas.add(
          _AlertaCaducidad(
            itemId: item['id']?.toString() ?? '',
            nombreAlimento:
                alimento?['nombre']?.toString() ?? 'Alimento #$alimentoId',
            unidadBase: alimento?['unidad_base']?.toString() ?? 'un',
            cantidadRestante: cantidad,
            ubicacion: item['ubicacion']?.toString() ?? 'DESPENSA',
            fecha: fecha,
            diasRestantes: _diasHasta(fecha),
            esEstimada: item['vencimiento_estimado'] == true,
          ),
        );
      }

      // Fechas más urgentes primero.
      alertas.sort((a, b) {
        final comparacion = a.diasRestantes.compareTo(b.diasRestantes);

        if (comparacion != 0) {
          return comparacion;
        }

        return a.nombreAlimento.compareTo(b.nombreAlimento);
      });

      if (!mounted) return;

      setState(() {
        _alertas = alertas;
        _sinFecha = sinFecha;
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
  // CLASIFICACIÓN Y FILTROS
  // =====================================================

  bool _estaEnVentana(_AlertaCaducidad alerta) {
    return alerta.diasRestantes <= _diasAnticipacion;
  }

  List<_AlertaCaducidad> _alertasVisibles() {
    return _alertas.where((alerta) {
      if (!_estaEnVentana(alerta)) return false;

      switch (_filtro) {
        case 'PASADA':
          return alerta.diasRestantes < 0;

        case 'HOY':
          return alerta.diasRestantes == 0;

        case 'PROXIMA':
          return alerta.diasRestantes > 0;

        default:
          return true;
      }
    }).toList();
  }

  Color _colorAlerta(int dias) {
    if (dias < 0) {
      return _modoOscuro
          ? Theme.of(context).colorScheme.error
          : const Color(0xFFC62828);
    }

    if (dias == 0) {
      return _modoOscuro ? Colors.deepOrange.shade200 : const Color(0xFFD35400);
    }

    if (dias <= 3) {
      return _modoOscuro ? Colors.amber.shade200 : const Color(0xFFB76E00);
    }

    return _colorAcento;
  }

  IconData _iconoAlerta(int dias) {
    if (dias < 0) {
      return Icons.warning_amber_outlined;
    }

    if (dias == 0) {
      return Icons.error_outline;
    }

    return Icons.schedule;
  }

  String _estadoAlerta(int dias) {
    if (dias < 0) {
      final pasados = dias.abs();

      return 'Fecha superada hace '
          '$pasados día${pasados == 1 ? '' : 's'}';
    }

    if (dias == 0) {
      return 'Fecha correspondiente a hoy';
    }

    if (dias == 1) {
      return 'Fecha prevista para mañana';
    }

    return 'Faltan $dias días';
  }

  String _ubicacionTexto(String ubicacion) {
    switch (ubicacion) {
      case 'DESPENSA':
        return 'Despensa';

      case 'REFRIGERADOR':
        return 'Refrigerador';

      case 'CONGELADOR':
        return 'Congelador';

      default:
        return ubicacion;
    }
  }

  // =====================================================
  // COMPONENTES PROVISIONALES
  // =====================================================

  Widget _filtroChip(String etiqueta, String valor) {
    return ChoiceChip(
      label: Text(etiqueta),
      selected: _filtro == valor,
      onSelected: (_) {
        setState(() {
          _filtro = valor;
        });
      },
    );
  }

  Widget _tarjetaAlerta(_AlertaCaducidad alerta) {
    final color = _colorAlerta(alerta.diasRestantes);

    return Card(
      color: _colorSuperficie,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
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
                Icon(_iconoAlerta(alerta.diasRestantes), color: color),

                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    alerta.nombreAlimento,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Text(
              _estadoAlerta(alerta.diasRestantes),
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            Text(
              'Disponible: ${_cantidadTexto(alerta.cantidadRestante, alerta.unidadBase)}',
            ),

            const SizedBox(height: 5),

            Text('Ubicación: ${_ubicacionTexto(alerta.ubicacion)}'),

            const SizedBox(height: 5),

            Text(
              alerta.esEstimada
                  ? 'Fecha estimada de caducidad: '
                        '${_fechaTexto(alerta.fecha)}'
                  : 'Fecha indicada: '
                        '${_fechaTexto(alerta.fecha)}',
            ),

            if (alerta.esEstimada) ...[
              const SizedBox(height: 10),

              Text(
                'Fecha referencial calculada '
                'por el sistema.',
                style: TextStyle(color: _colorTextoSecundario, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resumenAlertas() {
    final pasada = _alertas.where((alerta) => alerta.diasRestantes < 0).length;

    final hoy = _alertas.where((alerta) => alerta.diasRestantes == 0).length;

    final proximas = _alertas
        .where(
          (alerta) =>
              alerta.diasRestantes > 0 &&
              alerta.diasRestantes <= _diasAnticipacion,
        )
        .length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _colorSuperficie,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Fechas superadas: $pasada'),

          const SizedBox(height: 5),

          Text('Fechas para hoy: $hoy'),

          const SizedBox(height: 5),

          Text('Próximas: $proximas'),

          const SizedBox(height: 5),

          Text('Ingresos sin fecha: $_sinFecha'),
        ],
      ),
    );
  }

  // =====================================================
  // PANTALLA PRINCIPAL
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final nombreHogar = widget.hogar['nombre']?.toString() ?? 'Hogar';

    final visibles = _alertasVisibles();

    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? null
            : AccesoHogar.botonVolver(context),
        backgroundColor: verde,
        foregroundColor: Colors.white,
        title: const Text('Alertas de caducidad'),
        actions: [
          IconButton(
            tooltip: 'Actualizar alertas',
            onPressed: _cargando ? null : _cargarAlertas,
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
                    Icon(Icons.error_outline, size: 42, color: _colorError),

                    const SizedBox(height: 12),

                    Text(
                      'No se pudieron cargar '
                      'las alertas.\n$_error',
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 12),

                    ElevatedButton(
                      onPressed: _cargarAlertas,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _cargarAlertas,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Hogar: $nombreHogar',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _colorAcento,
                    ),
                  ),

                  const SizedBox(height: 16),

                  DropdownButtonFormField<int>(
                    key: ValueKey(_diasAnticipacion),
                    initialValue: _diasAnticipacion,
                    decoration: const InputDecoration(
                      labelText: 'Avisar con anticipación',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 día')),
                      DropdownMenuItem(value: 3, child: Text('3 días')),
                      DropdownMenuItem(value: 7, child: Text('7 días')),
                      DropdownMenuItem(value: 14, child: Text('14 días')),
                    ],
                    onChanged: (valor) {
                      if (valor == null) return;

                      setState(() {
                        _diasAnticipacion = valor;
                      });
                    },
                  ),

                  const SizedBox(height: 14),

                  _resumenAlertas(),

                  const SizedBox(height: 14),

                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filtroChip('Todas', 'TODOS'),
                        const SizedBox(width: 6),
                        _filtroChip('Fecha superada', 'PASADA'),
                        const SizedBox(width: 6),
                        _filtroChip('Hoy', 'HOY'),
                        const SizedBox(width: 6),
                        _filtroChip('Próximas', 'PROXIMA'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  Text(
                    'Alimentos que requieren atención '
                    '(${visibles.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: _colorAcento,
                    ),
                  ),

                  const SizedBox(height: 12),

                  if (visibles.isEmpty)
                    Card(
                      color: _colorSuperficie,
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No hay alimentos que '
                          'coincidan con estas alertas.\n\n'
                          'Puedes ampliar los días '
                          'de anticipación o actualizar '
                          'el inventario.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    for (final alerta in visibles) _tarjetaAlerta(alerta),

                  const SizedBox(height: 20),

                  Text(
                    'Las fechas estimadas son orientativas. '
                    'Una fecha no garantiza que el '
                    'alimento sea seguro para consumirlo. '
                    'Revisa su estado y las indicaciones '
                    'de conservación correspondientes.',
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
