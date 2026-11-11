import 'package:flutter/material.dart';
import 'package:nfc_foodtech_app/shared/widgets/acceso_hogar.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nfc_foodtech_app/features/compras/widgets/advertencia_stock.dart';
import 'package:nfc_foodtech_app/shared/widgets/sugerencias_compra.dart';

class SugerenciasCompraScreen extends StatefulWidget {
  final Map<String, dynamic> hogar;
  final String listaId;

  const SugerenciasCompraScreen({
    super.key,
    required this.hogar,
    required this.listaId,
  });

  @override
  State<SugerenciasCompraScreen> createState() =>
      _SugerenciasCompraScreenState();
}

class _SugerenciasCompraScreenState extends State<SugerenciasCompraScreen> {
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

  Color get _colorTextoSecundario => _modoOscuro
      ? Theme.of(context).colorScheme.onSurfaceVariant
      : Colors.black54;

  Color get _colorBorde => _modoOscuro
      ? Theme.of(context).colorScheme.outlineVariant
      : const Color(0xFFDCE8DE);

  Color get _colorError =>
      _modoOscuro ? Theme.of(context).colorScheme.error : Colors.red;

  static const int periodoDias = periodoHistorialSugerencias;

  final _supabase = Supabase.instance.client;

  List<SugerenciaCompra> _sugerencias = [];

  final Set<int> _ocultadas = {};

  bool _cargando = true;
  String? _error;
  int? _guardandoAlimentoId;
  int _versionCarga = 0;
  bool _hayDatosNoVerificables = false;
  final Set<int> _enviosInciertos = {};

  String get _hogarId => widget.hogar['id']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _cargarSugerencias();
  }

  // =====================================================
  // CANTIDADES Y UNIDADES
  // =====================================================

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

  List<String> _unidadesPermitidas(String base) {
    switch (base) {
      case 'g':
        return ['g', 'kg'];

      case 'ml':
        return ['ml', 'l'];

      default:
        return ['un'];
    }
  }

  double _factorUnidad(String unidad) {
    return unidad == 'kg' || unidad == 'l' ? 1000 : 1;
  }

  String _etiquetaUnidad(String unidad) {
    return unidad == 'l' ? 'L' : unidad;
  }

  void _mensaje(String texto) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), behavior: SnackBarBehavior.floating),
    );
  }

  // =====================================================
  // CARGAR SUGERENCIAS
  // =====================================================

  Future<void> _cargarSugerencias() async {
    if (!mounted || _guardandoAlimentoId != null) return;
    final version = ++_versionCarga;
    final usuarioId = _supabase.auth.currentUser?.id;
    setState(() {
      _cargando = true;
      _error = null;
      _ocultadas.clear();
    });
    try {
      final resultado = await consultarSugerenciasCompra(
        supabase: _supabase,
        hogarId: _hogarId,
        listaId: widget.listaId,
      );
      if (!mounted ||
          version != _versionCarga ||
          _supabase.auth.currentUser?.id != usuarioId)
        return;
      setState(() {
        _sugerencias = resultado.sugerencias;
        _hayDatosNoVerificables = resultado.registrosInvalidos > 0;
        _enviosInciertos.removeAll(resultado.pendientes);
        _cargando = false;
      });
    } catch (error) {
      if (!mounted || version != _versionCarga) return;
      setState(() {
        _error = error.toString();
        _cargando = false;
      });
    }
  }

  void _actualizarSugerencia(
    int alimentoId,
    ResultadoSugerenciasCompra resultado,
  ) {
    if (!mounted) return;
    setState(() {
      _sugerencias = [
        ..._sugerencias.where((dato) => dato.alimentoId != alimentoId),
        ...resultado.sugerencias,
      ]..sort(compararSugerenciasCompra);
      _hayDatosNoVerificables =
          _hayDatosNoVerificables || resultado.registrosInvalidos > 0;
    });
  }

  @override
  void dispose() {
    _versionCarga++;
    super.dispose();
  }

  // =====================================================
  // CONFIRMAR CANTIDAD SUGERIDA
  // =====================================================

  Future<Map<String, dynamic>?> _pedirCantidad(
    SugerenciaCompra sugerencia,
  ) async {
    final controlador = TextEditingController(
      text: _numeroTexto(sugerencia.sugerido),
    );

    String unidad = sugerencia.unidadBase;
    String? error;
    var respondido = false;

    final dialogo = DialogRoute<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, actualizarDialogo) {
            return AlertDialog(
              title: Text('Agregar ${sugerencia.nombre}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Puedes modificar la cantidad '
                    'antes de agregar el alimento '
                    'a la lista.',
                  ),

                  const SizedBox(height: 16),

                  TextField(
                    controller: controlador,
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

                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    key: ValueKey(unidad),
                    initialValue: unidad,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Unidad',
                      border: OutlineInputBorder(),
                    ),
                    items: _unidadesPermitidas(sugerencia.unidadBase).map((
                      valor,
                    ) {
                      return DropdownMenuItem<String>(
                        value: valor,
                        child: Text(_etiquetaUnidad(valor)),
                      );
                    }).toList(),
                    onChanged: (nuevaUnidad) {
                      if (nuevaUnidad == null) return;

                      final cantidadActual = double.tryParse(
                        controlador.text.trim().replaceAll(',', '.'),
                      );

                      actualizarDialogo(() {
                        if (cantidadActual != null && cantidadActual.isFinite) {
                          final cantidadBase =
                              cantidadActual * _factorUnidad(unidad);

                          final convertida =
                              cantidadBase / _factorUnidad(nuevaUnidad);

                          controlador.text = _numeroTexto(
                            convertida,
                            decimales: 6,
                          );
                        }

                        unidad = nuevaUnidad;
                        error = null;
                      });
                    },
                  ),

                  if (error != null) ...[
                    const SizedBox(height: 10),

                    Text(
                      error!,
                      style: TextStyle(color: _colorError, fontSize: 12),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (respondido) return;
                    respondido = true;
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancelar'),
                ),

                ElevatedButton(
                  onPressed: () {
                    if (respondido) return;
                    final texto = controlador.text.trim().replaceAll(',', '.');

                    final decimalesMaximos = unidad == 'kg' || unidad == 'l'
                        ? 6
                        : 3;

                    final formatoValido = RegExp(
                      r'^\d+(\.\d+)?$',
                    ).hasMatch(texto);

                    final partes = texto.split('.');

                    if (!formatoValido ||
                        (partes.length == 2 &&
                            partes[1].length > decimalesMaximos)) {
                      actualizarDialogo(() {
                        error =
                            'Cantidad inválida. Máximo '
                            '$decimalesMaximos decimales.';
                      });
                      return;
                    }

                    final cantidad = double.tryParse(texto);

                    if (cantidad == null ||
                        !cantidad.isFinite ||
                        cantidad <= 0) {
                      actualizarDialogo(() {
                        error = 'La cantidad debe ser mayor que cero.';
                      });
                      return;
                    }

                    final cantidadBase = cantidad * _factorUnidad(unidad);
                    if (!cantidadBase.isFinite) {
                      actualizarDialogo(
                        () => error = 'Cantidad fuera de rango.',
                      );
                      return;
                    }

                    final baseRedondeada = double.parse(
                      cantidadBase.toStringAsFixed(3),
                    );

                    if (baseRedondeada <= 0 ||
                        baseRedondeada > 9999999.999 ||
                        (cantidadBase - baseRedondeada).abs() > 0.0000001) {
                      actualizarDialogo(() {
                        error =
                            'Cantidad fuera de rango '
                            'o demasiado precisa.';
                      });
                      return;
                    }

                    respondido = true;
                    Navigator.pop(dialogContext, {
                      'cantidad': cantidad,
                      'unidad': unidad,
                    });
                  },
                  child: const Text('Agregar a la lista'),
                ),
              ],
            );
          },
        );
      },
    );

    final respuesta = await Navigator.of(
      context,
      rootNavigator: false,
    ).push(dialogo);
    // El campo sigue montado durante la animación de cierre.
    await dialogo.completed;
    controlador.dispose();

    return respuesta;
  }

  // =====================================================
  // ACEPTAR SUGERENCIA
  // =====================================================

  Future<void> _aceptarSugerencia(SugerenciaCompra sugerencia) async {
    if (_guardandoAlimentoId != null ||
        _cargando ||
        _enviosInciertos.contains(sugerencia.alimentoId))
      return;
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) {
      _mensaje('Debes iniciar sesión.');
      return;
    }
    setState(() => _guardandoAlimentoId = sugerencia.alimentoId);
    var envioIniciado = false;
    try {
      final datos = await _pedirCantidad(sugerencia);
      if (datos == null || !mounted) return;
      if (_supabase.auth.currentUser?.id != usuarioId) {
        throw StateError('La sesión cambió. Vuelve a abrir las sugerencias.');
      }

      final resultado = await consultarSugerenciasCompra(
        supabase: _supabase,
        hogarId: _hogarId,
        listaId: widget.listaId,
        alimentoId: sugerencia.alimentoId,
      );
      if (!mounted) return;
      _actualizarSugerencia(sugerencia.alimentoId, resultado);
      if (resultado.pendientes.contains(sugerencia.alimentoId)) {
        _mensaje('Este alimento ya tiene un producto pendiente en la lista.');
        return;
      }
      if (resultado.sugerencias.isEmpty) {
        _mensaje(
          'La sugerencia ya no aplica. Se actualizaron el stock y el consumo.',
        );
        return;
      }
      final actual = resultado.sugerencias.single;
      if (actual.unidadBase != sugerencia.unidadBase ||
          (actual.disponible - sugerencia.disponible).abs() > 0.0000001 ||
          (actual.consumido - sugerencia.consumido).abs() > 0.0000001) {
        _mensaje(
          'El stock o el consumo cambiaron. Revisa la cantidad sugerida actualizada.',
        );
        return;
      }

      final continuar = await confirmarStockCompra(
        context: context,
        supabase: _supabase,
        hogarId: _hogarId,
        alimentoId: actual.alimentoId,
        nombre: actual.nombre,
        cantidad: datos['cantidad'],
        unidad: datos['unidad'].toString(),
      );
      if (!continuar || !mounted) return;

      // Volver a consultar tras el diálogo reduce la ventana de duplicación.
      // La exclusión entre dispositivos requiere protección en el servidor.
      await validarListaSugerenciasCompra(
        supabase: _supabase,
        hogarId: _hogarId,
        listaId: widget.listaId,
      );
      final pendiente = await existePendienteSugerido(
        supabase: _supabase,
        listaId: widget.listaId,
        alimentoId: actual.alimentoId,
      );
      if (!mounted) return;
      if (pendiente) {
        setState(() => _ocultadas.add(actual.alimentoId));
        _mensaje('Este alimento ya tiene un producto pendiente en la lista.');
        return;
      }
      if (_supabase.auth.currentUser?.id != usuarioId) {
        throw StateError('La sesión cambió. Vuelve a abrir las sugerencias.');
      }

      if (!await AccesoHogar.verificar(context) || !mounted) return;
      envioIniciado = true;
      await _supabase
          .from('lista_compra_item')
          .insert({
            'lista_id': widget.listaId,
            'alimento_id': actual.alimentoId,
            'cantidad': datos['cantidad'],
            'unidad': datos['unidad'],
            'origen': 'SUGERIDO_CONSUMO',
            'estado': 'PENDIENTE',
            'agregado_por': usuarioId,
          })
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() => _ocultadas.add(actual.alimentoId));
      _mensaje('${actual.nombre} agregado a la lista de compras.');
    } on PostgrestException catch (error) {
      // Los SQLSTATE tienen cinco caracteres; solo tres dígitos pueden ser HTTP.
      final codigo = error.code ?? '';
      final estadoHttp = RegExp(r'^\d{3}$').hasMatch(codigo)
          ? int.tryParse(codigo)
          : null;
      if (envioIniciado &&
          (error.code == null ||
              (estadoHttp != null &&
                  (estadoHttp < 400 || estadoHttp >= 500)))) {
        _marcarEnvioIncierto(sugerencia.alimentoId);
      } else {
        _mensaje('No se pudo agregar: ${error.message}');
      }
    } catch (error) {
      if (envioIniciado && mounted) {
        _marcarEnvioIncierto(sugerencia.alimentoId);
      } else {
        _mensaje('No se pudo agregar: $error');
      }
    } finally {
      if (mounted) setState(() => _guardandoAlimentoId = null);
    }
  }

  void _marcarEnvioIncierto(int alimentoId) {
    if (!mounted) return;
    setState(() => _enviosInciertos.add(alimentoId));
    _mensaje(
      'El servidor no confirmó el agregado. Revisa la lista antes de reenviarlo.',
    );
  }

  // =====================================================
  // TARJETA DE SUGERENCIA
  // =====================================================

  Widget _tarjetaSugerencia(SugerenciaCompra sugerencia) {
    final guardando = _guardandoAlimentoId == sugerencia.alimentoId;

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
            Text(
              sugerencia.nombre,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
                color: _colorAcento,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              'Consumo en los últimos $periodoDias días: '
              '${_cantidadTexto(sugerencia.consumido, sugerencia.unidadBase)}',
            ),

            const SizedBox(height: 6),

            Text(
              'Disponible en despensa: '
              '${_cantidadTexto(sugerencia.disponible, sugerencia.unidadBase)}',
            ),

            const SizedBox(height: 6),

            Text(
              'Días con consumo registrado: '
              '${sugerencia.diasConsumo}',
            ),

            const SizedBox(height: 6),

            Text(
              'Objetivo orientativo para $diasReposicionSugerencias días: '
              '${_cantidadTexto(sugerencia.objetivo, sugerencia.unidadBase)}',
            ),

            const Divider(height: 26),

            Text(
              'Cantidad sugerida: '
              '${_cantidadTexto(sugerencia.sugerido, sugerencia.unidadBase)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _guardandoAlimentoId != null
                        ? null
                        : () {
                            setState(() {
                              _ocultadas.add(sugerencia.alimentoId);
                            });
                          },
                    child: const Text('Omitir'),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        _guardandoAlimentoId != null ||
                            _enviosInciertos.contains(sugerencia.alimentoId)
                        ? null
                        : () => _aceptarSugerencia(sugerencia),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: verde,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(guardando ? 'Agregando...' : 'Agregar'),
                  ),
                ),
              ],
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
    final hogarNombre = widget.hogar['nombre']?.toString() ?? 'Hogar';

    final visibles = _sugerencias
        .where((sugerencia) => !_ocultadas.contains(sugerencia.alimentoId))
        .toList();

    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        backgroundColor: verde,
        foregroundColor: Colors.white,
        title: const Text('Sugerencias de compra'),
        actions: [
          IconButton(
            tooltip: 'Actualizar sugerencias',
            onPressed: _cargando || _guardandoAlimentoId != null
                ? null
                : _cargarSugerencias,
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
                      'No se pudieron cargar '
                      'las sugerencias.\n$_error',
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 12),

                    ElevatedButton(
                      onPressed: _cargarSugerencias,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _cargarSugerencias,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Hogar: $hogarNombre',
                    style: TextStyle(
                      color: _colorAcento,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  const Text(
                    'Estas sugerencias se basan en '
                    'el consumo reciente y las '
                    'existencias actuales del hogar.',
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Nada se agregará automáticamente. '
                    'Puedes modificar la cantidad '
                    'o ignorar cualquier sugerencia.',
                    style: TextStyle(
                      color: _colorTextoSecundario,
                      fontSize: 12,
                    ),
                  ),

                  const SizedBox(height: 22),

                  if (_hayDatosNoVerificables)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Hay cantidades no verificables. No se sugieren alimentos con stock desconocido.',
                      ),
                    ),
                  if (_enviosInciertos.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Un agregado quedó sin confirmación. Revisa la lista antes de reenviarlo.',
                      ),
                    ),

                  Text(
                    'Sugerencias disponibles '
                    '(${visibles.length})',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
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
                          'No hay sugerencias por ahora.\n\n'
                          'Es posible que todavía no '
                          'existan consumos en dos días distintos, '
                          'que el inventario tenga '
                          'existencias suficientes '
                          'o que los alimentos ya '
                          'estén en la lista.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    for (final sugerencia in visibles)
                      _tarjetaSugerencia(sugerencia),

                  const SizedBox(height: 18),

                  Text(
                    'Se requieren consumos en dos días distintos dentro de los últimos 30 días. '
                    'Se propone completar un stock orientativo de 7 días según lo registrado. '
                    'Con poco historial puede subestimarse la necesidad; puedes ajustar la cantidad.',
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
}
