
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nfc_foodtech_app/config.dart';

import 'package:nfc_foodtech_app/features/auth/screens/registro_screen.dart';
import 'package:nfc_foodtech_app/features/auth/screens/recuperar_contrasena_screen.dart';

class InicioScreen extends StatefulWidget {
  const InicioScreen({super.key});

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> {
  static const Color verde = Color(0xFF236B4A);

  final _formKey = GlobalKey<FormState>();
  final _correoController = TextEditingController();
  final _contrasenaController = TextEditingController();

  bool _mostrarContrasena = false;
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
    _correoController.dispose();
    _contrasenaController.dispose();
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
  // INICIO DE SESIÓN CON CORREO
  // --------------------------------------------------

  Future<void> _iniciarSesion() async {
    if (_cargando) return;

    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() => _cargando = true);

    try {
      final respuesta =
          await Supabase.instance.client.auth.signInWithPassword(
        email: _correoController.text.trim(),
        password: _contrasenaController.text,
      );

      if (!mounted) return;

      if (respuesta.session == null) {
        _mostrarMensaje(
          'No se pudo iniciar sesión. Inténtalo nuevamente.',
        );
      }
    } on AuthException catch (error) {
      if (!mounted) return;

      if (error.code == 'email_not_confirmed') {
        _mostrarMensaje(
          'Debes confirmar tu correo antes de iniciar sesión.',
        );
      } else if (error.code == 'invalid_credentials') {
        _mostrarMensaje(
          'Correo o contraseña incorrectos.',
        );
      } else {
        _mostrarMensaje(error.message);
      }
    } catch (_) {
      if (!mounted) return;

      _mostrarMensaje(
        'Ocurrió un error al iniciar sesión.',
      );
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  // --------------------------------------------------
  // INICIO DE SESIÓN CON GOOGLE
  // --------------------------------------------------

  Future<void> _iniciarSesionGoogle() async {
    if (_cargando) return;

    setState(() => _cargando = true);

    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: AppConfig.authRedirectUrl,
      );
    } on AuthException catch (error) {
      if (!mounted) return;

      _mostrarMensaje(error.message);
    } catch (_) {
      if (!mounted) return;

      _mostrarMensaje(
        'No se pudo iniciar sesión con Google.',
      );
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  // --------------------------------------------------
  // DECORACIÓN DE CAMPOS
  // --------------------------------------------------

  InputDecoration _decoracion({
    required String etiqueta,
    required IconData icono,
    Widget? sufijo,
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

      suffixIcon: sufijo,

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
    );
  }

  // --------------------------------------------------
  // NAVEGACIÓN
  // --------------------------------------------------

  void _irARecuperarContrasena() {
    if (_cargando) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const RecuperarContrasenaScreen(),
      ),
    );
  }

  void _irARegistro() {
    if (_cargando) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const RegistroScreen(),
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),

            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 430,
              ),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // -------------------------------
                  // LOGO
                  // -------------------------------

                  Center(
                    child: Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        color: verde,
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: const Icon(
                        Icons.eco_rounded,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  Text(
                    'NFC-FoodTech',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.bold,
                      color: _colorPrincipal,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Cuida tus alimentos, reduce el desperdicio.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: _colorSecundario,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // -------------------------------
                  // TARJETA DE INICIO DE SESIÓN
                  // -------------------------------

                  Container(
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
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '¡Bienvenido!',
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                              color: _colorPrincipal,
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            'Inicia sesión para administrar tus alimentos.',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: _colorSecundario,
                            ),
                          ),

                          const SizedBox(height: 26),

                          // -----------------------
                          // CORREO ELECTRÓNICO
                          // -----------------------

                          TextFormField(
                            controller: _correoController,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            textInputAction: TextInputAction.next,

                            style: TextStyle(
                              color: esquema.onSurface,
                            ),

                            decoration: _decoracion(
                              etiqueta: 'Correo electrónico',
                              icono: Icons.email_outlined,
                            ),

                            validator: (valor) {
                              final correo = valor?.trim() ?? '';

                              if (correo.isEmpty) {
                                return 'Ingresa tu correo electrónico.';
                              }

                              if (!RegExp(
                                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                              ).hasMatch(correo)) {
                                return 'Ingresa un correo válido.';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 18),

                          // -----------------------
                          // CONTRASEÑA
                          // -----------------------

                          TextFormField(
                            controller: _contrasenaController,
                            obscureText: !_mostrarContrasena,
                            textInputAction: TextInputAction.done,

                            style: TextStyle(
                              color: esquema.onSurface,
                            ),

                            decoration: _decoracion(
                              etiqueta: 'Contraseña',
                              icono: Icons.lock_outline_rounded,

                              sufijo: IconButton(
                                tooltip: _mostrarContrasena
                                    ? 'Ocultar contraseña'
                                    : 'Mostrar contraseña',

                                onPressed: _cargando
                                    ? null
                                    : () {
                                        setState(() {
                                          _mostrarContrasena =
                                              !_mostrarContrasena;
                                        });
                                      },

                                icon: Icon(
                                  _mostrarContrasena
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: esquema.onSurfaceVariant,
                                ),
                              ),
                            ),

                            validator: (valor) {
                              if (valor == null || valor.isEmpty) {
                                return 'Ingresa tu contraseña.';
                              }

                              return null;
                            },

                            onFieldSubmitted: (_) {
                              _iniciarSesion();
                            },
                          ),

                          // -----------------------
                          // RECUPERAR CONTRASEÑA
                          // -----------------------

                          Align(
                            alignment: Alignment.centerRight,

                            child: TextButton(
                              onPressed: _cargando
                                  ? null
                                  : _irARecuperarContrasena,

                              child: Text(
                                '¿Olvidaste tu contraseña?',
                                style: TextStyle(
                                  color: _colorIconos,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // -----------------------
                          // INICIAR SESIÓN
                          // -----------------------

                          SizedBox(
                            height: 54,

                            child: ElevatedButton(
                              onPressed: _cargando
                                  ? null
                                  : _iniciarSesion,

                              style: ElevatedButton.styleFrom(
                                backgroundColor: verde,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    verde.withValues(alpha: 0.6),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
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
                                      'Iniciar sesión',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // -----------------------
                          // INICIAR SESIÓN CON GOOGLE
                          // -----------------------

                          OutlinedButton.icon(
                            onPressed: _cargando
                                ? null
                                : _iniciarSesionGoogle,

                            icon: const Icon(
                              Icons.g_mobiledata_rounded,
                              size: 30,
                            ),

                            label: const Text(
                              'Continuar con Google',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),

                            style: OutlinedButton.styleFrom(
                              foregroundColor: _colorIconos,
                              side: BorderSide(
                                color: esquema.outlineVariant,
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                            ),
                          ),

                          const SizedBox(height: 22),

                          // -----------------------
                          // CREAR CUENTA
                          // -----------------------

                          Text(
                            '¿Eres nuevo?',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _colorSecundario,
                            ),
                          ),

                          const SizedBox(height: 14),

                          OutlinedButton(
                            onPressed: _cargando
                                ? null
                                : _irARegistro,

                            style: OutlinedButton.styleFrom(
                              foregroundColor: _colorIconos,
                              side: BorderSide(
                                color: _colorIconos,
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 15,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),

                            child: const Text(
                              'Crear una cuenta',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // -------------------------------
                  // PIE DE PÁGINA
                  // -------------------------------

                  Text(
                    'Cada alimento cuenta 🌱',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _colorIconos,
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
