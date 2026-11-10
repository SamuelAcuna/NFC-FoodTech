
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SolicitudSoporteScreen extends StatefulWidget {
  const SolicitudSoporteScreen({super.key});

  @override
  State<SolicitudSoporteScreen> createState() =>
      _SolicitudSoporteScreenState();
}

class _SolicitudSoporteScreenState
    extends State<SolicitudSoporteScreen> {
  static const Color verde = Color(0xFF236B4A);

  static const Duration _esperaLectura =
      Duration(seconds: 8);

  static const Duration _esperaEnvio =
      Duration(seconds: 10);

  final _formKey = GlobalKey<FormState>();
  final _asuntoController = TextEditingController();
  final _mensajeController = TextEditingController();

  String _tipoSeleccionado = 'CONSULTA';

  bool _cargandoHistorial = true;
  String? _errorHistorial;

  List<Map<String, dynamic>> _solicitudes = [];

  int _versionFormulario = 0;
  int _versionCargaHistorial = 0;

  bool _envioIncierto = false;
  bool _vistaPreviaAbierta = false;

  static const Map<String, String> _tipos = {
    'CONSULTA': 'Consulta',
    'ERROR': 'Reportar un error',
    'SUGERENCIA': 'Sugerencia',
  };

  @override
  void initState() {
    super.initState();
    _cargarSolicitudes();
  }

  @override
  void dispose() {
    _asuntoController.dispose();
    _mensajeController.dispose();
    super.dispose();
  }

  // --------------------------------------------------
  // CONSULTAR HISTORIAL DE SOPORTE
  // --------------------------------------------------

  Future<void> _cargarSolicitudes() async {
    final usuario =
        Supabase.instance.client.auth.currentUser;

    final versionActual = ++_versionCargaHistorial;

    if (!mounted) return;

    if (usuario == null) {
      setState(() {
        _cargandoHistorial = false;
        _solicitudes = [];
        _errorHistorial = 'Debes iniciar sesión.';
      });
      return;
    }

    setState(() {
      _cargandoHistorial = true;
      _errorHistorial = null;
    });

    try {
      final respuesta = await Supabase.instance.client
          .from('solicitud_soporte')
          .select(
            'id, tipo, asunto, mensaje, estado, '
            'solicitado_en, respuesta, respondido_en',
          )
          .eq('solicitado_por', usuario.id)
          .order('solicitado_en', ascending: false)
          .limit(30)
          .timeout(_esperaLectura);

      if (!mounted ||
          versionActual != _versionCargaHistorial) {
        return;
      }

      if (Supabase.instance.client.auth.currentUser?.id !=
          usuario.id) {
        setState(() {
          _cargandoHistorial = false;
          _solicitudes = [];
          _errorHistorial =
              'La sesión cambió. Vuelve a abrir esta pantalla.';
        });
        return;
      }

      setState(() {
        _solicitudes =
            List<Map<String, dynamic>>.from(respuesta);
        _cargandoHistorial = false;
        _errorHistorial = null;
      });
    } on TimeoutException {
      if (!mounted ||
          versionActual != _versionCargaHistorial) {
        return;
      }

      setState(() {
        _cargandoHistorial = false;
        _errorHistorial =
            'No pudimos conectar con el servidor. '
            'Comprueba tu conexión e inténtalo nuevamente.';
      });
    } catch (error) {
      debugPrint('Error al consultar soporte: $error');

      if (!mounted ||
          versionActual != _versionCargaHistorial) {
        return;
      }

      setState(() {
        _cargandoHistorial = false;
        _errorHistorial =
            'No pudimos cargar tus solicitudes. '
            'Inténtalo nuevamente.';
      });
    }
  }

  // --------------------------------------------------
  // ENVIAR SOLICITUD A SUPABASE
  // --------------------------------------------------

  Future<void> _enviarSolicitud({
    required String tipo,
    required String asunto,
    required String mensaje,
  }) async {
    final usuario =
        Supabase.instance.client.auth.currentUser;

    if (usuario == null) {
      throw StateError(
        'Debes iniciar sesión para enviar una solicitud.',
      );
    }

    await Supabase.instance.client
        .from('solicitud_soporte')
        .insert({
          'tipo': tipo,
          'asunto': asunto,
          'mensaje': mensaje,
          'solicitado_por': usuario.id,
        })
        .timeout(_esperaEnvio);
  }

  // --------------------------------------------------
  // DECORACIÓN DE FORMULARIOS
  // --------------------------------------------------

  InputDecoration _decoracion({
    required String etiqueta,
    required IconData icono,
    String? ayuda,
  }) {
    final esquema = Theme.of(context).colorScheme;
    final oscuro = Theme.of(context).brightness == Brightness.dark;

    return InputDecoration(
      labelText: etiqueta,
      hintText: ayuda,
      prefixIcon: Icon(
        icono,
        color: esquema.primary,
      ),
      filled: true,
      fillColor: esquema.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 17,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: esquema.outlineVariant,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: oscuro ? esquema.primary : verde,
          width: 1.8,
        ),
      ),
    );
  }

  String _obtenerTipo(String tipo) {
    return _tipos[tipo] ?? tipo;
  }

  // --------------------------------------------------
  // REINICIAR FORMULARIO
  // --------------------------------------------------

  void _reiniciarFormulario({
    bool envioConfirmado = false,
  }) {
    _asuntoController.clear();
    _mensajeController.clear();
    _formKey.currentState?.reset();

    setState(() {
      _tipoSeleccionado = 'CONSULTA';
      _versionFormulario++;

      if (envioConfirmado) {
        _envioIncierto = false;
      }
    });
  }

  // --------------------------------------------------
  // MENSAJES
  // --------------------------------------------------

  void _mostrarMensaje(
    String mensaje, {
    bool exito = false,
  }) {
    if (!mounted) return;

    final oscuro = Theme.of(context).brightness == Brightness.dark;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            mensaje,
            style: oscuro ? const TextStyle(color: Colors.white) : null,
          ),
          backgroundColor: exito
              ? verde
              : const Color(0xFFB83D3D),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // --------------------------------------------------
  // VISTA PREVIA Y CONFIRMACIÓN DEL ENVÍO
  // --------------------------------------------------

  Future<void> _mostrarVistaPrevia() async {
    if (_vistaPreviaAbierta) return;

    if (_envioIncierto) {
      _mostrarMensaje(
        'El envío anterior no pudo confirmarse. '
        'Consulta tu historial antes de intentar '
        'enviarlo otra vez.',
      );
      return;
    }

    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (Supabase.instance.client.auth.currentUser == null) {
      _mostrarMensaje(
        'Debes iniciar sesión para enviar una solicitud.',
      );
      return;
    }

    final asunto = _asuntoController.text.trim();
    final mensaje = _mensajeController.text.trim();
    final tipo = _tipoSeleccionado;

    bool enviando = false;
    String? errorEnvio;

    _vistaPreviaAbierta = true;

    bool? enviado;

    try {
      enviado = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (
              dialogContext,
              actualizarDialogo,
            ) {
              final esquema =
                  Theme.of(dialogContext).colorScheme;

              return PopScope(
                canPop: !enviando,
                child: AlertDialog(
                  title: const Text(
                    'Revisar solicitud',
                  ),
                  content: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 500,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          _campoVistaPrevia(
                            'Tipo de solicitud',
                            _obtenerTipo(tipo),
                          ),

                          const SizedBox(height: 16),

                          _campoVistaPrevia(
                            'Asunto',
                            asunto,
                          ),

                          const SizedBox(height: 16),

                          _campoVistaPrevia(
                            'Descripción',
                            mensaje,
                          ),

                          const SizedBox(height: 22),

                          Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: esquema
                                  .surfaceContainerHighest,
                              borderRadius:
                                  BorderRadius.circular(12),
                            ),
                            child: const Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 21,
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Revisa la información '
                                    'antes de enviarla. '
                                    'Al confirmar, la solicitud '
                                    'se guardará en NFC-FoodTech.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (errorEnvio != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              errorEnvio!,
                              style: TextStyle(
                                color: esquema.error,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: enviando
                          ? null
                          : () {
                              Navigator.of(
                                dialogContext,
                              ).pop(false);
                            },
                      child: const Text(
                        'Volver al formulario',
                      ),
                    ),

                    FilledButton.icon(
                      onPressed:
                          enviando || _envioIncierto
                              ? null
                              : () async {
                                  actualizarDialogo(() {
                                    enviando = true;
                                    errorEnvio = null;
                                  });

                                  try {
                                    await _enviarSolicitud(
                                      tipo: tipo,
                                      asunto: asunto,
                                      mensaje: mensaje,
                                    );

                                    if (!dialogContext.mounted) {
                                      return;
                                    }

                                    Navigator.of(
                                      dialogContext,
                                    ).pop(true);
                                  } catch (error) {
                                    debugPrint(
                                      'Error al enviar soporte: $error',
                                    );

                                    if (!dialogContext.mounted) {
                                      return;
                                    }

                                    String mensajeError;

                                    if (error
                                        is PostgrestException) {
                                      if (error.code ==
                                          '42501') {
                                        mensajeError =
                                            'No tienes permisos '
                                            'para guardar la solicitud. '
                                            'Debemos revisar esto '
                                            'con tu equipo.';
                                      } else {
                                        mensajeError =
                                            'Error de Supabase: '
                                            '${error.message}';
                                      }
                                    } else {
                                      // Ante un error de red
                                      // no podemos saber si el
                                      // servidor guardó los datos.
                                      if (mounted) {
                                        setState(() {
                                          _envioIncierto = true;
                                        });
                                      }

                                      mensajeError =
                                          'No pudimos confirmar '
                                          'el envío. Es posible '
                                          'que se haya guardado. '
                                          'Consulta tu historial '
                                          'al recuperar la conexión '
                                          'antes de volver a enviarlo.';
                                    }

                                    actualizarDialogo(() {
                                      enviando = false;
                                      errorEnvio = mensajeError;
                                    });
                                  }
                                },
                      icon: enviando
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
                              Icons.send_rounded,
                            ),
                      label: Text(
                        enviando
                            ? 'Enviando...'
                            : 'Enviar solicitud',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: verde,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      _vistaPreviaAbierta = false;
    }

    if (!mounted) return;

    if (enviado == true) {
      _reiniciarFormulario(
        envioConfirmado: true,
      );

      _mostrarMensaje(
        '¡Tu solicitud fue enviada correctamente!',
        exito: true,
      );

      await _cargarSolicitudes();
    }
  }

  // --------------------------------------------------
  // CONFIRMAR UN NUEVO INTENTO
  // --------------------------------------------------

  Future<void> _confirmarNuevoIntento() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Envío pendiente de verificar',
          ),
          content: const Text(
            'No tenemos confirmación del envío anterior. '
            'Aunque no aparezca todavía en tu historial, '
            'podría haberse recibido.\n\n'
            'Si vuelves a enviarlo, podrías generar '
            'una solicitud duplicada.\n\n'
            '¿Quieres habilitar un nuevo intento '
            'de todas formas?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text(
                'Habilitar nuevo intento',
              ),
            ),
          ],
        );
      },
    );

    if (confirmado == true && mounted) {
      setState(() {
        _envioIncierto = false;
      });
    }
  }

  // --------------------------------------------------
  // CAMPOS DE LA VISTA PREVIA
  // --------------------------------------------------

  Widget _campoVistaPrevia(
    String etiqueta,
    String valor,
  ) {
    final esquema = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: esquema.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          valor,
          style: const TextStyle(
            fontSize: 15,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------
  // LIMPIAR FORMULARIO
  // --------------------------------------------------

  Future<void> _limpiarFormulario() async {
    if (_asuntoController.text.trim().isEmpty &&
        _mensajeController.text.trim().isEmpty &&
        _tipoSeleccionado == 'CONSULTA') {
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Limpiar formulario',
          ),
          content: const Text(
            '¿Quieres borrar la información '
            'que has ingresado?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Limpiar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) return;

    _reiniciarFormulario();
  }

  // --------------------------------------------------
  // FORMATEAR FECHAS
  // --------------------------------------------------

  String _formatearFecha(dynamic valor) {
    if (valor == null) {
      return 'Sin fecha';
    }

    final fecha = DateTime.tryParse(
      valor.toString(),
    );

    if (fecha == null) {
      return 'Fecha no disponible';
    }

    final local = fecha.toLocal();

    String dosDigitos(int numero) {
      return numero.toString().padLeft(2, '0');
    }

    return '${dosDigitos(local.day)}/'
        '${dosDigitos(local.month)}/'
        '${local.year} '
        '${dosDigitos(local.hour)}:'
        '${dosDigitos(local.minute)}';
  }

  // --------------------------------------------------
  // COLORES DE LOS ESTADOS
  // --------------------------------------------------

  Color _colorEstado(String estado) {
    switch (estado.toUpperCase()) {
      case 'PENDIENTE':
        return const Color(0xFF9A6700);

      case 'EN_PROCESO':
      case 'EN_GESTION':
      case 'EN_REVISION':
        return const Color(0xFF2563A6);

      case 'RESPONDIDA':
      case 'RESUELTA':
      case 'CERRADA':
        return verde;

      default:
        return const Color(0xFF707070);
    }
  }

  // --------------------------------------------------
  // TARJETA DEL HISTORIAL
  // --------------------------------------------------

  Widget _tarjetaSolicitud(
    Map<String, dynamic> solicitud,
  ) {
    final esquema = Theme.of(context).colorScheme;

    final oscuro =
        Theme.of(context).brightness == Brightness.dark;

    final tipo =
        solicitud['tipo']?.toString() ?? '';

    final asunto =
        solicitud['asunto']?.toString() ?? 'Sin asunto';

    final mensaje =
        solicitud['mensaje']?.toString() ?? '';

    final estado =
        solicitud['estado']?.toString() ?? 'PENDIENTE';

    final respuesta =
        solicitud['respuesta']?.toString().trim();

    final colorEstado = _colorEstado(estado);

    return Card(
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      color: esquema.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: esquema.outlineVariant,
        ),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),

        tilePadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),

        childrenPadding: const EdgeInsets.fromLTRB(
          16,
          0,
          16,
          18,
        ),

        title: Text(
          asunto,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),

        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment:
                WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: colorEstado.withValues(
                    alpha: oscuro ? 0.18 : 0.10,
                  ),
                  borderRadius:
                      BorderRadius.circular(8),
                ),
                child: Text(
                  estado.replaceAll('_', ' '),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: oscuro
                        ? esquema.onSurface
                        : colorEstado,
                  ),
                ),
              ),

              Text(
                _formatearFecha(
                  solicitud['solicitado_en'],
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: esquema.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'Tipo: ${_obtenerTipo(tipo)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: esquema.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 14),

                const Text(
                  'Tu mensaje',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                SelectableText(
                  mensaje,
                  style: const TextStyle(
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 18),

                Divider(
                  color: esquema.outlineVariant,
                ),

                const SizedBox(height: 10),

                const Text(
                  'Respuesta de soporte',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                if (respuesta != null &&
                    respuesta.isNotEmpty) ...[
                  SelectableText(
                    respuesta,
                    style: const TextStyle(
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Respondido el '
                    '${_formatearFecha(solicitud['respondido_en'])}',
                    style: TextStyle(
                      fontSize: 12,
                      color: esquema.onSurfaceVariant,
                    ),
                  ),
                ] else
                  Text(
                    'Todavía no hay una respuesta registrada.',
                    style: TextStyle(
                      fontSize: 13,
                      color: esquema.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------
  // CONSTRUIR HISTORIAL
  // --------------------------------------------------

  Widget _construirHistorial() {
    final esquema = Theme.of(context).colorScheme;

    final oscuro =
        Theme.of(context).brightness == Brightness.dark;

    final colorPrincipal =
        oscuro ? esquema.onSurface : verde;

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Mis solicitudes',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  color: colorPrincipal,
                ),
              ),
            ),

            IconButton(
              tooltip: 'Actualizar solicitudes',
              onPressed: _cargandoHistorial
                  ? null
                  : _cargarSolicitudes,
              icon: const Icon(
                Icons.refresh_rounded,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        if (_cargandoHistorial)
          const Padding(
            padding: EdgeInsets.symmetric(
              vertical: 24,
            ),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          )
        else if (_errorHistorial != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: esquema.surface,
              borderRadius:
                  BorderRadius.circular(16),
              border: Border.all(
                color: esquema.outlineVariant,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 35,
                  color: esquema.error,
                ),

                const SizedBox(height: 10),

                Text(
                  _errorHistorial!,
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 10),

                TextButton.icon(
                  onPressed: _cargarSolicitudes,
                  icon: const Icon(
                    Icons.refresh,
                  ),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          )
        else if (_solicitudes.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: esquema.surface,
              borderRadius:
                  BorderRadius.circular(18),
              border: Border.all(
                color: esquema.outlineVariant,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 46,
                  color: esquema.onSurfaceVariant,
                ),

                const SizedBox(height: 12),

                const Text(
                  'Todavía no tienes solicitudes',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'Cuando envíes una solicitud, '
                  'podrás revisar su estado aquí.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: esquema.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else ...[
          for (final solicitud in _solicitudes)
            _tarjetaSolicitud(solicitud),

          if (_solicitudes.length == 30)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Se muestran las 30 solicitudes '
                'más recientes.',
                style: TextStyle(
                  color: esquema.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
        ],
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

    final oscuro =
        tema.brightness == Brightness.dark;

    final colorPrincipal =
        oscuro ? esquema.onSurface : verde;

    return Scaffold(
      backgroundColor: tema.scaffoldBackgroundColor,

      appBar: AppBar(
        title: const Text('Soporte'),
        backgroundColor:
            tema.scaffoldBackgroundColor,
        foregroundColor: colorPrincipal,
      ),

      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 650,
            ),

            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),

              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,

                children: [
                  // -----------------------
                  // ENCABEZADO
                  // -----------------------

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),

                    decoration: BoxDecoration(
                      color: esquema.surface,
                      borderRadius:
                          BorderRadius.circular(24),
                      border: Border.all(
                        color: esquema.outlineVariant,
                      ),
                    ),

                    child: Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: oscuro
                                ? esquema
                                    .surfaceContainerHighest
                                : const Color(
                                    0xFFE1F1E6,
                                  ),
                            borderRadius:
                                BorderRadius.circular(24),
                          ),
                          child: Icon(
                            Icons.support_agent_rounded,
                            size: 44,
                            color: colorPrincipal,
                          ),
                        ),

                        const SizedBox(height: 16),

                        Text(
                          '¿Necesitas ayuda?',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.bold,
                            color: colorPrincipal,
                          ),
                        ),

                        const SizedBox(height: 10),

                        Text(
                          'Cuéntanos qué necesitas. '
                          'Puedes enviar una consulta, '
                          'reportar un error o compartir '
                          'una sugerencia para NFC-FoodTech.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: esquema.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  Text(
                    'Nueva solicitud',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      color: colorPrincipal,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // -----------------------
                  // FORMULARIO
                  // -----------------------

                  Form(
                    key: _formKey,

                    child: Container(
                      padding: const EdgeInsets.all(20),

                      decoration: BoxDecoration(
                        color: esquema.surface,
                        borderRadius:
                            BorderRadius.circular(22),
                        border: Border.all(
                          color: esquema.outlineVariant,
                        ),
                      ),

                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.stretch,

                        children: [
                          const Text(
                            'Tipo de solicitud',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),

                          const SizedBox(height: 10),

                          DropdownButtonFormField<String>(
                            key: ValueKey(
                              _versionFormulario,
                            ),
                            initialValue:
                                _tipoSeleccionado,
                            isExpanded: true,

                            decoration: _decoracion(
                              etiqueta: 'Seleccionar tipo',
                              icono: Icons.category_outlined,
                            ),

                            items: _tipos.entries.map(
                              (opcion) {
                                return DropdownMenuItem<String>(
                                  value: opcion.key,
                                  child: Text(
                                    opcion.value,
                                  ),
                                );
                              },
                            ).toList(),

                            onChanged: (valor) {
                              if (valor == null) return;

                              setState(() {
                                _tipoSeleccionado = valor;
                              });
                            },
                          ),

                          const SizedBox(height: 20),

                          const Text(
                            'Asunto',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),

                          const SizedBox(height: 10),

                          TextFormField(
                            controller:
                                _asuntoController,

                            textCapitalization:
                                TextCapitalization.sentences,

                            textInputAction:
                                TextInputAction.next,

                            maxLength: 100,

                            decoration: _decoracion(
                              etiqueta:
                                  'Asunto de la solicitud',
                              icono: Icons.subject_outlined,
                              ayuda:
                                  'Ejemplo: Problema al iniciar sesión',
                            ),

                            validator: (valor) {
                              final asunto =
                                  valor?.trim() ?? '';

                              if (asunto.isEmpty) {
                                return 'Ingresa un asunto.';
                              }

                              if (asunto.length < 5) {
                                return 'El asunto debe tener '
                                    'al menos 5 caracteres.';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 8),

                          const Text(
                            'Describe tu solicitud',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),

                          const SizedBox(height: 10),

                          TextFormField(
                            controller:
                                _mensajeController,

                            textCapitalization:
                                TextCapitalization.sentences,

                            keyboardType:
                                TextInputType.multiline,

                            minLines: 6,
                            maxLines: 10,
                            maxLength: 2000,

                            decoration: _decoracion(
                              etiqueta: 'Descripción',
                              icono: Icons.edit_note_rounded,
                              ayuda:
                                  'Explica lo ocurrido o describe tu sugerencia.',
                            ),

                            validator: (valor) {
                              final mensaje =
                                  valor?.trim() ?? '';

                              if (mensaje.isEmpty) {
                                return 'Ingresa una descripción.';
                              }

                              if (mensaje.length < 15) {
                                return 'Describe tu solicitud '
                                    'con al menos 15 caracteres.';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 12),

                          // -----------------------
                          // ADVERTENCIA SI EL ENVÍO
                          // NO PUDO CONFIRMARSE
                          // -----------------------

                          if (_envioIncierto) ...[
                            Container(
                              padding:
                                  const EdgeInsets.all(14),

                              decoration: BoxDecoration(
                                color: esquema
                                    .surfaceContainerHighest,
                                borderRadius:
                                    BorderRadius.circular(14),
                                border: Border.all(
                                  color: esquema.outlineVariant,
                                ),
                              ),

                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,

                                children: [
                                  const Text(
                                    'Envío anterior sin confirmar',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),

                                  const SizedBox(height: 7),

                                  const Text(
                                    'Comprueba tu historial '
                                    'al volver la conexión. '
                                    'No reenvíes automáticamente: '
                                    'la solicitud podría '
                                    'haberse guardado.',
                                  ),

                                  const SizedBox(height: 8),

                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      TextButton.icon(
                                        onPressed:
                                            _cargarSolicitudes,
                                        icon: const Icon(
                                          Icons.refresh,
                                        ),
                                        label: const Text(
                                          'Actualizar historial',
                                        ),
                                      ),

                                      TextButton(
                                        onPressed:
                                            _confirmarNuevoIntento,
                                        child: const Text(
                                          'Habilitar nuevo intento',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),
                          ],

                          // -----------------------
                          // VISTA PREVIA Y ENVÍO
                          // -----------------------

                          SizedBox(
                            height: 54,

                            child: ElevatedButton.icon(
                              onPressed:
                                  _mostrarVistaPrevia,

                              icon: const Icon(
                                Icons.visibility_outlined,
                              ),

                              label: const Text(
                                'Revisar y enviar solicitud',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              style:
                                  ElevatedButton.styleFrom(
                                backgroundColor: verde,
                                foregroundColor:
                                    Colors.white,

                                shape:
                                    RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          OutlinedButton.icon(
                            onPressed:
                                _limpiarFormulario,

                            icon: const Icon(
                              Icons.delete_outline,
                            ),

                            label: const Text(
                              'Limpiar formulario',
                            ),

                            style:
                                OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(
                                vertical: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // -----------------------
                  // HISTORIAL DE SOLICITUDES
                  // -----------------------

                  _construirHistorial(),

                  const SizedBox(height: 28),

                  Center(
                    child: Text(
                      'NFC-FoodTech · Cada alimento cuenta 🌱',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: esquema.onSurfaceVariant,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
