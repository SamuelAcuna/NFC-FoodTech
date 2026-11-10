
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nfc_foodtech_app/config.dart';

class RecuperarContrasenaScreen extends StatefulWidget {
  const RecuperarContrasenaScreen({super.key});

  @override
  State<RecuperarContrasenaScreen> createState() =>
      _RecuperarContrasenaScreenState();
}

class _RecuperarContrasenaScreenState
    extends State<RecuperarContrasenaScreen> {
  static const Color verde = Color(0xFF236B4A);
  static const Color rojoError = Color(0xFFB83D3D);

  final _formKey = GlobalKey<FormState>();
  final _correoController = TextEditingController();

  bool _cargando = false;
  bool _correoEnviado = false;

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
    _correoController.dispose();
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
  // ENVIAR CORREO DE RECUPERACIÓN
  // Se mantiene la lógica original de Supabase.
  // --------------------------------------------------

  Future<void> _enviarCorreo() async {
    if (_cargando) return;

    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _cargando = true;
    });

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _correoController.text.trim(),
        redirectTo: AppConfig.authRedirectUrl,
      );

      if (!mounted) return;

      setState(() {
        _correoEnviado = true;
      });
    } on AuthException catch (error) {
      if (!mounted) return;

      _mostrarMensaje(error.message);
    } catch (_) {
      if (!mounted) return;

      _mostrarMensaje(
        'No se pudo enviar la solicitud. '
        'Inténtalo nuevamente.',
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

  InputDecoration _decoracion() {
    final esquema = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: 'Correo electrónico',
      hintText: 'ejemplo@correo.com',

      labelStyle: TextStyle(
        color: esquema.onSurfaceVariant,
      ),

      floatingLabelStyle: TextStyle(
        color: _colorAcento,
      ),

      hintStyle: TextStyle(
        color: esquema.onSurfaceVariant,
      ),

      prefixIcon: Icon(
        Icons.email_outlined,
        color: _colorAcento,
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
    );
  }

  // --------------------------------------------------
  // FORMULARIO DE RECUPERACIÓN
  // --------------------------------------------------

  Widget _construirFormulario() {
    final esquema = Theme.of(context).colorScheme;

    return Form(
      key: _formKey,

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Recupera tu cuenta',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: _colorPrincipal,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            'Ingresa el correo asociado a tu cuenta. '
            'Te enviaremos un enlace para continuar '
            'con la recuperación de tu contraseña.',
            style: TextStyle(
              color: _colorSecundario,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 26),

          // Correo electrónico
          TextFormField(
            controller: _correoController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enabled: !_cargando,
            textInputAction: TextInputAction.done,

            style: TextStyle(
              color: esquema.onSurface,
            ),

            decoration: _decoracion(),

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

            onFieldSubmitted: (_) {
              _enviarCorreo();
            },
          ),

          const SizedBox(height: 24),

          // Enviar enlace
          SizedBox(
            height: 54,

            child: ElevatedButton(
              onPressed: _cargando ? null : _enviarCorreo,

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
                      'Enviar enlace de recuperación',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------
  // CONFIRMACIÓN DEL ENVÍO
  // --------------------------------------------------

  Widget _construirConfirmacion() {
    return Column(
      children: [
        Icon(
          Icons.mark_email_read_outlined,
          color: _colorAcento,
          size: 66,
        ),

        const SizedBox(height: 20),

        Text(
          'Revisa tu correo',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.bold,
            color: _colorPrincipal,
          ),
        ),

        const SizedBox(height: 12),

        Text(
          'Si la dirección corresponde a una cuenta, '
          'recibirás instrucciones para recuperar tu contraseña.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _colorSecundario,
            height: 1.5,
          ),
        ),

        const SizedBox(height: 12),

        Text(
          _correoController.text.trim(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: _colorAcento,
          ),
        ),

        const SizedBox(height: 26),

        // Volver al inicio
        SizedBox(
          width: double.infinity,
          height: 52,

          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
            },

            style: ElevatedButton.styleFrom(
              backgroundColor: verde,
              foregroundColor: Colors.white,
              elevation: 0,

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),

            child: const Text(
              'Volver al inicio de sesión',
              textAlign: TextAlign.center,
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Usar otra dirección
        TextButton(
          onPressed: _cargando
              ? null
              : () {
                  setState(() {
                    _correoEnviado = false;
                  });
                },

          child: Text(
            'Usar otro correo',
            style: TextStyle(
              color: _colorAcento,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------
  // PANTALLA PRINCIPAL
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final esquema = tema.colorScheme;

    return Scaffold(
      backgroundColor: tema.scaffoldBackgroundColor,

      appBar: AppBar(
        backgroundColor: tema.scaffoldBackgroundColor,
        foregroundColor: _colorPrincipal,
        elevation: 0,

        title: const Text(
          'Recuperar contraseña',
        ),
      ),

      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),

            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 430,
              ),

              child: Column(
                children: [
                  // -----------------------
                  // ÍCONO
                  // -----------------------

                  Container(
                    width: 76,
                    height: 76,

                    decoration: BoxDecoration(
                      color: verde,
                      borderRadius: BorderRadius.circular(23),
                    ),

                    child: const Icon(
                      Icons.lock_reset_rounded,
                      color: Colors.white,
                      size: 43,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // -----------------------
                  // TARJETA
                  // -----------------------

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),

                    decoration: BoxDecoration(
                      color: esquema.surface,
                      borderRadius: BorderRadius.circular(24),

                      border: Border.all(
                        color: esquema.outlineVariant,
                      ),
                    ),

                    child: _correoEnviado
                        ? _construirConfirmacion()
                        : _construirFormulario(),
                  ),

                  const SizedBox(height: 24),

                  Text(
                    'NFC-FoodTech 🌱',
                    style: TextStyle(
                      color: _colorAcento,
                      fontWeight: FontWeight.w600,
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
