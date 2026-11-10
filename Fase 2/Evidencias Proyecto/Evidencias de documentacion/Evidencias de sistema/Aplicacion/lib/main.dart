import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'theme_controller.dart';
import 'services/notificaciones_locales.dart';

import 'package:nfc_foodtech_app/features/auth/screens/inicio_screen.dart';
import 'package:nfc_foodtech_app/features/home/screens/home_screen.dart';
import 'package:nfc_foodtech_app/features/auth/screens/nueva_contrasena_screen.dart';
import 'package:nfc_foodtech_app/features/auth/screens/tutorial_screen.dart';
import 'package:nfc_foodtech_app/features/auth/screens/aceptacion_documentos_screen.dart';
import 'screens/completar_identificacion_screen.dart';
import 'package:nfc_foodtech_app/features/auth/screens/reactivar_cuenta_screen.dart';
import 'package:nfc_foodtech_app/features/auth/screens/m08_verificar_mfa_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
  );

  final usuario = Supabase.instance.client.auth.currentUser;

  await appTheme.cargarParaUsuario(usuario?.id);
  await NotificacionesLocales.instancia.inicializar();

  runApp(const NfcFoodTechApp());
}

class NfcFoodTechApp extends StatelessWidget {
  const NfcFoodTechApp({super.key});

  static const Color verde = Color(0xFF236B4A);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appTheme,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'NFC-FoodTech',
          themeMode: appTheme.modo,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: verde,
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: const Color(0xFFF3F7F3),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: verde,
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF101C16),
          ),
          home: const PantallaInicial(),
        );
      },
    );
  }
}

enum _EstadoAcceso {
  verificando,
  documentosPendientes,
  identificacionPendiente,
  desactivada,
  restringida,
  listo,
  error,
}

class PantallaInicial extends StatefulWidget {
  const PantallaInicial({super.key});

  @override
  State<PantallaInicial> createState() => _PantallaInicialState();
}

class _PantallaInicialState extends State<PantallaInicial> {
  static const Color verde = Color(0xFF236B4A);

  static const String _versionTerminos = 'BORRADOR-R81-1';

  static const String _versionPrivacidad = 'BORRADOR-R81-1';

  static const Duration _tiempoEspera = Duration(seconds: 8);

  late final StreamSubscription<AuthState> _authSubscription;

  bool _recuperandoContrasena = false;
  bool _tutorialFinalizadoEnSesion = false;

  String? _usuarioActualId;
  String? _errorAcceso;
  String? _estadoCuenta;

  _EstadoAcceso _estadoAcceso = _EstadoAcceso.verificando;

  int _versionVerificacion = 0;

  @override
  void initState() {
    super.initState();

    final auth = Supabase.instance.client.auth;

    _usuarioActualId = auth.currentUser?.id;

    if (auth.currentSession != null && _usuarioActualId != null) {
      _verificarAcceso();
    }

    _authSubscription = auth.onAuthStateChange.listen(
      (data) {
        if (!mounted) return;

        final usuarioId = auth.currentUser?.id;

        if (data.event == AuthChangeEvent.signedOut ||
            auth.currentSession == null) {
          _versionVerificacion++;

          appTheme.cargarParaUsuario(null);

          setState(() {
            _usuarioActualId = null;
            _recuperandoContrasena = false;
            _tutorialFinalizadoEnSesion = false;
            _estadoCuenta = null;
            _estadoAcceso = _EstadoAcceso.verificando;
            _errorAcceso = null;
          });

          return;
        }

        final cambioUsuario = _usuarioActualId != usuarioId;

        if (cambioUsuario) {
          _usuarioActualId = usuarioId;

          appTheme.cargarParaUsuario(usuarioId);

          _tutorialFinalizadoEnSesion = false;
          _recuperandoContrasena = false;
        }

        if (data.event == AuthChangeEvent.passwordRecovery) {
          setState(() {
            _recuperandoContrasena = true;
          });
          return;
        }

        if (cambioUsuario || data.event == AuthChangeEvent.signedIn) {
          _verificarAcceso();
        } else {
          // Actualizar la navegación cuando cambia
          // el token o el nivel de autenticación.
          setState(() {});
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Error de autenticación: $error');
      },
    );
  }

  @override
  void dispose() {
    _versionVerificacion++;
    _authSubscription.cancel();
    super.dispose();
  }

  // --------------------------------------------------
  // VERIFICAR ESTADO, R81 E IDENTIFICACIÓN
  // --------------------------------------------------

  Future<void> _verificarAcceso() async {
    final auth = Supabase.instance.client.auth;
    final usuario = auth.currentUser;

    final versionActual = ++_versionVerificacion;

    if (!mounted) return;

    if (usuario == null || auth.currentSession == null) {
      setState(() {
        _estadoAcceso = _EstadoAcceso.verificando;
      });
      return;
    }

    setState(() {
      _estadoAcceso = _EstadoAcceso.verificando;
      _errorAcceso = null;
    });

    bool vigente() {
      return mounted &&
          versionActual == _versionVerificacion &&
          auth.currentUser?.id == usuario.id &&
          auth.currentSession != null;
    }

    try {
      // --------------------------------------------
      // 1. REVISAR ESTADO DE LA CUENTA
      // --------------------------------------------
      // Se comprueba antes de R81 y RUT.

      final perfil = await Supabase.instance.client
          .from('perfil')
          .select('estado_cuenta, nombre, apellido')
          .eq('id', usuario.id)
          .maybeSingle()
          .timeout(_tiempoEspera);

      if (!vigente()) return;

      if (perfil == null) {
        throw StateError('No se encontró el perfil del usuario.');
      }

      final estado = perfil['estado_cuenta']?.toString() ?? '';

      _estadoCuenta = estado;

      if (estado == 'DESACTIVADA') {
        setState(() {
          _estadoAcceso = _EstadoAcceso.desactivada;
        });
        return;
      }

      if (estado != 'ACTIVA') {
        setState(() {
          _estadoAcceso = _EstadoAcceso.restringida;
        });
        return;
      }

      // --------------------------------------------
      // 2. REVISAR ACEPTACIÓN DE DOCUMENTOS
      // --------------------------------------------

      final aceptacion = await Supabase.instance.client
          .from('aceptacion_documentos')
          .select('usuario_id')
          .eq('usuario_id', usuario.id)
          .eq('terminos_version', _versionTerminos)
          .eq('privacidad_version', _versionPrivacidad)
          .maybeSingle()
          .timeout(_tiempoEspera);

      if (!vigente()) return;

      if (aceptacion == null) {
        setState(() {
          _estadoAcceso = _EstadoAcceso.documentosPendientes;
        });
        return;
      }

      // --------------------------------------------
      // 3. COMPROBAR IDENTIFICACIÓN
      // --------------------------------------------

      final identificacion = await Supabase.instance.client
          .from('perfil_identificacion')
          .select('usuario_id')
          .eq('usuario_id', usuario.id)
          .maybeSingle()
          .timeout(_tiempoEspera);

      if (!vigente()) return;

      final nombre = perfil['nombre']?.toString().trim() ?? '';

      final apellido = perfil['apellido']?.toString().trim() ?? '';

      if (identificacion == null || nombre.isEmpty || apellido.isEmpty) {
        setState(() {
          _estadoAcceso = _EstadoAcceso.identificacionPendiente;
        });
        return;
      }

      // --------------------------------------------
      // 4. CUENTA ACTIVA Y REQUISITOS COMPLETOS
      // --------------------------------------------

      setState(() {
        _estadoAcceso = _EstadoAcceso.listo;
      });
    } on TimeoutException {
      if (!vigente()) return;

      setState(() {
        _estadoAcceso = _EstadoAcceso.error;
        _errorAcceso =
            'No pudimos verificar tu cuenta. '
            'Comprueba tu conexión a internet '
            'e inténtalo nuevamente.';
      });
    } catch (error) {
      debugPrint('Error al verificar acceso: $error');

      if (!vigente()) return;

      setState(() {
        _estadoAcceso = _EstadoAcceso.error;
        _errorAcceso =
            'No pudimos comprobar los datos '
            'de tu cuenta. Inténtalo nuevamente.';
      });
    }
  }

  // --------------------------------------------------
  // CALLBACKS
  // --------------------------------------------------

  void _aceptacionRegistrada() {
    if (!mounted) return;
    _verificarAcceso();
  }

  void _identificacionCompletada() {
    if (!mounted) return;
    _verificarAcceso();
  }

  void _reactivacionCompletada() {
    if (!mounted) return;
    _verificarAcceso();
  }

  // --------------------------------------------------
  // M08: SEGUNDO FACTOR VERIFICADO
  // --------------------------------------------------

  void _mfaVerificado() {
    if (!mounted) return;

    // Después de verificar MFA, repetimos
    // las comprobaciones de acceso habituales.
    _verificarAcceso();
  }

  void _finalizarTutorial() {
    if (!mounted) return;

    setState(() {
      _tutorialFinalizadoEnSesion = true;
    });
  }

  // --------------------------------------------------
  // PANTALLA DE VERIFICACIÓN
  // --------------------------------------------------

  Widget _pantallaVerificacion({required bool error}) {
    final tema = Theme.of(context);
    final esquema = tema.colorScheme;

    return Scaffold(
      backgroundColor: tema.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (error)
                    Icon(
                      Icons.error_outline_rounded,
                      size: 56,
                      color: esquema.error,
                    )
                  else
                    const CircularProgressIndicator(color: verde),

                  const SizedBox(height: 20),

                  Text(
                    error
                        ? 'No pudimos verificar tu cuenta'
                        : 'Verificando tu cuenta...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    error
                        ? (_errorAcceso ?? 'Inténtalo nuevamente.')
                        : 'Estamos comprobando '
                              'tu estado y tus datos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: esquema.onSurfaceVariant),
                  ),

                  if (error) ...[
                    const SizedBox(height: 22),

                    FilledButton.icon(
                      onPressed: _verificarAcceso,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reintentar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: verde,
                        foregroundColor: Colors.white,
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

  // --------------------------------------------------
  // NAVEGACIÓN PRINCIPAL
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;

    final sesion = auth.currentSession;
    final usuario = auth.currentUser;

    // 1. Sin sesión.
    if (sesion == null || usuario == null) {
      return const InicioScreen();
    }

    // 2. Recuperación de contraseña.
    if (_recuperandoContrasena) {
      return const NuevaContrasenaScreen();
    }

    // 3. Verificar cuenta.
    if (_estadoAcceso == _EstadoAcceso.verificando) {
      return _pantallaVerificacion(error: false);
    }

    // 4. Error de conexión o consulta.
    if (_estadoAcceso == _EstadoAcceso.error) {
      return _pantallaVerificacion(error: true);
    }

    // 5. Cuenta desactivada.
    if (_estadoAcceso == _EstadoAcceso.desactivada) {
      return ReactivarCuentaScreen(
        estadoCuenta: 'DESACTIVADA',
        onReactivada: _reactivacionCompletada,
      );
    }

    // 6. Cuenta suspendida, baneada
    // o con estado no reconocido.
    if (_estadoAcceso == _EstadoAcceso.restringida) {
      return ReactivarCuentaScreen(
        estadoCuenta: _estadoCuenta ?? '',
        onReactivada: _reactivacionCompletada,
      );
    }

    // --------------------------------------------
    // M08: VERIFICAR SEGUNDO FACTOR
    // --------------------------------------------
    // Solo solicita MFA cuando hay un factor
    // registrado pero aún no verificado
    // en la sesión actual.
    //
    // Esto protege la navegación en Flutter.
    // Las operaciones sensibles también deberán
    // exigir AAL2 en el servidor.

    final nivelMfa = auth.mfa.getAuthenticatorAssuranceLevel();

    final requiereMfa =
        nivelMfa.currentLevel == AuthenticatorAssuranceLevels.aal1 &&
        nivelMfa.nextLevel == AuthenticatorAssuranceLevels.aal2;

    if (requiereMfa) {
      return M08VerificarMfaScreen(onVerificado: _mfaVerificado);
    }

    // 7. Aceptación de documentos.
    if (_estadoAcceso == _EstadoAcceso.documentosPendientes) {
      return AceptacionDocumentosScreen(
        onAceptacionRegistrada: _aceptacionRegistrada,
      );
    }

    // 8. Completar identificación.
    if (_estadoAcceso == _EstadoAcceso.identificacionPendiente) {
      return CompletarIdentificacionScreen(
        onCompletado: _identificacionCompletada,
      );
    }

    // 9. Tutorial.
    final tutorialGuardado =
        usuario.userMetadata?['tutorial_completado'] == true;

    if (!tutorialGuardado && !_tutorialFinalizadoEnSesion) {
      return TutorialScreen(onFinalizado: _finalizarTutorial);
    }

    // 10. Home.
    return const HomeScreen();
  }
}
