
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MiembrosHogarScreen extends StatefulWidget {
  final Map<String, dynamic> hogar;

  const MiembrosHogarScreen({
    super.key,
    required this.hogar,
  });

  @override
  State<MiembrosHogarScreen> createState() =>
      _MiembrosHogarScreenState();
}

class _MiembrosHogarScreenState
    extends State<MiembrosHogarScreen> {
  static const Color verde = Color(0xFF236B4A);

  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _miembros = [];

  bool _cargando = true;
  bool _procesando = false;
  String? _error;

  String get _hogarId => widget.hogar['id'].toString();

  String get _nombreHogar =>
      widget.hogar['nombre']?.toString() ?? 'Hogar';

  String? get _usuarioId =>
      _supabase.auth.currentUser?.id;

  Map<String, dynamic>? get _miembroActual {
    for (final miembro in _miembros) {
      if (miembro['perfil_id'] == _usuarioId) {
        return miembro;
      }
    }
    return null;
  }

  bool get _soyAdmin =>
      _miembroActual?['rol'] == 'ADMIN';

  bool get _soyCreador =>
      _miembroActual?['es_creador'] == true;

  @override
  void initState() {
    super.initState();
    _cargarMiembros();
  }

  Future<void> _cargarMiembros() async {
    if (!mounted) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await _supabase.rpc(
        'm16_listar_miembros',
        params: {
          'p_hogar_id': _hogarId,
        },
      );

      if (!mounted) return;

      if (respuesta is! List) {
        throw StateError('Respuesta de miembros inválida');
      }

      setState(() {
        _miembros = respuesta
            .map(
              (elemento) =>
                  Map<String, dynamic>.from(elemento as Map),
            )
            .toList();
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.message;
      });
    } catch (error) {
      debugPrint('M16: error cargando miembros: $error');

      if (!mounted) return;

      setState(() {
        _error = 'No se pudieron cargar los miembros.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  String _nombreIntegrante(Map<String, dynamic> miembro) {
    final nombre =
        miembro['nombre']?.toString().trim() ?? '';

    final apellido =
        miembro['apellido']?.toString().trim() ?? '';

    final completo = '$nombre $apellido'.trim();

    return completo.isNotEmpty
        ? completo
        : 'Integrante del hogar';
  }

  String _nombreAccion(String accion) {
    switch (accion) {
      case 'PROMOVER':
        return 'Asignar rol de administrador';
      case 'DEGRADAR':
        return 'Cambiar rol a miembro';
      case 'REMOVER':
        return 'Remover del hogar';
      case 'TRANSFERIR':
        return 'Transferir administración';
      case 'ABANDONAR':
        return 'Abandonar hogar';
      default:
        return accion;
    }
  }

  Future<bool> _confirmarAccion(
    String accion,
    String integrante,
  ) async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (contexto) {
        return AlertDialog(
          title: Text(_nombreAccion(accion)),
          content: Text(
            accion == 'ABANDONAR'
                ? '¿Seguro que deseas abandonar '
                    'el hogar "$_nombreHogar"?'
                : '¿Confirmas esta acción sobre '
                    '"$integrante"?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(contexto).pop(false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(contexto).pop(true);
              },
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );

    return resultado == true;
  }

  Future<void> _ejecutarAccion(
    String accion, {
    String? perfilId,
    String? nombreIntegrante,
  }) async {
    if (_procesando) return;

    final confirmado = await _confirmarAccion(
      accion,
      nombreIntegrante ?? 'este integrante',
    );

    if (!mounted || !confirmado) return;

    setState(() {
      _procesando = true;
      _error = null;
    });

    try {
      await _supabase.rpc(
        'm16_gestionar_miembro',
        params: {
          'p_hogar_id': _hogarId,
          'p_accion': accion,
          'p_perfil_id': perfilId,
        },
      );

      if (!mounted) return;

      if (accion == 'ABANDONAR') {
        Navigator.of(context).pop(true);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_nombreAccion(accion)}: operación realizada.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Si transferimos, los roles cambian.
      // Actualizamos desde Supabase.
      await _cargarMiembros();
    } on PostgrestException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      debugPrint('M16: error de operación: $error');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo completar la operación.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _procesando = false;
        });
      }
    }
  }

  Widget _tarjetaMiembro(
    Map<String, dynamic> miembro,
  ) {
    final esquema = Theme.of(context).colorScheme;

    final perfilId =
        miembro['perfil_id']?.toString() ?? '';

    final nombre = _nombreIntegrante(miembro);
    final rol = miembro['rol']?.toString() ?? 'MIEMBRO';

    final esAdmin = rol == 'ADMIN';
    final esPropio = perfilId == _usuarioId;
    final esCreador = miembro['es_creador'] == true;

    final puedeAdministrar =
        _soyAdmin && !esPropio && !_procesando;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 8,
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFE1F1E6),
            child: Icon(
              esAdmin
                  ? Icons.admin_panel_settings_outlined
                  : Icons.person_outline,
              color: verde,
            ),
          ),

          title: Text(
            esPropio ? '$nombre (Tú)' : nombre,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),

          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),

              Text(
                esAdmin
                    ? 'Administrador'
                    : 'Miembro',
              ),

              if (esCreador)
                Text(
                  'Responsable del hogar',
                  style: TextStyle(
                    fontSize: 12,
                    color: esquema.onSurfaceVariant,
                  ),
                ),
            ],
          ),

          trailing: puedeAdministrar
              ? PopupMenuButton<String>(
                  tooltip: 'Administrar integrante',
                  onSelected: (accion) {
                    _ejecutarAccion(
                      accion,
                      perfilId: perfilId,
                      nombreIntegrante: nombre,
                    );
                  },
                  itemBuilder: (_) => [
                    if (!esAdmin)
                      const PopupMenuItem(
                        value: 'PROMOVER',
                        child: Text('Hacer administrador'),
                      ),

                    if (esAdmin && !esCreador)
                      const PopupMenuItem(
                        value: 'DEGRADAR',
                        child: Text('Cambiar a miembro'),
                      ),

                    const PopupMenuItem(
                      value: 'TRANSFERIR',
                      child: Text(
                        'Transferir administración',
                      ),
                    ),

                    if (!esCreador)
                      const PopupMenuItem(
                        value: 'REMOVER',
                        child: Text('Remover del hogar'),
                      ),
                  ],
                )
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Miembros del hogar'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _procesando
                ? null
                : _cargarMiembros,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _cargarMiembros,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargarMiembros,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        _nombreHogar,
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                          color: esquema.onSurface,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Text(
                        '${_miembros.length} integrante(s) activos',
                        style: TextStyle(
                          color: esquema.onSurfaceVariant,
                        ),
                      ),

                      const SizedBox(height: 18),

                      ..._miembros.map(_tarjetaMiembro),

                      const SizedBox(height: 24),

                      if (_soyCreador)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: 12,
                          ),
                          child: Text(
                            'Para abandonar este hogar, '
                            'primero transfiere la '
                            'administración a otro integrante.',
                            style: TextStyle(
                              fontSize: 13,
                              color: esquema.onSurfaceVariant,
                            ),
                          ),
                        ),

                      if (!_soyCreador)
                        OutlinedButton.icon(
                          onPressed: _procesando
                              ? null
                              : () => _ejecutarAccion(
                                    'ABANDONAR',
                                  ),
                          icon: const Icon(
                            Icons.exit_to_app,
                          ),
                          label: const Text(
                            'Abandonar hogar',
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
