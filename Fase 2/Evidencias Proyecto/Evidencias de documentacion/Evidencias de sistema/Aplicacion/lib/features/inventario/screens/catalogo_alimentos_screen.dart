import 'package:nfc_foodtech_app/features/inventario/screens/crear_alimento_personalizado_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nfc_foodtech_app/features/inventario/screens/registro_multiple_screen.dart';

class CatalogoAlimentosScreen extends StatefulWidget {
  final Map<String, dynamic> hogar;

  const CatalogoAlimentosScreen({super.key, required this.hogar});

  @override
  State<CatalogoAlimentosScreen> createState() =>
      _CatalogoAlimentosScreenState();
}

class _CatalogoAlimentosScreenState extends State<CatalogoAlimentosScreen> {
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

  final _supabase = Supabase.instance.client;
  final _buscadorController = TextEditingController();

  final List<Map<String, dynamic>> _categorias = [];
  final List<Map<String, dynamic>> _alimentos = [];

  // La selección se conserva al cambiar de categoría.
  final Map<int, Map<String, dynamic>> _seleccionados = {};

  // Ruta de categorías: [principal, subcategoría, ...].
  final List<int> _rutaCategorias = [];

  String _busqueda = '';
  String? _error;

  bool _cargando = true;
  bool _continuando = false;

  @override
  void initState() {
    super.initState();
    _cargarCatalogo();
  }

  @override
  void dispose() {
    _buscadorController.dispose();
    super.dispose();
  }

  int _id(dynamic valor) {
    return (valor as num).toInt();
  }

  int? _idOpcional(dynamic valor) {
    if (valor == null) return null;
    return (valor as num).toInt();
  }

  String _normalizar(String texto) {
    return texto
        .toLowerCase()
        .trim()
        .replaceAll(RegExp('[áàäâ]'), 'a')
        .replaceAll(RegExp('[éèëê]'), 'e')
        .replaceAll(RegExp('[íìïî]'), 'i')
        .replaceAll(RegExp('[óòöô]'), 'o')
        .replaceAll(RegExp('[úùüû]'), 'u')
        .replaceAll('ñ', 'n');
  }

  String _nombreCategoria(int categoriaId) {
    for (final categoria in _categorias) {
      if (_id(categoria['id']) == categoriaId) {
        return categoria['nombre']?.toString() ?? 'Categoría';
      }
    }

    return 'Categoría';
  }

  Future<void> _crearAlimentoPersonalizado() async {
    if (_cargando || _continuando) return;

    final nuevoAlimento = await Navigator.of(context)
        .push<Map<String, dynamic>>(
          MaterialPageRoute(
            builder: (_) => CrearAlimentoPersonalizadoScreen(
              hogar: widget.hogar,
              categorias: _categorias,
              nombreInicial: _buscadorController.text.trim(),
              categoriaInicialId: _rutaCategorias.isEmpty
                  ? null
                  : _rutaCategorias.last,
            ),
          ),
        );

    if (!mounted || nuevoAlimento == null) return;

    final alimentoId = (nuevoAlimento['id'] as num).toInt();

    setState(() {
      // Incorporarlo al catálogo cargado.
      _alimentos.removeWhere(
        (alimento) => (alimento['id'] as num).toInt() == alimentoId,
      );

      _alimentos.add(nuevoAlimento);

      _alimentos.sort((a, b) {
        return _normalizar(
          a['nombre']?.toString() ?? '',
        ).compareTo(_normalizar(b['nombre']?.toString() ?? ''));
      });

      // Seleccionarlo automáticamente sin borrar
      // los otros alimentos ya seleccionados.
      _seleccionados[alimentoId] = nuevoAlimento;

      // Limpiar búsqueda para seguir explorando.
      _buscadorController.clear();
      _busqueda = '';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${nuevoAlimento['nombre']} creado y seleccionado',
          style: _modoOscuro ? const TextStyle(color: Colors.white) : null,
        ),
        backgroundColor: verde,
      ),
    );
  }

  Future<void> _cargarCatalogo() async {
    if (mounted) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }

    try {
      final hogarId = widget.hogar['id']?.toString();

      if (hogarId == null || hogarId.isEmpty) {
        throw Exception('No se recibió un hogar válido.');
      }

      final respuestaCategorias = await _supabase
          .from('categoria')
          .select('id, nombre, parent_id, activa')
          .eq('activa', true)
          .order('nombre');

      // Catálogo común de todos los hogares.
      final respuestaGlobales = await _supabase
          .from('alimento')
          .select(
            'id, nombre, categoria_id, unidad_base, '
            'estado, hogar_id',
          )
          .eq('activo', true)
          .eq('estado', 'APROBADO')
          .isFilter('hogar_id', null)
          .order('nombre')
          .limit(1000);

      // Alimentos propios del hogar seleccionado.
      // No se consultan alimentos privados de otros hogares.
      final respuestaLocales = await _supabase
          .from('alimento')
          .select(
            'id, nombre, categoria_id, unidad_base, '
            'estado, hogar_id',
          )
          .eq('activo', true)
          .eq('hogar_id', hogarId)
          .inFilter('estado', ['LOCAL', 'PROPUESTO', 'RECHAZADO'])
          .order('nombre')
          .limit(1000);

      if (!mounted) return;

      // Combinar por ID, evitando duplicar un mismo registro.
      final alimentosPorId = <int, Map<String, dynamic>>{};

      for (final dato in [...respuestaGlobales, ...respuestaLocales]) {
        final alimento = Map<String, dynamic>.from(dato);
        alimentosPorId[_id(alimento['id'])] = alimento;
      }

      final listaAlimentos = alimentosPorId.values.toList()
        ..sort((a, b) {
          return _normalizar(
            a['nombre']?.toString() ?? '',
          ).compareTo(_normalizar(b['nombre']?.toString() ?? ''));
        });

      setState(() {
        _categorias
          ..clear()
          ..addAll(
            respuestaCategorias.map((dato) => Map<String, dynamic>.from(dato)),
          );

        _alimentos
          ..clear()
          ..addAll(listaAlimentos);

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

  List<Map<String, dynamic>> _categoriasHijas(int? categoriaPadre) {
    final idsExistentes = _categorias
        .map((categoria) => _id(categoria['id']))
        .toSet();

    return _categorias.where((categoria) {
      final padre = _idOpcional(categoria['parent_id']);

      if (categoriaPadre == null) {
        // En la raíz mostrar categorías principales.
        // También mostrar categorías cuyo padre no esté activo.
        return padre == null || !idsExistentes.contains(padre);
      }

      return padre == categoriaPadre;
    }).toList();
  }

  List<Map<String, dynamic>> _alimentosVisibles() {
    if (_busqueda.trim().isNotEmpty) {
      final consulta = _normalizar(_busqueda);

      return _alimentos.where((alimento) {
        final nombre = _normalizar(alimento['nombre']?.toString() ?? '');

        return nombre.contains(consulta);
      }).toList();
    }

    if (_rutaCategorias.isEmpty) {
      return [];
    }

    final categoriaId = _rutaCategorias.last;

    return _alimentos.where((alimento) {
      return _idOpcional(alimento['categoria_id']) == categoriaId;
    }).toList();
  }

  void _abrirCategoria(int categoriaId) {
    setState(() {
      _rutaCategorias.add(categoriaId);
    });
  }

  void _volverCategoria() {
    if (_rutaCategorias.isEmpty) return;

    setState(() {
      _rutaCategorias.removeLast();
    });
  }

  void _alternarSeleccion(Map<String, dynamic> alimento) {
    final alimentoId = _id(alimento['id']);

    setState(() {
      if (_seleccionados.containsKey(alimentoId)) {
        _seleccionados.remove(alimentoId);
      } else {
        if (_seleccionados.length >= 50) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Puedes registrar hasta 50 alimentos a la vez.'),
            ),
          );
          return;
        }

        _seleccionados[alimentoId] = alimento;
      }
    });
  }

  Future<void> _continuarRegistro() async {
    if (_continuando || _seleccionados.isEmpty) return;

    setState(() {
      _continuando = true;
    });

    try {
      final registrados = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => RegistroMultipleScreen(
            hogar: widget.hogar,
            alimentos: _seleccionados.values.toList(),
          ),
        ),
      );

      if (!mounted) return;

      if (registrados == true) {
        // Volver al Home y comunicar el resultado.
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _continuando = false;
        });
      }
    }
  }

  IconData _iconoCategoria(String nombre) {
    final n = _normalizar(nombre);

    if (n.contains('fruta')) return Icons.apple_outlined;
    if (n.contains('verdura')) return Icons.eco_outlined;
    if (n.contains('lacteo')) return Icons.local_drink_outlined;
    if (n.contains('huevo')) return Icons.egg_outlined;
    if (n.contains('pan')) return Icons.bakery_dining_outlined;
    if (n.contains('carne')) return Icons.restaurant_outlined;
    if (n.contains('ave')) return Icons.set_meal_outlined;
    if (n.contains('pescado')) return Icons.set_meal_outlined;
    if (n.contains('bebida') || n.contains('bebestible')) {
      return Icons.local_cafe_outlined;
    }
    if (n.contains('cereal')) return Icons.grass_outlined;
    if (n.contains('conserva')) return Icons.inventory_2_outlined;
    if (n.contains('despensa')) return Icons.kitchen_outlined;
    if (n.contains('congelado')) return Icons.ac_unit_outlined;
    if (n.contains('snack')) return Icons.cookie_outlined;

    return Icons.category_outlined;
  }

  Widget _tituloSeccion(String titulo) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Text(
        titulo,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _tarjetaCategoria(Map<String, dynamic> categoria) {
    final nombre = categoria['nombre']?.toString() ?? '';
    final categoriaId = _id(categoria['id']);

    return InkWell(
      onTap: () => _abrirCategoria(categoriaId),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _colorSuperficie,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _colorBorde),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_iconoCategoria(nombre), color: _colorAcento, size: 32),
            const SizedBox(height: 9),
            Text(
              nombre,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaAlimento(Map<String, dynamic> alimento) {
    final alimentoId = _id(alimento['id']);
    final seleccionado = _seleccionados.containsKey(alimentoId);

    final nombre = alimento['nombre']?.toString() ?? 'Alimento';

    final unidad = alimento['unidad_base']?.toString() ?? 'un';

    final esLocal = alimento['hogar_id'] != null;
    final colorSeleccion = _modoOscuro
        ? Theme.of(context).colorScheme.onPrimaryContainer
        : verde;

    return Card(
      key: ValueKey('alimento_$alimentoId'),
      color: seleccionado
          ? (_modoOscuro
                ? Theme.of(context).colorScheme.primaryContainer
                : const Color(0xFFE8F5EC))
          : _colorSuperficie,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: seleccionado ? _colorAcento : _colorBorde),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _alternarSeleccion(alimento),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                seleccionado ? Icons.check_circle : Icons.circle_outlined,
                color: seleccionado
                    ? colorSeleccion
                    : (_modoOscuro
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Colors.black38),
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: _modoOscuro && seleccionado
                            ? colorSeleccion
                            : null,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      esLocal
                          ? 'Alimento de tu hogar · $unidad'
                          : 'Catálogo general · $unidad',
                      style: TextStyle(
                        fontSize: 12,
                        color: _modoOscuro && seleccionado
                            ? colorSeleccion
                            : _colorTextoSecundario,
                      ),
                    ),
                  ],
                ),
              ),
              if (seleccionado) Icon(Icons.check, color: colorSeleccion),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mensajeVacio(String mensaje) {
    return Padding(
      padding: const EdgeInsets.all(26),
      child: Center(
        child: Text(
          mensaje,
          textAlign: TextAlign.center,
          style: TextStyle(color: _colorTextoSecundario),
        ),
      ),
    );
  }

  Widget _construirCatalogo() {
    final buscando = _busqueda.trim().isNotEmpty;

    final categoriaActual = _rutaCategorias.isEmpty
        ? null
        : _rutaCategorias.last;

    final categoriasHijas = buscando
        ? <Map<String, dynamic>>[]
        : _categoriasHijas(categoriaActual);

    final alimentos = _alimentosVisibles();

    return CustomScrollView(
      slivers: [
        if (buscando)
          SliverToBoxAdapter(
            child: _tituloSeccion('Resultados (${alimentos.length})'),
          )
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  if (_rutaCategorias.isNotEmpty)
                    IconButton(
                      tooltip: 'Volver a categorías',
                      onPressed: _volverCategoria,
                      icon: const Icon(Icons.arrow_back),
                    ),
                  Expanded(
                    child: Text(
                      categoriaActual == null
                          ? 'Explora las categorías'
                          : _nombreCategoria(categoriaActual),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (categoriasHijas.isNotEmpty)
            SliverToBoxAdapter(
              child: _tituloSeccion(
                categoriaActual == null ? 'Categorías' : 'Subcategorías',
              ),
            ),
          if (categoriasHijas.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final ancho = constraints.crossAxisExtent;

                  final columnas = ancho >= 680
                      ? 4
                      : ancho >= 420
                      ? 3
                      : 2;

                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columnas,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.35,
                    ),
                    delegate: SliverChildBuilderDelegate((context, indice) {
                      return _tarjetaCategoria(categoriasHijas[indice]);
                    }, childCount: categoriasHijas.length),
                  );
                },
              ),
            ),
          if (categoriaActual != null)
            SliverToBoxAdapter(child: _tituloSeccion('Alimentos')),
        ],

        if (alimentos.isNotEmpty)
          SliverList(
            delegate: SliverChildBuilderDelegate((context, indice) {
              return _tarjetaAlimento(alimentos[indice]);
            }, childCount: alimentos.length),
          )
        else if (buscando)
          SliverToBoxAdapter(
            child: _mensajeVacio('No encontramos alimentos con ese nombre.'),
          )
        else if (categoriaActual != null && categoriasHijas.isEmpty)
          SliverToBoxAdapter(
            child: _mensajeVacio('Esta categoría todavía no tiene alimentos.'),
          ),

        // NUEVO: Botón para crear alimento personalizado
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: OutlinedButton.icon(
              onPressed: _crearAlimentoPersonalizado,
              icon: const Icon(Icons.add_circle_outline),
              label: Text(
                buscando
                    ? 'Crear "${_busqueda.trim()}"'
                    : 'Crear alimento personalizado',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _colorAcento,
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 12,
                ),
                side: BorderSide(color: _colorAcento),
              ),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _barraSeleccionados() {
    final alimentos = _seleccionados.values.toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: _colorSuperficie,
        border: Border(top: BorderSide(color: _colorBorde)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${alimentos.length} alimentos seleccionados',
              style: TextStyle(fontWeight: FontWeight.bold, color: _colorAcento),
            ),

            if (alimentos.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 39,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: alimentos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, indice) {
                    final alimento = alimentos[indice];

                    return InputChip(
                      label: Text(alimento['nombre']?.toString() ?? 'Alimento'),
                      onDeleted: () => _alternarSeleccion(alimento),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      visualDensity: VisualDensity.compact,
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: alimentos.isEmpty || _continuando
                    ? null
                    : _continuarRegistro,
                style: ElevatedButton.styleFrom(
                  backgroundColor: verde,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.arrow_forward),
                label: Text(
                  alimentos.isEmpty
                      ? 'Selecciona alimentos'
                      : 'Continuar con ${alimentos.length} alimentos',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombreHogar = widget.hogar['nombre']?.toString() ?? 'Hogar';

    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        backgroundColor: verde,
        foregroundColor: Colors.white,
        title: const Text('Catálogo de alimentos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar catálogo',
            onPressed: _cargando ? null : _cargarCatalogo,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: _colorSuperficie,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registrando en: $nombreHogar',
                  style: TextStyle(
                    color: _colorAcento,
                    fontWeight: FontWeight.w600,
                  ),
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
                    hintText: 'Buscar alimento...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _busqueda.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpiar búsqueda',
                            onPressed: () {
                              _buscadorController.clear();
                              setState(() {
                                _busqueda = '';
                              });
                            },
                            icon: const Icon(Icons.close),
                          ),
                    filled: true,
                    fillColor: _colorFondo,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
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
                            color: _modoOscuro
                                ? Theme.of(context).colorScheme.error
                                : Colors.red,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No se pudo cargar el catálogo.\n$_error',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _cargarCatalogo,
                            child: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _construirCatalogo(),
          ),
          if (!_cargando && _error == null) _barraSeleccionados(),
        ],
      ),
    );
  }
}
