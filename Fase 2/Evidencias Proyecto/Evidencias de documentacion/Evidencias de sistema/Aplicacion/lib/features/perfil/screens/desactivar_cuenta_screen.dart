
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DesactivarCuentaScreen extends StatefulWidget {
  const DesactivarCuentaScreen({super.key});

  @override
  State<DesactivarCuentaScreen> createState() =>
      _DesactivarCuentaScreenState();
}

class _DesactivarCuentaScreenState
    extends State<DesactivarCuentaScreen> {
  static const Color verde = Color(0xFF236B4A);

  final _supabase = Supabase.instance.client;
  final _confirmacionController = TextEditingController();

  bool _procesando = false;
  bool _desactivacionConfirmada = false;
  String? _error;

  @override
  void dispose() {
    _confirmacionController.dispose();
    super.dispose();
  }

  bool get _confirmacionValida =>
      _confirmacionController.text.trim().toUpperCase() ==
      'DESACTIVAR';

  // --------------------------------------------------
  // CERRAR SESIÓN
  // --------------------------------------------------

  Future<void> _cerrarSesion() async {
    try {
      await _supabase.auth.signOut();

      if (!mounted) return;

      Navigator.of(context).popUntil(
        (ruta) => ruta.isFirst,
      );
    } catch (error) {
      debugPrint('Error al cerrar sesión: $error');

      if (!mounted) return;

      setState(() {
        _error = 'La cuenta ya fue desactivada, '
            'pero no pudimos cerrar tu sesión. '
            'Presiona "Cerrar sesión" nuevamente.';
      });
    }
  }

  // --------------------------------------------------
  // M08: DESACTIVAR CUENTA
  // --------------------------------------------------

  Future<void> _desactivarCuenta() async {
    if (_procesando ||
        _desactivacionConfirmada ||
        !_confirmacionValida) {
      return;
    }

    final usuario = _supabase.auth.currentUser;

    if (usuario == null ||
        _supabase.auth.currentSession == null) {
      setState(() {
        _error = 'Tu sesión no está disponible. '
            'Inicia sesión nuevamente.';
      });
      return;
    }

    setState(() {
      _procesando = true;
      _error = null;
    });

    try {
      await _supabase
          .rpc('m08_desactivar_cuenta')
          .timeout(const Duration(seconds: 12));

      if (!mounted) return;

      if (_supabase.auth.currentUser?.id != usuario.id) {
        return;
      }

      setState(() {
        _desactivacionConfirmada = true;
      });

      await _cerrarSesion();
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _error = 'El servidor no confirmó la operación. '
            'La cuenta podría haberse desactivado. '
            'Cierra sesión y vuelve a ingresar '
            'para comprobar su estado.';
      });
    } on PostgrestException catch (error) {
      // --------------------------------------------------
      // MOSTRAR EL ERROR REAL DE SUPABASE
      // --------------------------------------------------

      debugPrint('========== ERROR M08 ==========');
      debugPrint('Código: ${error.code}');
      debugPrint('Mensaje: ${error.message}');
      debugPrint('Detalles: ${error.details}');
      debugPrint('Sugerencia: ${error.hint}');
      debugPrint('===============================');

      if (!mounted) return;

      final mensaje = error.message.toLowerCase();

      setState(() {
        if (mensaje.contains('transferir la administración')) {
          _error = 'No puedes desactivar tu cuenta '
              'mientras seas el único administrador '
              'activo de un hogar con otros integrantes. '
              'Primero debes transferir la administración.';
        } else if (mensaje.contains('no está activa')) {
          _error = 'La cuenta ya no está activa. '
              'Cierra sesión y vuelve a ingresar '
              'para consultar su estado.';
        } else {
          // Durante las pruebas mostraremos
          // el código y mensaje que entrega Supabase.

          _error =
              'ERROR DE SUPABASE\n\n'
              'Código: ${error.code ?? "Sin código"}\n\n'
              'Mensaje: ${error.message}\n\n'
              'Detalles: ${error.details ?? "Sin detalles"}';
        }
      });
    } catch (error) {
      debugPrint('========== ERROR GENERAL M08 ==========');
      debugPrint('Error: $error');
      debugPrint('======================================');

      if (!mounted) return;

      setState(() {
        _error = 'No pudimos confirmar la operación. '
            'Revisa el estado de tu cuenta '
            'antes de intentarlo nuevamente.\n\n'
            'Error: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _procesando = false;
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
      backgroundColor: tema.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Desactivar cuenta'),
        backgroundColor: tema.scaffoldBackgroundColor,
        foregroundColor: esquema.onSurface,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 480,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.pause_circle_outline_rounded,
                    size: 66,
                    color: esquema.error,
                  ),

                  const SizedBox(height: 18),

                  Text(
                    _desactivacionConfirmada
                        ? 'Cuenta desactivada'
                        : '¿Quieres desactivar tu cuenta?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                      color: esquema.onSurface,
                    ),
                  ),

                  const SizedBox(height: 14),

                  Text(
                    _desactivacionConfirmada
                        ? 'Tus datos permanecen guardados. '
                            'Cierra sesión y vuelve a ingresar '
                            'cuando quieras reactivar tu cuenta.'
                        : 'La desactivación es temporal. '
                            'Tu perfil, RUT, fotografía '
                            'y demás datos se conservarán '
                            'para una futura reactivación.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      height: 1.5,
                      color: esquema.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 24),

                  if (!_desactivacionConfirmada) ...[
                    Card(
                      color: esquema.surface,
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Antes de continuar',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 12),
                            Text(
                              '• La cuenta dejará de tener '
                              'acceso a los módulos protegidos.\n\n'
                              '• No se eliminará tu RUT '
                              'ni tu información personal.\n\n'
                              '• Si eres el único administrador '
                              'activo de un hogar con otros '
                              'integrantes activos, deberás '
                              'transferir la administración.\n\n'
                              '• Para volver a utilizar '
                              'NFC-FoodTech, tendrás que '
                              'iniciar sesión y reactivar '
                              'tu cuenta.',
                              style: TextStyle(height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Text(
                      'Escribe DESACTIVAR para confirmar',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: esquema.onSurface,
                      ),
                    ),

                    const SizedBox(height: 10),

                    TextField(
                      controller: _confirmacionController,
                      enabled: !_procesando,
                      textCapitalization:
                          TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'DESACTIVAR',
                        prefixIcon: const Icon(
                          Icons.edit_outlined,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onChanged: (_) {
                        setState(() {
                          _error = null;
                        });
                      },
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _procesando ||
                                !_confirmacionValida
                            ? null
                            : _desactivarCuenta,
                        style: FilledButton.styleFrom(
                          backgroundColor: esquema.error,
                          foregroundColor: esquema.onError,
                        ),
                        icon: _procesando
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: esquema.onError,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.pause_circle_outline,
                              ),
                        label: Text(
                          _procesando
                              ? 'Procesando...'
                              : 'Confirmar desactivación',
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    OutlinedButton(
                      onPressed: _procesando
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text(
                        'Cancelar y conservar mi cuenta',
                      ),
                    ),
                  ],

                  if (_desactivacionConfirmada)
                    FilledButton.icon(
                      onPressed: _procesando
                          ? null
                          : _cerrarSesion,
                      icon: const Icon(Icons.logout),
                      label: const Text('Cerrar sesión'),
                      style: FilledButton.styleFrom(
                        backgroundColor: verde,
                        foregroundColor: Colors.white,
                      ),
                    ),

                  if (_error != null) ...[
                    const SizedBox(height: 20),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: esquema.error,
                        height: 1.4,
                      ),
                    ),
                  ],

                  if (!_desactivacionConfirmada) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Esta acción no elimina definitivamente '
                      'tu cuenta.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: esquema.onSurfaceVariant,
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
}
