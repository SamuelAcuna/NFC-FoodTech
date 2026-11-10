
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CompletarIdentificacionScreen extends StatefulWidget {
  final VoidCallback onCompletado;

  const CompletarIdentificacionScreen({
    super.key,
    required this.onCompletado,
  });

  @override
  State<CompletarIdentificacionScreen> createState() =>
      _CompletarIdentificacionScreenState();
}

class _CompletarIdentificacionScreenState
    extends State<CompletarIdentificacionScreen> {
  static const Color verde = Color(0xFF236B4A);
  static const Duration espera = Duration(seconds: 8);

  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _nombreController = TextEditingController();
  final _apellidoController = TextEditingController();
  final _rutController = TextEditingController();

  bool _cargando = true;
  bool _guardando = false;
  bool _identificacionRegistrada = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidoController.dispose();
    _rutController.dispose();
    super.dispose();
  }

  // --------------------------------------------------
  // VALIDAR RUT CHILENO
  // --------------------------------------------------

  String _normalizarRut(String valor) {
    return valor
        .trim()
        .toUpperCase()
        .replaceAll('.', '')
        .replaceAll('-', '')
        .replaceAll(' ', '');
  }

  String _calcularDv(int rut) {
    int suma = 0;
    int multiplicador = 2;
    int numero = rut;

    while (numero > 0) {
      suma += (numero % 10) * multiplicador;
      numero ~/= 10;

      multiplicador++;

      if (multiplicador > 7) {
        multiplicador = 2;
      }
    }

    final resultado = 11 - (suma % 11);

    if (resultado == 11) return '0';
    if (resultado == 10) return 'K';

    return resultado.toString();
  }

  ({int numero, String dv})? _obtenerRutValido(
    String valor,
  ) {
    final rutLimpio = _normalizarRut(valor);

    if (!RegExp(r'^\d{7,8}[0-9K]$').hasMatch(
      rutLimpio,
    )) {
      return null;
    }

    final numero = int.tryParse(
      rutLimpio.substring(
        0,
        rutLimpio.length - 1,
      ),
    );

    if (numero == null ||
        numero < 1000000 ||
        numero > 99999999) {
      return null;
    }

    final dv = rutLimpio.substring(
      rutLimpio.length - 1,
    );

    if (_calcularDv(numero) != dv) {
      return null;
    }

    return (
      numero: numero,
      dv: dv,
    );
  }

  // --------------------------------------------------
  // CARGAR DATOS ACTUALES
  // --------------------------------------------------

  Future<void> _cargarDatos() async {
    final usuario = _supabase.auth.currentUser;

    if (usuario == null) {
      if (!mounted) return;

      setState(() {
        _cargando = false;
        _error = 'Debes iniciar sesión nuevamente.';
      });
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final perfil = await _supabase
          .from('perfil')
          .select('nombre, apellido')
          .eq('id', usuario.id)
          .maybeSingle()
          .timeout(espera);

      final identificacion = await _supabase
          .from('perfil_identificacion')
          .select('usuario_id')
          .eq('usuario_id', usuario.id)
          .maybeSingle()
          .timeout(espera);

      if (!mounted ||
          _supabase.auth.currentUser?.id != usuario.id) {
        return;
      }

      if (perfil == null) {
        throw StateError(
          'No se encontró el perfil del usuario.',
        );
      }

      _nombreController.text =
          perfil['nombre']?.toString() ?? '';

      _apellidoController.text =
          perfil['apellido']?.toString() ?? '';

      setState(() {
        _identificacionRegistrada =
            identificacion != null;
        _cargando = false;
        _error = null;
      });
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _cargando = false;
        _error =
            'No pudimos conectar con Supabase. '
            'Revisa tu conexión e inténtalo nuevamente.';
      });
    } catch (error) {
      debugPrint(
        'Error al cargar identificación: $error',
      );

      if (!mounted) return;

      setState(() {
        _cargando = false;
        _error =
            'No pudimos cargar tus datos. '
            'Inténtalo nuevamente.';
      });
    }
  }

  // --------------------------------------------------
  // GUARDAR IDENTIFICACIÓN Y PERFIL
  // --------------------------------------------------

  Future<void> _guardar() async {
    if (_guardando || _cargando) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final usuario = _supabase.auth.currentUser;

    if (usuario == null ||
        _supabase.auth.currentSession == null) {
      setState(() {
        _error = 'Debes iniciar sesión nuevamente.';
      });
      return;
    }

    final rut = _identificacionRegistrada
        ? null
        : _obtenerRutValido(_rutController.text);

    if (!_identificacionRegistrada && rut == null) {
      setState(() {
        _error =
            'Ingresa un RUT válido con su '
            'dígito verificador.';
      });
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      // Guardar nombre y apellido en el
      // perfil existente, sin tocar RUT ni DV.

      await _supabase
          .from('perfil')
          .update({
            'nombre': _nombreController.text.trim(),
            'apellido': _apellidoController.text.trim(),
          })
          .eq('id', usuario.id)
          .select('id')
          .single()
          .timeout(espera);

      if (_supabase.auth.currentUser?.id != usuario.id) {
        throw StateError('La sesión cambió.');
      }

      // Registrar RUT una sola vez.
      // El servidor también valida su unicidad
      // y el dígito verificador.

      if (!_identificacionRegistrada) {
        await _supabase
            .from('perfil_identificacion')
            .insert({
              'usuario_id': usuario.id,
              'rut': rut!.numero,
              'dv': rut.dv,
            })
            .timeout(espera);

        if (mounted) {
          setState(() {
            _identificacionRegistrada = true;
          });
        }
      }

      // Comprobación final contra Supabase.

      final identificacion = await _supabase
          .from('perfil_identificacion')
          .select('usuario_id')
          .eq('usuario_id', usuario.id)
          .maybeSingle()
          .timeout(espera);

      if (identificacion == null) {
        throw StateError(
          'No se confirmó la identificación.',
        );
      }

      if (!mounted ||
          _supabase.auth.currentUser?.id != usuario.id) {
        return;
      }

      widget.onCompletado();
    } on PostgrestException catch (error) {
      debugPrint(
        'Error de Supabase al identificar: $error',
      );

      if (!mounted) return;

      setState(() {
        _error = error.code == '23505'
            ? 'No se pudo asociar el RUT. '
                'Puede estar registrado en otra cuenta. '
                'Si ya tienes una cuenta, '
                'recupera su acceso en lugar de crear otra.'
            : 'No pudimos registrar tus datos. '
                'Verifica la información e inténtalo nuevamente.';
      });
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _error =
            'El servidor no confirmó la operación. '
            'Pulsa "Revisar datos" antes de '
            'intentarlo nuevamente.';
      });
    } catch (error) {
      debugPrint(
        'Error al completar identificación: $error',
      );

      if (!mounted) return;

      setState(() {
        _error =
            'No fue posible completar la identificación. '
            'Pulsa "Revisar datos" e inténtalo nuevamente.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  // --------------------------------------------------
  // DECORACIÓN DE CAMPOS
  // --------------------------------------------------

  InputDecoration _decoracion(
    String etiqueta,
    IconData icono,
  ) {
    final esquema = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: etiqueta,
      prefixIcon: Icon(icono),
      filled: true,
      fillColor: esquema.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: esquema.outlineVariant,
        ),
      ),
    );
  }

  // --------------------------------------------------
  // PANTALLA
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final esquema = tema.colorScheme;

    return Scaffold(
      backgroundColor: tema.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: _cargando
              ? const CircularProgressIndicator()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 480,
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(19),
                            decoration: BoxDecoration(
                              color: verde,
                              borderRadius:
                                  BorderRadius.circular(22),
                            ),
                            child: const Icon(
                              Icons.badge_outlined,
                              color: Colors.white,
                              size: 38,
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        Text(
                          'Completar identificación',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: esquema.onSurface,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          'Completa tus datos esenciales '
                          'para continuar en NFC-FoodTech.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color:
                                esquema.onSurfaceVariant,
                          ),
                        ),

                        const SizedBox(height: 24),

                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: 16,
                            ),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: esquema.error,
                              ),
                            ),
                          ),

                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: 16,
                            ),
                            child: OutlinedButton.icon(
                              onPressed: _guardando
                                  ? null
                                  : _cargarDatos,
                              icon: const Icon(
                                Icons.refresh_rounded,
                              ),
                              label: const Text(
                                'Revisar datos',
                              ),
                            ),
                          ),

                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _nombreController,
                                textCapitalization:
                                    TextCapitalization.words,
                                textInputAction:
                                    TextInputAction.next,
                                maxLength: 80,
                                decoration: _decoracion(
                                  'Nombre',
                                  Icons.person_outline,
                                ),
                                validator: (valor) {
                                  if (valor == null ||
                                      valor.trim().isEmpty) {
                                    return 'Ingresa tu nombre.';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 12),

                              TextFormField(
                                controller:
                                    _apellidoController,
                                textCapitalization:
                                    TextCapitalization.words,
                                textInputAction:
                                    TextInputAction.next,
                                maxLength: 80,
                                decoration: _decoracion(
                                  'Apellido',
                                  Icons.person_outline,
                                ),
                                validator: (valor) {
                                  if (valor == null ||
                                      valor.trim().isEmpty) {
                                    return 'Ingresa tu apellido.';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 12),

                              if (!_identificacionRegistrada)
                                TextFormField(
                                  controller: _rutController,
                                  keyboardType:
                                      TextInputType.text,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  maxLength: 14,
                                  decoration: _decoracion(
                                    'RUT (ej. 12.345.678-5)',
                                    Icons.assignment_ind_outlined,
                                  ),
                                  validator: (valor) {
                                    if (valor == null ||
                                        valor.trim().isEmpty) {
                                      return 'Ingresa tu RUT.';
                                    }

                                    if (_obtenerRutValido(valor) ==
                                        null) {
                                      return 'El RUT o su dígito '
                                          'verificador no es válido.';
                                    }

                                    return null;
                                  },
                                )
                              else
                                Card(
                                  color: esquema.surface,
                                  child: const ListTile(
                                    leading: Icon(
                                      Icons.verified_user_outlined,
                                    ),
                                    title: Text(
                                      'RUT registrado',
                                    ),
                                    subtitle: Text(
                                      'Ya tienes una identificación '
                                      'asociada a esta cuenta.',
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        Text(
                          'El RUT se utiliza para evitar '
                          'registros duplicados. '
                          'La validación del dígito '
                          'verificador no acredita por sí '
                          'sola la identidad del titular.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: esquema.onSurfaceVariant,
                          ),
                        ),

                        const SizedBox(height: 22),

                        SizedBox(
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: _guardando
                                ? null
                                : _guardar,
                            icon: _guardando
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child:
                                        CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.check_circle_outline,
                                  ),
                            label: Text(
                              _guardando
                                  ? 'Guardando...'
                                  : 'Guardar y continuar',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: verde,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        Text(
                          'La fotografía, fecha de nacimiento '
                          'y otras preferencias son opcionales '
                          'y podrás completarlas después.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: esquema.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
