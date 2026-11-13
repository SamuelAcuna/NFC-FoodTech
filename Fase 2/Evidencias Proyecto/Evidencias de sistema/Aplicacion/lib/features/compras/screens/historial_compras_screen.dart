import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// =====================================================
// R64 - MODELO DEL HISTORIAL DE COMPRAS
// =====================================================

class _CompraHistorial {
  final String id;
  final String nombreAlimento;
  final String nombreLista;
  final String unidad;
  final double cantidad;

  final DateTime? fecha;
  final bool fechaReferencial;

  final int? precio;
  final bool precioReferencial;

  const _CompraHistorial({
    required this.id,
    required this.nombreAlimento,
    required this.nombreLista,
    required this.unidad,
    required this.cantidad,
    required this.fecha,
    required this.fechaReferencial,
    required this.precio,
    required this.precioReferencial,
  });
}

// =====================================================
// R64 - HISTORIAL DE COMPRAS DEL HOGAR
// =====================================================

class HistorialComprasScreen extends StatefulWidget {
  final Map<String, dynamic> hogar;

  const HistorialComprasScreen({super.key, required this.hogar});

  @override
  State<HistorialComprasScreen> createState() => _HistorialComprasScreenState();
}

class _HistorialComprasScreenState extends State<HistorialComprasScreen> {
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

  final _supabase = Supabase.instance.client;
  final _busquedaController = TextEditingController();

  List<_CompraHistorial> _compras = [];

  bool _cargando = true;
  bool _datosParciales = false;

  String? _error;
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargarCompras();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  // =====================================================
  // UTILIDADES
  // =====================================================

  double _numero(dynamic valor) {
    if (valor is num) return valor.toDouble();

    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  String _numeroTexto(double valor) {
    return valor
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  String _cantidadTexto(double cantidad, String unidad) {
    final nombreUnidad = unidad == 'l' ? 'L' : unidad;

    return '${_numeroTexto(cantidad)} $nombreUnidad';
  }

  String _dinero(int valor) {
    final texto = valor.toString();

    final formateado = texto.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );

    return '\$$formateado';
  }

  DateTime? _fechaExacta(dynamic valor) {
    if (valor == null) return null;

    return DateTime.tryParse(valor.toString())?.toLocal();
  }

  DateTime? _fechaReferencial(dynamic valor) {
    if (valor == null) return null;

    final fecha = DateTime.tryParse(valor.toString());

    if (fecha == null) return null;

    // fecha_ingreso es DATE, no TIMESTAMPTZ.
    // Solo conserva día/mes/año.
    return DateTime(fecha.year, fecha.month, fecha.day);
  }

  String _fechaTexto(DateTime? fecha, {bool referencial = false}) {
    if (fecha == null) {
      return 'Fecha no disponible';
    }

    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');

    final fechaBase = '$dia/$mes/${fecha.year}';

    if (referencial) {
      return '$fechaBase · Referencial';
    }

    final hora = fecha.hour.toString().padLeft(2, '0');
    final minuto = fecha.minute.toString().padLeft(2, '0');

    return '$fechaBase · $hora:$minuto';
  }

  String _claveFecha(DateTime? fecha) {
    if (fecha == null) return 'SIN_FECHA';

    return '${fecha.year}-'
        '${fecha.month.toString().padLeft(2, '0')}-'
        '${fecha.day.toString().padLeft(2, '0')}';
  }

  String _tituloFecha(DateTime? fecha) {
    if (fecha == null) {
      return 'Sin fecha disponible';
    }

    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year}';
  }

  // =====================================================
  // CONSULTAR COMPRAS DEL HOGAR
  // =====================================================

  Future<void> _cargarCompras() async {
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

      // -------------------------------------------------
      // 1. LISTAS DEL HOGAR
      // -------------------------------------------------

      final respuestaListas = await _supabase
          .from('lista_compra')
          .select('id, nombre')
          .eq('hogar_id', hogarId)
          .limit(500);

      var datosParciales = respuestaListas.length == 500;

      final nombresListas = <String, String>{};

      for (final dato in respuestaListas) {
        final id = dato['id']?.toString();

        if (id == null) continue;

        nombresListas[id] = dato['nombre']?.toString() ?? 'Lista de compras';
      }

      if (nombresListas.isEmpty) {
        if (!mounted) return;

        setState(() {
          _compras = [];
          _datosParciales = datosParciales;
          _cargando = false;
        });

        return;
      }

      // -------------------------------------------------
      // 2. PRODUCTOS MARCADOS COMO COMPRADOS
      // -------------------------------------------------

      final idsListas = nombresListas.keys.toList();

      final productos = <Map<String, dynamic>>[];

      const tamanoLote = 100;

      for (var inicio = 0; inicio < idsListas.length; inicio += tamanoLote) {
        final fin = inicio + tamanoLote < idsListas.length
            ? inicio + tamanoLote
            : idsListas.length;

        final lote = idsListas.sublist(inicio, fin);

        final respuesta = await _supabase
            .from('lista_compra_item')
            .select(
              'id, lista_id, alimento_id, '
              'cantidad, unidad, estado, '
              'despensa_item_id, fecha_compra, '
              'precio_compra_clp',
            )
            .inFilter('lista_id', lote)
            .eq('estado', 'COMPRADO')
            .limit(1000);

        if (respuesta.length == 1000) {
          datosParciales = true;
        }

        productos.addAll(
          respuesta.map((dato) => Map<String, dynamic>.from(dato)),
        );
      }

      // Solo consideramos compras confirmadas
      // que quedaron vinculadas a la despensa.
      final confirmados = productos
          .where((producto) => producto['despensa_item_id'] != null)
          .toList();

      if (confirmados.isEmpty) {
        if (!mounted) return;

        setState(() {
          _compras = [];
          _datosParciales = datosParciales;
          _cargando = false;
        });

        return;
      }

      // -------------------------------------------------
      // 3. CONSULTAR INGRESOS VINCULADOS
      // -------------------------------------------------

      // Se utilizan únicamente como respaldo
      // de compras anteriores al nuevo trigger.
      final idsDespensa = confirmados
          .map((producto) => producto['despensa_item_id'].toString())
          .toSet()
          .toList();

      final despensaPorId = <String, Map<String, dynamic>>{};

      for (var inicio = 0; inicio < idsDespensa.length; inicio += tamanoLote) {
        final fin = inicio + tamanoLote < idsDespensa.length
            ? inicio + tamanoLote
            : idsDespensa.length;

        final lote = idsDespensa.sublist(inicio, fin);

        final respuesta = await _supabase
            .from('despensa_item')
            .select('id, precio_clp, fecha_ingreso')
            .eq('hogar_id', hogarId)
            .inFilter('id', lote);

        for (final dato in respuesta) {
          final id = dato['id']?.toString();

          if (id != null) {
            despensaPorId[id] = Map<String, dynamic>.from(dato);
          }
        }
      }

      // -------------------------------------------------
      // 4. CONSULTAR NOMBRES DE ALIMENTOS
      // -------------------------------------------------

      final idsAlimentos = confirmados
          .map((producto) => (producto['alimento_id'] as num).toInt())
          .toSet()
          .toList();

      final nombresAlimentos = <int, String>{};

      for (var inicio = 0; inicio < idsAlimentos.length; inicio += tamanoLote) {
        final fin = inicio + tamanoLote < idsAlimentos.length
            ? inicio + tamanoLote
            : idsAlimentos.length;

        final lote = idsAlimentos.sublist(inicio, fin);

        final respuesta = await _supabase
            .from('alimento')
            .select('id, nombre')
            .inFilter('id', lote);

        for (final dato in respuesta) {
          final id = (dato['id'] as num).toInt();

          nombresAlimentos[id] = dato['nombre']?.toString() ?? 'Alimento #$id';
        }
      }

      // -------------------------------------------------
      // 5. CONSTRUIR HISTORIAL
      // -------------------------------------------------

      final compras = <_CompraHistorial>[];

      for (final producto in confirmados) {
        final idDespensa = producto['despensa_item_id'].toString();

        final ingreso = despensaPorId[idDespensa];

        // Si el ingreso no es visible para el
        // hogar actual, no lo incluimos.
        if (ingreso == null) {
          continue;
        }

        final alimentoId = (producto['alimento_id'] as num).toInt();

        final listaId = producto['lista_id']?.toString() ?? '';

        final fechaGuardada = _fechaExacta(producto['fecha_compra']);

        final fechaEsReferencial = fechaGuardada == null;

        final fecha =
            fechaGuardada ?? _fechaReferencial(ingreso['fecha_ingreso']);

        final precioGuardado = producto['precio_compra_clp'];

        final precioEsReferencial = fechaGuardada == null;

        final precioValor = precioEsReferencial
            ? ingreso['precio_clp']
            : precioGuardado;

        int? precio;

        if (precioValor is num) {
          precio = precioValor.toInt();
        } else if (precioValor != null) {
          precio = int.tryParse(precioValor.toString());
        }

        compras.add(
          _CompraHistorial(
            id: producto['id'].toString(),
            nombreAlimento:
                nombresAlimentos[alimentoId] ?? 'Alimento #$alimentoId',
            nombreLista: nombresListas[listaId] ?? 'Lista de compras',
            unidad: producto['unidad']?.toString() ?? 'un',
            cantidad: _numero(producto['cantidad']),
            fecha: fecha,
            fechaReferencial: fechaEsReferencial,
            precio: precio,
            precioReferencial: precioEsReferencial,
          ),
        );
      }

      // -------------------------------------------------
      // 6. ORDEN CRONOLÓGICO DESCENDENTE
      // -------------------------------------------------

      compras.sort((a, b) {
        if (a.fecha == null && b.fecha == null) {
          return a.nombreAlimento.compareTo(b.nombreAlimento);
        }

        if (a.fecha == null) return 1;
        if (b.fecha == null) return -1;

        final comparacion = b.fecha!.compareTo(a.fecha!);

        if (comparacion != 0) {
          return comparacion;
        }

        return a.nombreAlimento.compareTo(b.nombreAlimento);
      });

      if (!mounted) return;

      setState(() {
        _compras = compras;
        _datosParciales = datosParciales;
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
  // BÚSQUEDA
  // =====================================================

  List<_CompraHistorial> _comprasVisibles() {
    final consulta = _busqueda.trim().toLowerCase();

    if (consulta.isEmpty) {
      return _compras;
    }

    return _compras.where((compra) {
      return compra.nombreAlimento.toLowerCase().contains(consulta) ||
          compra.nombreLista.toLowerCase().contains(consulta);
    }).toList();
  }

  // =====================================================
  // TARJETA RESUMEN
  // =====================================================

  Widget _resumen() {
    final comprasConPrecio = _compras
        .where((compra) => compra.precio != null)
        .toList();

    final comprasSinPrecio = _compras.length - comprasConPrecio.length;

    final preciosReferenciales = comprasConPrecio
        .where((compra) => compra.precioReferencial)
        .length;

    final total = comprasConPrecio.fold<int>(
      0,
      (suma, compra) => suma + (compra.precio ?? 0),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _colorSuperficie,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Compras confirmadas',
            style: TextStyle(color: _colorTextoSecundario),
          ),

          const SizedBox(height: 5),

          Text(
            '${_compras.length} producto(s)',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
              color: _colorAcento,
            ),
          ),

          const SizedBox(height: 14),

          Text(
            'Suma de precios conocidos',
            style: TextStyle(color: _colorTextoSecundario),
          ),

          const SizedBox(height: 5),

          Text(
            _dinero(total),
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.bold,
              color: _colorAcento,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Incluye ${comprasConPrecio.length} '
            'compra(s) con precio. '
            '$comprasSinPrecio sin precio '
            'registrado.',
            style: TextStyle(fontSize: 12, color: _colorTextoSecundario),
          ),

          if (preciosReferenciales > 0) ...[
            const SizedBox(height: 6),

            Text(
              '$preciosReferenciales precio(s) '
              'son referenciales porque '
              'proceden del inventario actual.',
              style: TextStyle(fontSize: 12, color: _colorAdvertencia),
            ),
          ],

          if (_datosParciales) ...[
            const SizedBox(height: 10),

            Text(
              'Atención: se alcanzó un límite '
              'de consulta. El historial '
              'podría estar incompleto.',
              style: TextStyle(
                color: _colorAdvertencia,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =====================================================
  // TARJETA DE PRODUCTO COMPRADO
  // =====================================================

  Widget _tarjetaCompra(_CompraHistorial compra) {
    return Card(
      key: ValueKey(compra.id),
      color: _colorSuperficie,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
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
                  backgroundColor: _modoOscuro
                      ? Theme.of(context).colorScheme.primaryContainer
                      : const Color(0xFFE8F5EC),
                  child: Icon(
                    Icons.shopping_bag_outlined,
                    color: _modoOscuro
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : verde,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        compra.nombreAlimento,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        compra.nombreLista,
                        style: TextStyle(
                          fontSize: 12,
                          color: _colorTextoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                Text(
                  compra.precio == null
                      ? 'Sin precio'
                      : _dinero(compra.precio!),
                  style: TextStyle(
                    color: _colorAcento,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Text('Cantidad: ${_cantidadTexto(compra.cantidad, compra.unidad)}'),

            const SizedBox(height: 5),

            Text(
              'Fecha: ${_fechaTexto(compra.fecha, referencial: compra.fechaReferencial)}',
              style: TextStyle(fontSize: 13, color: _colorTexto),
            ),

            if (compra.precioReferencial && compra.precio != null) ...[
              const SizedBox(height: 6),

              Text(
                'Precio referencial tomado '
                'del ingreso al inventario.',
                style: TextStyle(fontSize: 12, color: _colorAdvertencia),
              ),
            ],

            if (compra.fechaReferencial) ...[
              const SizedBox(height: 5),

              Text(
                'Fecha referencial: corresponde '
                'al ingreso al inventario, '
                'no necesariamente a la compra.',
                style: TextStyle(fontSize: 12, color: _colorTextoSecundario),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // =====================================================
  // ENCABEZADOS DE FECHA
  // =====================================================

  Widget _encabezadoFecha(String titulo) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 10),
      child: Text(
        titulo,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: _colorAcento,
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

    final visibles = _comprasVisibles();

    // Creamos encabezados por día.
    final elementos = <Object>[];

    String? fechaAnterior;

    for (final compra in visibles) {
      final clave = _claveFecha(compra.fecha);

      if (clave != fechaAnterior) {
        elementos.add(_tituloFecha(compra.fecha));

        fechaAnterior = clave;
      }

      elementos.add(compra);
    }

    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        title: const Text('Historial de compras'),
        backgroundColor: verde,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar historial de compras',
            onPressed: _cargando ? null : _cargarCompras,
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
                      onPressed: _cargarCompras,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                // ---------------------------------
                // RESUMEN Y BÚSQUEDA
                // ---------------------------------

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
                          fontWeight: FontWeight.bold,
                          color: _colorAcento,
                        ),
                      ),

                      const SizedBox(height: 12),

                      _resumen(),

                      const SizedBox(height: 14),

                      TextField(
                        controller: _busquedaController,
                        onChanged: (valor) {
                          setState(() {
                            _busqueda = valor;
                          });
                        },
                        decoration: InputDecoration(
                          hintText:
                              'Buscar producto '
                              'o lista...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: _colorFondo,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ---------------------------------
                // LISTADO DE COMPRAS
                // ---------------------------------
                Expanded(
                  child: elementos.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Todavía no hay '
                              'compras confirmadas '
                              'que estén vinculadas '
                              'a la despensa.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: elementos.length,
                          itemBuilder: (context, indice) {
                            final elemento = elementos[indice];

                            if (elemento is String) {
                              return _encabezadoFecha(elemento);
                            }

                            return _tarjetaCompra(
                              elemento as _CompraHistorial,
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
