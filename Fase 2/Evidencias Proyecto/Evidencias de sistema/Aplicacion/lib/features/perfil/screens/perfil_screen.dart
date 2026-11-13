import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nfc_foodtech_app/features/auth/screens/cambiar_contrasena_screen.dart';
import 'package:nfc_foodtech_app/features/perfil/screens/desactivar_cuenta_screen.dart';
import 'package:nfc_foodtech_app/screens/eliminar_cuenta_screen.dart';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  static const Color verde = Color(0xFF236B4A);
  static const int maximoFotoBytes = 2 * 1024 * 1024;

  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _nombreController = TextEditingController();
  final _apellidoController = TextEditingController();

  DateTime? _fechaNacimiento;
  String? _sexo;
  String? _avatarUrl;
  String? _error;

  bool _cargando = true;
  bool _guardando = false;
  bool _subiendoFoto = false;

  bool get _ocupado => _guardando || _subiendoFoto;

  final Map<String, String> _opcionesSexo = {
    'FEMENINO': 'Femenino',
    'MASCULINO': 'Masculino',
    'OTRO': 'Otro',
    'NO_INFORMA': 'Prefiero no informar',
  };

  // --------------------------------------------------
  // COLORES
  // --------------------------------------------------

  bool get _modoOscuro => Theme.of(context).brightness == Brightness.dark;

  Color get _colorPrincipal {
    final esquema = Theme.of(context).colorScheme;
    return _modoOscuro ? esquema.onSurface : verde;
  }

  Color get _colorSecundario => Theme.of(context).colorScheme.onSurfaceVariant;

  Color get _colorSuperficie => Theme.of(context).colorScheme.surface;

  Color get _colorBorde => Theme.of(context).colorScheme.outlineVariant;

  // --------------------------------------------------
  // CICLO DE VIDA
  // --------------------------------------------------

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidoController.dispose();
    super.dispose();
  }

  // --------------------------------------------------
  // FUNCIONES GENERALES
  // --------------------------------------------------

  String _formatearFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year}';
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), behavior: SnackBarBehavior.floating),
    );
  }

  // --------------------------------------------------
  // CARGAR PERFIL
  // --------------------------------------------------

  Future<void> _cargarPerfil() async {
    try {
      final usuario = _supabase.auth.currentUser;

      if (usuario == null) {
        throw Exception('No hay una sesión iniciada.');
      }

      final datos = await _supabase
          .from('perfil')
          .select('nombre, apellido, fecha_nacimiento, sexo, avatar_url')
          .eq('id', usuario.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (datos == null) {
        throw Exception(
          'No se encontró tu perfil. '
          'Intenta cerrar sesión e ingresar nuevamente.',
        );
      }

      if (!mounted) return;

      // Evitar datos de otra sesión.
      if (_supabase.auth.currentUser?.id != usuario.id) {
        return;
      }

      _nombreController.text = datos['nombre']?.toString() ?? '';

      _apellidoController.text = datos['apellido']?.toString() ?? '';

      final fecha = datos['fecha_nacimiento'];

      _fechaNacimiento = fecha == null
          ? null
          : DateTime.tryParse(fecha.toString());

      final sexo = datos['sexo']?.toString();

      _sexo = _opcionesSexo.containsKey(sexo) ? sexo : null;

      final urlFoto = datos['avatar_url']?.toString().trim();

      _avatarUrl = urlFoto == null || urlFoto.isEmpty ? null : urlFoto;

      setState(() {
        _error = null;
        _cargando = false;
      });
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _error =
            'No pudimos conectar con el servidor. '
            'Comprueba tu conexión a internet '
            'e inténtalo nuevamente.';
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) return;

      debugPrint('Error al cargar perfil: $error');

      setState(() {
        _error =
            'No pudimos cargar tu perfil. '
            'Verifica tu conexión e inténtalo nuevamente.';
        _cargando = false;
      });
    }
  }

  // --------------------------------------------------
  // FECHA DE NACIMIENTO
  // --------------------------------------------------

  Future<void> _seleccionarFecha() async {
    if (_ocupado) return;

    final hoy = DateTime.now();

    final fecha = await showDatePicker(
      context: context,
      initialDate:
          _fechaNacimiento ?? DateTime(hoy.year - 18, hoy.month, hoy.day),
      firstDate: DateTime(1900),
      lastDate: hoy,
      helpText: 'Selecciona tu fecha de nacimiento',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
      builder: (context, child) {
        final tema = Theme.of(context);

        return Theme(
          data: tema.copyWith(
            colorScheme: tema.colorScheme.copyWith(
              primary: _modoOscuro ? const Color(0xFF78CBA0) : verde,
            ),
          ),
          child: child!,
        );
      },
    );

    if (fecha != null && mounted) {
      setState(() {
        _fechaNacimiento = fecha;
      });
    }
  }

  // --------------------------------------------------
  // M08: GUARDAR DATOS PERSONALES DE FORMA SEGURA
  // --------------------------------------------------

  Future<void> _guardarPerfil() async {
    if (_ocupado) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final usuario = _supabase.auth.currentUser;

    if (usuario == null || _supabase.auth.currentSession == null) {
      _mostrarMensaje('Tu sesión ha expirado. Ingresa nuevamente.');
      return;
    }

    setState(() {
      _guardando = true;
    });

    try {
      // 1. Comprobar el estado actual de la cuenta.
      // Esta comprobación mejora la experiencia,
      // pero la seguridad real depende de RLS.

      final perfilActual = await _supabase
          .from('perfil')
          .select('estado_cuenta')
          .eq('id', usuario.id)
          .single()
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;

      if (_supabase.auth.currentUser?.id != usuario.id) {
        return;
      }

      if (perfilActual['estado_cuenta'] != 'ACTIVA') {
        _mostrarMensaje(
          'Tu cuenta no está activa. '
          'No puedes modificar tu perfil.',
        );
        return;
      }

      // 2. Preparar datos personales.

      final fecha = _fechaNacimiento;

      final nombre = _nombreController.text.trim();
      final apellido = _apellidoController.text.trim();

      // 3. Actualizar y solicitar la fila modificada.
      // Si RLS bloquea el cambio y no devuelve filas,
      // .single() generará un error en lugar de
      // mostrar un éxito falso.

      final resultado = await _supabase
          .from('perfil')
          .update({
            'nombre': nombre.isEmpty ? null : nombre,
            'apellido': apellido.isEmpty ? null : apellido,
            'fecha_nacimiento': fecha == null
                ? null
                : '${fecha.year}-'
                      '${fecha.month.toString().padLeft(2, '0')}-'
                      '${fecha.day.toString().padLeft(2, '0')}',
            'sexo': _sexo,
          })
          .eq('id', usuario.id)
          .select('id')
          .single()
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;

      if (_supabase.auth.currentUser?.id != usuario.id) {
        return;
      }

      // 4. Confirmar que se actualizó el perfil
      // de este mismo usuario.

      if (resultado['id'] != usuario.id) {
        throw StateError('No se pudo confirmar la actualización.');
      }

      _mostrarMensaje('Perfil actualizado correctamente.');
    } on TimeoutException {
      _mostrarMensaje(
        'El servidor no respondió a tiempo. '
        'Verifica los cambios antes de volver a guardar.',
      );
    } on PostgrestException catch (error) {
      debugPrint('========== ERROR PERFIL ==========');
      debugPrint('Código: ${error.code}');
      debugPrint('Mensaje: ${error.message}');
      debugPrint('Detalles: ${error.details}');
      debugPrint('=================================');

      _mostrarMensaje(
        'No se pudo actualizar el perfil. '
        'Comprueba que tu cuenta esté activa '
        'y tengas permiso para modificarla.',
      );
    } catch (error) {
      debugPrint('Error al guardar perfil: $error');

      _mostrarMensaje(
        'No se pudieron guardar los cambios. '
        'Revisa tu conexión y los permisos de Supabase.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  // --------------------------------------------------
  // VALIDAR FORMATO DE IMAGEN
  // --------------------------------------------------

  ({String extension, String mime})? _detectarImagen(Uint8List bytes) {
    // JPEG
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return (extension: 'jpg', mime: 'image/jpeg');
    }

    // PNG
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return (extension: 'png', mime: 'image/png');
    }

    // WebP
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return (extension: 'webp', mime: 'image/webp');
    }

    return null;
  }

  // --------------------------------------------------
  // IDENTIFICAR FOTO PROPIA EN STORAGE
  // --------------------------------------------------

  String? _rutaFotoPropia(String? url, String usuarioId) {
    if (url == null || url.isEmpty) {
      return null;
    }

    try {
      final urlCarpeta = _supabase.storage
          .from('fotos_perfil')
          .getPublicUrl('$usuarioId/');

      final base = Uri.parse(urlCarpeta);
      final imagen = Uri.parse(url);

      // Solo aceptar URLs del mismo proyecto.
      if (base.host != imagen.host ||
          base.scheme != imagen.scheme ||
          !imagen.path.startsWith(base.path)) {
        return null;
      }

      const marcador = '/storage/v1/object/public/fotos_perfil/';

      final indice = imagen.path.indexOf(marcador);

      if (indice < 0) {
        return null;
      }

      final ruta = Uri.decodeComponent(
        imagen.path.substring(indice + marcador.length),
      );

      if (!ruta.startsWith('$usuarioId/')) {
        return null;
      }

      return ruta;
    } catch (_) {
      return null;
    }
  }

  // --------------------------------------------------
  // LIMPIAR FOTOGRAFÍA ANTERIOR
  // --------------------------------------------------

  Future<void> _limpiarFotoAnterior(
    String? urlAnterior,
    String usuarioId,
  ) async {
    final ruta = _rutaFotoPropia(urlAnterior, usuarioId);

    if (ruta == null) {
      return;
    }

    try {
      await _supabase.storage
          .from('fotos_perfil')
          .remove([ruta])
          .timeout(const Duration(seconds: 10));
    } catch (error) {
      // Un error limpiando una foto antigua
      // no debe impedir que funcione el perfil.
      debugPrint('No fue posible limpiar la foto anterior: $error');
    }
  }

  // --------------------------------------------------
  // AGREGAR O CAMBIAR FOTO
  // --------------------------------------------------

  Future<void> _seleccionarYSubirFoto() async {
    if (_ocupado) return;

    final usuario = _supabase.auth.currentUser;

    if (usuario == null) {
      _mostrarMensaje('Inicia sesión para agregar una fotografía.');
      return;
    }

    XFile? seleccion;

    try {
      seleccion = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
    } catch (error) {
      debugPrint('Error al abrir la galería: $error');

      _mostrarMensaje('No pudimos abrir la galería de imágenes.');
      return;
    }

    if (seleccion == null || !mounted) {
      return;
    }

    setState(() {
      _subiendoFoto = true;
    });

    String? rutaNueva;

    try {
      final bytes = await seleccion.readAsBytes();

      if (bytes.isEmpty || bytes.length > maximoFotoBytes) {
        throw const FormatException(
          'La fotografía debe pesar como máximo 2 MB.',
        );
      }

      final formato = _detectarImagen(bytes);

      if (formato == null) {
        throw const FormatException('Selecciona una imagen JPG, PNG o WebP.');
      }

      // Evitar operaciones si cambió el usuario.
      if (_supabase.auth.currentUser?.id != usuario.id) {
        throw StateError('La sesión ha cambiado.');
      }

      final fotoAnterior = _avatarUrl;

      rutaNueva =
          '${usuario.id}/'
          'avatar_${DateTime.now().microsecondsSinceEpoch}'
          '.${formato.extension}';

      // Subir imagen a Supabase Storage.
      await _supabase.storage
          .from('fotos_perfil')
          .uploadBinary(
            rutaNueva,
            bytes,
            fileOptions: FileOptions(contentType: formato.mime, upsert: false),
          )
          .timeout(const Duration(seconds: 30));

      // Obtener URL de la fotografía subida.
      final urlNueva = _supabase.storage
          .from('fotos_perfil')
          .getPublicUrl(rutaNueva);

      if (_supabase.auth.currentUser?.id != usuario.id) {
        throw StateError('La sesión ha cambiado.');
      }

      // Guardar URL en el perfil.
      // La operación exige la fila actualizada.
      final resultado = await _supabase
          .from('perfil')
          .update({'avatar_url': urlNueva})
          .eq('id', usuario.id)
          .select('avatar_url')
          .single()
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;

      setState(() {
        _avatarUrl = resultado['avatar_url']?.toString();
      });

      _mostrarMensaje('Fotografía actualizada correctamente.');

      // Eliminar fotografía anterior si corresponde.
      await _limpiarFotoAnterior(fotoAnterior, usuario.id);
    } on FormatException catch (error) {
      _mostrarMensaje(error.message);
    } catch (error) {
      debugPrint('Error al subir fotografía: $error');

      _mostrarMensaje(
        'No pudimos guardar la fotografía. '
        'Revisa tu conexión y los permisos de Storage.',
      );

      // Si el archivo se subió pero ocurrió un
      // error, comprobar antes de eliminarlo.
      if (rutaNueva != null && _supabase.auth.currentUser?.id == usuario.id) {
        try {
          final perfil = await _supabase
              .from('perfil')
              .select('avatar_url')
              .eq('id', usuario.id)
              .maybeSingle()
              .timeout(const Duration(seconds: 8));

          final urlActual = perfil?['avatar_url']?.toString();

          final urlNueva = _supabase.storage
              .from('fotos_perfil')
              .getPublicUrl(rutaNueva);

          if (urlActual != urlNueva) {
            await _supabase.storage
                .from('fotos_perfil')
                .remove([rutaNueva])
                .timeout(const Duration(seconds: 10));
          } else if (mounted) {
            setState(() {
              _avatarUrl = urlActual;
            });

            _mostrarMensaje(
              'La fotografía ya se había guardado correctamente.',
            );
          }
        } catch (errorVerificacion) {
          debugPrint(
            'No se pudo verificar la fotografía: '
            '$errorVerificacion',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _subiendoFoto = false;
        });
      }
    }
  }

  // --------------------------------------------------
  // QUITAR FOTO
  // --------------------------------------------------

  Future<void> _quitarFoto() async {
    if (_ocupado || _avatarUrl == null) {
      return;
    }

    final usuario = _supabase.auth.currentUser;

    if (usuario == null) {
      return;
    }

    setState(() {
      _subiendoFoto = true;
    });

    try {
      final fotoAnterior = _avatarUrl;

      // Quitar referencia del perfil.
      await _supabase
          .from('perfil')
          .update({'avatar_url': null})
          .eq('id', usuario.id)
          .select('id')
          .single()
          .timeout(const Duration(seconds: 8));

      if (!mounted || _supabase.auth.currentUser?.id != usuario.id) {
        return;
      }

      setState(() {
        _avatarUrl = null;
      });

      _mostrarMensaje('Fotografía eliminada del perfil.');

      // Eliminar archivo del Storage.
      await _limpiarFotoAnterior(fotoAnterior, usuario.id);
    } catch (error) {
      debugPrint('Error al quitar fotografía: $error');

      _mostrarMensaje('No pudimos quitar la fotografía.');
    } finally {
      if (mounted) {
        setState(() {
          _subiendoFoto = false;
        });
      }
    }
  }

  // --------------------------------------------------
  // AVATAR
  // --------------------------------------------------

  Widget _avatar(ColorScheme esquema) {
    final colorFondo = _modoOscuro
        ? esquema.surfaceContainerHighest
        : const Color(0xFFE1F1E6);

    return CircleAvatar(
      radius: 42,
      backgroundColor: colorFondo,
      child: ClipOval(
        child: SizedBox(
          width: 84,
          height: 84,
          child: _avatarUrl == null
              ? Icon(Icons.person_rounded, size: 46, color: _colorPrincipal)
              : Image.network(
                  _avatarUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) {
                    return Icon(
                      Icons.person_rounded,
                      size: 46,
                      color: _colorPrincipal,
                    );
                  },
                ),
        ),
      ),
    );
  }

  // --------------------------------------------------
  // CAMBIAR CONTRASEÑA
  // --------------------------------------------------

  Future<void> _irACambiarContrasena() async {
    if (_ocupado) return;

    final actualizado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CambiarContrasenaScreen()),
    );

    if (!mounted) return;

    if (actualizado == true) {
      _mostrarMensaje('Contraseña actualizada correctamente.');
    }
  }

  // --------------------------------------------------
  // M08: DESACTIVAR CUENTA
  // --------------------------------------------------

  Future<void> _irADesactivarCuenta() async {
    if (_ocupado) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DesactivarCuentaScreen()),
    );
  }

  // --------------------------------------------------
  // M08: ELIMINACIÓN DEFINITIVA DE CUENTA
  // --------------------------------------------------

  bool get _eliminacionDisponible => false;

  Future<void> _irAEliminarCuenta() async {
    if (!_eliminacionDisponible || _ocupado) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const EliminarCuentaScreen()),
    );
  }

  // --------------------------------------------------
  // DECORACIÓN DE CAMPOS
  // --------------------------------------------------

  InputDecoration _decoracion(String etiqueta, IconData icono) {
    final esquema = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: etiqueta,
      labelStyle: TextStyle(color: esquema.onSurfaceVariant),
      floatingLabelStyle: TextStyle(
        color: _modoOscuro ? esquema.primary : verde,
      ),
      prefixIcon: Icon(icono, color: _modoOscuro ? esquema.primary : verde),
      filled: true,
      fillColor: esquema.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: esquema.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: _modoOscuro ? esquema.primary : verde,
          width: 1.7,
        ),
      ),
    );
  }

  // --------------------------------------------------
  // TÍTULOS DE SECCIÓN
  // --------------------------------------------------

  Widget _tituloSeccion(String titulo) {
    return Text(
      titulo,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.bold,
        color: _colorPrincipal,
      ),
    );
  }

  // --------------------------------------------------
  // PANTALLA PRINCIPAL
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final usuario = _supabase.auth.currentUser;
    final tema = Theme.of(context);
    final esquema = tema.colorScheme;

    return Scaffold(
      backgroundColor: tema.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Mi perfil',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: tema.scaffoldBackgroundColor,
        foregroundColor: _colorPrincipal,
        elevation: 0,
      ),
      body: SafeArea(
        child: _cargando
            ? Center(
                child: CircularProgressIndicator(
                  color: _modoOscuro ? esquema.primary : verde,
                ),
              )
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.account_circle_outlined,
                        size: 54,
                        color: _colorPrincipal,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _colorSecundario),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _cargando = true;
                            _error = null;
                          });

                          _cargarPerfil();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: verde,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // -----------------------
                          // ENCABEZADO DEL PERFIL
                          // -----------------------

                          Center(
                            child: Column(
                              children: [
                                _avatar(esquema),

                                const SizedBox(height: 10),

                                if (_subiendoFoto)
                                  const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: CircularProgressIndicator(),
                                  )
                                else
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      TextButton.icon(
                                        onPressed: _ocupado
                                            ? null
                                            : _seleccionarYSubirFoto,
                                        icon: const Icon(
                                          Icons.photo_camera_outlined,
                                        ),
                                        label: Text(
                                          _avatarUrl == null
                                              ? 'Agregar foto'
                                              : 'Cambiar foto',
                                        ),
                                      ),

                                      if (_avatarUrl != null)
                                        TextButton.icon(
                                          onPressed: _ocupado
                                              ? null
                                              : _quitarFoto,
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          label: const Text('Quitar'),
                                        ),
                                    ],
                                  ),

                                const SizedBox(height: 12),

                                Text(
                                  'Tus datos personales',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: _colorPrincipal,
                                  ),
                                ),

                                const SizedBox(height: 6),

                                Text(
                                  'Mantén tu información actualizada.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: _colorSecundario),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 28),

                          // -----------------------
                          // INFORMACIÓN DE CUENTA
                          // -----------------------
                          _tituloSeccion('Información de la cuenta'),

                          const SizedBox(height: 12),

                          TextFormField(
                            initialValue: usuario?.email ?? '',
                            readOnly: true,
                            style: TextStyle(color: esquema.onSurface),
                            decoration: _decoracion(
                              'Correo electrónico',
                              Icons.email_outlined,
                            ),
                          ),

                          const SizedBox(height: 24),

                          // -----------------------
                          // DATOS PERSONALES
                          // -----------------------
                          _tituloSeccion('Datos personales'),

                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _nombreController,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            style: TextStyle(color: esquema.onSurface),
                            decoration: _decoracion(
                              'Nombre',
                              Icons.person_outline,
                            ),
                          ),

                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _apellidoController,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.done,
                            style: TextStyle(color: esquema.onSurface),
                            decoration: _decoracion(
                              'Apellido',
                              Icons.person_outline,
                            ),
                          ),

                          const SizedBox(height: 14),

                          // -----------------------
                          // FECHA DE NACIMIENTO
                          // -----------------------
                          InkWell(
                            onTap: _ocupado ? null : _seleccionarFecha,
                            borderRadius: BorderRadius.circular(14),
                            child: InputDecorator(
                              decoration:
                                  _decoracion(
                                    'Fecha de nacimiento',
                                    Icons.calendar_month_outlined,
                                  ).copyWith(
                                    floatingLabelBehavior:
                                        FloatingLabelBehavior.always,
                                  ),
                              isEmpty: false,
                              child: Text(
                                _fechaNacimiento == null
                                    ? 'Seleccionar fecha'
                                    : _formatearFecha(_fechaNacimiento!),
                                style: TextStyle(
                                  color: _fechaNacimiento == null
                                      ? _colorSecundario
                                      : esquema.onSurface,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // -----------------------
                          // SEXO
                          // -----------------------
                          DropdownButtonFormField<String>(
                            initialValue: _sexo,
                            isExpanded: true,
                            dropdownColor: _colorSuperficie,
                            style: TextStyle(
                              color: esquema.onSurface,
                              fontSize: 16,
                            ),
                            decoration: _decoracion(
                              'Sexo',
                              Icons.person_search_outlined,
                            ),
                            items: _opcionesSexo.entries.map((opcion) {
                              return DropdownMenuItem<String>(
                                value: opcion.key,
                                child: Text(
                                  opcion.value,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: _ocupado
                                ? null
                                : (valor) {
                                    setState(() {
                                      _sexo = valor;
                                    });
                                  },
                          ),

                          const SizedBox(height: 28),

                          // -----------------------
                          // GUARDAR CAMBIOS
                          // -----------------------
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _ocupado ? null : _guardarPerfil,
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
                              label: Text(
                                _guardando ? 'Guardando...' : 'Guardar cambios',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: verde,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: verde.withValues(
                                  alpha: 0.65,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 28),

                          // -----------------------
                          // SEGURIDAD DE LA CUENTA
                          // -----------------------
                          _tituloSeccion('Seguridad de la cuenta'),

                          const SizedBox(height: 12),

                          // CAMBIAR CONTRASEÑA
                          Card(
                            color: esquema.surface,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: _colorBorde),
                            ),
                            child: ListTile(
                              leading: Icon(
                                Icons.lock_outline_rounded,
                                color: _modoOscuro ? esquema.primary : verde,
                              ),
                              title: Text(
                                'Cambiar contraseña',
                                style: TextStyle(
                                  color: esquema.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                'Actualiza la contraseña de tu cuenta.',
                                style: TextStyle(color: _colorSecundario),
                              ),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: _colorPrincipal,
                              ),
                              onTap: _ocupado ? null : _irACambiarContrasena,
                            ),
                          ),

                          const SizedBox(height: 12),

                          // -----------------------
                          // M08: DESACTIVAR CUENTA
                          // -----------------------
                          Card(
                            color: esquema.surface,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: _colorBorde),
                            ),
                            child: ListTile(
                              leading: Icon(
                                Icons.pause_circle_outline_rounded,
                                color: esquema.error,
                              ),
                              title: Text(
                                'Desactivar cuenta',
                                style: TextStyle(
                                  color: esquema.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                'Desactiva temporalmente tu cuenta '
                                'y conserva tus datos para volver.',
                                style: TextStyle(color: _colorSecundario),
                              ),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: esquema.error,
                              ),

                              onTap: _ocupado ? null : _irADesactivarCuenta,
                            ),
                          ),

                          if (_eliminacionDisponible) ...[
                            const SizedBox(height: 12),

                            // -----------------------
                            // M08: ELIMINAR CUENTA
                            // -----------------------
                            Card(
                              color: esquema.surface,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: _colorBorde),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  Icons.delete_forever_outlined,
                                  color: esquema.error,
                                ),
                                title: Text(
                                  'Eliminar cuenta definitivamente',
                                  style: TextStyle(
                                    color: esquema.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  'Consulta el proceso de eliminación '
                                  'permanente de tu cuenta.',
                                  style: TextStyle(color: _colorSecundario),
                                ),
                                trailing: Icon(
                                  Icons.chevron_right_rounded,
                                  color: esquema.error,
                                ),
                                onTap: _ocupado ? null : _irAEliminarCuenta,
                              ),
                            ),
                          ],

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
