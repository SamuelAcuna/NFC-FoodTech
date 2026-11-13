
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InvitacionesHogarScreen extends StatefulWidget {
  final Map<String, dynamic>? hogar;

  const InvitacionesHogarScreen({
    super.key,
    this.hogar,
  });

  @override
  State<InvitacionesHogarScreen> createState() =>
      _InvitacionesHogarScreenState();
}

class _InvitacionesHogarScreenState
    extends State<InvitacionesHogarScreen> {
  static const Color verde = Color(0xFF236B4A);

  final _supabase = Supabase.instance.client;

  final _codigoController = TextEditingController();

  bool _generando = false;
  bool _uniendo = false;

  String? _codigoGenerado;
  DateTime? _fechaExpiracion;
  String? _error;

  bool get _modoAdministrador => widget.hogar != null;

  String get _nombreHogar =>
      widget.hogar?['nombre']?.toString() ?? 'Hogar';

  @override
  void dispose() {
    _codigoController.dispose();
    super.dispose();
  }

  // =================================================
  // MOSTRAR MENSAJES
  // =================================================

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // =================================================
  // GENERAR CÓDIGO
  // =================================================

  Future<void> _generarInvitacion() async {
    if (_generando || !_modoAdministrador) return;

    final hogarId = widget.hogar?['id']?.toString();

    if (hogarId == null || hogarId.isEmpty) {
      setState(() {
        _error = 'No se identificó el hogar.';
      });
      return;
    }

    setState(() {
      _generando = true;
      _error = null;
    });

    try {
      final respuesta = await _supabase.rpc(
        'm17_generar_invitacion',
        params: {
          'p_hogar_id': hogarId,
        },
      );

      if (!mounted) return;

      if (respuesta is! Map ||
          respuesta['exito'] != true) {
        throw StateError(
          'El servidor no confirmó la invitación.',
        );
      }

      final codigo =
          respuesta['codigo']?.toString();

      final fecha =
          respuesta['expira_en']?.toString();

      if (codigo == null ||
          codigo.isEmpty ||
          fecha == null) {
        throw StateError(
          'La invitación llegó incompleta.',
        );
      }

      setState(() {
        _codigoGenerado = codigo;
        _fechaExpiracion =
            DateTime.tryParse(fecha)?.toLocal();
      });

      _mostrarMensaje(
        'Código de invitación generado.',
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.message;
      });
    } catch (error) {
      debugPrint(
        'M17: error generando invitación: $error',
      );

      if (!mounted) return;

      setState(() {
        _error =
            'No se pudo generar la invitación.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _generando = false;
        });
      }
    }
  }

  // =================================================
  // COPIAR CÓDIGO
  // =================================================

  Future<void> _copiarCodigo() async {
    final codigo = _codigoGenerado;

    if (codigo == null) return;

    await Clipboard.setData(
      ClipboardData(text: codigo),
    );

    _mostrarMensaje(
      'Código copiado al portapapeles.',
    );
  }

  // =================================================
  // UNIRSE AL HOGAR
  // =================================================

  Future<void> _unirseAlHogar() async {
    if (_uniendo) return;

    final codigo =
        _codigoController.text.trim().toUpperCase();

    if (!RegExp(r'^[A-F0-9]{16}$').hasMatch(codigo)) {
      setState(() {
        _error =
            'El código debe tener 16 caracteres válidos.';
      });
      return;
    }

    if (_supabase.auth.currentUser == null) {
      setState(() {
        _error = 'Debes iniciar sesión nuevamente.';
      });
      return;
    }

    setState(() {
      _uniendo = true;
      _error = null;
    });

    try {
      final respuesta = await _supabase.rpc(
        'm17_unirse_hogar',
        params: {
          'p_codigo': codigo,
        },
      );

      if (!mounted) return;

      if (respuesta is! Map ||
          respuesta['exito'] != true) {
        throw StateError(
          'El servidor no confirmó la incorporación.',
        );
      }

      debugPrint(
        'M17: incorporación al hogar completada.',
      );

      Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.message;
      });
    } catch (error) {
      debugPrint(
        'M17: error al unirse: $error',
      );

      if (!mounted) return;

      setState(() {
        _error =
            'No fue posible unirse al hogar.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _uniendo = false;
        });
      }
    }
  }

  // =================================================
  // FORMATO DE FECHA
  // =================================================

  String _formatearFecha(DateTime fecha) {
    String dosDigitos(int numero) =>
        numero.toString().padLeft(2, '0');

    return '${dosDigitos(fecha.day)}/'
        '${dosDigitos(fecha.month)}/'
        '${fecha.year} '
        '${dosDigitos(fecha.hour)}:'
        '${dosDigitos(fecha.minute)}';
  }

  // =================================================
  // INTERFAZ
  // =================================================

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final oscuro = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _modoAdministrador
              ? 'Invitar integrantes'
              : 'Unirse a un hogar',
        ),
      ),

      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),

            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: 520),

              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,

                children: [
                  Icon(
                    Icons.group_add_outlined,
                    size: 64,
                    color: oscuro ? esquema.primary : verde,
                  ),

                  const SizedBox(height: 18),

                  Text(
                    _modoAdministrador
                        ? 'Invita a tu hogar'
                        : 'Únete a un hogar',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    _modoAdministrador
                        ? 'Genera un código para que '
                          'otra persona pueda incorporarse '
                          'a "$_nombreHogar".'
                        : 'Introduce el código que '
                          'te entregó el administrador '
                          'del hogar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: esquema.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 28),

                  if (_modoAdministrador) ...[
                    // =================================
                    // GENERAR INVITACIÓN
                    // =================================

                    FilledButton.icon(
                      onPressed: _generando
                          ? null
                          : _generarInvitacion,

                      style: FilledButton.styleFrom(
                        backgroundColor: verde,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.all(16),
                      ),

                      icon: _generando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.vpn_key_outlined,
                            ),

                      label: Text(
                        _generando
                            ? 'Generando código...'
                            : 'Generar código de invitación',
                      ),
                    ),

                    if (_codigoGenerado != null) ...[
                      const SizedBox(height: 24),

                      Card(
                        child: Padding(
                          padding:
                              const EdgeInsets.all(20),

                          child: Column(
                            children: [
                              const Text(
                                'Código de invitación',
                                style: TextStyle(
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),

                              const SizedBox(height: 14),

                              SelectableText(
                                _codigoGenerado!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 23,
                                  letterSpacing: 2,
                                  fontWeight:
                                      FontWeight.bold,
                                  color: oscuro ? esquema.primary : verde,
                                ),
                              ),

                              const SizedBox(height: 16),

                              OutlinedButton.icon(
                                onPressed: _copiarCodigo,
                                icon: const Icon(
                                  Icons.copy_outlined,
                                ),
                                label: const Text(
                                  'Copiar código',
                                ),
                              ),

                              if (_fechaExpiracion !=
                                  null) ...[
                                const SizedBox(height: 14),

                                Text(
                                  'Válido hasta el '
                                  '${_formatearFecha(_fechaExpiracion!)}',
                                  textAlign:
                                      TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: esquema
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    Text(
                      'Generar otro código invalida '
                      'el anterior. Comparte el código '
                      'únicamente con personas '
                      'que desees incorporar al hogar.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color:
                            esquema.onSurfaceVariant,
                      ),
                    ),
                  ] else ...[
                    // =================================
                    // INGRESAR CÓDIGO
                    // =================================

                    TextField(
                      controller: _codigoController,
                      enabled: !_uniendo,
                      textCapitalization:
                          TextCapitalization.characters,
                      maxLength: 16,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(
                          16,
                        ),
                      ],
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Código de invitación',
                        hintText:
                            'Ej. A1B2C3D4E5F60708',
                        prefixIcon: Icon(
                          Icons.key_outlined,
                        ),
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 16),

                    FilledButton.icon(
                      onPressed:
                          _uniendo ? null : _unirseAlHogar,

                      style: FilledButton.styleFrom(
                        backgroundColor: verde,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.all(16),
                      ),

                      icon: _uniendo
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.login_outlined,
                            ),

                      label: Text(
                        _uniendo
                            ? 'Ingresando al hogar...'
                            : 'Unirse al hogar',
                      ),
                    ),
                  ],

                  if (_error != null) ...[
                    const SizedBox(height: 18),

                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: esquema.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
