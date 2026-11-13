
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NuevaContrasenaScreen extends StatefulWidget {
  const NuevaContrasenaScreen({super.key});

  @override
  State<NuevaContrasenaScreen> createState() =>
      _NuevaContrasenaScreenState();
}

class _NuevaContrasenaScreenState
    extends State<NuevaContrasenaScreen> {
  static const Color verde = Color(0xFF236B4A);
  static const Color rojoError = Color(0xFFB83D3D);

  final _formKey = GlobalKey<FormState>();

  final _contrasenaController = TextEditingController();
  final _confirmacionController = TextEditingController();

  bool _mostrarContrasena = false;
  bool _mostrarConfirmacion = false;
  bool _cargando = false;

  // --------------------------------------------------
  // COLORES ADAPTADOS AL TEMA
  // --------------------------------------------------

  bool get _modoOscuro =>
      Theme.of(context).brightness == Brightness.dark;

  Color get _colorPrincipal {
    final esquema = Theme.of(context).colorScheme;

    return _modoOscuro ? esquema.onSurface : verde;
  }

  Color get _colorAcento {
    final esquema = Theme.of(context).colorScheme;

    return _modoOscuro ? esquema.primary : verde;
  }

  Color get _colorSecundario =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  // --------------------------------------------------
  // CICLO DE VIDA
  // --------------------------------------------------

  @override
  void dispose() {
    _contrasenaController.dispose();
    _confirmacionController.dispose();
    super.dispose();
  }

  // --------------------------------------------------
  // MENSAJES
  // --------------------------------------------------

  void _mostrarMensaje(
    String mensaje, {
    bool exito = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            mensaje,
            style: _modoOscuro ? const TextStyle(color: Colors.white) : null,
          ),
          backgroundColor: exito ? verde : rojoError,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // --------------------------------------------------
  // GUARDAR NUEVA CONTRASEÑA
  // Se conserva la lógica original de Supabase.
  // --------------------------------------------------

  Future<void> _guardarContrasena() async {
    if (_cargando) return;

    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _cargando = true;
    });

    try {
      final auth = Supabase.instance.client.auth;

      if (auth.currentSession == null) {
        _mostrarMensaje(
          'El enlace de recuperación no es válido '
          'o ha expirado.',
        );
        return;
      }

      await auth.updateUser(
        UserAttributes(
          password: _contrasenaController.text,
        ),
      );

      if (!mounted) return;

      _mostrarMensaje(
        'Tu contraseña se actualizó correctamente.',
        exito: true,
      );

      await Future<void>.delayed(
        const Duration(milliseconds: 900),
      );

      // Al cerrar sesión, main.dart vuelve a InicioScreen.
      await auth.signOut();
    } on AuthException catch (error) {
      if (!mounted) return;

      _mostrarMensaje(error.message);
    } catch (error) {
      if (!mounted) return;

      debugPrint(
        'Error al actualizar contraseña: $error',
      );

      _mostrarMensaje(
        'No se pudo actualizar la contraseña. '
        'Solicita un nuevo enlace e inténtalo nuevamente.',
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
  // CAMPOS ADAPTADOS AL TEMA
  // --------------------------------------------------

  InputDecoration _decoracion({
    required String etiqueta,
    required bool mostrar,
    required VoidCallback alternar,
  }) {
    final esquema = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: etiqueta,

      labelStyle: TextStyle(
        color: esquema.onSurfaceVariant,
      ),

      floatingLabelStyle: TextStyle(
        color: _colorAcento,
      ),

      prefixIcon: Icon(
        Icons.lock_outline_rounded,
        color: _colorAcento,
      ),

      suffixIcon: IconButton(
        tooltip: mostrar
            ? 'Ocultar contraseña'
            : 'Mostrar contraseña',

        onPressed: _cargando ? null : alternar,

        icon: Icon(
          mostrar
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
          color: _colorAcento,
          width: 1.8,
        ),
      ),

      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: esquema.error,
        ),
      ),

      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: esquema.error,
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
        title: const Text('Nueva contraseña'),
        backgroundColor: tema.scaffoldBackgroundColor,
        foregroundColor: _colorPrincipal,
        elevation: 0,
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
                      // -----------------------
                      // ÍCONO PRINCIPAL
                      // -----------------------

                      Icon(
                        Icons.lock_reset_rounded,
                        size: 64,
                        color: _colorAcento,
                      ),

                      const SizedBox(height: 20),

                      // -----------------------
                      // TÍTULO
                      // -----------------------

                      Text(
                        'Crea una nueva contraseña',
                        textAlign: TextAlign.center,

                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _colorPrincipal,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        'Ingresa y confirma tu nueva contraseña '
                        'para recuperar el acceso a tu cuenta.',
                        textAlign: TextAlign.center,

                        style: TextStyle(
                          color: _colorSecundario,
                          height: 1.5,
                        ),
                      ),

                      const SizedBox(height: 28),

                      // -----------------------
                      // NUEVA CONTRASEÑA
                      // -----------------------

                      TextFormField(
                        controller: _contrasenaController,
                        obscureText: !_mostrarContrasena,
                        enabled: !_cargando,

                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,

                        style: TextStyle(
                          color: esquema.onSurface,
                        ),

                        decoration: _decoracion(
                          etiqueta: 'Nueva contraseña',
                          mostrar: _mostrarContrasena,

                          alternar: () {
                            setState(() {
                              _mostrarContrasena =
                                  !_mostrarContrasena;
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

                      const SizedBox(height: 18),

                      // -----------------------
                      // CONFIRMAR CONTRASEÑA
                      // -----------------------

                      TextFormField(
                        controller: _confirmacionController,
                        obscureText: !_mostrarConfirmacion,
                        enabled: !_cargando,

                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,

                        style: TextStyle(
                          color: esquema.onSurface,
                        ),

                        decoration: _decoracion(
                          etiqueta: 'Confirmar contraseña',
                          mostrar: _mostrarConfirmacion,

                          alternar: () {
                            setState(() {
                              _mostrarConfirmacion =
                                  !_mostrarConfirmacion;
                            });
                          },
                        ),

                        validator: (valor) {
                          if (valor == null || valor.isEmpty) {
                            return 'Confirma tu contraseña.';
                          }

                          if (valor !=
                              _contrasenaController.text) {
                            return 'Las contraseñas no coinciden.';
                          }

                          return null;
                        },

                        onFieldSubmitted: (_) {
                          _guardarContrasena();
                        },
                      ),

                      const SizedBox(height: 26),

                      // -----------------------
                      // GUARDAR NUEVA CONTRASEÑA
                      // -----------------------

                      SizedBox(
                        height: 54,

                        child: ElevatedButton(
                          onPressed: _cargando
                              ? null
                              : _guardarContrasena,

                          style: ElevatedButton.styleFrom(
                            backgroundColor: verde,
                            foregroundColor: Colors.white,

                            disabledBackgroundColor:
                                verde.withValues(alpha: 0.6),

                            elevation: 0,

                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(15),
                            ),
                          ),

                          child: _cargando
                              ? const SizedBox(
                                  width: 23,
                                  height: 23,

                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Guardar nueva contraseña',
                                  textAlign: TextAlign.center,

                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
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
