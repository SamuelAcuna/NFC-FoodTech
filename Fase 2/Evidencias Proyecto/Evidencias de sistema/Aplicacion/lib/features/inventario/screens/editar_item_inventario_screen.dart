import 'dart:async';
import 'package:nfc_foodtech_app/services/notificaciones_locales.dart';
import 'package:flutter/material.dart';
import 'package:nfc_foodtech_app/shared/widgets/acceso_hogar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditarItemInventarioScreen extends StatefulWidget {
  final Map<String, dynamic> registro;
  final String nombreAlimento;
  final String unidadBase;

  const EditarItemInventarioScreen({
    super.key,
    required this.registro,
    required this.nombreAlimento,
    required this.unidadBase,
  });

  @override
  State<EditarItemInventarioScreen> createState() =>
      _EditarItemInventarioScreenState();
}

class _EditarItemInventarioScreenState
    extends State<EditarItemInventarioScreen> {
  static const Color verde = Color(0xFF236B4A);
  static const Color fondo = Color(0xFFF3F7F3);

  final _formKey = GlobalKey<FormState>();

  final _cantidadController = TextEditingController();
  final _precioController = TextEditingController();
  final _observacionesController = TextEditingController();

  late String _ubicacion;
  late double _cantidadOriginal;

  DateTime? _fecha;
  DateTime? _fechaOriginal;

  String? _precioOriginal;
  String _observacionesOriginal = '';

  bool _fechaModificada = false;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();

    final registro = widget.registro;

    _cantidadOriginal = _numero(registro['cantidad_restante']) ?? 0;

    _cantidadController.text = _formatearNumero(_cantidadOriginal);

    _ubicacion = registro['ubicacion']?.toString() ?? 'DESPENSA';

    _fechaOriginal = _leerFecha(registro['fecha_vencimiento']);

    _fecha = _fechaOriginal;

    _precioOriginal = registro['precio_clp']?.toString();
    _precioController.text = _precioOriginal ?? '';

    _observacionesOriginal = registro['observaciones']?.toString() ?? '';

    _observacionesController.text = _observacionesOriginal;
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    _precioController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  // --------------------------------------------------
  // CONVERSIONES Y FORMATO
  // --------------------------------------------------

  double? _numero(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor?.toString() ?? '');
  }

  String _formatearNumero(double valor) {
    return valor
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  DateTime? _leerFecha(dynamic valor) {
    if (valor == null) return null;

    final fecha = DateTime.tryParse(valor.toString());

    if (fecha == null) return null;

    return DateTime(fecha.year, fecha.month, fecha.day);
  }

  String _fechaSql(DateTime fecha) {
    final mes = fecha.month.toString().padLeft(2, '0');
    final dia = fecha.day.toString().padLeft(2, '0');

    return '${fecha.year}-$mes-$dia';
  }

  String _fechaVisible(DateTime? fecha) {
    if (fecha == null) return 'Sin fecha';

    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year}';
  }

  // --------------------------------------------------
  // VALIDACIONES
  // --------------------------------------------------

  String? _validarCantidad(String? valor) {
    final texto = (valor ?? '').trim().replaceAll(',', '.');

    if (!RegExp(r'^\d+(?:\.\d{1,3})?$').hasMatch(texto)) {
      return 'Ingresa una cantidad con hasta 3 decimales';
    }

    final cantidad = double.tryParse(texto);

    if (cantidad == null ||
        !cantidad.isFinite ||
        cantidad <= 0 ||
        cantidad > 9999999.999) {
      return 'La cantidad debe ser mayor que 0';
    }

    return null;
  }

  String? _validarPrecio(String? valor) {
    final texto = (valor ?? '').trim();

    if (texto.isEmpty) return null;

    final precio = int.tryParse(texto);

    if (precio == null || precio < 0 || precio > 2147483647) {
      return 'Ingresa un precio válido en pesos';
    }

    return null;
  }

  // --------------------------------------------------
  // SELECCIONAR FECHA
  // --------------------------------------------------

  Future<void> _elegirFecha() async {
    final seleccion = await showDatePicker(
      context: context,
      useRootNavigator: false,
      initialDate: _fecha ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Indicar fecha de caducidad',
    );

    if (!mounted || seleccion == null) return;

    setState(() {
      _fecha = seleccion;
      _fechaModificada = true;
    });
  }

  void _mostrarMensaje(String texto) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), behavior: SnackBarBehavior.floating),
    );
  }

  // --------------------------------------------------
  // GUARDAR CAMBIOS EN SUPABASE
  // --------------------------------------------------

  Future<void> _guardar() async {
    if (_guardando) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final id = widget.registro['id']?.toString();

    if (id == null || id.isEmpty) {
      _mostrarMensaje('No se encontró el identificador del ingreso.');
      return;
    }

    final cantidad = double.parse(
      _cantidadController.text.trim().replaceAll(',', '.'),
    );

    final cambiaCantidad = (cantidad - _cantidadOriginal).abs() > 0.000001;

    final cambiaUbicacion =
        _ubicacion != widget.registro['ubicacion']?.toString();

    final precioTexto = _precioController.text.trim();

    final cambiaPrecio = precioTexto != (_precioOriginal ?? '');

    final observaciones = _observacionesController.text.trim();

    final cambiaObservaciones = observaciones != _observacionesOriginal.trim();

    if (!cambiaCantidad &&
        !cambiaUbicacion &&
        !_fechaModificada &&
        !cambiaPrecio &&
        !cambiaObservaciones) {
      _mostrarMensaje('No hay cambios para guardar.');
      return;
    }

    setState(() {
      _guardando = true;
    });

    try {
      if (!await AccesoHogar.verificar(context) || !mounted) return;
      final resultado = await Supabase.instance.client.rpc(
        'editar_item_inventario',
        params: {
          'p_item_id': id,

          'p_nueva_cantidad': cambiaCantidad ? cantidad : null,

          'p_nueva_ubicacion': cambiaUbicacion ? _ubicacion : null,

          'p_cambiar_fecha': _fechaModificada,

          'p_nueva_fecha': _fechaModificada && _fecha != null
              ? _fechaSql(_fecha!)
              : null,

          'p_cambiar_precio': cambiaPrecio,

          'p_nuevo_precio': cambiaPrecio && precioTexto.isNotEmpty
              ? int.parse(precioTexto)
              : null,

          'p_cambiar_observaciones': cambiaObservaciones,

          'p_nuevas_observaciones': cambiaObservaciones ? observaciones : null,
        },
      );

      unawaited(NotificacionesLocales.instancia.sincronizar());
      if (!mounted) return;

      // Actualizar las alertas del usuario después de
      // guardar cambios de fecha o ubicación.
      try {
        await Supabase.instance.client.rpc('m28_sincronizar_alertas');
      } catch (error) {
        debugPrint('No se pudieron sincronizar las alertas: $error');
      }

      if (!mounted) return;

      final datos = Map<String, dynamic>.from(resultado as Map);

      Navigator.of(context).pop({'actualizado': true, 'aviso': datos['aviso']});
    } on PostgrestException catch (error) {
      _mostrarMensaje('No se pudo guardar: ${error.message}');
    } catch (error) {
      _mostrarMensaje('Error al editar el ingreso: $error');
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  // --------------------------------------------------
  // INTERFAZ
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final esEstimada = widget.registro['vencimiento_estimado'] == true;

    final tema = Theme.of(context);
    final esquema = tema.colorScheme;
    final oscuro = tema.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: oscuro ? tema.scaffoldBackgroundColor : fondo,
      appBar: AppBar(
        title: const Text('Editar ingreso'),
        backgroundColor: verde,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.nombreAlimento,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: oscuro ? esquema.primary : verde,
              ),
            ),

            const SizedBox(height: 6),

            Text('Cantidad expresada en ${widget.unidadBase}'),

            const SizedBox(height: 20),

            // CANTIDAD DISPONIBLE
            TextFormField(
              controller: _cantidadController,
              enabled: !_guardando,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Cantidad disponible (${widget.unidadBase})',
                border: const OutlineInputBorder(),
                helperText: 'Corregir esta cantidad registrará un AJUSTE.',
                helperMaxLines: 2,
              ),
              validator: _validarCantidad,
            ),

            const SizedBox(height: 16),

            // UBICACIÓN
            DropdownButtonFormField<String>(
              key: ValueKey(_ubicacion),
              initialValue: _ubicacion,
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
                        _ubicacion = valor;
                      });
                    },
            ),

            const SizedBox(height: 18),

            // FECHA DE CADUCIDAD
            Text(
              'Caducidad: ${_fechaVisible(_fecha)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 5),

            Text(
              !_fechaModificada && esEstimada
                  ? 'Fecha estimada por el sistema'
                  : 'Fecha indicada manualmente',
              style: TextStyle(color: esquema.onSurfaceVariant),
            ),

            const SizedBox(height: 8),

            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: _guardando ? null : _elegirFecha,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: const Text('Cambiar fecha'),
                ),

                TextButton.icon(
                  onPressed: _guardando
                      ? null
                      : () {
                          setState(() {
                            _fecha = null;
                            _fechaModificada = true;
                          });
                        },
                  icon: const Icon(Icons.close),
                  label: const Text('Quitar fecha'),
                ),

                if (_fechaModificada)
                  TextButton(
                    onPressed: _guardando
                        ? null
                        : () {
                            setState(() {
                              _fecha = _fechaOriginal;
                              _fechaModificada = false;
                            });
                          },
                    child: const Text('Deshacer cambio'),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // PRECIO
            TextFormField(
              controller: _precioController,
              enabled: !_guardando,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Precio en CLP (opcional)',
                prefixText: r'$ ',
                border: OutlineInputBorder(),
              ),
              validator: _validarPrecio,
            ),

            const SizedBox(height: 16),

            // OBSERVACIONES
            TextFormField(
              controller: _observacionesController,
              enabled: !_guardando,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Observaciones (opcional)',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 14),

            // GUARDAR
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _guardando ? null : _guardar,
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
                    : const Icon(Icons.save_outlined),
                label: Text(_guardando ? 'Guardando...' : 'Guardar cambios'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
