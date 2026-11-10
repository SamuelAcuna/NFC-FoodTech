import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class M08ConfigurarMfaScreen extends StatefulWidget {
  const M08ConfigurarMfaScreen({super.key});

  @override
  State<M08ConfigurarMfaScreen> createState() => _M08ConfigurarMfaScreenState();
}

class _M08ConfigurarMfaScreenState extends State<M08ConfigurarMfaScreen> {
  static const Color verde = Color(0xFF236B4A);

  final _supabase = Supabase.instance.client;
  final _codigoController = TextEditingController();

  String? _factorId;
  String? _secreto;
  String? _mensaje;

  bool _cargando = false;
  bool _verificado = false;

  String? _usuarioInicial;
  late final StreamSubscription<AuthState> _sesion;

  @override
  void initState() {
    super.initState();
    _usuarioInicial = _supabase.auth.currentUser?.id;
    _sesion = _supabase.auth.onAuthStateChange.listen((_) {
      if (!mounted || _supabase.auth.currentUser?.id == _usuarioInicial) return;
      _codigoController.clear();
      setState(() {
        _factorId = null;
        _secreto = null;
        _mensaje = 'La sesion cambio. Vuelve a abrir esta pantalla.';
      });
    });
  }

  @override
  void dispose() {
    _sesion.cancel();
    _codigoController.dispose();
    super.dispose();
  }

  Future<void> _registrarFactor() async {
    if (_cargando || _factorId != null) return;

    if (_supabase.auth.currentUser == null ||
        _supabase.auth.currentUser?.id != _usuarioInicial ||
        !(kDebugMode && const bool.fromEnvironment('M08_PREPARACION_LOCAL'))) {
      setState(() {
        _mensaje =
            'La configuracion local requiere debug y habilitacion explicita.';
      });
      return;
    }

    setState(() {
      _cargando = true;
      _mensaje = null;
    });

    final usuario = _supabase.auth.currentUser?.id;
    try {
      final respuesta = await _supabase.auth.mfa.enroll(
        factorType: FactorType.totp,
        friendlyName: 'NFC-FoodTech M08',
      );

      if (!mounted || _supabase.auth.currentUser?.id != usuario) return;

      setState(() {
        _factorId = respuesta.id;
        _secreto = respuesta.totp?.secret;
        _mensaje =
            'Registra esta clave en Google Authenticator. '
            'Después introduce el código de seis dígitos.';
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _mensaje = 'No se pudo iniciar MFA: ${error.message}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mensaje = 'Ocurrió un error al configurar MFA.';
      });
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  Future<void> _verificarFactor() async {
    if (_cargando ||
        _factorId == null ||
        _supabase.auth.currentUser?.id != _usuarioInicial)
      return;

    final codigo = _codigoController.text.trim();

    if (!RegExp(r'^\d{6}$').hasMatch(codigo)) {
      setState(() {
        _mensaje = 'Introduce un código de seis dígitos.';
      });
      return;
    }

    setState(() {
      _cargando = true;
      _mensaje = null;
    });

    final usuario = _supabase.auth.currentUser?.id;
    try {
      await _supabase.auth.mfa.challengeAndVerify(
        factorId: _factorId!,
        code: codigo,
      );

      if (!mounted || _supabase.auth.currentUser?.id != usuario) return;

      setState(() {
        _verificado = true;
        _secreto = null;
        _mensaje =
            'Autenticador verificado correctamente. '
            'Tu cuenta ahora tiene MFA configurado.';
      });

      _codigoController.clear();
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _mensaje = 'No se pudo verificar: ${error.message}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mensaje = 'No se pudo comprobar el código.';
      });
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final esquema = tema.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Configurar autenticador')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 550),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Seguridad adicional M08',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 12),

                const Text(
                  'Utilizaremos una aplicación autenticadora '
                  'para confirmar operaciones sensibles.',
                ),

                const SizedBox(height: 20),

                if (!_verificado && _factorId == null)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _cargando ? null : _registrarFactor,
                      child: const Text('Preparar Google Authenticator'),
                    ),
                  ),

                if (!_verificado && _secreto != null) ...[
                  const SizedBox(height: 20),

                  const Text(
                    'En Google Authenticator selecciona '
                    '"Introducir clave de configuración".',
                  ),

                  const SizedBox(height: 12),

                  const Text('Nombre de la cuenta: NFC-FoodTech'),

                  const SizedBox(height: 12),

                  const Text(
                    'Clave de configuración:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 8),

                  SelectableText(
                    _secreto!,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),

                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _secreto!));
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar clave'),
                  ),

                  const SizedBox(height: 16),

                  TextField(
                    controller: _codigoController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Código de seis dígitos',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _cargando ? null : _verificarFactor,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: verde,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        _cargando ? 'Verificando...' : 'Verificar autenticador',
                      ),
                    ),
                  ),
                ],

                if (_mensaje != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _mensaje!,
                    style: TextStyle(
                      color: _verificado
                          ? (tema.brightness == Brightness.dark
                                ? esquema.primary
                                : verde)
                          : esquema.onSurface,
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                const Text(
                  'Importante: no compartas la clave de '
                  'configuración ni los códigos temporales. '
                  'Guarda un método de respaldo antes de '
                  'depender de MFA para acceder a tu cuenta.',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
