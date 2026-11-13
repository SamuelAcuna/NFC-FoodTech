
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CambiarContrasenaScreen extends StatefulWidget {
  const CambiarContrasenaScreen({super.key});

  @override
  State<CambiarContrasenaScreen> createState() =>
      _CambiarContrasenaScreenState();
}

class _CambiarContrasenaScreenState
    extends State<CambiarContrasenaScreen> {
  static const Color verde = Color(0xFF236B4A);

  final _formKey = GlobalKey<FormState>();

  final _actualController = TextEditingController();
  final _nuevaController = TextEditingController();
  final _confirmarController = TextEditingController();
  final _codigoController = TextEditingController();

  bool _mostrarActual = false;
  bool _mostrarNueva = false;
  bool _mostrarConfirmacion = false;

  bool _cargando = false;
  bool _enviandoCodigo = false;
  bool _codigoSolicitado = false;

  // --------------------------------------------------
  // COLORES ADAPTADOS AL TEMA
  // --------------------------------------------------

  bool get _modoOscuro =>
      Theme.of(context).brightness == Brightness.dark;

  Color get _colorPrincipal {
    final esquema = Theme.of(context).colorScheme;
    return _modoOscuro ? esquema.onSurface : verde;
  }

  Color get _colorSecundario =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  Color get _colorIconos {
    final esquema = Theme.of(context).colorScheme;
    return _modoOscuro ? esquema.primary : verde;
  }

  // --------------------------------------------------
  // CICLO DE VIDA
  // --------------------------------------------------

  @override
  void dispose() {
    _actualController.dispose();
    _nuevaController.dispose();
    _confirmarController.dispose();
    _codigoController.dispose();
    super.dispose();
  }

  // --------------------------------------------------
  // MENSAJES
  // --------------------------------------------------

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // --------------------------------------------------
  // CÓDIGO DE VERIFICACIÓN
  // --------------------------------------------------

  Future<void> _solicitarCodigo() async {
    if (_enviandoCodigo || _cargando) return;

    setState(() {
      _enviandoCodigo = true;
    });

    try {
      await Supabase.instance.client.auth.reauthenticate();

      if (!mounted) return;

      setState(() {
        _codigoSolicitado = true;
      });

      _mostrarMensaje(
        'Revisa tu correo para obtener el código de verificación.',
      );
    } on AuthException catch (error) {
      _mostrarMensaje(error.message);
    } catch (_) {
      _mostrarMensaje(
        'No se pudo enviar el código. Inténtalo nuevamente.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _enviandoCodigo = false;
        });
      }
    }
  }

  // --------------------------------------------------
  // CAMBIAR CONTRASEÑA
  // Conserva la lógica existente de Supabase.
  // --------------------------------------------------

  Future<void> _cambiarContrasena() async {
    if (_cargando || _enviandoCodigo) return;

    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_actualController.text == _nuevaController.text) {
      _mostrarMensaje(
        'La nueva contraseña debe ser diferente de la actual.',
      );
      return;
    }

    if (_codigoSolicitado &&
        _codigoController.text.trim().isEmpty) {
      _mostrarMensaje(
        'Ingresa el código enviado a tu correo.',
      );
      return;
    }

    setState(() {
      _cargando = true;
    });

    try {
      final auth = Supabase.instance.client.auth;

      if (auth.currentSession == null) {
        _mostrarMensaje(
          'Tu sesión ha expirado. Inicia sesión nuevamente.',
        );
        return;
      }

      await auth.updateUser(
        UserAttributes(
          password: _nuevaController.text,
          currentPassword: _actualController.text,
          nonce: _codigoSolicitado
              ? _codigoController.text.trim()
              : null,
        ),
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } on AuthException catch (error) {
      if (!mounted) return;

      switch (error.code) {
        case 'current_password_mismatch':
          _mostrarMensaje(
            'La contraseña actual no es correcta.',
          );
          break;

        case 'current_password_required':
          _mostrarMensaje(
            'Debes ingresar tu contraseña actual.',
          );
          break;

        case 'reauthentication_needed':
          _mostrarMensaje(
            'Por seguridad, Supabase requiere verificar '
            'tu identidad. Presiona "Enviar código '
            'de verificación".',
          );
          break;

        case 'same_password':
          _mostrarMensaje(
            'Elige una contraseña diferente a la anterior.',
          );
          break;

        case 'weak_password':
          _mostrarMensaje(
            'La contraseña no cumple los requisitos '
            'de seguridad.',
          );
          break;

        default:
          _mostrarMensaje(error.message);
          break;
      }
    } catch (error) {
      debugPrint(
        'Error al cambiar contraseña: $error',
      );

      _mostrarMensaje(
        'No se pudo actualizar la contraseña. '
        'Inténtalo otra vez.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  // --------------------------------------------------
  // DECORACIÓN ADAPTADA AL TEMA
  // --------------------------------------------------

  InputDecoration _decoracion({
    required String etiqueta,
    required IconData icono,
    bool? visible,
    VoidCallback? alternar,
  }) {
    final esquema = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: etiqueta,
      labelStyle: TextStyle(
        color: esquema.onSurfaceVariant,
      ),
      floatingLabelStyle: TextStyle(
        color: _colorIconos,
      ),
      prefixIcon: Icon(
        icono,
        color: _colorIconos,
      ),

      suffixIcon: alternar == null
          ? null
          : IconButton(
              tooltip: visible == true
                  ? 'Ocultar contraseña'
                  : 'Mostrar contraseña',
              onPressed: _cargando ? null : alternar,
              icon: Icon(
                visible == true
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: esquema.onSurfaceVariant,
              ),
            ),

      filled: true,
      fillColor: esquema.surface,

      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 18,
      ),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
      ),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: esquema.outlineVariant,
        ),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: _colorIconos,
          width: 1.8,
        ),
      ),

      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: esquema.outlineVariant.withValues(
            alpha: 0.6,
          ),
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

      appBar: AppBar(
        title: const Text('Cambiar contraseña'),
        backgroundColor: tema.scaffoldBackgroundColor,
        foregroundColor: _colorPrincipal,
      ),

      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 430,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: esquema.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: esquema.outlineVariant,
                  ),
                ),

                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                    children: [
                      // Encabezado
                      Icon(
                        Icons.lock_reset_rounded,
                        size: 60,
                        color: _colorIconos,
                      ),

                      const SizedBox(height: 16),

                      Text(
                        'Protege tu cuenta',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _colorPrincipal,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        'Ingresa tu contraseña actual y '
                        'elige una nueva. Esta opción está '
                        'pensada para cuentas que usan contraseña.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _colorSecundario,
                          height: 1.5,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 26),

                      // Contraseña actual
                      TextFormField(
                        controller: _actualController,
                        enabled: !_cargando,
                        obscureText: !_mostrarActual,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        style: TextStyle(
                          color: esquema.onSurface,
                        ),
                        decoration: _decoracion(
                          etiqueta: 'Contraseña actual',
                          icono: Icons.lock_outline_rounded,
                          visible: _mostrarActual,
                          alternar: () {
                            setState(() {
                              _mostrarActual = !_mostrarActual;
                            });
                          },
                        ),
                        validator: (valor) {
                          if (valor == null || valor.isEmpty) {
                            return 'Ingresa tu contraseña actual.';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // Nueva contraseña
                      TextFormField(
                        controller: _nuevaController,
                        enabled: !_cargando,
                        obscureText: !_mostrarNueva,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        style: TextStyle(
                          color: esquema.onSurface,
                        ),
                        decoration: _decoracion(
                          etiqueta: 'Nueva contraseña',
                          icono: Icons.lock_outline_rounded,
                          visible: _mostrarNueva,
                          alternar: () {
                            setState(() {
                              _mostrarNueva = !_mostrarNueva;
                            });
                          },
                        ),
                        validator: (valor) {
                          if (valor == null || valor.length < 8) {
                            return 'Usa al menos 8 caracteres.';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // Confirmar contraseña
                      TextFormField(
                        controller: _confirmarController,
                        enabled: !_cargando,
                        obscureText: !_mostrarConfirmacion,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        style: TextStyle(
                          color: esquema.onSurface,
                        ),
                        decoration: _decoracion(
                          etiqueta: 'Confirmar contraseña',
                          icono: Icons.verified_user_outlined,
                          visible: _mostrarConfirmacion,
                          alternar: () {
                            setState(() {
                              _mostrarConfirmacion =
                                  !_mostrarConfirmacion;
                            });
                          },
                        ),
                        validator: (valor) {
                          if (valor == null || valor.isEmpty) {
                            return 'Confirma tu nueva contraseña.';
                          }

                          if (valor != _nuevaController.text) {
                            return 'Las contraseñas no coinciden.';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 18),

                      // Código de verificación de Supabase
                      OutlinedButton.icon(
                        onPressed: _cargando || _enviandoCodigo
                            ? null
                            : _solicitarCodigo,

                        icon: _enviandoCodigo
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.mark_email_read_outlined,
                              ),

                        label: Text(
                          _enviandoCodigo
                              ? 'Enviando...'
                              : 'Enviar código de verificación '
                                  '(si se solicita)',
                          textAlign: TextAlign.center,
                        ),

                        style: OutlinedButton.styleFrom(
                          foregroundColor: _colorIconos,
                          side: BorderSide(
                            color: esquema.outlineVariant,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                      ),

                      if (_codigoSolicitado) ...[
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: _codigoController,
                          enabled: !_cargando,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.done,
                          style: TextStyle(
                            color: esquema.onSurface,
                          ),
                          decoration: _decoracion(
                            etiqueta: 'Código recibido por correo',
                            icono: Icons.pin_outlined,
                          ),
                        ),
                      ],

                      const SizedBox(height: 22),

                      // Guardar nueva contraseña
                      SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _cargando || _enviandoCodigo
                              ? null
                              : _cambiarContrasena,

                          style: ElevatedButton.styleFrom(
                            backgroundColor: verde,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                verde.withValues(alpha: 0.6),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(15),
                            ),
                          ),

                          child: _cargando
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Guardar nueva contraseña',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
