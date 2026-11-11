import 'dart:async';
import 'package:nfc_foodtech_app/services/notificaciones_locales.dart';
import 'package:flutter/material.dart';
import 'package:nfc_foodtech_app/shared/widgets/acceso_hogar.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nfc_foodtech_app/features/compras/widgets/advertencia_stock.dart';

class ConfirmarCompraScreen extends StatefulWidget {
  final Map<String, dynamic> hogar;
  final Map<String, dynamic> item;
  final String listaId;

  const ConfirmarCompraScreen({
    super.key,
    required this.hogar,
    required this.item,
    required this.listaId,
  });

  @override
  State<ConfirmarCompraScreen> createState() => _ConfirmarCompraScreenState();
}

class _ConfirmarCompraScreenState extends State<ConfirmarCompraScreen> {
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

  Color get _colorAdvertencia =>
      _modoOscuro ? Colors.orange.shade300 : Colors.deepOrange;

  final _supabase = Supabase.instance.client;
  final _precioController = TextEditingController();

  String _ubicacion = 'DESPENSA';
  DateTime? _fechaVencimiento;

  bool _guardando = false;
  bool _compraConfirmada = false;
  String? _error;

  @override
  void dispose() {
    _precioController.dispose();
    super.dispose();
  }

  // =====================================================
  // FORMATOS
  // =====================================================

  String _numeroTexto(dynamic valor) {
    final numero = valor is num
        ? valor.toDouble()
        : double.tryParse(valor?.toString() ?? '') ?? 0;

    return numero
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  String _cantidadTexto() {
    final cantidad = _numeroTexto(widget.item['cantidad']);

    final unidad = widget.item['unidad']?.toString() ?? 'un';

    return '$cantidad ${unidad == 'l' ? 'L' : unidad}';
  }

  String _fechaSql(DateTime fecha) {
    final mes = fecha.month.toString().padLeft(2, '0');
    final dia = fecha.day.toString().padLeft(2, '0');

    return '${fecha.year}-$mes-$dia';
  }

  String _fechaVisible(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year}';
  }

  String _nombreUbicacion(String valor) {
    switch (valor) {
      case 'DESPENSA':
        return 'Despensa';

      case 'REFRIGERADOR':
        return 'Refrigerador';

      case 'CONGELADOR':
        return 'Congelador';

      default:
        return valor;
    }
  }

  // =====================================================
  // FECHA OPCIONAL
  // =====================================================

  Future<void> _seleccionarFecha() async {
    if (_guardando) return;

    final ahora = DateTime.now();

    final elegida = await showDatePicker(
      context: context,
      useRootNavigator: false,
      initialDate: _fechaVencimiento ?? ahora,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Fecha indicada en el alimento',
    );

    if (!mounted || elegida == null) return;

    setState(() {
      _fechaVencimiento = elegida;
    });
  }

  // =====================================================
  // CONFIRMAR INGRESO
  // =====================================================

  Future<void> _confirmarCompra() async {
    if (_guardando || _compraConfirmada) return;

    FocusScope.of(context).unfocus();

    final itemId = widget.item['id']?.toString();
    final hogarId = widget.hogar['id']?.toString();

    if (itemId == null ||
        itemId.isEmpty ||
        hogarId == null ||
        hogarId.isEmpty) {
      setState(() {
        _error = 'Faltan datos de la compra o del hogar.';
      });
      return;
    }

    final precioTexto = _precioController.text.trim();

    int? precio;

    if (precioTexto.isNotEmpty) {
      precio = int.tryParse(precioTexto);

      if (precio == null || precio < 0) {
        setState(() {
          _error = 'Ingresa un precio válido en pesos.';
        });
        return;
      }

      if (precio > 2147483647) {
        setState(() {
          _error = 'El precio supera el límite permitido.';
        });
        return;
      }
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      final lista = await _supabase
          .from('lista_compra')
          .select('id')
          .eq('id', widget.listaId)
          .eq('hogar_id', hogarId)
          .eq('estado', 'ABIERTA')
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (lista == null) {
        throw StateError('La lista ya no está disponible para este hogar.');
      }

      final item = await _supabase
          .from('lista_compra_item')
          .select('id, alimento_id, cantidad, unidad, estado, despensa_item_id')
          .eq('id', itemId)
          .eq('lista_id', widget.listaId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (item == null ||
          item['despensa_item_id'] != null ||
          !['PENDIENTE', 'COMPRADO'].contains(item['estado'])) {
        throw StateError('El producto ya no está pendiente de ingresar.');
      }

      if (item['alimento_id'] != widget.item['alimento_id'] ||
          num.tryParse(item['cantidad']?.toString() ?? '') !=
              num.tryParse(widget.item['cantidad']?.toString() ?? '') ||
          item['unidad'] != widget.item['unidad']) {
        throw StateError('El producto cambió. Vuelve a actualizar la lista.');
      }

      if (!mounted) return;

      final continuar = await confirmarStockCompra(
        context: context,
        supabase: _supabase,
        hogarId: hogarId,
        alimentoId: (item['alimento_id'] as num).toInt(),
        nombre: widget.item['nombre_alimento']?.toString() ?? 'Alimento',
        cantidad: item['cantidad'],
        unidad: item['unidad']?.toString() ?? '',
      );

      if (!continuar || !mounted) return;

      // Una sola RPC:
      // crea despensa_item y vincula lista_compra_item
      // en la misma transacción.
      if (!await AccesoHogar.verificar(context) || !mounted) return;
      final despensaId = await _supabase.rpc(
        'm27_confirmar_compra_item',
        params: {
          'p_lista_item_id': itemId,
          'p_ubicacion': _ubicacion,
          'p_fecha_vencimiento': _fechaVencimiento == null
              ? null
              : _fechaSql(_fechaVencimiento!),
          'p_precio_clp': precio,
        },
      );

      if (despensaId != null) {
        unawaited(NotificacionesLocales.instancia.sincronizar());
      }
      if (!mounted) return;

      if (despensaId == null) {
        throw Exception('No se recibió el identificador del ingreso.');
      }

      _compraConfirmada = true;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  // =====================================================
  // PANTALLA
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final nombre = widget.item['nombre_alimento']?.toString() ?? 'Alimento';

    final yaMarcadoComprado = widget.item['estado'] == 'COMPRADO';

    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        backgroundColor: verde,
        foregroundColor: Colors.white,
        title: const Text('Confirmar compra'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: _colorSuperficie,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombre,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'Cantidad: ${_cantidadTexto()}',
                    style: TextStyle(
                      color: _colorAcento,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  if (yaMarcadoComprado) ...[
                    const SizedBox(height: 10),

                    Text(
                      'Este producto ya estaba marcado '
                      'como comprado, pero todavía no '
                      'tenía un ingreso vinculado '
                      'al inventario.',
                      style: TextStyle(color: _colorAdvertencia),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 22),

          const Text(
            '¿Dónde guardarás este alimento?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),

          const SizedBox(height: 10),

          DropdownButtonFormField<String>(
            initialValue: _ubicacion,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Ubicación',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'DESPENSA', child: Text('Despensa')),
              DropdownMenuItem(
                value: 'REFRIGERADOR',
                child: Text('Refrigerador'),
              ),
              DropdownMenuItem(value: 'CONGELADOR', child: Text('Congelador')),
            ],
            onChanged: _guardando
                ? null
                : (valor) {
                    if (valor == null) return;

                    setState(() {
                      _ubicacion = valor;
                    });
                  },
          ),

          const SizedBox(height: 8),

          Text(
            'Ubicación seleccionada: '
            '${_nombreUbicacion(_ubicacion)}',
            style: TextStyle(color: _colorTextoSecundario, fontSize: 12),
          ),

          const SizedBox(height: 24),

          const Text(
            'Fecha de caducidad (opcional)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),

          const SizedBox(height: 10),

          OutlinedButton.icon(
            onPressed: _guardando ? null : _seleccionarFecha,
            icon: const Icon(Icons.calendar_month),
            label: Text(
              _fechaVencimiento == null
                  ? 'Seleccionar fecha'
                  : _fechaVisible(_fechaVencimiento!),
            ),
          ),

          if (_fechaVencimiento != null)
            TextButton(
              onPressed: _guardando
                  ? null
                  : () {
                      setState(() {
                        _fechaVencimiento = null;
                      });
                    },
              child: const Text('Quitar fecha'),
            ),

          const SizedBox(height: 8),

          Text(
            'Si no ingresas una fecha, se utilizará '
            'la estimación referencial del sistema '
            'cuando esté disponible.',
            style: TextStyle(fontSize: 12, color: _colorTextoSecundario),
          ),

          const SizedBox(height: 24),

          const Text(
            'Precio pagado (opcional)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),

          const SizedBox(height: 10),

          TextField(
            controller: _precioController,
            enabled: !_guardando,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Precio en CLP',
              hintText: 'Ej: 1200',
              prefixIcon: Icon(Icons.attach_money),
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Si ingresas un precio, este se asociará '
            'a la cantidad comprada para estimar '
            'posibles pérdidas económicas.',
            style: TextStyle(fontSize: 12, color: _colorTextoSecundario),
          ),

          if (_error != null) ...[
            const SizedBox(height: 20),

            Text(
              _error!,
              style: TextStyle(color: _colorError, fontWeight: FontWeight.w600),
            ),
          ],

          const SizedBox(height: 28),

          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _guardando ? null : _confirmarCompra,
              style: ElevatedButton.styleFrom(
                backgroundColor: verde,
                foregroundColor: Colors.white,
              ),
              icon: _guardando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check),
              label: Text(
                _guardando
                    ? 'Registrando...'
                    : 'Confirmar e ingresar a despensa',
              ),
            ),
          ),

          const SizedBox(height: 12),

          Text(
            'Al confirmar, el alimento se registrará '
            'una sola vez en el inventario del hogar.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _colorTextoSecundario),
          ),
        ],
      ),
    );
  }
}
