
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AceptacionDocumentosScreen extends StatefulWidget {
  final VoidCallback onAceptacionRegistrada;

  const AceptacionDocumentosScreen({
    super.key,
    required this.onAceptacionRegistrada,
  });

  @override
  State<AceptacionDocumentosScreen> createState() =>
      _AceptacionDocumentosScreenState();
}

class _AceptacionDocumentosScreenState
    extends State<AceptacionDocumentosScreen> {
  static const Color verde = Color(0xFF236B4A);

  static const String versionTerminos =
      'BORRADOR-R81-1';

  static const String versionPrivacidad =
      'BORRADOR-R81-1';

  static const Duration tiempoEspera =
      Duration(seconds: 8);

  bool _aceptaDocumentos = false;
  bool _guardando = false;
  bool _mostrarErrorAceptacion = false;

  String? _errorServidor;

  // --------------------------------------------------
  // DOCUMENTOS PRELIMINARES
  // --------------------------------------------------

  static const String _textoTerminos = '''
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
''';

  static const String _textoPrivacidad = '''
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
''';

  // --------------------------------------------------
  // COLORES
  // --------------------------------------------------

  bool get _modoOscuro =>
      Theme.of(context).brightness ==
      Brightness.dark;

  Color get _colorPrincipal {
    final esquema = Theme.of(context).colorScheme;

    return _modoOscuro
        ? esquema.onSurface
        : verde;
  }

  // --------------------------------------------------
  // MOSTRAR DOCUMENTOS
  // --------------------------------------------------

  void _abrirDocumento({
    required String titulo,
    required String contenido,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final tema = Theme.of(dialogContext);
        final esquema = tema.colorScheme;

        final oscuro =
            tema.brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor: esquema.surface,

          title: Text(
            titulo,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: esquema.onSurface,
            ),
          ),

          content: SizedBox(
            width: 480,

            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.start,

                children: [
                  Container(
                    padding: const EdgeInsets.all(12),

                    decoration: BoxDecoration(
                      color: oscuro
                          ? const Color(0xFF43371E)
                          : const Color(0xFFFFF4D6),

                      borderRadius:
                          BorderRadius.circular(10),
                    ),

                    child: Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,

                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 20,
                          color: oscuro
                              ? const Color(0xFFFFD98B)
                              : const Color(0xFF8B6200),
                        ),

                        const SizedBox(width: 8),

                        Expanded(
                          child: Text(
                            'Documento preliminar para '
                            'pruebas del proyecto. '
                            'Pendiente de revisión y aprobación.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: oscuro
                                  ? const Color(0xFFFFE2A4)
                                  : const Color(0xFF765600),
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
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  void _mostrarTerminos() {
    _abrirDocumento(
      titulo: 'Términos de uso',
      contenido: _textoTerminos,
    );
  }

  void _mostrarPrivacidad() {
    _abrirDocumento(
      titulo: 'Política de privacidad',
      contenido: _textoPrivacidad,
    );
  }

  // --------------------------------------------------
  // VERIFICAR SI LA ACEPTACIÓN QUEDÓ REGISTRADA
  // --------------------------------------------------

  Future<bool> _aceptacionExiste(
    String usuarioId,
  ) async {
    final registro = await Supabase.instance.client
        .from('aceptacion_documentos')
        .select('usuario_id')
        .eq('usuario_id', usuarioId)
        .eq(
          'terminos_version',
          versionTerminos,
        )
        .eq(
          'privacidad_version',
          versionPrivacidad,
        )
        .maybeSingle()
        .timeout(tiempoEspera);

    return registro != null;
  }

  // --------------------------------------------------
  // GUARDAR ACEPTACIÓN EN SUPABASE
  // --------------------------------------------------

  Future<void> _guardarAceptacion() async {
    if (_guardando) return;

    if (!_aceptaDocumentos) {
      setState(() {
        _mostrarErrorAceptacion = true;
      });
      return;
    }

    final auth = Supabase.instance.client.auth;
    final usuario = auth.currentUser;

    if (usuario == null ||
        auth.currentSession == null) {
      setState(() {
        _errorServidor =
            'Tu sesión no está disponible. '
            'Inicia sesión nuevamente.';
      });
      return;
    }

    setState(() {
      _guardando = true;
      _errorServidor = null;
    });

    try {
      // No enviamos aceptado_en.
      // PostgreSQL establece la fecha con now().

      await Supabase.instance.client
          .from('aceptacion_documentos')
          .insert({
            'usuario_id': usuario.id,
            'terminos_version':
                versionTerminos,
            'privacidad_version':
                versionPrivacidad,
          })
          .timeout(tiempoEspera);

      // Confirmar que el registro sea consultable
      // antes de continuar al tutorial o Home.

      final confirmado =
          await _aceptacionExiste(usuario.id);

      if (!mounted) return;

      if (auth.currentUser?.id != usuario.id) {
        setState(() {
          _errorServidor =
              'La sesión cambió. '
              'Vuelve a iniciar sesión.';
        });
        return;
      }

      if (!confirmado) {
        setState(() {
          _errorServidor =
              'El servidor no confirmó la aceptación. '
              'Inténtalo nuevamente.';
        });
        return;
      }

      widget.onAceptacionRegistrada();
    } on PostgrestException catch (error) {
      debugPrint(
        'Error de Supabase al registrar R81: $error',
      );

      // Una respuesta de duplicado puede ocurrir
      // si la operación anterior sí se guardó.
      if (error.code == '23505') {
        try {
          final confirmado =
              await _aceptacionExiste(usuario.id);

          if (!mounted) return;

          if (confirmado &&
              auth.currentUser?.id == usuario.id) {
            widget.onAceptacionRegistrada();
            return;
          }
        } catch (verificacionError) {
          debugPrint(
            'Error al verificar aceptación existente: '
            '$verificacionError',
          );
        }
      }

      if (!mounted) return;

      setState(() {
        _errorServidor =
            'No se pudo registrar la aceptación. '
            'Comprueba tu conexión e inténtalo nuevamente.';
      });
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _errorServidor =
            'El servidor no confirmó la operación. '
            'Es posible que la aceptación se haya '
            'guardado. Puedes volver a intentarlo; '
            'el sistema comprobará el registro existente.';
      });
    } catch (error) {
      debugPrint(
        'Error al guardar aceptación R81: $error',
      );

      if (!mounted) return;

      setState(() {
        _errorServidor =
            'Ocurrió un error al registrar la '
            'aceptación. Inténtalo nuevamente.';
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
  // PANTALLA
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final esquema = tema.colorScheme;

    return Scaffold(
      backgroundColor:
          tema.scaffoldBackgroundColor,

      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),

            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: 520),

              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,

                children: [
                  Center(
                    child: Container(
                      width: 78,
                      height: 78,

                      decoration: BoxDecoration(
                        color: verde,
                        borderRadius:
                            BorderRadius.circular(24),
                      ),

                      child: const Icon(
                        Icons.description_outlined,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  Text(
                    'Revisión de documentos',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                      color: _colorPrincipal,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    'Antes de continuar en NFC-FoodTech, '
                    'revisa los términos de uso y la '
                    'política de privacidad utilizados '
                    'en esta versión de prueba.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: esquema.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 26),

                  Container(
                    padding: const EdgeInsets.all(20),

                    decoration: BoxDecoration(
                      color: esquema.surface,
                      borderRadius:
                          BorderRadius.circular(20),

                      border: Border.all(
                        color: esquema.outlineVariant,
                      ),
                    ),

                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,

                      children: [
                        const Text(
                          'Documentos disponibles',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 12),

                        ListTile(
                          contentPadding: EdgeInsets.zero,

                          leading: const Icon(
                            Icons.article_outlined,
                          ),

                          title: const Text(
                            'Términos de uso',
                          ),

                          subtitle: const Text(
                            'Versión preliminar R81',
                          ),

                          trailing: const Icon(
                            Icons.chevron_right,
                          ),

                          onTap: _mostrarTerminos,
                        ),

                        Divider(
                          color: esquema.outlineVariant,
                        ),

                        ListTile(
                          contentPadding: EdgeInsets.zero,

                          leading: const Icon(
                            Icons.privacy_tip_outlined,
                          ),

                          title: const Text(
                            'Política de privacidad',
                          ),

                          subtitle: const Text(
                            'Versión preliminar R81',
                          ),

                          trailing: const Icon(
                            Icons.chevron_right,
                          ),

                          onTap: _mostrarPrivacidad,
                        ),

                        const SizedBox(height: 12),

                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,

                          controlAffinity:
                              ListTileControlAffinity.leading,

                          activeColor: _modoOscuro ? esquema.primary : verde,
                          checkColor: _modoOscuro ? esquema.onPrimary : null,

                          value: _aceptaDocumentos,

                          onChanged: _guardando
                              ? null
                              : (valor) {
                                  setState(() {
                                    _aceptaDocumentos =
                                        valor ?? false;

                                    if (_aceptaDocumentos) {
                                      _mostrarErrorAceptacion =
                                          false;
                                    }

                                    _errorServidor = null;
                                  });
                                },

                          title: const Text(
                            'He leído y acepto los términos '
                            'de uso y la política de privacidad '
                            'de esta versión de prueba.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),

                        if (_mostrarErrorAceptacion)
                          Padding(
                            padding:
                                const EdgeInsets.only(top: 8),

                            child: Text(
                              'Debes aceptar ambos documentos '
                              'para continuar.',
                              style: TextStyle(
                                color: esquema.error,
                                fontSize: 12,
                              ),
                            ),
                          ),

                        if (_errorServidor != null)
                          Padding(
                            padding:
                                const EdgeInsets.only(top: 12),

                            child: Text(
                              _errorServidor!,
                              style: TextStyle(
                                color: esquema.error,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  Card(
                    color: esquema.surface,

                    child: const Padding(
                      padding: EdgeInsets.all(15),

                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,

                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                          ),

                          SizedBox(width: 12),

                          Expanded(
                            child: Text(
                              'Esta aceptación corresponde '
                              'a documentos preliminares '
                              'del proyecto académico. '
                              'Las versiones definitivas '
                              'deberán revisarse y aprobarse '
                              'antes de publicar la aplicación.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    height: 54,

                    child: ElevatedButton.icon(
                      onPressed: _guardando
                          ? null
                          : _guardarAceptacion,

                      icon: _guardando
                          ? const SizedBox(
                              width: 20,
                              height: 20,

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
                            ? 'Registrando...'
                            : 'Aceptar y continuar',
                      ),

                      style: ElevatedButton.styleFrom(
                        backgroundColor: verde,
                        foregroundColor: Colors.white,

                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(15),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  Center(
                    child: Text(
                      'NFC-FoodTech · Cada alimento cuenta 🌱',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: esquema.onSurfaceVariant,
                      ),
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
