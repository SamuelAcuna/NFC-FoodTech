import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nfc_foodtech_app/services/notificaciones_locales.dart';

class PreferenciasNotificacionesScreen extends StatefulWidget {
  const PreferenciasNotificacionesScreen({super.key});

  @override
  State<PreferenciasNotificacionesScreen> createState() =>
      _PreferenciasNotificacionesScreenState();
}

class _PreferenciasNotificacionesScreenState
    extends State<PreferenciasNotificacionesScreen>
    with WidgetsBindingObserver {
  static const Color verde = Color(0xFF236B4A);
  static const Duration _esperaServidor = Duration(seconds: 8);

  // Plantillas que ya existen en Supabase.
  static const int _idProximo = 2;
  static const int _idSuperada = 3;
  static const int _idRevision = 4;

  final SharedPreferencesAsync _preferencias = SharedPreferencesAsync();

  String? _usuarioId;
  String? _error;

  bool _cargando = true;
  bool _guardando = false;
  bool _pendienteSincronizacion = false;

  String? _avisoSincronizacion;

  bool _alertasCaducidad = true;
  bool _alertasFechaSuperada = true;
  bool _recordatoriosRevision = true;
  bool _silenciarTodas = false;

  int _diasAnticipacion = 3;

  TimeOfDay _horaPreferida = const TimeOfDay(hour: 9, minute: 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargarPreferencias();
    unawaited(NotificacionesLocales.instancia.comprobarPermiso());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(NotificacionesLocales.instancia.comprobarPermiso());
    }
  }

  // --------------------------------------------------
  // CLAVES LOCALES POR USUARIO
  // --------------------------------------------------

  String _clave(String nombre) {
    return 'nfc_foodtech_notif_${_usuarioId}_$nombre';
  }

  String _horaComoTexto(TimeOfDay hora) {
    final horas = hora.hour.toString().padLeft(2, '0');
    final minutos = hora.minute.toString().padLeft(2, '0');

    return '$horas:$minutos';
  }

  TimeOfDay? _interpretarHora(dynamic valor) {
    if (valor == null) return null;

    final partes = valor.toString().split(':');

    if (partes.length < 2) return null;

    final hora = int.tryParse(partes[0]);
    final minuto = int.tryParse(partes[1]);

    if (hora == null ||
        minuto == null ||
        hora < 0 ||
        hora > 23 ||
        minuto < 0 ||
        minuto > 59) {
      return null;
    }

    return TimeOfDay(hour: hora, minute: minuto);
  }

  // --------------------------------------------------
  // GUARDAR COPIA LOCAL
  // --------------------------------------------------

  Future<void> _guardarCacheLocal({required bool pendiente}) async {
    // Marcar como pendiente antes de guardar permite
    // detectar cambios que no se han sincronizado.

    await _preferencias.setBool(_clave('pendiente_sync'), pendiente);

    await _preferencias.setBool(_clave('caducidad'), _alertasCaducidad);

    await _preferencias.setBool(
      _clave('fecha_superada'),
      _alertasFechaSuperada,
    );

    await _preferencias.setBool(_clave('revision'), _recordatoriosRevision);

    await _preferencias.setBool(_clave('silencio'), _silenciarTodas);

    await _preferencias.setInt(_clave('dias'), _diasAnticipacion);

    await _preferencias.setString(
      _clave('hora'),
      _horaComoTexto(_horaPreferida),
    );
  }

  // --------------------------------------------------
  // CARGAR PREFERENCIAS LOCALES Y DE SUPABASE
  // --------------------------------------------------

  Future<void> _cargarPreferencias() async {
    try {
      final usuario = Supabase.instance.client.auth.currentUser;

      if (usuario == null) {
        throw StateError('No existe una sesión activa.');
      }

      _usuarioId = usuario.id;

      // Primero consultar preferencias locales.
      // Así mantenemos los ajustes guardados anteriormente.

      final caducidad = await _preferencias.getBool(_clave('caducidad'));

      final superada = await _preferencias.getBool(_clave('fecha_superada'));

      final revision = await _preferencias.getBool(_clave('revision'));

      final silencio = await _preferencias.getBool(_clave('silencio'));

      final dias = await _preferencias.getInt(_clave('dias'));

      final hora = await _preferencias.getString(_clave('hora'));

      final pendiente =
          await _preferencias.getBool(_clave('pendiente_sync')) ?? false;

      if (!mounted ||
          Supabase.instance.client.auth.currentUser?.id != usuario.id) {
        return;
      }

      setState(() {
        _alertasCaducidad = caducidad ?? true;
        _alertasFechaSuperada = superada ?? true;
        _recordatoriosRevision = revision ?? true;
        _silenciarTodas = silencio ?? false;

        _diasAnticipacion = [1, 2, 3, 5, 7].contains(dias) ? dias! : 3;

        _horaPreferida =
            _interpretarHora(hora) ?? const TimeOfDay(hour: 9, minute: 0);

        _pendienteSincronizacion = pendiente;
      });

      // Si hay cambios locales pendientes, no reemplazarlos
      // con información antigua del servidor.

      if (pendiente) {
        setState(() {
          _cargando = false;
          _error = null;

          _avisoSincronizacion =
              'Tienes cambios guardados solo en este dispositivo. '
              'Presiona Guardar preferencias con internet '
              'para sincronizarlos.';
        });

        return;
      }

      // --------------------------------------------------
      // CONSULTAR PREFERENCIAS DE SUPABASE
      // --------------------------------------------------

      try {
        final filas = await Supabase.instance.client
            .from('preferencia_notificacion')
            .select(
              'plantilla_id, habilitada, '
              'dias_anticipacion, hora_envio',
            )
            .eq('perfil_id', usuario.id)
            .inFilter('plantilla_id', [_idProximo, _idSuperada, _idRevision])
            .timeout(_esperaServidor);

        if (!mounted ||
            Supabase.instance.client.auth.currentUser?.id != usuario.id) {
          return;
        }

        final registros = <int, Map<String, dynamic>>{};

        for (final fila in filas) {
          final id = int.tryParse(fila['plantilla_id'].toString());

          if (id != null) {
            registros[id] = Map<String, dynamic>.from(fila);
          }
        }

        if (registros.isNotEmpty) {
          final proximo = registros[_idProximo];
          final superadaServidor = registros[_idSuperada];
          final revisionServidor = registros[_idRevision];

          final horaServidor =
              _interpretarHora(proximo?['hora_envio']) ??
              _interpretarHora(superadaServidor?['hora_envio']) ??
              _interpretarHora(revisionServidor?['hora_envio']);

          final diasServidor = proximo?['dias_anticipacion'];

          final diasNumero = diasServidor is num
              ? diasServidor.toInt()
              : int.tryParse(diasServidor?.toString() ?? '');

          setState(() {
            _alertasCaducidad =
                proximo?['habilitada'] as bool? ?? _alertasCaducidad;

            _alertasFechaSuperada =
                superadaServidor?['habilitada'] as bool? ??
                _alertasFechaSuperada;

            _recordatoriosRevision =
                revisionServidor?['habilitada'] as bool? ??
                _recordatoriosRevision;

            if ([1, 2, 3, 5, 7].contains(diasNumero)) {
              _diasAnticipacion = diasNumero!;
            }

            if (horaServidor != null) {
              _horaPreferida = horaServidor;
            }
          });

          // Actualizar copia local con los valores del servidor.

          await _guardarCacheLocal(pendiente: false);
        }

        if (!mounted) return;

        setState(() {
          _cargando = false;
          _error = null;

          _avisoSincronizacion = registros.isEmpty
              ? 'Aún no hay preferencias en Supabase '
                    'para esta cuenta. '
                    'Pulsa Guardar para registrarlas.'
              : null;
        });
      } on TimeoutException {
        if (!mounted) return;

        setState(() {
          _cargando = false;
          _error = null;

          _avisoSincronizacion =
              'Sin conexión con Supabase. '
              'Se muestran los ajustes guardados '
              'en este dispositivo.';
        });
      } catch (error) {
        debugPrint('Error al consultar preferencias: ${error.runtimeType}');

        if (!mounted) return;

        setState(() {
          _cargando = false;
          _error = null;

          _avisoSincronizacion =
              'No se pudo consultar Supabase. '
              'Se muestran los ajustes guardados '
              'en este dispositivo.';
        });
      }
    } catch (error) {
      debugPrint('Error al cargar preferencias locales: ${error.runtimeType}');

      if (!mounted) return;

      setState(() {
        _error = 'No se pudieron cargar las preferencias.';
        _cargando = false;
      });
    }
  }

  // --------------------------------------------------
  // SELECCIONAR HORA
  // --------------------------------------------------

  Future<void> _seleccionarHora() async {
    if (_guardando) return;

    final resultado = await showTimePicker(
      context: context,
      initialTime: _horaPreferida,
    );

    if (resultado == null || !mounted) return;

    setState(() {
      _horaPreferida = resultado;
    });
  }

  // --------------------------------------------------
  // GUARDAR PREFERENCIAS
  // --------------------------------------------------

  bool _diagnosticando = false;
  String _diagnostico =
      'Inspecciona antes y despues de guardar las preferencias.';

  Future<void> _diagnosticar(Future<String> Function() accion) async {
    if (!kDebugMode || _diagnosticando) return;
    setState(() => _diagnosticando = true);
    try {
      final resultado = await accion();
      if (mounted) setState(() => _diagnostico = resultado);
    } catch (e) {
      if (mounted)
        setState(() => _diagnostico = 'Error de diagnostico: ${e.runtimeType}');
    } finally {
      if (mounted) setState(() => _diagnosticando = false);
    }
  }

  Future<void> _guardarPreferencias() async {
    if (_guardando || _usuarioId == null) return;

    final usuario = Supabase.instance.client.auth.currentUser;

    if (usuario?.id != _usuarioId) {
      _mostrarMensaje(
        'La sesión cambió. '
        'Vuelve a abrir las preferencias.',
      );
      return;
    }

    setState(() {
      _guardando = true;
    });

    // --------------------------------------------------
    // 1. GUARDAR LOCALMENTE
    // --------------------------------------------------

    try {
      await _guardarCacheLocal(pendiente: true);
      unawaited(NotificacionesLocales.instancia.sincronizar());

      if (!mounted) return;

      setState(() {
        _pendienteSincronizacion = true;
      });
    } catch (error) {
      debugPrint('Error al guardar caché: ${error.runtimeType}');

      _mostrarMensaje(
        'No se pudieron guardar las preferencias '
        'en este dispositivo.',
      );

      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }

      return;
    }

    // --------------------------------------------------
    // 2. SINCRONIZAR CON SUPABASE
    // --------------------------------------------------

    try {
      if (Supabase.instance.client.auth.currentUser?.id != usuario!.id) {
        throw StateError('La sesión cambió antes del envío.');
      }

      final hora = '${_horaComoTexto(_horaPreferida)}:00';

      await Supabase.instance.client
          .from('preferencia_notificacion')
          .upsert([
            {
              'perfil_id': usuario.id,
              'plantilla_id': _idProximo,
              'habilitada': _alertasCaducidad,
              'dias_anticipacion': _diasAnticipacion,
              'hora_envio': hora,
            },
            {
              'perfil_id': usuario.id,
              'plantilla_id': _idSuperada,
              'habilitada': _alertasFechaSuperada,
              'dias_anticipacion': null,
              'hora_envio': hora,
            },
            {
              'perfil_id': usuario.id,
              'plantilla_id': _idRevision,
              'habilitada': _recordatoriosRevision,
              'dias_anticipacion': null,
              'hora_envio': hora,
            },
          ], onConflict: 'perfil_id,plantilla_id')
          .timeout(_esperaServidor);

      if (!mounted) return;

      await _preferencias.setBool(_clave('pendiente_sync'), false);

      if (!mounted) return;

      setState(() {
        _pendienteSincronizacion = false;
        _avisoSincronizacion = null;
      });

      _mostrarMensaje(
        'Preferencias guardadas en Supabase '
        'y en este dispositivo.',
        exito: true,
      );
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _avisoSincronizacion =
            'El servidor no confirmó el guardado. '
            'Tus cambios están en este dispositivo. '
            'Presiona Guardar con internet para sincronizarlos; '
            'la operación anterior pudo haberse aplicado.';
      });

      _mostrarMensaje(
        'Guardado localmente. '
        'Sincronización pendiente.',
      );
    } catch (error) {
      debugPrint('Error al sincronizar preferencias: ${error.runtimeType}');

      if (!mounted) return;

      setState(() {
        _avisoSincronizacion =
            'Se guardó en este dispositivo, '
            'pero Supabase aún no confirmó los cambios. '
            'Intenta sincronizarlos más tarde.';
      });

      _mostrarMensaje(
        'Guardado localmente. '
        'No se pudo sincronizar.',
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
  // TÍTULOS DE SECCIÓN
  // --------------------------------------------------

  Widget _tituloSeccion(String titulo, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 12),
      child: Text(
        titulo,
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  // --------------------------------------------------
  // INTERFAZ DE USUARIO
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final esquema = tema.colorScheme;

    final oscuro = tema.brightness == Brightness.dark;

    final colorPrincipal = oscuro ? esquema.onSurface : verde;

    return Scaffold(
      backgroundColor: tema.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Preferencias de notificaciones'),
        backgroundColor: tema.scaffoldBackgroundColor,
        foregroundColor: colorPrincipal,
      ),
      body: SafeArea(
        child: _cargando
            ? Center(
                child: CircularProgressIndicator(
                  color: oscuro ? esquema.primary : verde,
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
                        Icons.error_outline,
                        size: 48,
                        color: oscuro ? esquema.error : verde,
                      ),

                      const SizedBox(height: 14),

                      Text(_error!, textAlign: TextAlign.center),

                      const SizedBox(height: 18),

                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _cargando = true;
                            _error = null;
                          });

                          _cargarPreferencias();
                        },
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        'Personaliza tus avisos',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                          color: colorPrincipal,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Elige tus avisos de caducidad. Android puede '
                        'retrasar su entrega por ahorro de batería.',
                        style: TextStyle(
                          color: esquema.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),

                      const SizedBox(height: 12),
                      ValueListenableBuilder<bool?>(
                        valueListenable:
                            NotificacionesLocales.instancia.permiso,
                        builder: (context, permitido, _) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Notificaciones Android',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  !NotificacionesLocales.instancia.disponible
                                      ? 'Los avisos locales están disponibles en Android.'
                                      : permitido == true
                                      ? 'Permiso concedido.'
                                      : permitido == false
                                      ? 'Permiso no concedido. El centro interno sigue disponible.'
                                      : 'No se pudo consultar el permiso.',
                                ),
                                if (NotificacionesLocales
                                        .instancia
                                        .disponible &&
                                    permitido != true)
                                  TextButton(
                                    onPressed: () async {
                                      await NotificacionesLocales.instancia
                                          .solicitarPermiso();
                                      if (mounted &&
                                          NotificacionesLocales
                                                  .instancia
                                                  .permiso
                                                  .value !=
                                              true) {
                                        _mostrarMensaje(
                                          'Puedes habilitar las notificaciones en Ajustes de Android > Aplicaciones > NFC-FoodTech > Notificaciones.',
                                        );
                                      }
                                    },
                                    child: const Text('Activar avisos Android'),
                                  ),
                                ValueListenableBuilder<String?>(
                                  valueListenable:
                                      NotificacionesLocales.instancia.error,
                                  builder: (context, error, _) => error == null
                                      ? const SizedBox.shrink()
                                      : Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(error),
                                            TextButton(
                                              onPressed: NotificacionesLocales
                                                  .instancia
                                                  .sincronizar,
                                              child: const Text(
                                                'Reintentar agenda',
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (kDebugMode)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Diagnostico Android (solo debug)',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const Text(
                                  'Las pruebas usan el mismo canal e icono; '
                                  'ignoran preferencias de caducidad y silencio, pero no el permiso Android. '
                                  'La prueba se solicita para +3 minutos; Android puede retrasarla. '
                                  'Inspeccionar no sincroniza ni cancela avisos.',
                                ),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton(
                                      onPressed: _diagnosticando
                                          ? null
                                          : () => _diagnosticar(
                                              () => NotificacionesLocales
                                                  .instancia
                                                  .publicarPruebaDebug(
                                                    programada: false,
                                                  ),
                                            ),
                                      child: const Text('PUBLICAR AHORA'),
                                    ),
                                    TextButton(
                                      onPressed: _diagnosticando
                                          ? null
                                          : () => _diagnosticar(
                                              () => NotificacionesLocales
                                                  .instancia
                                                  .publicarPruebaDebug(
                                                    programada: true,
                                                  ),
                                            ),
                                      child: const Text('PROGRAMAR PRUEBA'),
                                    ),
                                    TextButton(
                                      onPressed: _diagnosticando
                                          ? null
                                          : () => _diagnosticar(
                                              NotificacionesLocales
                                                  .instancia
                                                  .inspeccionarDebug,
                                            ),
                                      child: const Text('INSPECCIONAR'),
                                    ),
                                  ],
                                ),
                                if (_diagnosticando)
                                  const LinearProgressIndicator(),
                                SelectableText(_diagnostico),
                              ],
                            ),
                          ),
                        ),
                      // ---------------------------
                      // CADUCIDAD ESTIMADA
                      // ---------------------------

                      _tituloSeccion('Caducidad estimada', colorPrincipal),

                      Card(
                        child: Column(
                          children: [
                            SwitchListTile(
                              title: const Text('Alimentos próximos a caducar'),
                              subtitle: const Text(
                                'Recordar alimentos '
                                'próximos a su fecha estimada.',
                              ),
                              secondary: const Icon(
                                Icons.event_available_outlined,
                              ),
                              value: _alertasCaducidad,
                              activeThumbColor: verde,
                              onChanged: _guardando
                                  ? null
                                  : (valor) {
                                      setState(() {
                                        _alertasCaducidad = valor;
                                      });
                                    },
                            ),

                            if (_alertasCaducidad) ...[
                              const Divider(height: 1),

                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: Text('Avisar con anticipación'),
                                    ),

                                    DropdownButton<int>(
                                      value: _diasAnticipacion,
                                      items: const [
                                        DropdownMenuItem(
                                          value: 1,
                                          child: Text('1 día'),
                                        ),
                                        DropdownMenuItem(
                                          value: 2,
                                          child: Text('2 días'),
                                        ),
                                        DropdownMenuItem(
                                          value: 3,
                                          child: Text('3 días'),
                                        ),
                                        DropdownMenuItem(
                                          value: 5,
                                          child: Text('5 días'),
                                        ),
                                        DropdownMenuItem(
                                          value: 7,
                                          child: Text('7 días'),
                                        ),
                                      ],
                                      onChanged: _guardando
                                          ? null
                                          : (valor) {
                                              if (valor == null) {
                                                return;
                                              }

                                              setState(() {
                                                _diasAnticipacion = valor;
                                              });
                                            },
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            const Divider(height: 1),

                            SwitchListTile(
                              title: const Text('Fecha estimada superada'),
                              subtitle: const Text(
                                'Avisar cuando se supere '
                                'la fecha estimada de caducidad.',
                              ),
                              secondary: const Icon(
                                Icons.warning_amber_outlined,
                              ),
                              value: _alertasFechaSuperada,
                              activeThumbColor: verde,
                              onChanged: _guardando
                                  ? null
                                  : (valor) {
                                      setState(() {
                                        _alertasFechaSuperada = valor;
                                      });
                                    },
                            ),
                          ],
                        ),
                      ),

                      // ---------------------------
                      // INVENTARIO
                      // ---------------------------
                      _tituloSeccion('Inventario', colorPrincipal),

                      Card(
                        child: SwitchListTile(
                          title: const Text('Recordatorios de revisión'),
                          subtitle: const Text(
                            'Recordar que debes revisar '
                            'y actualizar tu inventario.',
                          ),
                          secondary: const Icon(Icons.inventory_2_outlined),
                          value: _recordatoriosRevision,
                          activeThumbColor: verde,
                          onChanged: _guardando
                              ? null
                              : (valor) {
                                  setState(() {
                                    _recordatoriosRevision = valor;
                                  });
                                },
                        ),
                      ),

                      // ---------------------------
                      // HORARIO Y SILENCIO
                      // ---------------------------
                      _tituloSeccion('Horarios y silencio', colorPrincipal),

                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.schedule_outlined),
                              title: const Text('Hora preferida'),
                              subtitle: Text(_horaComoTexto(_horaPreferida)),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: _guardando ? null : _seleccionarHora,
                            ),

                            const Divider(height: 1),

                            SwitchListTile(
                              title: const Text('Silenciar todas'),
                              subtitle: const Text(
                                'Guardar la preferencia '
                                'de no recibir avisos.',
                              ),
                              secondary: const Icon(
                                Icons.notifications_off_outlined,
                              ),
                              value: _silenciarTodas,
                              activeThumbColor: verde,
                              onChanged: _guardando
                                  ? null
                                  : (valor) {
                                      setState(() {
                                        _silenciarTodas = valor;
                                      });
                                    },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ---------------------------
                      // INFORMACIÓN
                      // ---------------------------
                      Card(
                        color: esquema.surface,
                        child: Padding(
                          padding: const EdgeInsets.all(15),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: esquema.primary),

                              const SizedBox(width: 12),

                              const Expanded(
                                child: Text(
                                  'Los avisos locales de caducidad usan la hora de America/Santiago. '
                                  'Silenciar todas afecta solo a este dispositivo. '
                                  'Los recordatorios periódicos de revisión no se programan en esta etapa. '
                                  'Los cambios de otros integrantes se reflejan al sincronizar. '
                                  'No se garantiza entrega después de Forzar detención.',
                                  style: TextStyle(fontSize: 12, height: 1.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ---------------------------
                      // ESTADO DE SINCRONIZACIÓN
                      // ---------------------------
                      if (_avisoSincronizacion != null) ...[
                        const SizedBox(height: 14),

                        Card(
                          color: esquema.surface,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Icon(
                                  _pendienteSincronizacion
                                      ? Icons.sync_problem_outlined
                                      : Icons.info_outline,
                                  color: esquema.primary,
                                ),

                                const SizedBox(width: 12),

                                Expanded(
                                  child: Text(
                                    _avisoSincronizacion!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // ---------------------------
                      // GUARDAR
                      // ---------------------------
                      SizedBox(
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: _guardando ? null : _guardarPreferencias,
                          icon: _guardando
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            _guardando
                                ? 'Guardando...'
                                : 'Guardar preferencias',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: verde,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
