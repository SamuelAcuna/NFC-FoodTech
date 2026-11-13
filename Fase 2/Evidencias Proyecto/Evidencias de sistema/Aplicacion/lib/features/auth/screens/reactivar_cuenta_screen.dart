
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReactivarCuentaScreen extends StatefulWidget {
  final String estadoCuenta;
  final VoidCallback onReactivada;

  const ReactivarCuentaScreen({
    super.key,
    required this.estadoCuenta,
    required this.onReactivada,
  });

  @override
  State<ReactivarCuentaScreen> createState() =>
      _ReactivarCuentaScreenState();
}

class _ReactivarCuentaScreenState
    extends State<ReactivarCuentaScreen> {
  static const Color verde = Color(0xFF236B4A);

  final _supabase = Supabase.instance.client;

  bool _procesando = false;
  String? _error;

  bool get _puedeReactivar =>
      widget.estadoCuenta == 'DESACTIVADA';

  Future<void> _reactivarCuenta() async {
    if (_procesando || !_puedeReactivar) return;

    final usuario = _supabase.auth.currentUser;

    if (usuario == null ||
        _supabase.auth.currentSession == null) {
      setState(() {
        _error = 'Debes iniciar sesión nuevamente.';
      });
      return;
    }

    setState(() {
      _procesando = true;
      _error = null;
    });

    try {
      // La función identifica al usuario
      // directamente desde auth.uid().
      await _supabase
          .rpc('m08_reactivar_cuenta')
          .timeout(const Duration(seconds: 10));

      if (!mounted ||
          _supabase.auth.currentUser?.id != usuario.id) {
        return;
      }

      // Main volverá a verificar el estado
      // y los requisitos R81 e identificación.
      widget.onReactivada();
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _error =
            'No pudimos confirmar la operación. '
            'Es posible que la cuenta ya esté activa. '
            'Presiona "Comprobar estado".';
      });
    } on PostgrestException catch (error) {
      debugPrint('Error al reactivar cuenta: $error');

      if (!mounted) return;

      setState(() {
        _error =
            'No pudimos reactivar tu cuenta. '
            'Comprueba tu conexión e inténtalo nuevamente.';
      });
    } catch (error) {
      debugPrint('Error de reactivación: $error');

      if (!mounted) return;

      setState(() {
        _error =
            'Ocurrió un error. '
            'Comprueba el estado antes de volver a intentar.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _procesando = false;
        });
      }
    }
  }

  Future<void> _cerrarSesion() async {
    if (_procesando) return;

    setState(() {
      _procesando = true;
      _error = null;
    });

    try {
      await _supabase.auth.signOut();
    } catch (error) {
      debugPrint('Error al cerrar sesión: $error');

      if (!mounted) return;

      setState(() {
        _error =
            'No pudimos cerrar la sesión. '
            'Inténtalo nuevamente.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _procesando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final esquema = tema.colorScheme;
    final oscuro = tema.brightness == Brightness.dark;

    final titulo = _puedeReactivar
        ? 'Cuenta desactivada'
        : 'Acceso restringido';

    final descripcion = _puedeReactivar
        ? 'Tu cuenta de NFC-FoodTech está '
            'desactivada temporalmente. '
            'Puedes reactivarla para recuperar '
            'tu perfil, RUT y datos anteriores.'
        : widget.estadoCuenta == 'SUSPENDIDA'
            ? 'Tu cuenta se encuentra suspendida. '
                'La reactivación voluntaria '
                'no está disponible.'
            : widget.estadoCuenta == 'BANEADA'
                ? 'Tu cuenta tiene una restricción '
                    'administrativa. No puedes '
                    'reactivarla desde esta pantalla.'
                : 'No podemos habilitar tu cuenta '
                    'con el estado actual.';

    return Scaffold(
      backgroundColor: tema.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: 470),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      height: 80,
                      width: 80,
                      decoration: BoxDecoration(
                        color: oscuro
                            ? esquema.surfaceContainerHighest
                            : const Color(0xFFE1F1E6),
                        borderRadius:
                            BorderRadius.circular(24),
                      ),
                      child: Icon(
                        _puedeReactivar
                            ? Icons.pause_circle_outline
                            : Icons.lock_outline_rounded,
                        size: 45,
                        color: oscuro
                            ? esquema.primary
                            : verde,
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                      color: esquema.onSurface,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    descripcion,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      height: 1.5,
                      color: esquema.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 24),

                  if (_puedeReactivar)
                    Card(
                      color: esquema.surface,
                      child: const Padding(
                        padding: EdgeInsets.all(16),
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
                                'La reactivación utiliza '
                                'tu cuenta original. '
                                'No necesitas registrarte '
                                'otra vez ni ingresar '
                                'nuevamente tu RUT.',
                                style: TextStyle(
                                  height: 1.5,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: esquema.error,
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  if (_puedeReactivar) ...[
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _procesando
                            ? null
                            : _reactivarCuenta,
                        icon: _procesando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.refresh_rounded,
                              ),
                        label: Text(
                          _procesando
                              ? 'Procesando...'
                              : 'Reactivar mi cuenta',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: verde,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    OutlinedButton.icon(
                      onPressed: _procesando
                          ? null
                          : widget.onReactivada,
                      icon: const Icon(
                        Icons.sync_rounded,
                      ),
                      label: const Text(
                        'Comprobar estado',
                      ),
                    ),

                    const SizedBox(height: 12),
                  ],

                  TextButton.icon(
                    onPressed:
                        _procesando ? null : _cerrarSesion,
                    icon: const Icon(
                      Icons.logout_rounded,
                    ),
                    label: const Text(
                      'Cerrar sesión',
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
