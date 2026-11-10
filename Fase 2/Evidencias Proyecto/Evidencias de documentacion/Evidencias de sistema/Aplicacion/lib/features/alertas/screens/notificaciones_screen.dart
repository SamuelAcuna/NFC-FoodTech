import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nfc_foodtech_app/features/alertas/screens/preferencias_notificaciones_screen.dart';
import 'package:nfc_foodtech_app/shared/models/texto_notificacion.dart';

class NotificacionesScreen extends StatefulWidget {
  const NotificacionesScreen({super.key});

  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesScreen> {
  static const Color verde = Color(0xFF236B4A);
  static const Duration tiempoEspera = Duration(seconds: 8);

  bool _cargando = true;
  String? _error;

  List<Map<String, dynamic>> _notificaciones = [];
  Map<int, Map<String, dynamic>> _plantillas = {};

  final Set<String> _marcandoLeidas = {};

  int _versionCarga = 0;

  @override
  void initState() {
    super.initState();
    _cargarNotificaciones();
  }

  // --------------------------------------------------
  // CARGAR NOTIFICACIONES DESDE SUPABASE
  // --------------------------------------------------

  Future<void> _cargarNotificaciones() async {
    final usuario = Supabase.instance.client.auth.currentUser;
    final versionActual = ++_versionCarga;

    if (!mounted) return;

    if (usuario == null) {
      setState(() {
        _cargando = false;
        _error = 'Debes iniciar sesión.';
        _notificaciones = [];
        _plantillas = {};
      });
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
      _notificaciones = [];
      _plantillas = {};
    });

    // Sincronizar las notificaciones del usuario:
    // cancelar avisos obsoletos y generar los nuevos.
    try {
      final resumen = await Supabase.instance.client
          .rpc('m28_sincronizar_alertas')
          .timeout(tiempoEspera);

      debugPrint('M28: resultado de sincronización: $resumen');
    } on TimeoutException {
      debugPrint('M28: tiempo de espera agotado al sincronizar alertas.');
    } on PostgrestException catch (error) {
      debugPrint('M28 ERROR: ${error.message}');
    } catch (error) {
      debugPrint('M28 ERROR inesperado: $error');
    }

    if (!mounted || versionActual != _versionCarga) {
      return;
    }

    if (Supabase.instance.client.auth.currentUser?.id != usuario.id) {
      return;
    }

    try {
      // Obtener las notificaciones del usuario autenticado.
      // Las canceladas no se muestran.
      final resultado = await Supabase.instance.client
          .from('notificacion')
          .select(
            'id, perfil_id, plantilla_id, despensa_item_id, datos, '
            'estado, programada_para, leida_en, created_at',
          )
          .eq('perfil_id', usuario.id)
          .neq('estado', 'CANCELADA')
          .order('created_at', ascending: false)
          .limit(30)
          .timeout(tiempoEspera);

      final notificaciones = List<Map<String, dynamic>>.from(resultado);

      // --------------------------------------------------
      // IDENTIFICAR EL HOGAR DE CADA NOTIFICACIÓN
      // --------------------------------------------------

      // Esta sección consulta los hogares de forma agrupada.
      // No se necesitan consultas individuales por notificación.
      //
      // Si falla la consulta de hogares, las notificaciones
      // siguen mostrándose normalmente.

      try {
        final idsItems = notificaciones
            .map((n) => n['despensa_item_id']?.toString())
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();

        if (idsItems.isNotEmpty) {
          // Buscar los hogares asociados a los productos.
          final resultadoItems = await Supabase.instance.client
              .from('despensa_item')
              .select('id, hogar_id')
              .inFilter('id', idsItems)
              .timeout(tiempoEspera);

          final Map<String, String> hogarPorItem = {};

          for (final item in resultadoItems) {
            final itemId = item['id']?.toString();
            final hogarId = item['hogar_id']?.toString();

            if (itemId != null && hogarId != null) {
              hogarPorItem[itemId] = hogarId;
            }
          }

          // Reunir los IDs de hogares sin repetirlos.
          final idsHogares = hogarPorItem.values.toSet().toList();

          final Map<String, String> nombresHogares = {};

          if (idsHogares.isNotEmpty) {
            // Obtener los nombres reales de los hogares.
            final resultadoHogares = await Supabase.instance.client
                .from('hogar')
                .select('id, nombre')
                .inFilter('id', idsHogares)
                .timeout(tiempoEspera);

            for (final hogar in resultadoHogares) {
              final id = hogar['id']?.toString();
              final nombre = hogar['nombre']?.toString();

              if (id != null && nombre != null && nombre.isNotEmpty) {
                nombresHogares[id] = nombre;
              }
            }
          }

          // Asociar el nombre del hogar a cada notificación.
          for (final notificacion in notificaciones) {
            final itemId = notificacion['despensa_item_id']?.toString();

            final hogarId = hogarPorItem[itemId];
            final nombre = nombresHogares[hogarId];

            if (nombre != null) {
              notificacion['nombre_hogar'] = nombre;
            }
          }
        }
      } on TimeoutException {
        debugPrint('M28: tiempo de espera al consultar nombres de hogares.');
      } catch (error) {
        debugPrint(
          'M28: no se pudieron obtener los nombres de hogares: $error',
        );
      }

      // --------------------------------------------------
      // OBTENER LAS PLANTILLAS DE NOTIFICACIONES
      // --------------------------------------------------

      final idsPlantillas = notificaciones
          .map((fila) => fila['plantilla_id'])
          .whereType<num>()
          .map((id) => id.toInt())
          .toSet()
          .toList();

      final Map<int, Map<String, dynamic>> plantillas = {};

      if (idsPlantillas.isNotEmpty) {
        final resultadoPlantillas = await Supabase.instance.client
            .from('plantilla_notificacion')
            .select(
              'id, codigo, categoria, '
              'titulo_tpl, cuerpo_tpl',
            )
            .inFilter('id', idsPlantillas)
            .timeout(tiempoEspera);

        for (final plantilla in resultadoPlantillas) {
          final id = int.tryParse(plantilla['id'].toString());

          if (id != null) {
            plantillas[id] = Map<String, dynamic>.from(plantilla);
          }
        }
      }

      // Evitar actualizar una pantalla desmontada
      // o una carga que ya fue reemplazada.
      if (!mounted || versionActual != _versionCarga) {
        return;
      }

      if (Supabase.instance.client.auth.currentUser?.id != usuario.id) {
        setState(() {
          _cargando = false;
          _notificaciones = [];
          _plantillas = {};
          _error = 'La sesión cambió. Vuelve a abrir esta pantalla.';
        });
        return;
      }

      setState(() {
        _notificaciones = notificaciones;
        _plantillas = plantillas;
        _cargando = false;
        _error = null;
      });
    } on TimeoutException {
      if (!mounted || versionActual != _versionCarga) {
        return;
      }

      setState(() {
        _cargando = false;
        _error =
            'No pudimos conectar con el servidor. '
            'Comprueba tu conexión a internet '
            'e inténtalo nuevamente.';
      });
    } catch (error) {
      debugPrint('Error al consultar notificaciones: $error');

      if (!mounted || versionActual != _versionCarga) {
        return;
      }

      setState(() {
        _cargando = false;
        _error =
            'No se pudieron cargar las notificaciones. '
            'Inténtalo nuevamente.';
      });
    }
  }

  // --------------------------------------------------
  // MARCAR UNA NOTIFICACIÓN COMO LEÍDA
  // --------------------------------------------------

  Future<void> _marcarComoLeida(Map<String, dynamic> notificacion) async {
    final id = notificacion['id']?.toString();
    final usuario = Supabase.instance.client.auth.currentUser;

    if (id == null || id.isEmpty) {
      _mostrarMensaje('No se pudo identificar la notificación.');
      return;
    }

    if (usuario == null) {
      _mostrarMensaje('Debes iniciar sesión.');
      return;
    }

    if (_marcandoLeidas.contains(id)) return;

    if (notificacion['leida_en'] != null) return;

    setState(() {
      _marcandoLeidas.add(id);
    });

    try {
      final fechaLectura = DateTime.now().toUtc().toIso8601String();

      final resultado = await Supabase.instance.client
          .from('notificacion')
          .update({'estado': 'LEIDA', 'leida_en': fechaLectura})
          .eq('id', id)
          .eq('perfil_id', usuario.id)
          .isFilter('leida_en', null)
          .select('id, estado, leida_en')
          .maybeSingle()
          .timeout(tiempoEspera);

      if (!mounted) return;

      if (Supabase.instance.client.auth.currentUser?.id != usuario.id) {
        _mostrarMensaje('La sesión cambió. Actualiza la pantalla.');
        return;
      }

      if (resultado == null) {
        _mostrarMensaje(
          'No se pudo confirmar el cambio. '
          'Actualiza las notificaciones para verificar su estado.',
        );
        return;
      }

      final fechaConfirmada = resultado['leida_en'];

      if (fechaConfirmada == null) {
        _mostrarMensaje(
          'Supabase no confirmó la fecha de lectura. '
          'Actualiza la pantalla.',
        );
        return;
      }

      setState(() {
        _notificaciones = _notificaciones.map((fila) {
          if (fila['id']?.toString() != id) {
            return fila;
          }

          return {
            ...fila,
            'estado': resultado['estado'],
            'leida_en': fechaConfirmada,
          };
        }).toList();
      });

      _mostrarMensaje('Notificación marcada como leída.', exito: true);
    } on TimeoutException {
      _mostrarMensaje(
        'El servidor no confirmó la operación. '
        'Actualiza las notificaciones antes de intentarlo nuevamente.',
      );
    } catch (error) {
      debugPrint('Error al marcar notificación como leída: $error');

      _mostrarMensaje(
        'No se pudo marcar la notificación como leída. '
        'Verifica tu conexión e inténtalo nuevamente.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _marcandoLeidas.remove(id);
        });
      }
    }
  }

  // --------------------------------------------------
  // MOSTRAR MENSAJES
  // --------------------------------------------------

  void _mostrarMensaje(String mensaje, {bool exito = false}) {
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
          behavior: SnackBarBehavior.floating,
          backgroundColor: exito ? verde : const Color(0xFFB83D3D),
        ),
      );
  }

  // --------------------------------------------------
  // NAVEGACIÓN
  // --------------------------------------------------

  void _abrirPreferencias() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PreferenciasNotificacionesScreen(),
      ),
    );
  }

  // --------------------------------------------------
  // FORMATEAR FECHAS
  // --------------------------------------------------

  String _formatearFecha(dynamic valor) {
    if (valor == null) {
      return 'Sin fecha';
    }

    final fecha = DateTime.tryParse(valor.toString());

    if (fecha == null) {
      return 'Fecha no disponible';
    }

    final local = fecha.toLocal();

    String dosDigitos(int numero) {
      return numero.toString().padLeft(2, '0');
    }

    return '${dosDigitos(local.day)}/'
        '${dosDigitos(local.month)}/'
        '${local.year} · '
        '${dosDigitos(local.hour)}:'
        '${dosDigitos(local.minute)}';
  }

  // --------------------------------------------------
  // COMPLETAR TEXTOS DE PLANTILLAS
  // --------------------------------------------------

  Map<String, dynamic>? _obtenerPlantilla(Map<String, dynamic> notificacion) {
    final id = int.tryParse(notificacion['plantilla_id'].toString());

    if (id == null) return null;

    return _plantillas[id];
  }

  String _obtenerTitulo(Map<String, dynamic> notificacion) {
    final plantilla = _obtenerPlantilla(notificacion);

    final titulo = plantilla?['titulo_tpl']?.toString() ?? '';

    if (titulo.isEmpty) {
      return 'Notificación';
    }

    return completarTextoNotificacion(titulo, notificacion['datos']);
  }

  String _obtenerMensaje(Map<String, dynamic> notificacion) {
    final plantilla = _obtenerPlantilla(notificacion);

    final mensaje = plantilla?['cuerpo_tpl']?.toString() ?? '';

    if (mensaje.isEmpty) {
      return 'No hay un mensaje disponible '
          'para esta notificación.';
    }

    return completarTextoNotificacion(mensaje, notificacion['datos']);
  }

  // --------------------------------------------------
  // TARJETA DE NOTIFICACIÓN
  // --------------------------------------------------

  Widget _construirTarjeta(Map<String, dynamic> notificacion) {
    final esquema = Theme.of(context).colorScheme;

    final oscuro = Theme.of(context).brightness == Brightness.dark;

    final leida = notificacion['leida_en'] != null;

    final estado = notificacion['estado']?.toString() ?? 'SIN ESTADO';

    final titulo = _obtenerTitulo(notificacion);

    final mensaje = _obtenerMensaje(notificacion);

    // NUEVO: nombre real del hogar al que pertenece el alimento.
    final nombreHogar = notificacion['nombre_hogar']?.toString();

    final id = notificacion['id']?.toString() ?? '';

    final marcando = _marcandoLeidas.contains(id);

    return Card(
      color: esquema.surface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: esquema.outlineVariant),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        leading: CircleAvatar(
          backgroundColor: oscuro
              ? esquema.surfaceContainerHighest
              : const Color(0xFFE1F1E6),
          child: Icon(
            leida
                ? Icons.notifications_none_rounded
                : Icons.notifications_active_outlined,
            color: oscuro ? esquema.primary : verde,
          ),
        ),
        title: Text(
          titulo,
          style: TextStyle(
            fontSize: 15,
            fontWeight: leida ? FontWeight.w500 : FontWeight.bold,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Fecha de creación de la notificación.
              Text(
                _formatearFecha(notificacion['created_at']),
                style: TextStyle(fontSize: 12, color: esquema.onSurfaceVariant),
              ),

              // NUEVO: identificar el hogar.
              if (nombreHogar != null && nombreHogar.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  'Hogar: $nombreHogar',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: esquema.onSurfaceVariant,
                  ),
                ),
              ],

              const SizedBox(height: 5),

              // Estado de lectura.
              Text(
                leida ? 'Leída' : 'No leída',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: leida
                      ? esquema.onSurfaceVariant
                      : (oscuro ? esquema.primary : verde),
                ),
              ),
            ],
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  mensaje,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),

                const SizedBox(height: 16),

                Divider(color: esquema.outlineVariant),

                const SizedBox(height: 9),

                Text(
                  'Estado: '
                  '${estado.replaceAll('_', ' ')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: esquema.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  'Programada para: '
                  '${_formatearFecha(notificacion['programada_para'])}',
                  style: TextStyle(
                    fontSize: 12,
                    color: esquema.onSurfaceVariant,
                  ),
                ),

                if (leida) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Leída el: '
                    '${_formatearFecha(notificacion['leida_en'])}',
                    style: TextStyle(
                      fontSize: 12,
                      color: esquema.onSurfaceVariant,
                    ),
                  ),
                ],

                // Botón para marcar como leída.
                if (!leida) ...[
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: marcando
                          ? null
                          : () => _marcarComoLeida(notificacion),
                      icon: marcando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.done_all_rounded),
                      label: Text(
                        marcando ? 'Guardando...' : 'Marcar como leída',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: verde,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------
  // ESTADO VACÍO
  // --------------------------------------------------

  Widget _construirEstadoVacio() {
    final esquema = Theme.of(context).colorScheme;

    final oscuro = Theme.of(context).brightness == Brightness.dark;

    final colorPrincipal = oscuro ? esquema.onSurface : verde;

    return Column(
      children: [
        const SizedBox(height: 45),

        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            color: oscuro
                ? esquema.surfaceContainerHighest
                : const Color(0xFFE1F1E6),
            borderRadius: BorderRadius.circular(32),
          ),
          child: Icon(
            Icons.notifications_none_rounded,
            size: 58,
            color: colorPrincipal,
          ),
        ),

        const SizedBox(height: 25),

        Text(
          'Todavía no tienes notificaciones',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: colorPrincipal,
          ),
        ),

        const SizedBox(height: 14),

        Text(
          'Cuando se generen notificaciones '
          'para tu cuenta, podrás consultarlas aquí.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            color: esquema.onSurfaceVariant,
          ),
        ),

        const SizedBox(height: 24),

        Card(
          color: esquema.surface,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Cuando tus alimentos estén próximos '
                    'a su fecha de caducidad y tengas '
                    'las alertas activadas, '
                    'aparecerán aquí.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
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

    final oscuro = tema.brightness == Brightness.dark;

    final colorPrincipal = oscuro ? esquema.onSurface : verde;

    final noLeidas = _notificaciones.where((n) => n['leida_en'] == null).length;

    return Scaffold(
      backgroundColor: tema.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Notificaciones'),
        backgroundColor: tema.scaffoldBackgroundColor,
        foregroundColor: colorPrincipal,
        actions: [
          IconButton(
            tooltip: 'Actualizar notificaciones',
            onPressed: _cargando ? null : _cargarNotificaciones,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Preferencias de notificaciones',
            onPressed: _abrirPreferencias,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _cargarNotificaciones,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_cargando)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 80),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 55),
                          child: Column(
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                size: 56,
                                color: esquema.error,
                              ),

                              const SizedBox(height: 18),

                              Text(_error!, textAlign: TextAlign.center),

                              const SizedBox(height: 16),

                              FilledButton.icon(
                                onPressed: _cargarNotificaciones,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Reintentar'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: verde,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (_notificaciones.isEmpty)
                        _construirEstadoVacio()
                      else ...[
                        Text(
                          'Centro de notificaciones',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                            color: colorPrincipal,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          '${_notificaciones.length} recientes · '
                          '$noLeidas no leídas',
                          style: TextStyle(
                            fontSize: 14,
                            color: esquema.onSurfaceVariant,
                          ),
                        ),

                        const SizedBox(height: 22),

                        for (final notificacion in _notificaciones)
                          _construirTarjeta(notificacion),

                        if (_notificaciones.length == 30)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              'Se muestran las 30 notificaciones '
                              'más recientes.',
                              style: TextStyle(
                                fontSize: 12,
                                color: esquema.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],

                      const SizedBox(height: 28),

                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _abrirPreferencias,
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('Configurar preferencias'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: verde,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 22),

                      Center(
                        child: Text(
                          'NFC-FoodTech 🌱',
                          style: TextStyle(
                            fontSize: 13,
                            color: esquema.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
