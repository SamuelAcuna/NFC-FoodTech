import 'dart:async';
import 'package:nfc_foodtech_app/services/notificaciones_locales.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegistroMultipleScreen extends StatefulWidget {
  final Map<String, dynamic> hogar;
  final List<Map<String, dynamic>> alimentos;

  const RegistroMultipleScreen({
    super.key,
    required this.hogar,
    required this.alimentos,
  });

  @override
  State<RegistroMultipleScreen> createState() => _RegistroMultipleScreenState();
}

class _LineaRegistro {
  final Map<String, dynamic> alimento;

  final cantidadController = TextEditingController();
  final precioController = TextEditingController();

  late String unidadSeleccionada;

  String ubicacion = 'DESPENSA';
  DateTime? fechaManual;

  _LineaRegistro(this.alimento) {
    // Por defecto usar la unidad real del catálogo.
    // El usuario puede cambiarla a kg o L.
    unidadSeleccionada = alimento['unidad_base']?.toString() ?? 'un';
  }

  void dispose() {
    cantidadController.dispose();
    precioController.dispose();
  }
}

class _RegistroMultipleScreenState extends State<RegistroMultipleScreen> {
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

  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  late final List<_LineaRegistro> _lineas;

  bool _guardando = false;
  bool _cargandoCategorias = true;

  @override
  void initState() {
    super.initState();

    _lineas = widget.alimentos
        .map((alimento) => _LineaRegistro(alimento))
        .toList();

    _cargarUbicacionesSugeridas();
  }

  @override
  void dispose() {
    for (final linea in _lineas) {
      linea.dispose();
    }

    super.dispose();
  }

  // =====================================================
  // UNIDADES DE MEDIDA
  // =====================================================

  List<String> _unidadesPermitidas(String unidadBase) {
    switch (unidadBase) {
      case 'g':
        return ['g', 'kg'];

      case 'ml':
        return ['ml', 'L'];

      case 'un':
        return ['un'];

      default:
        return [unidadBase];
    }
  }

  String _nombreUnidad(String unidad) {
    switch (unidad) {
      case 'g':
        return 'Gramos (g)';

      case 'kg':
        return 'Kilogramos (kg)';

      case 'ml':
        return 'Mililitros (ml)';

      case 'L':
        return 'Litros (L)';

      case 'un':
        return 'Unidades (un)';

      default:
        return unidad;
    }
  }

  double? _convertirACantidadBase(_LineaRegistro linea) {
    final texto = linea.cantidadController.text.trim().replaceAll(',', '.');

    final cantidad = double.tryParse(texto);

    if (cantidad == null || !cantidad.isFinite) {
      return null;
    }

    final unidadBase = linea.alimento['unidad_base']?.toString();

    double factor;

    if (unidadBase == 'g') {
      factor = linea.unidadSeleccionada == 'kg' ? 1000 : 1;
    } else if (unidadBase == 'ml') {
      factor = linea.unidadSeleccionada == 'L' ? 1000 : 1;
    } else {
      factor = 1;
    }

    final resultado = cantidad * factor;

    if (!resultado.isFinite) return null;

    // La base utiliza numeric(10,3).
    return double.parse(resultado.toStringAsFixed(3));
  }

  String _formatearCantidad(double cantidad) {
    // Quitar ceros decimales innecesarios.
    final texto = cantidad.toStringAsFixed(3);

    return texto
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  String? _validarCantidad(String? valor, _LineaRegistro linea) {
    final texto = (valor ?? '').trim().replaceAll(',', '.');

    if (texto.isEmpty) {
      return 'Ingresa una cantidad';
    }

    final cantidad = double.tryParse(texto);

    if (cantidad == null || !cantidad.isFinite || cantidad <= 0) {
      return 'Cantidad no válida';
    }

    // Evitar más de 3 decimales en el formulario.
    final partes = texto.split('.');

    if (partes.length > 2 || (partes.length == 2 && partes[1].length > 3)) {
      return 'Máximo 3 decimales';
    }

    final cantidadBase = _convertirACantidadBase(linea);

    if (cantidadBase == null ||
        cantidadBase <= 0 ||
        cantidadBase > 9999999.999) {
      return 'La cantidad supera el límite permitido';
    }

    return null;
  }

  String? _validarPrecio(String? valor) {
    final texto = (valor ?? '').trim();

    if (texto.isEmpty) return null;

    final precio = int.tryParse(texto);

    if (precio == null || precio < 0 || precio > 2147483647) {
      return 'Precio no válido';
    }

    return null;
  }

  // =====================================================
  // UBICACIONES
  // =====================================================

  Future<void> _cargarUbicacionesSugeridas() async {
    try {
      final ids = _lineas
          .map((linea) => linea.alimento['categoria_id'])
          .whereType<num>()
          .map((id) => id.toInt())
          .toSet()
          .toList();

      if (ids.isEmpty) return;

      final respuesta = await _supabase
          .from('categoria')
          .select('id, temp_conservacion')
          .inFilter('id', ids);

      final categorias = <int, String>{};

      for (final categoria in respuesta) {
        final id = (categoria['id'] as num).toInt();

        final temperatura = categoria['temp_conservacion'] as String?;

        if (temperatura != null) {
          categorias[id] = temperatura;
        }
      }

      if (!mounted) return;

      setState(() {
        for (final linea in _lineas) {
          final categoriaId = (linea.alimento['categoria_id'] as num?)?.toInt();

          final temperatura = categorias[categoriaId];

          switch (temperatura) {
            case 'REFRIGERADO':
              linea.ubicacion = 'REFRIGERADOR';
              break;

            case 'CONGELADO':
              linea.ubicacion = 'CONGELADOR';
              break;

            default:
              linea.ubicacion = 'DESPENSA';
          }
        }
      });
    } catch (error) {
      debugPrint('Error al consultar ubicaciones: $error');
    } finally {
      if (mounted) {
        setState(() {
          _cargandoCategorias = false;
        });
      }
    }
  }

  // =====================================================
  // FECHAS OPCIONALES
  // =====================================================

  String _formatearFecha(DateTime fecha) {
    final anio = fecha.year.toString();
    final mes = fecha.month.toString().padLeft(2, '0');
    final dia = fecha.day.toString().padLeft(2, '0');

    return '$anio-$mes-$dia';
  }

  Future<void> _seleccionarFecha(_LineaRegistro linea) async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: linea.fechaManual ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Fecha indicada en el envase',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );

    if (fecha == null || !mounted) return;

    setState(() {
      linea.fechaManual = fecha;
    });
  }

  // =====================================================
  // GUARDAR ALIMENTOS
  // =====================================================

  Future<void> _guardarAlimentos() async {
    if (_guardando || _cargandoCategorias) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final hogarId = widget.hogar['id']?.toString();

    if (hogarId == null || hogarId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay un hogar seleccionado')),
      );
      return;
    }

    FocusScope.of(context).unfocus();

    final productos = _lineas.map((linea) {
      final cantidadBase = _convertirACantidadBase(linea)!;

      final precioTexto = linea.precioController.text.trim();

      final precio = precioTexto.isEmpty ? null : int.parse(precioTexto);

      return {
        'alimento_id': linea.alimento['id'],

        // Siempre se guarda en g, ml o un.
        'cantidad': cantidadBase,

        'ubicacion': linea.ubicacion,

        // Si es NULL, el trigger de Supabase
        // intentará calcular la fecha estimada.
        'fecha_vencimiento': linea.fechaManual == null
            ? null
            : _formatearFecha(linea.fechaManual!),

        'vencimiento_estimado': false,

        'precio_clp': precio,
      };
    }).toList();

    setState(() {
      _guardando = true;
    });

    try {
      final resultado = await _supabase.rpc(
        'm19_registrar_multiples',
        params: {'p_hogar_id': hogarId, 'p_items': productos},
      );

      unawaited(NotificacionesLocales.instancia.sincronizar());
      if (!mounted) return;

      debugPrint('M19: alimentos registrados: $resultado');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${productos.length} alimentos registrados'),
          backgroundColor: verde,
        ),
      );

      Navigator.pop(context, true);
    } on PostgrestException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error de Supabase: ${error.message}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo registrar: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  // =====================================================
  // TARJETA DE ALIMENTO
  // =====================================================

  Widget _construirAlimento(_LineaRegistro linea, int indice) {
    final nombre = linea.alimento['nombre']?.toString() ?? 'Alimento';

    final unidadBase = linea.alimento['unidad_base']?.toString() ?? 'un';

    final cantidadBase = _convertirACantidadBase(linea);

    final unidades = _unidadesPermitidas(unidadBase);

    return Card(
      color: _colorSuperficie,
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _colorBorde),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _modoOscuro
                      ? Theme.of(context).colorScheme.primaryContainer
                      : verde.withValues(alpha: 0.10),
                  child: Text(
                    '${indice + 1}',
                    style: TextStyle(
                      color: _modoOscuro
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : verde,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    nombre,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // CANTIDAD Y UNIDAD
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: linea.cantidadController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      hintText: 'Ej: 1',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (valor) => _validarCantidad(valor, linea),
                    onChanged: (_) {
                      setState(() {});
                    },
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: linea.unidadSeleccionada,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Unidad',
                      border: OutlineInputBorder(),
                    ),
                    items: unidades.map((unidad) {
                      return DropdownMenuItem<String>(
                        value: unidad,
                        child: Text(
                          _nombreUnidad(unidad),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      );
                    }).toList(),
                    onChanged: _guardando
                        ? null
                        : (valor) {
                            if (valor == null) return;

                            setState(() {
                              linea.unidadSeleccionada = valor;
                            });

                            _formKey.currentState?.validate();
                          },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            if (cantidadBase != null &&
                cantidadBase > 0 &&
                cantidadBase <= 9999999.999)
              Text(
                'Se guardará: '
                '${_formatearCantidad(cantidadBase)} '
                '$unidadBase',
                style: TextStyle(
                  color: _colorAcento,
                  fontWeight: FontWeight.w600,
                ),
              ),

            const SizedBox(height: 16),

            // UBICACIÓN
            DropdownButtonFormField<String>(
              key: ValueKey(
                'ubicacion_${linea.alimento['id']}_'
                '${linea.ubicacion}',
              ),
              initialValue: linea.ubicacion,
              decoration: const InputDecoration(
                labelText: 'Ubicación',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'DESPENSA', child: Text('Despensa')),
                DropdownMenuItem(
                  value: 'REFRIGERADOR',
                  child: Text('Refrigerador'),
                ),
                DropdownMenuItem(
                  value: 'CONGELADOR',
                  child: Text('Congelador'),
                ),
              ],
              onChanged: _guardando
                  ? null
                  : (valor) {
                      if (valor == null) return;

                      setState(() {
                        linea.ubicacion = valor;
                      });
                    },
            ),

            const SizedBox(height: 16),

            // FECHA OPCIONAL
            const Text(
              'Fecha de vencimiento (opcional)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 5),

            Row(
              children: [
                Expanded(
                  child: Text(
                    linea.fechaManual == null
                        ? 'Se estimará automáticamente '
                              'si existe una referencia'
                        : _formatearFecha(linea.fechaManual!),
                    style: TextStyle(
                      color: linea.fechaManual == null
                          ? _colorAcento
                          : (_modoOscuro
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.black87),
                      fontSize: 13,
                    ),
                  ),
                ),

                TextButton.icon(
                  onPressed: _guardando ? null : () => _seleccionarFecha(linea),
                  icon: const Icon(Icons.calendar_today_outlined, size: 17),
                  label: const Text('Elegir'),
                ),

                if (linea.fechaManual != null)
                  IconButton(
                    tooltip: 'Quitar fecha',
                    onPressed: _guardando
                        ? null
                        : () {
                            setState(() {
                              linea.fechaManual = null;
                            });
                          },
                    icon: const Icon(Icons.close, size: 19),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // PRECIO OPCIONAL
            TextFormField(
              controller: linea.precioController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Precio en CLP (opcional)',
                hintText: 'Ej: 1500',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
              validator: _validarPrecio,
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // PANTALLA
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        backgroundColor: verde,
        foregroundColor: Colors.white,
        title: const Text('Registrar alimentos'),
      ),
      body: _lineas.isEmpty
          ? const Center(child: Text('No se seleccionaron alimentos'))
          : Form(
              key: _formKey,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_lineas.length} '
                          'alimentos seleccionados',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 6),

                        Text(
                          'Ingresa cantidades y unidades. '
                          'Las fechas son opcionales.',
                          style: TextStyle(color: _colorTextoSecundario),
                        ),
                      ],
                    ),
                  ),

                  if (_cargandoCategorias) const LinearProgressIndicator(),

                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _lineas.length,
                      itemBuilder: (context, indice) {
                        return _construirAlimento(_lineas[indice], indice);
                      },
                    ),
                  ),

                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: verde,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _guardando || _cargandoCategorias
                              ? null
                              : _guardarAlimentos,
                          icon: _guardando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: Text(
                            _guardando
                                ? 'Guardando...'
                                : 'Guardar '
                                      '${_lineas.length} alimentos',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
