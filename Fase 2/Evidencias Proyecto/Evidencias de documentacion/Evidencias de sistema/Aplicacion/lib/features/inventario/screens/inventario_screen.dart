import 'package:flutter/material.dart';
import 'package:nfc_foodtech_app/shared/widgets/acceso_hogar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nfc_foodtech_app/features/inventario/screens/historial_movimientos_screen.dart';
import 'package:nfc_foodtech_app/features/inventario/screens/movimiento_alimento_screen.dart';
import 'package:nfc_foodtech_app/features/indicadores/screens/indicadores_screen.dart';
import 'package:nfc_foodtech_app/features/compras/screens/lista_compras_screen.dart';
import 'package:nfc_foodtech_app/features/alertas/screens/alertas_caducidad_screen.dart';
import 'package:nfc_foodtech_app/features/inventario/screens/editar_item_inventario_screen.dart';
import 'package:nfc_foodtech_app/features/inventario/widgets/reposicion_automatica.dart';

// =====================================================
// MODELO VISUAL DE AGRUPACIÓN
// =====================================================

class _GrupoInventario {
  final int alimentoId;
  final String nombre;
  final String unidadBase;
  final String categoria;
  final List<Map<String, dynamic>> registros;

  _GrupoInventario({
    required this.alimentoId,
    required this.nombre,
    required this.unidadBase,
    required this.categoria,
    required this.registros,
  });

  double get cantidadTotal {
    return registros.fold<double>(0, (total, registro) {
      final valor = registro['cantidad_restante'];

      final cantidad = valor is num
          ? valor.toDouble()
          : double.tryParse(valor?.toString() ?? '') ?? 0;

      return total + cantidad;
    });
  }
}

// =====================================================
// PANTALLA INVENTARIO
// =====================================================

class InventarioScreen extends StatefulWidget {
  final Map<String, dynamic> hogar;
  final VoidCallback? onDatosActualizados;

  const InventarioScreen({
    super.key,
    required this.hogar,
    this.onDatosActualizados,
  });

  @override
  State<InventarioScreen> createState() => InventarioScreenState();
}

class InventarioScreenState extends State<InventarioScreen> {
  Future<void> actualizarDatos() => _cargarInventario(verificarAcceso: true);
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

  Color get _colorNeutro => _modoOscuro
      ? Theme.of(context).colorScheme.onSurfaceVariant
      : Colors.blueGrey;

  final _supabase = Supabase.instance.client;
  final _busquedaController = TextEditingController();

  List<_GrupoInventario> _grupos = [];

  bool _cargando = true;
  String? _error;

  // =====================================================
  // R33: FILTROS
  // =====================================================

  String _busqueda = '';
  String _filtroCategoria = 'TODAS';
  String _filtroUbicacion = 'TODAS';
  String _filtroEstado = 'DISPONIBLE';

  // =====================================================
  // R34: ORDENAMIENTO
  // =====================================================

  String _ordenInventario = 'CADUCIDAD';

  // =====================================================
  // R35: AGRUPACIÓN POR UBICACIÓN
  // =====================================================

  bool _agruparPorUbicacion = false;
  bool _abriendoListaCompras = false;

  static const List<String> _ubicaciones = [
    'DESPENSA',
    'REFRIGERADOR',
    'CONGELADOR',
  ];

  @override
  void initState() {
    super.initState();
    _cargarInventario();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  // =====================================================
  // CONVERSIONES Y FORMATO DE CANTIDADES
  // =====================================================

  double _numero(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  String _quitarCeros(String valor) {
    return valor
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  String _formatearCantidad(double cantidad, String unidadBase) {
    if (unidadBase == 'g' && cantidad >= 1000) {
      return '${_quitarCeros((cantidad / 1000).toStringAsFixed(6))} kg';
    }

    if (unidadBase == 'ml' && cantidad >= 1000) {
      return '${_quitarCeros((cantidad / 1000).toStringAsFixed(6))} L';
    }

    return '${_quitarCeros(cantidad.toStringAsFixed(3))} $unidadBase';
  }

  // =====================================================
  // FECHAS
  // =====================================================

  DateTime? _fecha(dynamic valor) {
    if (valor == null) return null;

    final fecha = DateTime.tryParse(valor.toString());

    if (fecha == null) return null;

    return DateTime.utc(fecha.year, fecha.month, fecha.day);
  }

  DateTime _hoy() {
    final ahora = DateTime.now();

    return DateTime.utc(ahora.year, ahora.month, ahora.day);
  }

  int? _diasRestantes(dynamic fechaValor) {
    final fecha = _fecha(fechaValor);

    if (fecha == null) return null;

    return fecha.difference(_hoy()).inDays;
  }

  String _fechaFormateada(dynamic valor) {
    final fecha = _fecha(valor);

    if (fecha == null) return 'Sin fecha';

    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year}';
  }

  String _estadoFecha(dynamic valor) {
    final dias = _diasRestantes(valor);

    if (dias == null) {
      return 'Sin fecha referencial';
    }

    if (dias < 0) {
      return 'Fecha pasada';
    }

    if (dias == 0) {
      return 'Fecha para hoy';
    }

    if (dias <= 3) {
      return 'Próximo: $dias día(s)';
    }

    return 'Faltan $dias días';
  }

  Color _colorFecha(dynamic valor) {
    final dias = _diasRestantes(valor);

    if (dias == null) {
      return _colorNeutro;
    }

    if (dias < 0) {
      return _modoOscuro
          ? Theme.of(context).colorScheme.error
          : Colors.red.shade700;
    }

    if (dias <= 3) {
      return _modoOscuro ? Colors.orange.shade300 : Colors.orange.shade800;
    }

    return _colorAcento;
  }

  DateTime? _fechaMasProxima(_GrupoInventario grupo) {
    DateTime? proxima;

    for (final registro in grupo.registros) {
      final fecha = _fecha(registro['fecha_vencimiento']);

      if (fecha == null) continue;

      if (proxima == null || fecha.isBefore(proxima)) {
        proxima = fecha;
      }
    }

    return proxima;
  }

  DateTime? _fechaIngresoGrupo(_GrupoInventario grupo) {
    DateTime? fechaMasAntigua;

    for (final registro in grupo.registros) {
      final fecha = _fecha(registro['fecha_ingreso']);

      if (fecha == null) continue;

      if (fechaMasAntigua == null || fecha.isBefore(fechaMasAntigua)) {
        fechaMasAntigua = fecha;
      }
    }

    return fechaMasAntigua;
  }

  int _compararFechas(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;

    return a.compareTo(b);
  }

  // =====================================================
  // NOMBRES Y ESTADOS
  // =====================================================

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

  String _nombreEstado(dynamic valor) {
    switch (valor?.toString()) {
      case 'DISPONIBLE':
        return 'Disponible';

      case 'AGOTADO':
        return 'Agotado';

      case 'DESECHADO':
        return 'Desechado';

      default:
        return 'Sin estado';
    }
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'DISPONIBLE':
        return _colorAcento;

      case 'AGOTADO':
        return _colorNeutro;

      case 'DESECHADO':
        return _modoOscuro
            ? Theme.of(context).colorScheme.error
            : Colors.red.shade700;

      default:
        return _modoOscuro
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : Colors.grey;
    }
  }

  IconData _iconoUbicacion(String ubicacion) {
    switch (ubicacion) {
      case 'REFRIGERADOR':
        return Icons.kitchen_outlined;

      case 'CONGELADOR':
        return Icons.ac_unit;

      default:
        return Icons.inventory_2_outlined;
    }
  }

  // =====================================================
  // CONSULTAR INVENTARIO EN SUPABASE
  // =====================================================

  Future<void> _cargarInventario({bool verificarAcceso = false}) async {
    if (verificarAcceso && (!await AccesoHogar.verificar(context) || !mounted))
      return;
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

      // Traemos todos los estados para permitir R33.
      // El filtro inicial sigue siendo DISPONIBLE.
      final respuestaInventario = await _supabase
          .from('despensa_item')
          .select(
            'id, alimento_id, cantidad_inicial, '
            'cantidad_restante, fecha_ingreso, '
            'fecha_vencimiento, vencimiento_estimado, '
            'ubicacion, estado, precio_clp, observaciones, '
            'fecha_inicio_congelacion, fecha_previa_congelacion',
          )
          .eq('hogar_id', hogarId)
          .limit(1000);

      final registros = respuestaInventario
          .map((dato) => Map<String, dynamic>.from(dato))
          .toList();

      // -------------------------------------------------
      // OBTENER ALIMENTOS
      // -------------------------------------------------

      final idsAlimentos = registros
          .map((dato) => (dato['alimento_id'] as num).toInt())
          .toSet()
          .toList();

      final alimentosPorId = <int, Map<String, dynamic>>{};

      if (idsAlimentos.isNotEmpty) {
        final respuestaAlimentos = await _supabase
            .from('alimento')
            .select('id, nombre, unidad_base, categoria_id')
            .inFilter('id', idsAlimentos);

        for (final dato in respuestaAlimentos) {
          final alimento = Map<String, dynamic>.from(dato);

          final id = (alimento['id'] as num).toInt();

          alimentosPorId[id] = alimento;
        }
      }

      // -------------------------------------------------
      // R33: OBTENER CATEGORÍAS
      // -------------------------------------------------

      final categoriasPorId = <int, String>{};

      final idsCategorias = alimentosPorId.values
          .map((alimento) => alimento['categoria_id'])
          .where((id) => id != null)
          .map((id) => (id as num).toInt())
          .toSet()
          .toList();

      if (idsCategorias.isNotEmpty) {
        final respuestaCategorias = await _supabase
            .from('categoria')
            .select('id, nombre')
            .inFilter('id', idsCategorias);

        for (final dato in respuestaCategorias) {
          final id = (dato['id'] as num).toInt();

          categoriasPorId[id] = dato['nombre']?.toString() ?? 'Sin categoría';
        }
      }

      // -------------------------------------------------
      // AGRUPAR POR ALIMENTO
      // -------------------------------------------------

      final registrosAgrupados = <int, List<Map<String, dynamic>>>{};

      for (final registro in registros) {
        final alimentoId = (registro['alimento_id'] as num).toInt();

        registrosAgrupados
            .putIfAbsent(alimentoId, () => <Map<String, dynamic>>[])
            .add(registro);
      }

      final grupos = <_GrupoInventario>[];

      for (final entrada in registrosAgrupados.entries) {
        final alimentoId = entrada.key;
        final alimento = alimentosPorId[alimentoId];

        final categoriaId = alimento?['categoria_id'];

        final nombreCategoria = categoriaId == null
            ? 'Sin categoría'
            : categoriasPorId[(categoriaId as num).toInt()] ?? 'Sin categoría';

        final grupo = _GrupoInventario(
          alimentoId: alimentoId,
          nombre: alimento?['nombre']?.toString() ?? 'Alimento #$alimentoId',
          unidadBase: alimento?['unidad_base']?.toString() ?? 'un',
          categoria: nombreCategoria,
          registros: entrada.value,
        );

        // FEFO visual dentro de cada grupo.
        grupo.registros.sort((a, b) {
          final fechaA = _fecha(a['fecha_vencimiento']);
          final fechaB = _fecha(b['fecha_vencimiento']);

          final comparacion = _compararFechas(fechaA, fechaB);

          if (comparacion != 0) {
            return comparacion;
          }

          return _compararFechas(
            _fecha(a['fecha_ingreso']),
            _fecha(b['fecha_ingreso']),
          );
        });

        grupos.add(grupo);
      }

      if (!mounted) return;

      setState(() {
        _grupos = grupos;
        _cargando = false;
      });
      widget.onDatosActualizados?.call();
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
  // R33: OBTENER CATEGORÍAS DISPONIBLES
  // =====================================================

  List<String> _categoriasDisponibles() {
    final categorias = _grupos.map((grupo) => grupo.categoria).toSet().toList();

    categorias.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return categorias;
  }

  // =====================================================
  // R33, R34 Y R35: APLICAR FILTROS Y ORDENAMIENTO
  // =====================================================

  List<_GrupoInventario> _obtenerGruposVisibles() {
    final consulta = _busqueda.trim().toLowerCase();

    final gruposFiltrados = <String, _GrupoInventario>{};

    // Filtrar cada ingreso individual.
    // Esto evita mostrar ingresos de otras ubicaciones
    // o estados dentro de un grupo filtrado.
    for (final grupo in _grupos) {
      if (consulta.isNotEmpty &&
          !grupo.nombre.toLowerCase().contains(consulta)) {
        continue;
      }

      if (_filtroCategoria != 'TODAS' && grupo.categoria != _filtroCategoria) {
        continue;
      }

      for (final registro in grupo.registros) {
        final ubicacion = registro['ubicacion']?.toString() ?? 'DESPENSA';

        final estado = registro['estado']?.toString() ?? 'DISPONIBLE';

        if (_filtroUbicacion != 'TODAS' && ubicacion != _filtroUbicacion) {
          continue;
        }

        if (_filtroEstado != 'TODOS' && estado != _filtroEstado) {
          continue;
        }

        // Si agrupamos por ubicación, el mismo
        // alimento puede aparecer en más de una
        // sección sin mezclar sus ingresos.
        final clave = _agruparPorUbicacion
            ? '${grupo.alimentoId}_$ubicacion'
            : '${grupo.alimentoId}';

        final grupoVisible = gruposFiltrados.putIfAbsent(
          clave,
          () => _GrupoInventario(
            alimentoId: grupo.alimentoId,
            nombre: grupo.nombre,
            unidadBase: grupo.unidadBase,
            categoria: grupo.categoria,
            registros: <Map<String, dynamic>>[],
          ),
        );

        grupoVisible.registros.add(registro);
      }
    }

    final visibles = gruposFiltrados.values.toList();

    // Ordenar los ingresos dentro de cada grupo.
    for (final grupo in visibles) {
      grupo.registros.sort((a, b) {
        if (_ordenInventario == 'INGRESO_RECIENTE') {
          return _compararFechas(
            _fecha(b['fecha_ingreso']),
            _fecha(a['fecha_ingreso']),
          );
        }

        if (_ordenInventario == 'INGRESO_ANTIGUO') {
          return _compararFechas(
            _fecha(a['fecha_ingreso']),
            _fecha(b['fecha_ingreso']),
          );
        }

        // Por defecto, el ingreso con fecha
        // referencial más próxima aparece primero.
        return _compararFechas(
          _fecha(a['fecha_vencimiento']),
          _fecha(b['fecha_vencimiento']),
        );
      });
    }

    // -------------------------------------------------
    // R34: ORDENAR GRUPOS
    // -------------------------------------------------

    visibles.sort((a, b) {
      int comparacion = 0;

      switch (_ordenInventario) {
        case 'NOMBRE':
          comparacion = a.nombre.toLowerCase().compareTo(
            b.nombre.toLowerCase(),
          );
          break;

        case 'CATEGORIA':
          comparacion = a.categoria.toLowerCase().compareTo(
            b.categoria.toLowerCase(),
          );
          break;

        case 'INGRESO_RECIENTE':
          comparacion = _compararFechas(
            _fechaIngresoGrupo(b),
            _fechaIngresoGrupo(a),
          );
          break;

        case 'INGRESO_ANTIGUO':
          comparacion = _compararFechas(
            _fechaIngresoGrupo(a),
            _fechaIngresoGrupo(b),
          );
          break;

        case 'CADUCIDAD':
        default:
          comparacion = _compararFechas(
            _fechaMasProxima(a),
            _fechaMasProxima(b),
          );
          break;
      }

      if (comparacion != 0) {
        return comparacion;
      }

      return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });

    return visibles;
  }

  // =====================================================
  // R33: LIMPIAR FILTROS
  // =====================================================

  void _limpiarFiltros() {
    _busquedaController.clear();

    setState(() {
      _busqueda = '';
      _filtroCategoria = 'TODAS';
      _filtroUbicacion = 'TODAS';
      _filtroEstado = 'DISPONIBLE';
      _ordenInventario = 'CADUCIDAD';
      _agruparPorUbicacion = false;
    });
  }

  // =====================================================
  // ABRIR CONSUMO Y DESCARTE
  // =====================================================

  Future<void> _abrirListaCompras() async {
    if (_abriendoListaCompras) return;
    _abriendoListaCompras = true;
    var huboCompra = false;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ListaComprasScreen(
            hogar: widget.hogar,
            onCompraConfirmada: () => huboCompra = true,
          ),
        ),
      );
      if (mounted && huboCompra) await _cargarInventario();
    } finally {
      _abriendoListaCompras = false;
    }
  }

  Future<void> _abrirMovimiento(
    Map<String, dynamic> registro,
    String unidadBase,
    String nombreAlimento,
  ) async {
    final resultado = await Navigator.of(context)
        .push<ResultadoMovimientoAlimento>(
          MaterialPageRoute(
            builder: (_) => MovimientoAlimentoScreen(
              registro: registro,
              hogarId: widget.hogar['id'].toString(),
              nombreAlimento: nombreAlimento,
              unidadBase: unidadBase,
            ),
          ),
        );

    if (!mounted) return;

    // También refrescar al volver de un movimiento cuyo resultado fue incierto.
    await _cargarInventario();
    if (!mounted) return;

    if (resultado?.registrado == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${resultado!.mensaje}${_error == null ? '' : ' No se pudo actualizar la vista del inventario.'}',
          ),
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // =====================================================
  // M19 - R36: EDITAR INGRESO
  // =====================================================

  Future<void> _abrirEdicion(
    Map<String, dynamic> registro,
    String unidadBase,
    String nombreAlimento,
  ) async {
    final resultado = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => EditarItemInventarioScreen(
          registro: registro,
          nombreAlimento: nombreAlimento,
          unidadBase: unidadBase,
        ),
      ),
    );

    if (!mounted) return;

    if (resultado?['actualizado'] == true) {
      await _cargarInventario();

      if (!mounted) return;

      final aviso = resultado?['aviso']?.toString();

      if (_error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              aviso != null && aviso.isNotEmpty
                  ? aviso
                  : 'Alimento actualizado correctamente.',
            ),
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // =====================================================
  // R33: CONTROLES DE FILTROS Y R34 ORDENAMIENTO
  // =====================================================

  Widget _controlesInventario() {
    final categorias = _categoriasDisponibles();

    return ExpansionTile(
      key: const PageStorageKey('filtros_inventario'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 10),
      leading: Icon(Icons.tune, color: _colorAcento),
      title: Text(
        'Filtros y ordenamiento',
        style: TextStyle(color: _colorAcento, fontWeight: FontWeight.w600),
      ),
      children: [
        // ---------------------------------------------
        // FILTRO POR CATEGORÍA
        // ---------------------------------------------

        DropdownButtonFormField<String>(
          key: const ValueKey('filtro_categoria'),
          isExpanded: true,
          initialValue: categorias.contains(_filtroCategoria)
              ? _filtroCategoria
              : 'TODAS',
          decoration: const InputDecoration(
            labelText: 'Categoría',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          items: [
            const DropdownMenuItem(
              value: 'TODAS',
              child: Text('Todas las categorías'),
            ),
            for (final categoria in categorias)
              DropdownMenuItem(
                value: categoria,
                child: Text(categoria, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (valor) {
            if (valor == null) return;

            setState(() {
              _filtroCategoria = valor;
            });
          },
        ),

        const SizedBox(height: 12),

        // ---------------------------------------------
        // FILTRO POR UBICACIÓN
        // ---------------------------------------------
        DropdownButtonFormField<String>(
          key: const ValueKey('filtro_ubicacion'),
          isExpanded: true,
          initialValue: _filtroUbicacion,
          decoration: const InputDecoration(
            labelText: 'Ubicación',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          items: const [
            DropdownMenuItem(
              value: 'TODAS',
              child: Text('Todas las ubicaciones'),
            ),
            DropdownMenuItem(value: 'DESPENSA', child: Text('Despensa')),
            DropdownMenuItem(
              value: 'REFRIGERADOR',
              child: Text('Refrigerador'),
            ),
            DropdownMenuItem(value: 'CONGELADOR', child: Text('Congelador')),
          ],
          onChanged: (valor) {
            if (valor == null) return;

            setState(() {
              _filtroUbicacion = valor;
            });
          },
        ),

        const SizedBox(height: 12),

        // ---------------------------------------------
        // FILTRO POR ESTADO
        // ---------------------------------------------
        DropdownButtonFormField<String>(
          key: const ValueKey('filtro_estado'),
          isExpanded: true,
          initialValue: _filtroEstado,
          decoration: const InputDecoration(
            labelText: 'Estado',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          items: const [
            DropdownMenuItem(value: 'DISPONIBLE', child: Text('Disponibles')),
            DropdownMenuItem(value: 'AGOTADO', child: Text('Agotados')),
            DropdownMenuItem(value: 'DESECHADO', child: Text('Desechados')),
            DropdownMenuItem(value: 'TODOS', child: Text('Todos los estados')),
          ],
          onChanged: (valor) {
            if (valor == null) return;

            setState(() {
              _filtroEstado = valor;
            });
          },
        ),

        const SizedBox(height: 12),

        // ---------------------------------------------
        // R34: ORDENAMIENTO
        // ---------------------------------------------
        DropdownButtonFormField<String>(
          key: const ValueKey('orden_inventario'),
          isExpanded: true,
          initialValue: _ordenInventario,
          decoration: const InputDecoration(
            labelText: 'Ordenar por',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          items: const [
            DropdownMenuItem(
              value: 'CADUCIDAD',
              child: Text('Caducidad más próxima'),
            ),
            DropdownMenuItem(
              value: 'NOMBRE',
              child: Text('Nombre del alimento'),
            ),
            DropdownMenuItem(value: 'CATEGORIA', child: Text('Categoría')),
            DropdownMenuItem(
              value: 'INGRESO_RECIENTE',
              child: Text('Ingreso más reciente'),
            ),
            DropdownMenuItem(
              value: 'INGRESO_ANTIGUO',
              child: Text('Ingreso más antiguo'),
            ),
          ],
          onChanged: (valor) {
            if (valor == null) return;

            setState(() {
              _ordenInventario = valor;
            });
          },
        ),

        const SizedBox(height: 14),

        // ---------------------------------------------
        // R35: AGRUPAR POR UBICACIÓN
        // ---------------------------------------------
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Agrupar por ubicación',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Separar los alimentos por despensa, '
            'refrigerador y congelador.',
          ),
          value: _agruparPorUbicacion,
          activeThumbColor: _colorAcento,
          onChanged: (valor) {
            setState(() {
              _agruparPorUbicacion = valor;
            });
          },
        ),

        const SizedBox(height: 6),

        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _limpiarFiltros,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Restablecer filtros'),
          ),
        ),
      ],
    );
  }

  // =====================================================
  // DETALLE DE CADA INGRESO
  // =====================================================

  Widget _detalleRegistro(
    Map<String, dynamic> registro,
    String unidadBase,
    int indice,
    String nombreAlimento,
  ) {
    final cantidad = _numero(registro['cantidad_restante']);

    final inicial = _numero(registro['cantidad_inicial']);

    final fecha = registro['fecha_vencimiento'];

    final esEstimada = registro['vencimiento_estimado'] == true;

    final ubicacion = registro['ubicacion']?.toString() ?? 'DESPENSA';

    final estado = registro['estado']?.toString() ?? 'DISPONIBLE';

    final estaDisponible = estado == 'DISPONIBLE' && cantidad > 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _colorFondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ingreso ${indice + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _colorAcento,
                  ),
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: _colorEstado(estado).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _nombreEstado(estado),
                  style: TextStyle(
                    color: _colorEstado(estado),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Text(
            'Cantidad restante: '
            '${_formatearCantidad(cantidad, unidadBase)}',
          ),

          Text(
            'Cantidad inicial: '
            '${_formatearCantidad(inicial, unidadBase)}',
          ),

          const SizedBox(height: 5),

          Text('Ubicación: ${_nombreUbicacion(ubicacion)}'),

          Text(
            'Fecha de ingreso: '
            '${_fechaFormateada(registro['fecha_ingreso'])}',
          ),

          const SizedBox(height: 5),

          Text(
            fecha == null
                ? 'Sin fecha de caducidad registrada'
                : '${esEstimada ? 'Fecha estimada' : 'Fecha indicada'}: '
                      '${_fechaFormateada(fecha)}',
          ),

          if (fecha != null) ...[
            const SizedBox(height: 4),

            Text(
              _estadoFecha(fecha),
              style: TextStyle(
                color: _colorFecha(fecha),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],

          if (registro['fecha_inicio_congelacion'] != null) ...[
            const SizedBox(height: 5),

            Text(
              'Congelado desde: '
              '${_fechaFormateada(registro['fecha_inicio_congelacion'])}',
              style: TextStyle(fontSize: 12, color: _colorNeutro),
            ),
          ],

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: estaDisponible
                  ? () => _abrirMovimiento(registro, unidadBase, nombreAlimento)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: verde,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.restaurant_outlined),
              label: const Text('Consumir o descartar'),
            ),
          ),

          const SizedBox(height: 8),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: estaDisponible
                  ? () => _abrirEdicion(registro, unidadBase, nombreAlimento)
                  : null,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar ingreso'),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // TARJETA DE ALIMENTO
  // =====================================================

  Widget _tarjetaGrupo(_GrupoInventario grupo) {
    final fecha = _fechaMasProxima(grupo);

    return Card(
      color: _colorSuperficie,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _colorBorde),
      ),
      child: ExpansionTile(
        key: PageStorageKey(
          'inventario_${grupo.alimentoId}_'
          '${grupo.registros.first['ubicacion']}_'
          '${_agruparPorUbicacion ? 'ubicacion' : 'normal'}',
        ),
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: _modoOscuro
              ? Theme.of(context).colorScheme.primaryContainer
              : const Color(0xFFE8F5EC),
          child: Icon(Icons.inventory_2_outlined, color: _colorAcento),
        ),
        title: Text(
          grupo.nombre,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 5),

            Text(
              grupo.categoria,
              style: TextStyle(fontSize: 12, color: _colorTextoSecundario),
            ),

            Text(
              '${_formatearCantidad(grupo.cantidadTotal, grupo.unidadBase)} restantes',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: _colorAcento,
              ),
            ),

            Text(
              '${grupo.registros.length} ingreso(s)',
              style: TextStyle(fontSize: 12, color: _colorTextoSecundario),
            ),

            if (fecha != null)
              Text(
                'Fecha más próxima: '
                '${_fechaFormateada(fecha)}',
                style: TextStyle(fontSize: 12, color: _colorFecha(fecha)),
              ),
          ],
        ),
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Registros separados por ingreso',
                style: TextStyle(color: _colorTextoSecundario, fontSize: 12),
              ),
            ),
          ),

          for (var indice = 0; indice < grupo.registros.length; indice++)
            _detalleRegistro(
              grupo.registros[indice],
              grupo.unidadBase,
              indice,
              grupo.nombre,
            ),
        ],
      ),
    );
  }

  // =====================================================
  // R35: ENCABEZADO DE UBICACIÓN
  // =====================================================

  Widget _encabezadoUbicacion(String ubicacion) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Row(
        children: [
          Icon(_iconoUbicacion(ubicacion), color: _colorAcento),

          const SizedBox(width: 10),

          Text(
            _nombreUbicacion(ubicacion),
            style: TextStyle(
              color: _colorAcento,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(child: Divider(color: _colorBorde)),
        ],
      ),
    );
  }

  // =====================================================
  // R35: CONSTRUIR SECCIONES VISUALES
  // =====================================================

  List<Object> _construirElementos(List<_GrupoInventario> visibles) {
    if (!_agruparPorUbicacion) {
      return <Object>[...visibles];
    }

    final elementos = <Object>[];

    for (final ubicacion in _ubicaciones) {
      final gruposUbicacion = visibles
          .where(
            (grupo) => grupo.registros.any(
              (registro) => registro['ubicacion'] == ubicacion,
            ),
          )
          .toList();

      if (gruposUbicacion.isEmpty) {
        continue;
      }

      elementos.add(ubicacion);
      elementos.addAll(gruposUbicacion);
    }

    return elementos;
  }

  // =====================================================
  // PANTALLA PRINCIPAL
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final nombreHogar = widget.hogar['nombre']?.toString() ?? 'Hogar';

    final visibles = _obtenerGruposVisibles();

    final elementos = _construirElementos(visibles);

    final totalIngresos = _grupos.fold<int>(
      0,
      (total, grupo) => total + grupo.registros.length,
    );

    final ingresosVisibles = visibles.fold<int>(
      0,
      (total, grupo) => total + grupo.registros.length,
    );

    final cantidadDisponible = _grupos.fold<int>(0, (total, grupo) {
      return total +
          grupo.registros.where((registro) {
            return registro['estado'] == 'DISPONIBLE' &&
                _numero(registro['cantidad_restante']) > 0;
          }).length;
    });

    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        leading: AccesoHogar.botonVolver(context),
        backgroundColor: verde,
        foregroundColor: Colors.white,
        title: const Text('Mi inventario'),
        actions: [
          // LISTA DE COMPRAS
          IconButton(
            tooltip: 'Lista de compras',
            onPressed: _abrirListaCompras,
            icon: const Icon(Icons.shopping_cart_outlined),
          ),

          // INDICADORES
          IconButton(
            tooltip: 'Ver indicadores del hogar',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => IndicadoresScreen(hogar: widget.hogar),
                ),
              );
            },
            icon: const Icon(Icons.bar_chart_outlined),
          ),

          // HISTORIAL DE MOVIMIENTOS
          IconButton(
            tooltip: 'Ver historial de movimientos',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      HistorialMovimientosScreen(hogar: widget.hogar),
                ),
              );
            },
            icon: const Icon(Icons.history),
          ),

          // ACTUALIZAR INVENTARIO
          IconButton(
            tooltip: 'Actualizar inventario',
            onPressed: _cargando
                ? null
                : () => _cargarInventario(verificarAcceso: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: Column(
        children: [
          // =========================================
          // BUSCADOR Y FILTROS
          // =========================================

          Material(
            color: _colorSuperficie,
            child: Container(
              width: double.infinity,
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

                  const SizedBox(height: 8),

                  Text(
                    '$cantidadDisponible ingresos disponibles · '
                    '$totalIngresos ingresos registrados',
                    style: TextStyle(color: _colorTextoSecundario),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: _busquedaController,
                    onChanged: (valor) {
                      setState(() {
                        _busqueda = valor;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Buscar en mi inventario...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: _colorFondo,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // FILTROS R33, R34 Y R35
                  _controlesInventario(),

                  const SizedBox(height: 8),

                  Text(
                    'Mostrando $ingresosVisibles '
                    'de $totalIngresos ingresos',
                    style: TextStyle(
                      fontSize: 12,
                      color: _colorTextoSecundario,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // ALERTAS DE CADUCIDAD
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                AlertasCaducidadScreen(hogar: widget.hogar),
                          ),
                        );
                      },
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: const Text('Ver alertas de caducidad'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // =========================================
          // LISTADO
          // =========================================
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
                            color: _modoOscuro
                                ? Theme.of(context).colorScheme.error
                                : Colors.red,
                            size: 42,
                          ),

                          const SizedBox(height: 12),

                          Text(
                            'No se pudo cargar el inventario.\n$_error',
                            textAlign: TextAlign.center,
                          ),

                          const SizedBox(height: 12),

                          ElevatedButton(
                            onPressed: () =>
                                _cargarInventario(verificarAcceso: true),
                            child: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  )
                : elementos.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _grupos.isEmpty
                            ? 'Tu inventario está vacío.\n'
                                  'Registra alimentos desde el catálogo.'
                            : 'No hay ingresos que coincidan '
                                  'con los filtros seleccionados.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _colorTextoSecundario),
                      ),
                    ),
                  )
                : ListView.builder(
                    key: const PageStorageKey('inventario_listado'),
                    padding: const EdgeInsets.only(top: 8, bottom: 20),
                    itemCount: elementos.length,
                    itemBuilder: (context, indice) {
                      final elemento = elementos[indice];

                      if (elemento is String) {
                        return _encabezadoUbicacion(elemento);
                      }

                      return _tarjetaGrupo(elemento as _GrupoInventario);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
