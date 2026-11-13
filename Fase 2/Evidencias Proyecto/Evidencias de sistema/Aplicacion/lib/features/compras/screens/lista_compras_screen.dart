import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nfc_foodtech_app/shared/widgets/acceso_hogar.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nfc_foodtech_app/features/compras/widgets/advertencia_stock.dart';
import 'package:nfc_foodtech_app/features/compras/widgets/estimacion_compra.dart';
import 'package:nfc_foodtech_app/features/compras/screens/sugerencias_compra_screen.dart';
import 'package:nfc_foodtech_app/features/compras/screens/confirmar_compra_screen.dart';
import 'package:nfc_foodtech_app/features/compras/screens/historial_compras_screen.dart';

class ListaComprasScreen extends StatefulWidget {
  final Map<String, dynamic> hogar;
  final VoidCallback? onCompraConfirmada;

  const ListaComprasScreen({
    super.key,
    required this.hogar,
    this.onCompraConfirmada,
  });

  @override
  State<ListaComprasScreen> createState() => _ListaComprasScreenState();
}

class _ListaComprasScreenState extends State<ListaComprasScreen> {
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

  Color get _colorAdvertencia =>
      _modoOscuro ? Colors.orange.shade300 : Colors.deepOrange;

  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _listas = [];
  List<Map<String, dynamic>> _items = [];

  String? _listaId;
  String? _error;
  String? _errorItems;

  bool _cargando = true;
  bool _cargandoItems = false;
  bool _procesando = false;

  EstimacionGasto? _estimacion;
  bool _cargandoEstimacion = false;
  bool _errorEstimacion = false;
  int _versionCargaItems = 0;

  String get _hogarId {
    return widget.hogar['id']?.toString() ?? '';
  }

  @override
  void initState() {
    super.initState();
    _cargarListas();
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

  String _cantidadTexto(dynamic cantidad, dynamic unidad) {
    final u = unidad?.toString() ?? 'un';

    final nombreUnidad = u == 'l' ? 'L' : u;

    return '${_numeroTexto(_numero(cantidad))} $nombreUnidad';
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), behavior: SnackBarBehavior.floating),
    );
  }

  Map<String, dynamic>? get _listaActual {
    for (final lista in _listas) {
      if (lista['id']?.toString() == _listaId) {
        return lista;
      }
    }

    return null;
  }

  bool get _listaAbierta {
    return _listaActual?['estado'] == 'ABIERTA';
  }

  // =====================================================
  // CARGAR LISTAS DEL HOGAR
  // =====================================================

  Future<void> _cargarListas({String? seleccionarId}) async {
    if (!mounted) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      if (_hogarId.isEmpty) {
        throw Exception('No hay un hogar seleccionado.');
      }

      final respuesta = await _supabase
          .from('lista_compra')
          .select('id, nombre, estado, creada_en, cerrada_en')
          .eq('hogar_id', _hogarId)
          .order('creada_en', ascending: false)
          .limit(500);

      final listas = respuesta
          .map((dato) => Map<String, dynamic>.from(dato))
          .toList();

      final idPreferido = seleccionarId ?? _listaId;

      String? nuevoId;

      for (final lista in listas) {
        if (lista['id']?.toString() == idPreferido) {
          nuevoId = idPreferido;
          break;
        }
      }

      if (nuevoId == null) {
        for (final lista in listas) {
          if (lista['estado'] == 'ABIERTA') {
            nuevoId = lista['id']?.toString();
            break;
          }
        }
      }

      if (nuevoId == null && listas.isNotEmpty) {
        nuevoId = listas.first['id']?.toString();
      }

      if (!mounted) return;

      setState(() {
        _listas = listas;
        _listaId = nuevoId;
        _cargando = false;
      });

      await _cargarItems();
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
  // CARGAR PRODUCTOS DE LA LISTA
  // =====================================================

  Future<void> _cargarItems() async {
    if (!mounted) return;

    final listaIdConsultada = _listaId;
    final versionActual = ++_versionCargaItems;

    if (listaIdConsultada == null) {
      setState(() {
        _items = [];
        _errorItems = null;
        _cargandoItems = false;
        _estimacion = null;
        _cargandoEstimacion = false;
        _errorEstimacion = false;
      });
      return;
    }

    setState(() {
      _cargandoItems = true;
      _errorItems = null;
      _estimacion = null;
      _cargandoEstimacion = false;
      _errorEstimacion = false;
    });

    try {
      final items = <Map<String, dynamic>>[];
      const pagina = 400;
      var desde = 0;
      while (true) {
        final respuesta = await _supabase
            .from('lista_compra_item')
            .select(
              'id, lista_id, alimento_id, cantidad, '
              'unidad, origen, estado, despensa_item_id',
            )
            .eq('lista_id', listaIdConsultada)
            .order('id')
            .range(desde, desde + pagina - 1);
        items.addAll(respuesta.map((dato) => Map<String, dynamic>.from(dato)));
        if (respuesta.length < pagina) break;
        desde += pagina;
      }

      final idsAlimentos = items
          .map((item) => (item['alimento_id'] as num).toInt())
          .toSet()
          .toList();

      final nombres = <int, String>{};
      final unidadesBase = <int, String>{};

      const tamanoLote = 100;

      for (var inicio = 0; inicio < idsAlimentos.length; inicio += tamanoLote) {
        final fin = inicio + tamanoLote < idsAlimentos.length
            ? inicio + tamanoLote
            : idsAlimentos.length;

        final lote = idsAlimentos.sublist(inicio, fin);

        final alimentos = await _supabase
            .from('alimento')
            .select('id, nombre, unidad_base, hogar_id')
            .inFilter('id', lote);

        for (final alimento in alimentos) {
          final id = (alimento['id'] as num).toInt();

          nombres[id] = alimento['nombre']?.toString() ?? 'Alimento #$id';
          final base = alimento['unidad_base']?.toString();
          if (base != null &&
              (alimento['hogar_id'] == null ||
                  alimento['hogar_id'].toString() == _hogarId)) {
            unidadesBase[id] = base;
          }
        }
      }

      for (final item in items) {
        final id = (item['alimento_id'] as num).toInt();

        item['nombre_alimento'] = nombres[id] ?? 'Alimento #$id';
      }

      items.sort((a, b) {
        final aComprado = a['estado'] == 'COMPRADO';
        final bComprado = b['estado'] == 'COMPRADO';

        if (aComprado != bComprado) {
          return aComprado ? 1 : -1;
        }

        return a['nombre_alimento'].toString().compareTo(
          b['nombre_alimento'].toString(),
        );
      });

      if (!mounted ||
          _listaId != listaIdConsultada ||
          versionActual != _versionCargaItems) {
        return;
      }

      setState(() {
        _items = items;
        _cargandoItems = false;
        _cargandoEstimacion = true;
      });

      unawaited(
        _cargarEstimacion(
          items,
          unidadesBase,
          listaIdConsultada,
          versionActual,
        ),
      );
    } on PostgrestException catch (error) {
      if (!mounted ||
          _listaId != listaIdConsultada ||
          versionActual != _versionCargaItems) {
        return;
      }

      setState(() {
        _errorItems = error.message;
        _cargandoItems = false;
      });
    } catch (error) {
      if (!mounted ||
          _listaId != listaIdConsultada ||
          versionActual != _versionCargaItems) {
        return;
      }

      setState(() {
        _errorItems = error.toString();
        _cargandoItems = false;
      });
    }
  }

  Future<void> _cargarEstimacion(
    List<Map<String, dynamic>> items,
    Map<int, String> unidadesBase,
    String listaId,
    int version,
  ) async {
    try {
      final resultado = await consultarEstimacionCompra(
        supabase: _supabase,
        hogarId: _hogarId,
        items: items,
        unidadesBase: unidadesBase,
      );
      if (!mounted || _listaId != listaId || version != _versionCargaItems)
        return;
      setState(() {
        _estimacion = resultado;
        _cargandoEstimacion = false;
      });
    } catch (error) {
      debugPrint('No se pudo estimar el gasto de la lista: $error');
      if (!mounted || _listaId != listaId || version != _versionCargaItems)
        return;
      setState(() {
        _estimacion = null;
        _errorEstimacion = true;
        _cargandoEstimacion = false;
      });
    }
  }

  // =====================================================
  // CREAR LISTA
  // =====================================================

  Future<void> _crearLista() async {
    if (_procesando) return;

    setState(() => _procesando = true);

    try {
      final nombre = await showDialog<String>(
        context: context,
        useRootNavigator: false,
        builder: (_) => const _DialogoNuevaListaCompra(),
      );
      if (nombre == null || !mounted) return;

      final usuarioId = _supabase.auth.currentUser?.id;
      if (usuarioId == null) {
        _mostrarMensaje('Debes iniciar sesión.');
        return;
      }

      if (!await AccesoHogar.verificar(context) || !mounted) return;
      final creada = await _supabase
          .from('lista_compra')
          .insert({
            'hogar_id': _hogarId,
            'nombre': nombre,
            'estado': 'ABIERTA',
            'creada_por': usuarioId,
          })
          .select('id')
          .single();

      final nuevaId = creada['id'].toString();

      await _cargarListas(seleccionarId: nuevaId);

      _mostrarMensaje('Lista creada correctamente.');
    } on PostgrestException catch (error) {
      _mostrarMensaje('No se pudo crear la lista: ${error.message}');
    } catch (error) {
      _mostrarMensaje('Error al crear la lista: $error');
    } finally {
      if (mounted) {
        setState(() {
          _procesando = false;
        });
      }
    }
  }

  // =====================================================
  // CARGAR CATÁLOGO DISPONIBLE
  // =====================================================

  Future<List<Map<String, dynamic>>> _cargarAlimentosDisponibles() async {
    // Catálogo global aprobado.
    final globales = await _supabase
        .from('alimento')
        .select('id, nombre, unidad_base')
        .eq('estado', 'APROBADO')
        .isFilter('hogar_id', null)
        .order('nombre')
        .limit(1000);

    // Alimentos personalizados del hogar.
    final locales = await _supabase
        .from('alimento')
        .select('id, nombre, unidad_base')
        .eq('hogar_id', _hogarId)
        .order('nombre')
        .limit(1000);

    final porId = <int, Map<String, dynamic>>{};

    for (final dato in [...globales, ...locales]) {
      final alimento = Map<String, dynamic>.from(dato);

      final id = (alimento['id'] as num).toInt();

      porId[id] = alimento;
    }

    final alimentos = porId.values.toList();

    alimentos.sort(
      (a, b) => a['nombre'].toString().toLowerCase().compareTo(
        b['nombre'].toString().toLowerCase(),
      ),
    );

    return alimentos;
  }

  // =====================================================
  // ADVERTENCIA DE EXISTENCIAS
  // =====================================================

  Future<bool> _confirmarProductoEnDespensa(
    int alimentoId,
    String nombre,
    dynamic cantidad,
    String unidad,
  ) {
    return confirmarStockCompra(
      context: context,
      supabase: _supabase,
      hogarId: _hogarId,
      alimentoId: alimentoId,
      nombre: nombre,
      cantidad: cantidad,
      unidad: unidad,
    );
  }

  // =====================================================
  // AGREGAR PRODUCTO A LA LISTA
  // =====================================================

  Future<void> _agregarProducto() async {
    if (_procesando || !_listaAbierta) return;

    final listaId = _listaId;

    if (listaId == null) return;

    setState(() {
      _procesando = true;
    });

    try {
      final alimentos = await _cargarAlimentosDisponibles();

      if (!mounted) return;

      if (alimentos.isEmpty) {
        _mostrarMensaje('No hay alimentos disponibles en el catálogo.');
        return;
      }

      final producto = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _FormularioProductoCompra(alimentos: alimentos),
      );

      if (producto == null || !mounted) return;

      // Evitar que una navegación de lista termine
      // guardando un ítem en otra lista.
      if (_listaId != listaId || !_listaAbierta) {
        _mostrarMensaje('La lista seleccionada cambió. Intenta de nuevo.');
        return;
      }

      final alimentoId = producto['alimento_id'] as int;

      final nombre = producto['nombre'].toString();

      final continuar = await _confirmarProductoEnDespensa(
        alimentoId,
        nombre,
        producto['cantidad'],
        producto['unidad'].toString(),
      );

      if (!continuar || !mounted) return;

      final lista = await _supabase
          .from('lista_compra')
          .select('id')
          .eq('id', listaId)
          .eq('hogar_id', _hogarId)
          .eq('estado', 'ABIERTA')
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;
      if (lista == null || _listaId != listaId || !_listaAbierta) {
        _mostrarMensaje('La lista ya no está disponible para este hogar.');
        return;
      }

      final usuarioId = _supabase.auth.currentUser?.id;

      if (usuarioId == null) {
        throw Exception('Debes iniciar sesión.');
      }

      if (!await AccesoHogar.verificar(context) || !mounted) return;
      await _supabase.from('lista_compra_item').insert({
        'lista_id': listaId,
        'alimento_id': alimentoId,
        'cantidad': producto['cantidad'],
        'unidad': producto['unidad'],
        'origen': 'MANUAL',
        'estado': 'PENDIENTE',
        'agregado_por': usuarioId,
      });

      await _cargarItems();

      _mostrarMensaje('$nombre agregado a la lista.');
    } on PostgrestException catch (error) {
      _mostrarMensaje(
        'No se pudo agregar el alimento: '
        '${error.message}',
      );
    } catch (error) {
      _mostrarMensaje('Error al agregar alimento: $error');
    } finally {
      if (mounted) {
        setState(() {
          _procesando = false;
        });
      }
    }
  }

  // =====================================================
  // MARCAR COMPRADO / PENDIENTE
  // =====================================================

  Future<void> _abrirConfirmacionCompra(Map<String, dynamic> item) async {
    if (_procesando || !_listaAbierta) return;

    final listaId = _listaId;

    if (listaId == null) return;

    // Si ya existe un ingreso vinculado,
    // nunca volvemos a registrarlo.
    if (item['despensa_item_id'] != null) {
      _mostrarMensaje('Este producto ya está ingresado en la despensa.');
      return;
    }

    setState(() {
      _procesando = true;
    });

    try {
      final confirmado = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ConfirmarCompraScreen(
            hogar: widget.hogar,
            listaId: listaId,
            item: item,
          ),
        ),
      );

      if (!mounted) return;

      if (confirmado == true) {
        widget.onCompraConfirmada?.call();
        await _cargarItems();

        if (!mounted) return;

        if (_errorItems == null) {
          _mostrarMensaje('Compra registrada en el inventario correctamente.');
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _procesando = false;
        });
      }
    }
  }

  // =====================================================
  // INTERFAZ PROVISIONAL
  // =====================================================

  Widget _selectorListas() {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey(_listaId),
            initialValue: _listaId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Lista de compras',
              border: OutlineInputBorder(),
            ),
            items: _listas.map((lista) {
              final id = lista['id'].toString();
              final nombre = lista['nombre']?.toString() ?? 'Lista';

              final estado = lista['estado']?.toString() ?? '';

              return DropdownMenuItem(
                value: id,
                child: Text(
                  '$nombre ($estado)',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: _procesando
                ? null
                : (id) {
                    if (id == null) return;

                    setState(() {
                      _listaId = id;
                      _items = [];
                    });

                    _cargarItems();
                  },
          ),
        ),

        const SizedBox(width: 8),

        IconButton.filled(
          tooltip: 'Crear nueva lista',
          onPressed: _procesando ? null : _crearLista,
          icon: const Icon(Icons.add),
          style: IconButton.styleFrom(
            backgroundColor: verde,
            foregroundColor: _modoOscuro ? Colors.white : null,
          ),
        ),
      ],
    );
  }

  Widget _tarjetaItem(Map<String, dynamic> item) {
    final nombre = item['nombre_alimento']?.toString() ?? 'Alimento';

    final estado = item['estado']?.toString() ?? '';

    final comprado = estado == 'COMPRADO';

    final tieneIngreso = item['despensa_item_id'] != null;

    final pendiente = estado == 'PENDIENTE';
    final estimacion = _estimacion?.porItem[item['id']?.toString()];

    String descripcion;

    if (comprado && tieneIngreso) {
      descripcion = 'Comprado · Ingresado a despensa';
    } else if (comprado) {
      descripcion = 'Comprado · Pendiente de ingresar a despensa';
    } else if (pendiente) {
      descripcion = 'Pendiente';
    } else {
      descripcion = 'Descartado de la lista';
    }

    return Card(
      color: _colorSuperficie,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          CheckboxListTile(
            activeColor: _colorAcento,
            value: comprado,
            onChanged: !_listaAbierta || _procesando || !pendiente
                ? null
                : (_) {
                    // Marcar comprado ahora significa
                    // confirmar su ingreso a la despensa.
                    _abrirConfirmacionCompra(item);
                  },
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              nombre,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                decoration: comprado ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: Text(
              '${_cantidadTexto(item['cantidad'], item['unidad'])} · $descripcion',
            ),
          ),

          if (pendiente)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                _cargandoEstimacion
                    ? 'Calculando estimación...'
                    : _errorEstimacion
                    ? 'Estimación no disponible'
                    : estimacion == null
                    ? 'Sin estimación'
                    : 'Estimación: ${dineroEstimadoCompra(estimacion.importeClp)}\n'
                          'Referencia: ${fechaReferenciaCompra(estimacion.fechaReferencia)}',
              ),
            ),

          // Para las compras antiguas:
          // fueron marcadas COMPRADO antes
          // de implementar la integración.
          if (comprado && !tieneIngreso && _listaAbierta)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _procesando
                      ? null
                      : () => _abrirConfirmacionCompra(item),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Ingresar a despensa'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _contenidoLista() {
    if (_cargandoItems) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorItems != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Error al cargar productos:\n$_errorItems',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _cargarItems,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Text(
          'Esta lista todavía no tiene productos.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargarItems,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: _items.length,
        itemBuilder: (context, indice) {
          return _tarjetaItem(_items[indice]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombreHogar = widget.hogar['nombre']?.toString() ?? 'Hogar';

    final pendientes = _items
        .where((item) => item['estado'] == 'PENDIENTE')
        .length;

    final comprados = _items
        .where((item) => item['estado'] == 'COMPRADO')
        .length;

    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? null
            : AccesoHogar.botonVolver(context),
        backgroundColor: verde,
        foregroundColor: Colors.white,
        title: const Text('Lista de compras'),
        actions: [
          IconButton(
            tooltip: 'Historial de compras',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => HistorialComprasScreen(hogar: widget.hogar),
                ),
              );
            },
            icon: const Icon(Icons.receipt_long_outlined),
          ),
          IconButton(
            tooltip: 'Sugerencias de compra',
            onPressed: _listaId == null || !_listaAbierta || _procesando
                ? null
                : () async {
                    if (_procesando || _listaId == null || !_listaAbierta)
                      return;
                    final listaId = _listaId!;
                    setState(() => _procesando = true);
                    try {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SugerenciasCompraScreen(
                            hogar: widget.hogar,
                            listaId: listaId,
                          ),
                        ),
                      );
                      if (!mounted) return;
                      // Recargar también las estimaciones al regresar.
                      await _cargarListas(seleccionarId: listaId);
                    } finally {
                      if (mounted) setState(() => _procesando = false);
                    }
                  },
            icon: const Icon(Icons.lightbulb_outline),
          ),
          IconButton(
            tooltip: 'Actualizar listas',
            onPressed: _procesando ? null : () => _cargarListas(),
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
                    Text(
                      'No se pudieron cargar las listas.\n$_error',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => _cargarListas(),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
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

                  const SizedBox(height: 12),

                  if (_listas.isEmpty) ...[
                    const Text(
                      'Todavía no hay listas de compras '
                      'para este hogar.',
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _procesando ? null : _crearLista,
                      icon: const Icon(Icons.add),
                      label: const Text('Crear primera lista'),
                    ),
                  ] else ...[
                    _selectorListas(),

                    const SizedBox(height: 14),

                    Text(
                      '$pendientes pendientes · '
                      '$comprados comprados',
                    ),

                    if (!_listaAbierta) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Esta lista no está abierta. '
                        'Se muestra en modo de lectura.',
                        style: TextStyle(color: _colorAdvertencia),
                      ),
                    ],

                    const SizedBox(height: 12),

                    if (!_cargandoItems && _errorItems == null) ...[
                      ResumenEstimacionCompra(
                        estimacion: _estimacion,
                        cargando: _cargandoEstimacion,
                        error: _errorEstimacion,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Expanded(child: _contenidoLista()),
                  ],
                ],
              ),
            ),
      floatingActionButton:
          !_cargando && _error == null && _listaId != null && _listaAbierta
          ? FloatingActionButton.extended(
              onPressed: _procesando ? null : _agregarProducto,
              backgroundColor: verde,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Agregar alimento'),
            )
          : null,
    );
  }
}

class _DialogoNuevaListaCompra extends StatefulWidget {
  const _DialogoNuevaListaCompra();

  @override
  State<_DialogoNuevaListaCompra> createState() =>
      _DialogoNuevaListaCompraState();
}

class _DialogoNuevaListaCompraState extends State<_DialogoNuevaListaCompra> {
  final _controlador = TextEditingController();
  bool _respondido = false;

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  void _responder({required bool crear}) {
    if (_respondido || ModalRoute.of(context)?.isCurrent != true) return;
    final nombre = _controlador.text.trim();
    if (crear && nombre.isEmpty) return;
    _respondido = true;
    Navigator.of(context).pop(crear ? nombre : null);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva lista de compras'),
      content: TextField(
        controller: _controlador,
        autofocus: true,
        maxLength: 80,
        decoration: const InputDecoration(
          labelText: 'Nombre de la lista',
          hintText: 'Ej: Compras de la semana',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _responder(crear: false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => _responder(crear: true),
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

// =====================================================
// FORMULARIO PROVISIONAL PARA AGREGAR ALIMENTOS
// =====================================================

class _FormularioProductoCompra extends StatefulWidget {
  final List<Map<String, dynamic>> alimentos;

  const _FormularioProductoCompra({required this.alimentos});

  @override
  State<_FormularioProductoCompra> createState() =>
      _FormularioProductoCompraState();
}

class _FormularioProductoCompraState extends State<_FormularioProductoCompra> {
  final _cantidadController = TextEditingController();

  Map<String, dynamic>? _alimento;
  String _busqueda = '';
  String _unidad = 'un';
  String? _error;

  @override
  void dispose() {
    _cantidadController.dispose();
    super.dispose();
  }

  List<String> _unidadesPermitidas() {
    final base = _alimento?['unidad_base']?.toString() ?? 'un';

    switch (base) {
      case 'g':
        return ['g', 'kg'];

      case 'ml':
        return ['ml', 'l'];

      default:
        return ['un'];
    }
  }

  String _nombreUnidad(String unidad) {
    return unidad == 'l' ? 'L' : unidad;
  }

  void _guardar() {
    if (_alimento == null) {
      setState(() {
        _error = 'Selecciona un alimento.';
      });
      return;
    }

    final texto = _cantidadController.text.trim().replaceAll(',', '.');

    if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(texto)) {
      setState(() {
        _error =
            'Ingresa una cantidad válida, '
            'con máximo 3 decimales.';
      });
      return;
    }

    final cantidad = double.tryParse(texto);

    if (cantidad == null ||
        !cantidad.isFinite ||
        cantidad <= 0 ||
        cantidad > 9999999.999) {
      setState(() {
        _error = 'La cantidad no es válida.';
      });
      return;
    }

    Navigator.of(context).pop({
      'alimento_id': (_alimento!['id'] as num).toInt(),
      'nombre': _alimento!['nombre'].toString(),
      'cantidad': cantidad,
      'unidad': _unidad,
    });
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final oscuro = Theme.of(context).brightness == Brightness.dark;

    final consulta = _busqueda.trim().toLowerCase();

    final visibles = widget.alimentos
        .where((alimento) {
          return alimento['nombre'].toString().toLowerCase().contains(consulta);
        })
        .take(60)
        .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Agregar a la lista',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),

              const SizedBox(height: 12),

              TextField(
                decoration: const InputDecoration(
                  labelText: 'Buscar alimento',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (valor) {
                  setState(() {
                    _busqueda = valor;
                  });
                },
              ),

              const SizedBox(height: 8),

              Expanded(
                child: ListView.builder(
                  itemCount: visibles.length,
                  itemBuilder: (context, indice) {
                    final alimento = visibles[indice];

                    final seleccionado = _alimento?['id'] == alimento['id'];

                    return ListTile(
                      dense: true,
                      title: Text(alimento['nombre'].toString()),
                      trailing: seleccionado
                          ? Icon(
                              Icons.check_circle,
                              color: oscuro
                                  ? esquema.primary
                                  : const Color(0xFF236B4A),
                            )
                          : null,
                      onTap: () {
                        setState(() {
                          _alimento = alimento;
                          _unidad = alimento['unidad_base']?.toString() ?? 'un';
                          _error = null;
                        });
                      },
                    );
                  },
                ),
              ),

              if (_alimento != null) ...[
                const Divider(),

                Text(
                  'Seleccionado: ${_alimento!['nombre']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cantidadController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Cantidad',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    SizedBox(
                      width: 110,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('${_alimento!['id']}_$_unidad'),
                        initialValue: _unidad,
                        decoration: const InputDecoration(
                          labelText: 'Unidad',
                          border: OutlineInputBorder(),
                        ),
                        items: _unidadesPermitidas().map((unidad) {
                          return DropdownMenuItem(
                            value: unidad,
                            child: Text(_nombreUnidad(unidad)),
                          );
                        }).toList(),
                        onChanged: (valor) {
                          if (valor == null) return;

                          setState(() {
                            _unidad = valor;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 8),

                Text(
                  _error!,
                  style: TextStyle(color: oscuro ? esquema.error : Colors.red),
                ),
              ],

              const SizedBox(height: 14),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _alimento == null ? null : _guardar,
                  child: const Text('Agregar a la lista'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
