
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class M08VerificarMfaScreen extends StatefulWidget {
  final VoidCallback onVerificado;

  const M08VerificarMfaScreen({
    super.key,
    required this.onVerificado,
  });

  @override
  State<M08VerificarMfaScreen> createState() =>
      _M08VerificarMfaScreenState();
}

class _M08VerificarMfaScreenState
    extends State<M08VerificarMfaScreen> {
  static const Color verde = Color(0xFF236B4A);

  final _supabase = Supabase.instance.client;
  final _codigoController = TextEditingController();

  String? _factorId;
  String? _error;

  bool _cargando = true;
  bool _verificando = false;

  @override
  void initState() {
    super.initState();
    _cargarFactor();
  }

  @override
  void dispose() {
    _codigoController.dispose();
    super.dispose();
  }

  // -------------------------------------------
  // CARGAR FACTOR TOTP VERIFICADO
  // -------------------------------------------

  Future<void> _cargarFactor() async {
    final usuario = _supabase.auth.currentUser;

    if (usuario == null) {
      if (!mounted) return;

      setState(() {
        _cargando = false;
        _error = 'No existe una sesión activa.';
      });
      return;
    }

    try {
      final respuesta =
          await _supabase.auth.mfa.listFactors();

      if (!mounted) return;

      if (_supabase.auth.currentUser?.id != usuario.id) {
        return;
      }

      // La lista totp contiene factores verificados.
      if (respuesta.totp.isEmpty) {
        setState(() {
          _cargando = false;
          _error =
              'No encontramos un autenticador '
              'verificado para esta cuenta.';
        });
        return;
      }

      setState(() {
        _factorId = respuesta.totp.first.id;
        _error = null;
        _cargando = false;
      });
    } on AuthException catch (error) {
      if (!mounted) return;

      setState(() {
        _cargando = false;
        _error =
            'No se pudo consultar MFA: ${error.message}';
      });
    } catch (error) {
      debugPrint('Error al cargar MFA: $error');

      if (!mounted) return;

      setState(() {
        _cargando = false;
        _error = 'No pudimos cargar tu autenticador.';
      });
    }
  }

  // -------------------------------------------
  // VERIFICAR CÓDIGO DEL AUTENTICADOR
  // -------------------------------------------

  Future<void> _verificarCodigo() async {
    if (_verificando || _factorId == null) return;

    final usuario = _supabase.auth.currentUser;
    final codigo = _codigoController.text.trim();

    if (usuario == null) {
      setState(() {
        _error = 'Tu sesión ha expirado.';
      });
      return;
    }

    if (!RegExp(r'^\d{6}$').hasMatch(codigo)) {
      setState(() {
        _error = 'Ingresa un código válido de seis dígitos.';
      });
      return;
    }

    setState(() {
      _verificando = true;
      _error = null;
    });

    try {
      await _supabase.auth.mfa.challengeAndVerify(
        factorId: _factorId!,
        code: codigo,
      );

      if (!mounted) return;

      if (_supabase.auth.currentUser?.id != usuario.id) {
        return;
      }

      // Confirmar que Supabase elevó la sesión a AAL2.
      final nivel = _supabase.auth.mfa
          .getAuthenticatorAssuranceLevel();

      if (nivel.currentLevel !=
        AuthenticatorAssuranceLevels.aal2) {
        throw StateError(
          'La sesión no alcanzó el nivel AAL2.',
        );
      }

      _codigoController.clear();

      widget.onVerificado();
    } on AuthException catch (error) {
      debugPrint('Error al verificar MFA: ${error.message}');

      if (!mounted) return;

      setState(() {
        _error =
            'El código no pudo verificarse. '
            'Comprueba el autenticador e inténtalo nuevamente.';
      });
    } catch (error) {
      debugPrint('Error inesperado MFA: $error');

      if (!mounted) return;

      setState(() {
        _error = 'No fue posible completar la verificación.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _verificando = false;
        });
      }
    }
  }

  // -------------------------------------------
  // CERRAR SESIÓN
  // -------------------------------------------

  Future<void> _cerrarSesion() async {
    try {
      await _supabase.auth.signOut();
    } catch (error) {
      debugPrint('Error al cerrar sesión MFA: $error');

      if (!mounted) return;

      setState(() {
        _error = 'No se pudo cerrar la sesión.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final esquema = tema.colorScheme;
    final oscuro = tema.brightness == Brightness.dark;

    final colorTitulo =
        oscuro ? esquema.onSurface : verde;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: tema.scaffoldBackgroundColor,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Verificación de seguridad'),
          backgroundColor: tema.scaffoldBackgroundColor,
          foregroundColor: colorTitulo,
          actions: [
            IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: _cerrarSesion,
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 450),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 65,
                      color: colorTitulo,
                    ),

                    const SizedBox(height: 20),

                    Text(
                      'Verifica tu identidad',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: colorTitulo,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'Abre Google Authenticator e '
                      'introduce el código de seis dígitos '
                      'asociado a NFC-FoodTech.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: esquema.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 28),

                    if (_cargando)
                      const Center(
                        child: CircularProgressIndicator(),
                      )
                    else ...[
                      TextField(
                        controller: _codigoController,
                        enabled:
                            !_verificando && _factorId != null,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        maxLength: 6,
                        obscureText: false,
                        decoration: const InputDecoration(
                          labelText: 'Código de seguridad',
                          hintText: '000000',
                          border: OutlineInputBorder(),
                          prefixIcon:
                              Icon(Icons.lock_outline),
                        ),
                        onSubmitted: (_) => _verificarCodigo(),
                      ),

                      const SizedBox(height: 12),

                      SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _verificando ||
                                  _factorId == null
                              ? null
                              : _verificarCodigo,
                          icon: _verificando
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
                                  Icons.check_circle_outline,
                                ),
                          label: Text(
                            _verificando
                                ? 'Verificando...'
                                : 'Verificar y continuar',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: verde,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 18),

                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: esquema.error,
                        ),
                      ),

                      if (!_cargando &&
                          _factorId == null)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _cargando = true;
                              _error = null;
                            });
                            _cargarFactor();
                          },
                          child: const Text('Reintentar'),
                        ),
                    ],

                    const SizedBox(height: 20),

                    Text(
                      'Si no puedes acceder al autenticador, '
                      'cierra sesión y utiliza el proceso '
                      'de recuperación de cuenta correspondiente.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: esquema.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
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
