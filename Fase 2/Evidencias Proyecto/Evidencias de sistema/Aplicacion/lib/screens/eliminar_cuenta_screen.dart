import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nfc_foodtech_app/features/auth/screens/m08_configurar_mfa_screen.dart';
import 'package:nfc_foodtech_app/features/auth/screens/m08_verificar_mfa_screen.dart';
import '../services/m08_eliminacion_local.dart';

class EliminarCuentaScreen extends StatefulWidget {
  const EliminarCuentaScreen({super.key});

  @override
  State<EliminarCuentaScreen> createState() => _EliminarCuentaScreenState();
}

class _EliminarCuentaScreenState extends State<EliminarCuentaScreen> {
  static const Color verde = Color(0xFF236B4A);
  bool get _preparacionLocal => false;
  final _confirmacionController = TextEditingController();
  final _codigoMfaController = TextEditingController();
  final _contrasenaController = TextEditingController();
  late final M08EliminacionLocal _control;
  late final StreamSubscription<AuthState> _sesion;

  bool get _revisando => _control.estado == EstadoM08.revisando;
  bool get _eliminandoCuenta => _control.ocupado;
  bool get _mfaCorrecto => _control.estado == EstadoM08.simulada;
  Map<String, dynamic>? get _resultado => _control.revision == null
      ? null
      : {
          ...Map<String, dynamic>.from(_control.revision!['resumen'] as Map),
          'apto': _control.revision!['apto'],
        };
  String? get _error =>
      _control.estado == EstadoM08.error ? _control.mensaje : null;
  String? get _resultadoEliminacion =>
      _control.estado == EstadoM08.inicial ||
          _control.estado == EstadoM08.revisando ||
          _control.estado == EstadoM08.error
      ? null
      : _control.mensaje;

  @override
  void initState() {
    super.initState();
    if (!_preparacionLocal) return;
    _control = M08EliminacionLocal.supabase()..addListener(_actualizar);
    final usuario = Supabase.instance.client.auth.currentUser?.id;
    _sesion = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (!mounted) return;
      if (Supabase.instance.client.auth.currentUser?.id != usuario) {
        _confirmacionController.clear();
        _codigoMfaController.clear();
        _contrasenaController.clear();
        _control.cambioSesion();
      }
    });
  }

  void _actualizar() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_preparacionLocal) {
      _sesion.cancel();
      _control.removeListener(_actualizar);
      _control.dispose();
    }
    _confirmacionController.dispose();
    _codigoMfaController.dispose();
    _contrasenaController.dispose();
    super.dispose();
  }

  Future<void> _revisarRequisitos() async {
    if (_preparacionLocal) await _control.revisar();
  }

  Future<void> _abrirConfiguracionMfa() async {
    if (!_preparacionLocal || _control.ocupado) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const M08ConfigurarMfaScreen()),
    );
    if (mounted) await _control.revisar();
  }

  Future<void> _verificarMfaSesion() async {
    if (!_preparacionLocal || _control.ocupado) return;
    final usuario = Supabase.instance.client.auth.currentUser?.id;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (contexto) => M08VerificarMfaScreen(
          onVerificado: () {
            if (contexto.mounted &&
                Supabase.instance.client.auth.currentUser?.id == usuario) {
              Navigator.of(contexto).pop();
            }
          },
        ),
      ),
    );
    if (mounted) await _control.revisar();
  }

  Future<void> _probarConfirmacionMfa() async {
    if (!_preparacionLocal || !_control.puedeSimular) return;
    final usuario = Supabase.instance.client.auth.currentUser?.id;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Simular confirmacion de cuenta'),
        content: const Text(
          'Se verificaran identidad y requisitos. No se eliminara ninguna cuenta ni ningun hogar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(contexto, true),
            child: const Text('Simular'),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmar != true ||
        Supabase.instance.client.auth.currentUser?.id != usuario)
      return;
    try {
      await _control.simular(
        confirmacion: _confirmacionController.text.trim(),
        contrasena: _contrasenaController.text,
        codigo: _codigoMfaController.text.trim(),
      );
    } finally {
      if (mounted) {
        _contrasenaController.clear();
        _codigoMfaController.clear();
      }
    }
  }

  // ==================================================
  // COMPONENTE: FILA DE REVISIÓN
  // ==================================================

  Widget _filaResultado(String etiqueta, dynamic valor) {
    final esquema = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              etiqueta,
              style: TextStyle(color: esquema.onSurfaceVariant),
            ),
          ),
          Text(
            '$valor',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: esquema.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // ==================================================
  // COMPONENTE: INFORMACIÓN DE ELIMINACIÓN
  // ==================================================

  Widget _informacion(IconData icono, String titulo, String descripcion) {
    final esquema = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: esquema.onSurfaceVariant, size: 23),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: esquema.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  descripcion,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
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

  // ==================================================
  // INTERFAZ
  // ==================================================

  @override
  Widget build(BuildContext context) {
    if (!_preparacionLocal) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cuenta')),
        body: const SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'La eliminación definitiva de cuentas no está disponible.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    final tema = Theme.of(context);
    final esquema = tema.colorScheme;

    final oscuro = tema.brightness == Brightness.dark;

    final colorPrincipal = oscuro ? esquema.onSurface : verde;
    final colorExito = oscuro ? esquema.primary : verde;

    final resultado = _resultado;
    final apto = resultado?['apto'] == true;

    return PopScope(
      canPop: !_eliminandoCuenta,
      child: Scaffold(
        backgroundColor: tema.scaffoldBackgroundColor,

        appBar: AppBar(
          title: const Text(
            'Eliminar cuenta',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: tema.scaffoldBackgroundColor,
          foregroundColor: colorPrincipal,
          elevation: 0,
          automaticallyImplyLeading: !_eliminandoCuenta,
        ),

        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --------------------------------
                    // ENCABEZADO
                    // --------------------------------

                    Center(
                      child: CircleAvatar(
                        radius: 39,
                        backgroundColor: esquema.error.withValues(alpha: 0.10),
                        child: Icon(
                          Icons.delete_forever_outlined,
                          size: 42,
                          color: esquema.error,
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    Center(
                      child: Text(
                        'Eliminación definitiva',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                          color: colorPrincipal,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'La eliminacion real no esta habilitada. '
                      'La preparacion local solo revisa requisitos y simula la confirmacion.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: esquema.onSurfaceVariant,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 28),

                    // --------------------------------
                    // CONSECUENCIAS
                    // --------------------------------
                    Text(
                      '¿Qué implica eliminar tu cuenta?',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: colorPrincipal,
                      ),
                    ),

                    const SizedBox(height: 14),

                    _informacion(
                      Icons.person_remove_outlined,
                      'Datos personales',
                      'Se eliminarán el perfil y '
                          'los datos personales asociados '
                          'según las relaciones configuradas.',
                    ),

                    _informacion(
                      Icons.photo_outlined,
                      'Fotografías',
                      'Las cuentas con archivos '
                          'detectados no pueden pasar '
                          'esta prueba de eliminación.',
                    ),

                    _informacion(
                      Icons.support_agent_outlined,
                      'Soporte',
                      'Las solicitudes de soporte '
                          'deben cumplir las reglas '
                          'de eliminación establecidas.',
                    ),

                    _informacion(
                      Icons.home_outlined,
                      'Hogares',
                      'No se permite eliminar '
                          'cuentas que sigan siendo creadoras de hogares '
                          'o mantengan membresias activas.',
                    ),

                    const SizedBox(height: 22),

                    // --------------------------------
                    // ADVERTENCIA
                    // --------------------------------
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: esquema.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: esquema.error),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: esquema.error,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'La eliminacion real esta deshabilitada. '
                              'La preparacion requiere debug y habilitacion explicita. '
                              'El backend nuevo todavia necesita despliegue y validacion autorizados.',
                              style: TextStyle(
                                color: esquema.onSurface,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // --------------------------------
                    // OPERACIONES DE PRUEBA
                    // --------------------------------
                    if (_preparacionLocal) ...[
                      const SizedBox(height: 24),

                      Text(
                        'Control de eliminación M08',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: colorPrincipal,
                        ),
                      ),

                      const SizedBox(height: 14),

                      // REVISAR REQUISITOS
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _revisando || _eliminandoCuenta
                              ? null
                              : _revisarRequisitos,
                          icon: _revisando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.fact_check_outlined),
                          label: Text(
                            _revisando ? 'Revisando...' : 'Revisar requisitos',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: verde,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      if (_control.pendiente)
                        OutlinedButton.icon(
                          onPressed: _control.ocupado
                              ? null
                              : _control.consultarEstado,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Consultar estado de la solicitud'),
                        ),
                      if (_control.autenticacion['contrasena'] == true) ...[
                        TextField(
                          controller: _contrasenaController,
                          enabled: !_control.ocupado,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText:
                                'Contrasena actual (solo para verificar en Auth)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      for (final bloqueo
                          in (_control.revision?['bloqueos'] as List? ?? []))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${bloqueo['codigo']}: ${bloqueo['mensaje']}',
                            style: TextStyle(color: esquema.error),
                          ),
                        ),
                      for (final consecuencia
                          in (_control.revision?['consecuencias'] as List? ??
                              []))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('$consecuencia'),
                        ),

                      if (_control.autenticacion['totp_en_sesion'] == true)
                        TextButton(
                          onPressed: _control.ocupado
                              ? null
                              : _verificarMfaSesion,
                          child: const Text('Verificar TOTP de esta sesion'),
                        ),

                      // CONFIGURACIÓN MFA
                      Text(
                        'Autenticación adicional',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colorPrincipal,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Google Authenticator permite '
                        'confirmar tu identidad '
                        'con códigos temporales.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: esquema.onSurfaceVariant,
                        ),
                      ),

                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _eliminandoCuenta
                              ? null
                              : _abrirConfiguracionMfa,
                          icon: const Icon(Icons.shield_outlined),
                          label: const Text('Configurar Google Authenticator'),
                        ),
                      ),

                      const SizedBox(height: 26),

                      const Divider(),

                      const SizedBox(height: 16),

                      // --------------------------------
                      // CONFIRMACIÓN DEFINITIVA
                      // --------------------------------
                      Text(
                        'Simular confirmacion segura',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: esquema.error,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        'Escribe ELIMINAR y verifica tu identidad con el metodo indicado. '
                        'Esta operacion no borra datos.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: esquema.onSurfaceVariant,
                        ),
                      ),

                      const SizedBox(height: 18),

                      TextField(
                        controller: _confirmacionController,
                        enabled: !_eliminandoCuenta,
                        decoration: const InputDecoration(
                          labelText: 'Escribe ELIMINAR',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.edit_outlined),
                        ),
                      ),

                      const SizedBox(height: 16),

                      if (_control.autenticacion['requiere_totp'] == true &&
                          _control.autenticacion['totp_en_sesion'] != true)
                        TextField(
                          controller: _codigoMfaController,
                          enabled: !_eliminandoCuenta,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          maxLength: 6,
                          decoration: const InputDecoration(
                            labelText: 'Código de Google Authenticator',
                            hintText: '000000',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                        ),

                      const SizedBox(height: 8),

                      // BOTÓN ELIMINACIÓN
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: !_control.puedeSimular
                              ? null
                              : _probarConfirmacionMfa,
                          icon: _eliminandoCuenta
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: oscuro
                                        ? esquema.onError
                                        : Colors.white,
                                  ),
                                )
                              : const Icon(Icons.delete_forever_outlined),
                          label: Text(
                            _eliminandoCuenta
                                ? 'Procesando simulacion...'
                                : 'Simular confirmacion segura',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: esquema.error,
                            foregroundColor: oscuro
                                ? esquema.onError
                                : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),

                      // RESULTADO
                      if (_resultadoEliminacion != null) ...[
                        const SizedBox(height: 16),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _mfaCorrecto
                                  ? Icons.check_circle_outline
                                  : Icons.error_outline,
                              color: _mfaCorrecto ? colorExito : esquema.error,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _resultadoEliminacion!,
                                style: TextStyle(
                                  color: _mfaCorrecto
                                      ? colorExito
                                      : esquema.error,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 14),

                      Text(
                        'El servidor valida la identidad y registra la simulacion. '
                        'Esta version no contiene una operacion de borrado.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: esquema.onSurfaceVariant,
                        ),
                      ),
                    ],

                    // --------------------------------
                    // ERRORES GENERALES
                    // --------------------------------
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: esquema.error)),
                    ],

                    // --------------------------------
                    // RESULTADO DE REVISIÓN
                    // --------------------------------
                    if (resultado != null) ...[
                      const SizedBox(height: 24),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: esquema.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: esquema.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  apto
                                      ? Icons.check_circle_outline
                                      : Icons.info_outline,
                                  color: apto ? colorExito : esquema.error,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    apto
                                        ? 'Revisión preliminar aprobada'
                                        : 'Requisitos pendientes',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: esquema.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 14),

                            _filaResultado(
                              'Estado de la cuenta',
                              resultado['estado_cuenta'] ?? '-',
                            ),

                            _filaResultado(
                              'Hogares creados',
                              resultado['hogares_creados'] ?? 0,
                            ),

                            _filaResultado(
                              'Membresias activas',
                              resultado['membresias_activas'] ?? 0,
                            ),

                            _filaResultado(
                              'Soporte',
                              resultado['soporte'] ?? 0,
                            ),

                            _filaResultado(
                              'Archivos',
                              resultado['archivos'] ?? 0,
                            ),

                            _filaResultado(
                              'Auditoría',
                              resultado['auditoria'] ?? 0,
                            ),

                            _filaResultado(
                              'Membresias REMOVIDO (no activas)',
                              resultado['membresias_removidas'] ?? 0,
                            ),

                            const SizedBox(height: 12),

                            Text(
                              apto
                                  ? 'Esta revisión no sustituye '
                                        'las comprobaciones del servidor '
                                        'al momento de eliminar.'
                                  : 'Existen dependencias '
                                        'que deben resolverse '
                                        'antes de la eliminación.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: esquema.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // --------------------------------
                    // VOLVER AL PERFIL
                    // --------------------------------
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _eliminandoCuenta
                            ? null
                            : () {
                                Navigator.of(context).pop();
                              },
                        child: const Text('Volver a mi perfil'),
                      ),
                    ),

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
