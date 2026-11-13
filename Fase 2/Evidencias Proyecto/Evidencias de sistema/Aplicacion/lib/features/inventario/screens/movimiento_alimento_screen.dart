import 'dart:async';
import 'package:nfc_foodtech_app/services/notificaciones_locales.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nfc_foodtech_app/features/inventario/widgets/reposicion_automatica.dart';
import 'package:nfc_foodtech_app/shared/widgets/acceso_hogar.dart';

class MovimientoAlimentoScreen extends StatefulWidget {
  final Map<String, dynamic> registro;
  final String hogarId;
  final String nombreAlimento;
  final String unidadBase;

  const MovimientoAlimentoScreen({
    super.key,
    required this.registro,
    required this.hogarId,
    required this.nombreAlimento,
    required this.unidadBase,
  });

  @override
  State<MovimientoAlimentoScreen> createState() =>
      _MovimientoAlimentoScreenState();
}

class _MovimientoAlimentoScreenState extends State<MovimientoAlimentoScreen> {
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

  Color get _colorError =>
      _modoOscuro ? Theme.of(context).colorScheme.error : Colors.red;

  final _supabase = Supabase.instance.client;
  final _cantidadController = TextEditingController();

  String _tipo = 'CONSUMO';
  late String _unidadSeleccionada;

  List<Map<String, dynamic>> _motivos = [];
  int? _motivoSeleccionado;

  bool _cargandoMotivos = true;
  bool _guardando = false;
  bool _finalizado = false;
  bool _movimientoIncierto = false;
  late final _reposicion = ReposicionAutomatica(
    supabase: _supabase,
    verificarAcceso: () => AccesoHogar.verificar(context),
  );

  @override
  void initState() {
    super.initState();

    _unidadSeleccionada = widget.unidadBase;

    _cargarMotivos();
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    super.dispose();
  }

  // =====================================================
  // CANTIDADES Y UNIDADES
  // =====================================================

  double _numero(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  double get _disponible {
    return _numero(widget.registro['cantidad_restante']);
  }

  List<String> _unidadesPermitidas() {
    switch (widget.unidadBase) {
      case 'g':
        return ['g', 'kg'];

      case 'ml':
        return ['ml', 'L'];

      case 'un':
        return ['un'];

      default:
        return [widget.unidadBase];
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

  double _factorConversion(String unidad) {
    if (unidad == 'kg' || unidad == 'L') {
      return 1000;
    }

    return 1;
  }

  int _decimalesPermitidos(String unidad) {
    // Para conservar hasta 3 decimales en la BD,
    // kg y L pueden tener hasta 6 decimales.
    if (unidad == 'kg' || unidad == 'L') {
      return 6;
    }

    return 3;
  }

  String _formatearNumero(double valor, {int decimales = 3}) {
    return valor
        .toStringAsFixed(decimales)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  String _textoParaCampo(double valor, String unidad) {
    return _formatearNumero(valor, decimales: _decimalesPermitidos(unidad));
  }

  String _formatearCantidadBase(double valor) {
    if (widget.unidadBase == 'g' && valor >= 1000) {
      return '${_formatearNumero(valor / 1000, decimales: 6)} kg';
    }

    if (widget.unidadBase == 'ml' && valor >= 1000) {
      return '${_formatearNumero(valor / 1000, decimales: 6)} L';
    }

    return '${_formatearNumero(valor)} '
        '${widget.unidadBase}';
  }

  double? _cantidadIngresada() {
    final texto = _cantidadController.text.trim().replaceAll(',', '.');

    return double.tryParse(texto);
  }

  double? _cantidadEnBase() {
    final cantidad = _cantidadIngresada();

    if (cantidad == null || !cantidad.isFinite) {
      return null;
    }

    return cantidad * _factorConversion(_unidadSeleccionada);
  }

  String? _validarCantidad() {
    final texto = _cantidadController.text.trim().replaceAll(',', '.');

    if (texto.isEmpty) {
      return 'Debes indicar una cantidad.';
    }

    // Solo números positivos con separador decimal.
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(texto)) {
      return 'Ingresa una cantidad válida.';
    }

    final partes = texto.split('.');

    final decimalesMaximos = _decimalesPermitidos(_unidadSeleccionada);

    if (partes.length == 2 && partes[1].length > decimalesMaximos) {
      return 'Máximo $decimalesMaximos decimales '
          'para $_unidadSeleccionada.';
    }

    final cantidad = double.tryParse(texto);

    if (cantidad == null || !cantidad.isFinite || cantidad <= 0) {
      return 'La cantidad debe ser mayor que cero.';
    }

    final cantidadBase = _cantidadEnBase();

    if (cantidadBase == null || !cantidadBase.isFinite || cantidadBase <= 0) {
      return 'No se pudo convertir la cantidad.';
    }

    if (cantidadBase > 9999999.999) {
      return 'La cantidad supera el límite permitido.';
    }

    // La BD utiliza numeric(10,3).
    // No permitimos perder precisión silenciosamente.
    final redondeada = double.parse(cantidadBase.toStringAsFixed(3));

    if ((cantidadBase - redondeada).abs() > 0.0000001) {
      return 'La cantidad tiene más precisión '
          'de la admitida.';
    }

    if (redondeada <= 0) {
      return 'La cantidad es demasiado pequeña.';
    }

    if (redondeada > _disponible + 0.0000001) {
      return 'La cantidad supera lo disponible.';
    }

    return null;
  }

  // =====================================================
  // CAMBIAR UNIDAD SIN ALTERAR LA CANTIDAD REAL
  // =====================================================

  void _cambiarUnidad(String nuevaUnidad) {
    if (_guardando) return;

    final cantidadAnterior = _cantidadIngresada();

    double? cantidadBase;

    if (cantidadAnterior != null &&
        cantidadAnterior.isFinite &&
        cantidadAnterior >= 0) {
      cantidadBase = cantidadAnterior * _factorConversion(_unidadSeleccionada);
    }

    setState(() {
      _unidadSeleccionada = nuevaUnidad;

      if (cantidadBase != null) {
        final cantidadConvertida =
            cantidadBase / _factorConversion(nuevaUnidad);

        _cantidadController.text = _textoParaCampo(
          cantidadConvertida,
          nuevaUnidad,
        );
      }
    });
  }

  // =====================================================
  // MOTIVOS DE DESCARTE
  // =====================================================

  Future<void> _cargarMotivos() async {
    try {
      final respuesta = await _supabase
          .from('tipo_desperdicio')
          .select('id, nombre')
          .eq('activo', true)
          .order('nombre');

      if (!mounted) return;

      setState(() {
        _motivos = respuesta
            .map((dato) => Map<String, dynamic>.from(dato))
            .toList();

        _cargandoMotivos = false;
      });
    } catch (error) {
      debugPrint('Error al cargar motivos de descarte: $error');

      if (!mounted) return;

      setState(() {
        _motivos = [];
        _cargandoMotivos = false;
      });
    }
  }

  // =====================================================
  // OPCIONES RÁPIDAS
  // =====================================================

  void _seleccionarCantidad(double cantidad) {
    if (_guardando) return;

    if (cantidad <= 0) return;

    final cantidadBase = cantidad * _factorConversion(_unidadSeleccionada);

    if (cantidadBase > _disponible + 0.0000001) {
      return;
    }

    _cantidadController.text = _textoParaCampo(cantidad, _unidadSeleccionada);

    setState(() {});
  }

  void _seleccionarTodo() {
    if (_guardando || _disponible <= 0) return;

    final cantidadConvertida =
        _disponible / _factorConversion(_unidadSeleccionada);

    _cantidadController.text = _textoParaCampo(
      cantidadConvertida,
      _unidadSeleccionada,
    );

    setState(() {});
  }

  Widget _botonRapido(String etiqueta, double cantidad) {
    final cantidadSeleccionada = _cantidadIngresada();

    final activo =
        cantidadSeleccionada != null &&
        (cantidadSeleccionada - cantidad).abs() < 0.0000001;

    final cantidadBase = cantidad * _factorConversion(_unidadSeleccionada);

    final habilitado =
        cantidadBase > 0 && cantidadBase <= _disponible + 0.0000001;

    return OutlinedButton(
      onPressed: habilitado && !_guardando
          ? () => _seleccionarCantidad(cantidad)
          : null,
      style: OutlinedButton.styleFrom(
        backgroundColor: activo ? verde : _colorSuperficie,
        foregroundColor: activo ? Colors.white : _colorAcento,
        side: BorderSide(
          color: activo
              ? verde
              : (_modoOscuro
                    ? Theme.of(context).colorScheme.outlineVariant
                    : Colors.black26),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
      child: Text(etiqueta, textAlign: TextAlign.center),
    );
  }

  Widget _opcionesRapidas() {
    if (_unidadSeleccionada == 'un') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fracciones de una unidad',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(child: _botonRapido('¼', 0.25)),
              const SizedBox(width: 6),
              Expanded(child: _botonRapido('½', 0.5)),
              const SizedBox(width: 6),
              Expanded(child: _botonRapido('¾', 0.75)),
              const SizedBox(width: 6),
              Expanded(child: _botonRapido('1 un', 1)),
            ],
          ),

          const SizedBox(height: 6),

          Text(
            'Estas fracciones corresponden a una '
            'unidad, no al total del inventario.',
            style: TextStyle(fontSize: 12, color: _colorTextoSecundario),
          ),
        ],
      );
    }

    final esUnidadGrande =
        _unidadSeleccionada == 'kg' || _unidadSeleccionada == 'L';

    final cantidades = esUnidadGrande
        ? <double>[0.25, 0.5, 1, 2]
        : <double>[50, 100, 250, 500];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cantidades rápidas ($_unidadSeleccionada)',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),

        const SizedBox(height: 10),

        Row(
          children: [
            for (final cantidad in cantidades) ...[
              Expanded(
                child: _botonRapido(_formatearNumero(cantidad), cantidad),
              ),

              if (cantidad != cantidades.last) const SizedBox(width: 6),
            ],
          ],
        ),
      ],
    );
  }

  // =====================================================
  // GUARDAR MOVIMIENTO
  // =====================================================

  Future<void> _guardarMovimiento() async {
    if (_guardando || _finalizado || _movimientoIncierto) return;

    FocusScope.of(context).unfocus();

    final error = _validarCantidad();

    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    if (_tipo == 'DESCARTE' && _motivoSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un motivo de descarte.')),
      );
      return;
    }

    final itemId = widget.registro['id']?.toString();

    if (itemId == null || itemId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se identificó el ingreso del inventario.'),
        ),
      );
      return;
    }

    // Convertir siempre a la unidad base de Supabase.
    // g/kg -> g
    // ml/L -> ml
    // un -> un
    final cantidadBase = double.parse(_cantidadEnBase()!.toStringAsFixed(3));

    setState(() {
      _guardando = true;
    });

    try {
      final resultado = await _reposicion.registrar(
        hogarId: widget.hogarId,
        ingresoId: itemId,
        tipo: _tipo,
        cantidad: cantidadBase,
        motivoDescarte: _motivoSeleccionado,
        seleccionarLista: _seleccionarListaReposicion,
      );
      if (resultado.registrado) {
        unawaited(NotificacionesLocales.instancia.sincronizar());
      }
      if (!mounted) return;
      if (resultado.registrado) {
        _finalizado = true;
        Navigator.of(context).pop(resultado);
      } else {
        setState(() => _movimientoIncierto = resultado.incierto);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resultado.mensaje),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<String?> _seleccionarListaReposicion(
    List<Map<String, dynamic>> listas,
  ) async {
    if (!mounted) return null;
    var respondido = false;
    return showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Consumo registrado'),
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Selecciona una lista para la reposición. Puedes continuar sin agregar el producto.',
            ),
          ),
          for (final lista in listas)
            SimpleDialogOption(
              onPressed: () {
                if (respondido) return;
                respondido = true;
                Navigator.pop(dialogContext, lista['id'].toString());
              },
              child: Text(lista['nombre']?.toString() ?? 'Lista'),
            ),
          SimpleDialogOption(
            onPressed: () {
              if (respondido) return;
              respondido = true;
              Navigator.pop(dialogContext);
            },
            child: const Text('Continuar sin reposición'),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // INTERFAZ
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final errorCantidad = _validarCantidad();

    final cantidadBase = errorCantidad == null
        ? double.parse(_cantidadEnBase()!.toStringAsFixed(3))
        : null;

    final cantidadValida = cantidadBase != null;

    final restante = cantidadValida
        ? (_disponible - cantidadBase).clamp(0.0, _disponible).toDouble()
        : _disponible;

    return PopScope<ResultadoMovimientoAlimento>(
      canPop: !_guardando,
      child: Scaffold(
        backgroundColor: _colorFondo,
        appBar: AppBar(
          backgroundColor: verde,
          foregroundColor: Colors.white,
          title: const Text('Consumo y descarte'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // INFORMACIÓN DEL ALIMENTO
            Card(
              color: _colorSuperficie,
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.nombreAlimento,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      'Disponible: '
                      '${_formatearCantidadBase(_disponible)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _colorAcento,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // TIPO DE MOVIMIENTO
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'CONSUMO',
                    icon: Icon(Icons.restaurant_outlined),
                    label: Text('Consumir'),
                  ),
                  ButtonSegment(
                    value: 'DESCARTE',
                    icon: Icon(Icons.delete_outline),
                    label: Text('Descartar'),
                  ),
                ],
                selected: {_tipo},
                onSelectionChanged: _guardando
                    ? null
                    : (seleccion) {
                        setState(() {
                          _tipo = seleccion.first;
                        });
                      },
              ),
            ),

            const SizedBox(height: 24),

            // SELECTOR DE UNIDAD
            DropdownButtonFormField<String>(
              key: ValueKey(_unidadSeleccionada),
              initialValue: _unidadSeleccionada,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Unidad de medida',
                prefixIcon: Icon(Icons.scale_outlined),
                border: OutlineInputBorder(),
              ),
              items: _unidadesPermitidas().map((unidad) {
                return DropdownMenuItem<String>(
                  value: unidad,
                  child: Text(
                    _nombreUnidad(unidad),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: _guardando
                  ? null
                  : (unidad) {
                      if (unidad == null) return;

                      _cambiarUnidad(unidad);
                    },
            ),

            const SizedBox(height: 18),

            // BOTONES RÁPIDOS
            _opcionesRapidas(),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _guardando ? null : _seleccionarTodo,
                icon: const Icon(Icons.done_all),
                label: const Text('Todo lo disponible'),
              ),
            ),

            const SizedBox(height: 20),

            // CANTIDAD MANUAL
            TextField(
              controller: _cantidadController,
              enabled: !_guardando,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
              ],
              onChanged: (_) {
                setState(() {});
              },
              decoration: InputDecoration(
                labelText: 'Cantidad ($_unidadSeleccionada)',
                hintText: _unidadSeleccionada == 'un'
                    ? 'Ej: 0,5'
                    : _unidadSeleccionada == 'kg' || _unidadSeleccionada == 'L'
                    ? 'Ej: 0,5'
                    : 'Ej: 250',
                helperText:
                    'Puedes utilizar los botones rápidos '
                    'o escribir la cantidad.',
                border: const OutlineInputBorder(),
              ),
            ),

            if (_cantidadController.text.isNotEmpty &&
                errorCantidad != null) ...[
              const SizedBox(height: 7),

              Text(
                errorCantidad,
                style: TextStyle(color: _colorError, fontSize: 12),
              ),
            ],

            // MOSTRAR LA CONVERSIÓN
            if (cantidadValida) ...[
              const SizedBox(height: 10),

              Text(
                'Equivale a: '
                '${_formatearNumero(cantidadBase)} '
                '${widget.unidadBase}',
                style: TextStyle(
                  color: _colorAcento,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],

            // MOTIVO SOLO EN DESCARTE
            if (_tipo == 'DESCARTE') ...[
              const SizedBox(height: 24),

              const Text(
                '¿Por qué se descartó?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),

              const SizedBox(height: 10),

              if (_cargandoMotivos)
                const Center(child: CircularProgressIndicator())
              else if (_motivos.isEmpty)
                Text(
                  'No se pudieron cargar los motivos.',
                  style: TextStyle(color: _colorError),
                )
              else
                DropdownButtonFormField<int>(
                  initialValue: _motivoSeleccionado,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Motivo de descarte',
                    border: OutlineInputBorder(),
                  ),
                  items: _motivos.map((motivo) {
                    final id = (motivo['id'] as num).toInt();

                    return DropdownMenuItem<int>(
                      value: id,
                      child: Text(
                        motivo['nombre']?.toString() ?? '',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: _guardando
                      ? null
                      : (id) {
                          setState(() {
                            _motivoSeleccionado = id;
                          });
                        },
                ),
            ],

            const SizedBox(height: 25),

            // RESUMEN DEL MOVIMIENTO
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _colorSuperficie,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _tipo == 'CONSUMO'
                            ? 'Cantidad consumida'
                            : 'Cantidad descartada',
                      ),
                      Text(
                        cantidadValida
                            ? _formatearCantidadBase(cantidadBase)
                            : '—',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Cantidad restante'),
                      Text(
                        _formatearCantidadBase(restante),
                        style: TextStyle(
                          color: _colorAcento,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // CONFIRMAR MOVIMIENTO
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed:
                    _guardando ||
                        _finalizado ||
                        _movimientoIncierto ||
                        !cantidadValida ||
                        (_tipo == 'DESCARTE' &&
                            (_cargandoMotivos || _motivoSeleccionado == null))
                    ? null
                    : _guardarMovimiento,
                style: ElevatedButton.styleFrom(
                  backgroundColor: verde,
                  foregroundColor: Colors.white,
                ),
                icon: _guardando
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check),
                label: Text(
                  _guardando
                      ? 'Guardando...'
                      : _tipo == 'CONSUMO'
                      ? 'Confirmar consumo'
                      : 'Confirmar descarte',
                ),
              ),
            ),

            const SizedBox(height: 12),

            if (_movimientoIncierto)
              const Text(
                'Movimiento no confirmado. Vuelve al inventario para comprobarlo antes de realizar otra operación.',
              ),

            Text(
              _tipo == 'CONSUMO'
                  ? 'El consumo no se registrará como desperdicio.'
                  : 'Solo se registrará como desperdicio '
                        'la cantidad descartada.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: _colorTextoSecundario),
            ),
          ],
        ),
      ),
    );
  }
}
