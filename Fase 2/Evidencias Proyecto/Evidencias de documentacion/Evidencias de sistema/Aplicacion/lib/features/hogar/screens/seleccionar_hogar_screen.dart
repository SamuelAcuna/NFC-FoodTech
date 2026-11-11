import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nfc_foodtech_app/features/hogar/screens/hogar_form_screen.dart';
import 'package:nfc_foodtech_app/features/hogar/screens/miembros_hogar_screen.dart';
import 'package:nfc_foodtech_app/features/hogar/screens/invitaciones_hogar_screen.dart';

// ======================================================
// NFC-FOODTECH
// M14 - SELECCIÓN Y GESTIÓN DE HOGARES
// ======================================================

class SeleccionarHogarScreen extends StatefulWidget {
  const SeleccionarHogarScreen({super.key});

  @override
  State<SeleccionarHogarScreen> createState() => _SeleccionarHogarScreenState();
}

class _SeleccionarHogarScreenState extends State<SeleccionarHogarScreen>
    with WidgetsBindingObserver {
  static const Color verde = Color(0xFF236B4A);

  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _hogares = [];

  bool _cargando = true;
  bool _abriendoPantalla = false;

  String? _error;
  int _revisionCarga = 0;
  String? _usuarioId;
  late final StreamSubscription<AuthState> _authSubscription;

  // ======================================================
  // INICIALIZACIÓN
  // ======================================================

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _usuarioId = _supabase.auth.currentUser?.id;
    _authSubscription = _supabase.auth.onAuthStateChange.listen((_) {
      if (!mounted) return;
      final usuarioId = _supabase.auth.currentUser?.id;
      if (_usuarioId != usuarioId) {
        _usuarioId = usuarioId;
        _cargarHogares();
      }
    });
    _cargarHogares();
  }

  @override
  void dispose() {
    _revisionCarga++;
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _cargarHogares();
  }

  // ======================================================
  // M14 - CARGAR HOGARES DEL USUARIO
  // ======================================================

  Future<void> _cargarHogares() async {
    if (!mounted) return;
    final revision = ++_revisionCarga;
    final usuarioId = _supabase.auth.currentUser?.id;
    bool vigente() =>
        mounted &&
        revision == _revisionCarga &&
        _supabase.auth.currentUser?.id == usuarioId;

    setState(() {
      _cargando = true;
      _error = null;
      _hogares = [];
    });
    try {
      if (usuarioId == null)
        throw StateError('Debes iniciar sesión nuevamente.');
      final data = await _supabase
          .rpc('m14_listar_hogares')
          .timeout(const Duration(seconds: 15));
      if (!vigente()) return;
      if (data is! List)
        throw StateError('La respuesta del hogar no es válida.');
      if (data.length > 1) {
        throw StateError(
          'Se encontró más de un hogar activo. Contacta a soporte.',
        );
      }
      final hogares = data
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (hogares.isNotEmpty &&
          (hogares.single['id'] is! String ||
              (hogares.single['id'] as String).trim().isEmpty)) {
        throw StateError('No se pudo identificar tu hogar.');
      }
      setState(() => _hogares = hogares);
    } catch (error) {
      if (vigente()) {
        setState(() {
          _error = error is StateError
              ? error.message.toString()
              : 'No se pudo consultar tu hogar. Reintenta.';
        });
      }
    } finally {
      if (vigente()) setState(() => _cargando = false);
    }
  }

  // ======================================================
  // M15 - CREAR O EDITAR HOGAR
  // ======================================================

  Future<void> _abrirFormulario({Map<String, dynamic>? hogar}) async {
    if (_abriendoPantalla ||
        _cargando ||
        _error != null ||
        (hogar == null && _hogares.isNotEmpty))
      return;

    setState(() {
      _abriendoPantalla = true;
    });

    try {
      final guardado = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => HogarFormScreen(hogar: hogar)),
      );

      if (!mounted) return;

      await _cargarHogares();
      if (!mounted) return;

      if (guardado == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hogar == null
                  ? 'Hogar creado correctamente.'
                  : 'Hogar actualizado correctamente.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _abriendoPantalla = false;
        });
      }
    }
  }

  // ======================================================
  // M16 - ABRIR MIEMBROS DEL HOGAR
  // ======================================================

  Future<void> _abrirMiembros(Map<String, dynamic> hogar) async {
    if (_abriendoPantalla || _cargando || _error != null) return;

    setState(() {
      _abriendoPantalla = true;
    });

    try {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => MiembrosHogarScreen(hogar: hogar)),
      );

      if (!mounted) return;

      // Actualizar roles o membresías después
      // de cualquier operación de M16.
      await _cargarHogares();
    } finally {
      if (mounted) {
        setState(() {
          _abriendoPantalla = false;
        });
      }
    }
  }

  // ======================================================
  // M17 - GENERAR INVITACIÓN
  // ======================================================

  Future<void> _abrirInvitaciones(Map<String, dynamic> hogar) async {
    if (_abriendoPantalla || _cargando || _error != null) return;

    setState(() {
      _abriendoPantalla = true;
    });

    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => InvitacionesHogarScreen(hogar: hogar),
        ),
      );

      if (!mounted) return;

      await _cargarHogares();
    } finally {
      if (mounted) {
        setState(() {
          _abriendoPantalla = false;
        });
      }
    }
  }

  // ======================================================
  // M17 - UNIRSE A UN HOGAR
  // ======================================================

  Future<void> _unirseAHogar() async {
    if (_abriendoPantalla || _cargando || _error != null || _hogares.isNotEmpty)
      return;

    setState(() {
      _abriendoPantalla = true;
    });

    try {
      final incorporado = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const InvitacionesHogarScreen()),
      );

      if (!mounted) return;

      await _cargarHogares();
      if (!mounted) return;

      if (incorporado == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Te incorporaste al hogar correctamente.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _abriendoPantalla = false;
        });
      }
    }
  }

  // ======================================================
  // TARJETA DE UN HOGAR
  // ======================================================

  Widget _tarjetaHogar(Map<String, dynamic> hogar) {
    final esquema = Theme.of(context).colorScheme;
    final oscuro = Theme.of(context).brightness == Brightness.dark;

    final nombre = hogar['nombre']?.toString() ?? 'Hogar';

    final rol = hogar['rol']?.toString() ?? 'MIEMBRO';

    final esAdmin = rol == 'ADMIN';

    final adultos = hogar['adultos'];
    final menores = hogar['menores'];

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: esquema.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: esquema.outlineVariant),
      ),

      child: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            // ========================================
            // INFORMACIÓN PRINCIPAL DEL HOGAR
            // ========================================

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: const Color(0xFFE1F1E6),
                  child: const Icon(
                    Icons.home_outlined,
                    color: verde,
                    size: 27,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        nombre,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: esquema.onSurface,
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        esAdmin ? 'Administrador' : 'Miembro',
                        style: TextStyle(
                          fontSize: 13,
                          color: esquema.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                if (esAdmin)
                  Icon(
                    Icons.admin_panel_settings_outlined,
                    color: oscuro ? esquema.primary : verde,
                  ),
              ],
            ),

            // ========================================
            // INFORMACIÓN ADICIONAL
            // ========================================
            if (adultos != null || menores != null) ...[
              const SizedBox(height: 14),

              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  if (adultos != null)
                    Text(
                      'Adultos: $adultos',
                      style: TextStyle(
                        fontSize: 13,
                        color: esquema.onSurfaceVariant,
                      ),
                    ),

                  if (menores != null)
                    Text(
                      'Menores: $menores',
                      style: TextStyle(
                        fontSize: 13,
                        color: esquema.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],

            const SizedBox(height: 16),

            Divider(color: esquema.outlineVariant),

            const SizedBox(height: 10),

            // ========================================
            // M15, M16 Y M17 - ACCIONES
            //
            // Wrap evita problemas de desbordamiento
            // en dispositivos con pantalla pequeña.
            // ========================================
            Wrap(
              spacing: 8,
              runSpacing: 8,

              children: [
                // M16 - VER MIEMBROS
                // ADMIN y MIEMBRO

                OutlinedButton.icon(
                  onPressed: _abriendoPantalla
                      ? null
                      : () => _abrirMiembros(hogar),

                  icon: const Icon(Icons.groups_outlined, size: 19),

                  label: const Text('Miembros'),
                ),

                // M17 - INVITAR
                // Solo ADMIN
                if (esAdmin)
                  OutlinedButton.icon(
                    onPressed: _abriendoPantalla
                        ? null
                        : () => _abrirInvitaciones(hogar),

                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 19),

                    label: const Text('Invitar'),
                  ),

                // M15 - EDITAR
                // Solo ADMIN
                if (esAdmin)
                  OutlinedButton.icon(
                    onPressed: _abriendoPantalla
                        ? null
                        : () => _abrirFormulario(hogar: hogar),

                    icon: const Icon(Icons.edit_outlined, size: 19),

                    label: const Text('Editar'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ======================================================
  // PANTALLA PRINCIPAL
  // ======================================================

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final oscuro = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi hogar'),

        actions: [
          // M17 - UNIRSE MEDIANTE CÓDIGO
          if (!_cargando && _error == null && _hogares.isEmpty)
            IconButton(
              tooltip: 'Unirse a un hogar',
              onPressed: _abriendoPantalla ? null : _unirseAHogar,

              icon: const Icon(Icons.group_add_outlined),
            ),
        ],
      ),

      // M15 - CREAR HOGAR
      floatingActionButton: !_cargando && _error == null && _hogares.isEmpty
          ? FloatingActionButton.extended(
              backgroundColor: verde,
              foregroundColor: Colors.white,

              onPressed: _abriendoPantalla ? null : () => _abrirFormulario(),

              icon: const Icon(Icons.add),

              label: const Text('Crear hogar'),
            )
          : null,

      body: RefreshIndicator(
        onRefresh: _cargarHogares,

        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            // ========================================
            // ERROR DE CARGA
            // ========================================
            : _error != null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),

                children: [
                  const SizedBox(height: 90),

                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),

                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: esquema.error),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Center(
                    child: TextButton.icon(
                      onPressed: _cargarHogares,

                      icon: const Icon(Icons.refresh),

                      label: const Text('Reintentar'),
                    ),
                  ),
                ],
              )
            // ========================================
            // SIN HOGARES
            // ========================================
            : _hogares.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),

                children: [
                  const SizedBox(height: 100),

                  Icon(
                    Icons.home_outlined,
                    size: 60,
                    color: oscuro ? esquema.primary : verde,
                  ),

                  const SizedBox(height: 16),

                  const Center(
                    child: Text(
                      'Todavía no perteneces '
                      'a ningún hogar.',
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),

                      child: Text(
                        'Puedes crear un hogar '
                        'o unirte con un código '
                        'de invitación.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: esquema.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              )
            // ========================================
            // LISTADO DE HOGARES
            // ========================================
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),

                padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),

                itemCount: _hogares.length,

                itemBuilder: (context, index) {
                  final hogar = _hogares[index];

                  return _tarjetaHogar(hogar);
                },
              ),
      ),
    );
  }
}
