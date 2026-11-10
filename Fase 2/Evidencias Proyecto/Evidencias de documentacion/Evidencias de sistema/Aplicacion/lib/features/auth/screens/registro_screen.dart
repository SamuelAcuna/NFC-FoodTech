
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nfc_foodtech_app/config.dart';

class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  static const Color verde = Color(0xFF236B4A);
  static const Color rojoError = Color(0xFFB83D3D);

  final _formKey = GlobalKey<FormState>();

  final _correoController = TextEditingController();
  final _contrasenaController = TextEditingController();
  final _confirmarContrasenaController = TextEditingController();

  bool _mostrarContrasena = false;
  bool _mostrarConfirmacion = false;
  bool _cargando = false;

  // R81: aceptación de documentos.
  bool _aceptaDocumentos = false;
  bool _mostrarErrorAceptacion = false;

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

  Color get _colorBorde =>
      Theme.of(context).colorScheme.outlineVariant;

  // --------------------------------------------------
  // VALIDACIÓN R81
  // --------------------------------------------------

  bool _validarAceptacion() {
    if (_aceptaDocumentos) {
      setState(() {
        _mostrarErrorAceptacion = false;
      });
      return true;
    }

    setState(() {
      _mostrarErrorAceptacion = true;
    });

    _mostrarMensaje(
      'Debes aceptar los términos y la política de privacidad.',
    );

    return false;
  }

  // --------------------------------------------------
  // REGISTRO CON CORREO
  // Se mantiene la lógica original.
  // --------------------------------------------------

  Future<void> _registrarUsuario() async {
    if (_cargando) return;

    FocusScope.of(context).unfocus();

    final formularioValido =
        _formKey.currentState!.validate();
    final aceptacionValida = _validarAceptacion();

    if (!formularioValido || !aceptacionValida) return;

    setState(() {
      _cargando = true;
    });

    try {
      final respuesta =
          await Supabase.instance.client.auth.signUp(
        email: _correoController.text.trim(),
        password: _contrasenaController.text,
        emailRedirectTo: AppConfig.authRedirectUrl,
      );

      if (!mounted) return;

      _mostrarMensaje(
        respuesta.session == null
            ? 'Cuenta creada. Revisa tu correo '
                'para confirmar el registro.'
            : '¡Tu cuenta se creó correctamente!',
        exito: true,
      );
    } on AuthException catch (error) {
      if (!mounted) return;

      String mensaje;

      if (error.code == 'over_email_send_rate_limit') {
        mensaje =
            'Se alcanzó el límite de correos. '
            'Inténtalo más tarde.';
      } else if (error.code == 'user_already_exists') {
        mensaje = 'Este correo ya tiene una cuenta.';
      } else {
        mensaje = error.message;
      }

      _mostrarMensaje(mensaje);
    } catch (_) {
      if (!mounted) return;

      _mostrarMensaje(
        'Ocurrió un error. Inténtalo nuevamente.',
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
  // REGISTRO CON GOOGLE
  // Se mantiene la lógica original.
  // --------------------------------------------------

  Future<void> _registrarConGoogle() async {
    if (_cargando) return;

    if (!_validarAceptacion()) return;

    setState(() {
      _cargando = true;
    });

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
        'No se pudo continuar con Google. '
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
  // DOCUMENTOS PRELIMINARES R81
  // --------------------------------------------------

  void _abrirDocumento({
    required String titulo,
    required String contenido,
  }) {
    showDialog<void>(
      context: context,
      builder: (contextoDialogo) {
        final tema = Theme.of(contextoDialogo);
        final esquema = tema.colorScheme;
        final oscuro =
            tema.brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor: esquema.surface,

          title: Text(
            titulo,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: esquema.onSurface,
            ),
          ),

          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Aviso de documento preliminar.
                  Container(
                    padding: const EdgeInsets.all(12),

                    decoration: BoxDecoration(
                      color: oscuro
                          ? const Color(0xFF43371E)
                          : const Color(0xFFFFF4D6),
                      borderRadius: BorderRadius.circular(10),
                    ),

                    child: Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: oscuro
                              ? const Color(0xFFFFD98B)
                              : const Color(0xFF8B6200),
                          size: 20,
                        ),

                        const SizedBox(width: 8),

                        Expanded(
                          child: Text(
                            'Documento preliminar para pruebas. '
                            'Pendiente de revisión y aprobación.',
                            style: TextStyle(
                              color: oscuro
                                  ? const Color(0xFFFFE2A4)
                                  : const Color(0xFF765600),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  SelectableText(
                    contenido,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: esquema.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),

          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(contextoDialogo).pop(),
              child: Text(
                'Cerrar',
                style: TextStyle(
                  color: oscuro ? esquema.primary : verde,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _mostrarTerminos() {
    _abrirDocumento(
      titulo: 'Términos de uso',
      contenido: '''
1. PROPÓSITO DE NFC-FOODTECH

NFC-FoodTech es una aplicación orientada a facilitar la organización de alimentos en el hogar y apoyar la reducción del desperdicio alimentario.

2. CUENTAS DE USUARIO

Para utilizar las funcionalidades de la aplicación, los usuarios pueden crear una cuenta mediante correo electrónico o Google.

3. REGISTRO DE INFORMACIÓN

Los usuarios son responsables de ingresar y mantener actualizada la información de los alimentos que registran.

4. FECHAS ESTIMADAS DE CADUCIDAD

Las fechas estimadas de caducidad son referencias para organizar los alimentos. No garantizan que un producto sea seguro para su consumo.

Los usuarios deben revisar el estado real de los alimentos y seguir las indicaciones de conservación correspondientes.

5. USO DE LA APLICACIÓN

La aplicación está destinada a la gestión doméstica de alimentos. Su funcionamiento y disponibilidad pueden variar durante el desarrollo del proyecto.

6. CONDICIONES DEFINITIVAS

Las condiciones completas, la entidad responsable y los procedimientos asociados a las cuentas deberán definirse antes de publicar la aplicación.
''',
    );
  }

  void _mostrarPrivacidad() {
    _abrirDocumento(
      titulo: 'Política de privacidad',
      contenido: '''
1. FINALIDAD DEL TRATAMIENTO

NFC-FoodTech utiliza información para permitir el acceso a la aplicación y apoyar la gestión de alimentos del hogar.

2. INFORMACIÓN DE LA CUENTA

El registro mediante correo electrónico utiliza una dirección de correo y credenciales de autenticación.

El acceso mediante Google utiliza el proveedor de autenticación correspondiente.

3. INFORMACIÓN INGRESADA POR EL USUARIO

La aplicación contempla información de perfil, alimentos registrados, cantidades, ubicaciones y movimientos de consumo o desperdicio.

4. SERVICIOS UTILIZADOS

El proyecto utiliza Supabase para funciones de autenticación y almacenamiento de información. También puede utilizar Google para la autenticación.

5. CONTROL DE LA INFORMACIÓN

Los procedimientos para consultar, actualizar y solicitar la eliminación de datos deben definirse y verificarse antes de su publicación.

6. DOCUMENTO DEFINITIVO

Está pendiente establecer y aprobar la identificación del responsable de los datos, los plazos de conservación, las medidas aplicables, los mecanismos para ejercer derechos y los canales de contacto.
''',
    );
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
          duration: const Duration(seconds: 5),
        ),
      );
  }

  // --------------------------------------------------
  // CAMPOS ADAPTADOS AL TEMA
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
        color: _colorAcento,
      ),

      prefixIcon: Icon(
        icono,
        color: _colorAcento,
      ),

      suffixIcon: sufijo,

      filled: true,
      fillColor: esquema.surface,

      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 18,
      ),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: _colorBorde,
        ),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: _colorAcento,
          width: 1.7,
        ),
      ),

      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: esquema.error,
        ),
      ),

      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: esquema.error,
          width: 1.7,
        ),
      ),
    );
  }

  // --------------------------------------------------
  // CICLO DE VIDA
  // --------------------------------------------------

  @override
  void dispose() {
    _correoController.dispose();
    _contrasenaController.dispose();
    _confirmarContrasenaController.dispose();
    super.dispose();
  }

  // --------------------------------------------------
  // PANTALLA DE REGISTRO
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
            padding: const EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 24,
            ),

            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 440,
              ),

              child: Column(
                children: [
                  // -------------------------------
                  // LOGO
                  // -------------------------------

                  Container(
                    width: 72,
                    height: 72,

                    decoration: BoxDecoration(
                      color: verde,
                      borderRadius: BorderRadius.circular(24),
                    ),

                    child: const Icon(
                      Icons.eco_rounded,
                      color: Colors.white,
                      size: 39,
                    ),
                  ),

                  const SizedBox(height: 14),

                  Text(
                    'NFC-FoodTech',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                      color: _colorPrincipal,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    'Aprovecha mejor tus alimentos',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: _colorSecundario,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // -------------------------------
                  // TARJETA DE REGISTRO
                  // -------------------------------

                  Container(
                    padding: const EdgeInsets.all(24),

                    decoration: BoxDecoration(
                      color: esquema.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _colorBorde,
                      ),

                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: _modoOscuro ? 0.10 : 0.04,
                          ),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),

                    child: Form(
                      key: _formKey,

                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Crea tu cuenta',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: _colorPrincipal,
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            'Empieza a organizar tus alimentos '
                            'y a reducir el desperdicio.',
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
                            keyboardType:
                                TextInputType.emailAddress,
                            autocorrect: false,
                            textInputAction: TextInputAction.next,

                            style: TextStyle(
                              color: esquema.onSurface,
                            ),

                            decoration: _decoracion(
                              etiqueta: 'Correo electrónico',
                              icono: Icons.mail_outline_rounded,
                            ),

                            validator: (valor) {
                              final correo = valor?.trim() ?? '';

                              if (correo.isEmpty) {
                                return 'Ingresa tu correo electrónico';
                              }

                              if (!RegExp(
                                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                              ).hasMatch(correo)) {
                                return 'Ingresa un correo válido';
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
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.next,

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
                                  color: _colorSecundario,
                                ),
                              ),
                            ),

                            validator: (valor) {
                              if (valor == null || valor.isEmpty) {
                                return 'Ingresa una contraseña';
                              }

                              if (valor.length < 6) {
                                return 'Debe tener al menos 6 caracteres';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 18),

                          // -----------------------
                          // CONFIRMAR CONTRASEÑA
                          // -----------------------

                          TextFormField(
                            controller:
                                _confirmarContrasenaController,
                            obscureText: !_mostrarConfirmacion,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,

                            onFieldSubmitted: (_) {
                              _registrarUsuario();
                            },

                            style: TextStyle(
                              color: esquema.onSurface,
                            ),

                            decoration: _decoracion(
                              etiqueta: 'Repetir contraseña',
                              icono: Icons.verified_user_outlined,

                              sufijo: IconButton(
                                tooltip: _mostrarConfirmacion
                                    ? 'Ocultar contraseña'
                                    : 'Mostrar contraseña',

                                onPressed: _cargando
                                    ? null
                                    : () {
                                        setState(() {
                                          _mostrarConfirmacion =
                                              !_mostrarConfirmacion;
                                        });
                                      },

                                icon: Icon(
                                  _mostrarConfirmacion
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: _colorSecundario,
                                ),
                              ),
                            ),

                            validator: (valor) {
                              if (valor == null || valor.isEmpty) {
                                return 'Repite tu contraseña';
                              }

                              if (valor !=
                                  _contrasenaController.text) {
                                return 'Las contraseñas no coinciden';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 24),

                          // -----------------------
                          // R81: TÉRMINOS Y PRIVACIDAD
                          // -----------------------

                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),

                            decoration: BoxDecoration(
                              color: _modoOscuro
                                  ? esquema.surfaceContainerHighest
                                  : const Color(0xFFF7FAF7),

                              borderRadius:
                                  BorderRadius.circular(14),

                              border: Border.all(
                                color: _mostrarErrorAceptacion
                                    ? esquema.error
                                    : _colorBorde,
                              ),
                            ),

                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,

                                  controlAffinity:
                                      ListTileControlAffinity.leading,

                                  activeColor: _colorAcento,
                                  checkColor: _modoOscuro
                                      ? esquema.onPrimary
                                      : Colors.white,

                                  value: _aceptaDocumentos,

                                  onChanged: _cargando
                                      ? null
                                      : (valor) {
                                          setState(() {
                                            _aceptaDocumentos =
                                                valor ?? false;

                                            if (_aceptaDocumentos) {
                                              _mostrarErrorAceptacion =
                                                  false;
                                            }
                                          });
                                        },

                                  title: Text(
                                    'He leído y acepto los términos '
                                    'de uso y la política de privacidad.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.4,
                                      color: esquema.onSurface,
                                    ),
                                  ),
                                ),

                                Padding(
                                  padding:
                                      const EdgeInsets.only(left: 12),

                                  child: Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 4,

                                    children: [
                                      TextButton(
                                        onPressed: _mostrarTerminos,

                                        child: Text(
                                          'Ver términos de uso',
                                          style: TextStyle(
                                            color: _colorAcento,
                                          ),
                                        ),
                                      ),

                                      Text(
                                        '•',
                                        style: TextStyle(
                                          color: _colorSecundario,
                                        ),
                                      ),

                                      TextButton(
                                        onPressed: _mostrarPrivacidad,

                                        child: Text(
                                          'Ver privacidad',
                                          style: TextStyle(
                                            color: _colorAcento,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                if (_mostrarErrorAceptacion)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(
                                      left: 12,
                                      top: 4,
                                    ),

                                    child: Text(
                                      'Debes aceptar ambos documentos '
                                      'para continuar.',
                                      style: TextStyle(
                                        color: esquema.error,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),

                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 12,
                                    top: 6,
                                  ),

                                  child: Text(
                                    'Documentos preliminares para '
                                    'pruebas del proyecto.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _colorSecundario,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // -----------------------
                          // CREAR CUENTA CON CORREO
                          // -----------------------

                          SizedBox(
                            height: 54,

                            child: ElevatedButton(
                              onPressed: _cargando
                                  ? null
                                  : _registrarUsuario,

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
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Crear cuenta',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // -----------------------
                          // REGISTRARSE CON GOOGLE
                          // -----------------------

                          OutlinedButton.icon(
                            onPressed: _cargando
                                ? null
                                : _registrarConGoogle,

                            icon: const Icon(
                              Icons.g_mobiledata_rounded,
                              size: 30,
                            ),

                            label: const Text(
                              'Registrarse con Google',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),

                            style: OutlinedButton.styleFrom(
                              foregroundColor: _colorAcento,

                              side: BorderSide(
                                color: _colorBorde,
                              ),

                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),

                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(15),
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // -----------------------
                          // VOLVER AL INICIO DE SESIÓN
                          // -----------------------

                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment:
                                WrapCrossAlignment.center,
                            spacing: 4,

                            children: [
                              Text(
                                '¿Ya tienes una cuenta?',
                                style: TextStyle(
                                  color: _colorSecundario,
                                  fontSize: 13,
                                ),
                              ),

                              TextButton(
                                onPressed: _cargando
                                    ? null
                                    : () {
                                        Navigator.of(context).pop();
                                      },

                                child: Text(
                                  'Inicia sesión',
                                  style: TextStyle(
                                    color: _colorAcento,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,

                            children: [
                              Icon(
                                Icons.eco_outlined,
                                color: _colorAcento,
                                size: 17,
                              ),

                              const SizedBox(width: 7),

                              Flexible(
                                child: Text(
                                  'Tu despensa, mejor organizada.',
                                  textAlign: TextAlign.center,

                                  style: TextStyle(
                                    color: _colorSecundario,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Text(
                    'NFC-FoodTech · Menos desperdicio, '
                    'mejor aprovechamiento',
                    textAlign: TextAlign.center,

                    style: TextStyle(
                      color: _colorSecundario,
                      fontSize: 11,
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
