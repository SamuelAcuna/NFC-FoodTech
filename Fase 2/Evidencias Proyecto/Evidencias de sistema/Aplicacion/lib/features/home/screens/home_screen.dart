import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nfc_foodtech_app/features/inventario/screens/catalogo_alimentos_screen.dart';
import 'package:nfc_foodtech_app/features/perfil/screens/perfil_screen.dart';
import 'package:nfc_foodtech_app/features/configuracion/screens/configuracion_screen.dart';
import 'package:nfc_foodtech_app/features/alertas/screens/notificaciones_screen.dart';
import 'package:nfc_foodtech_app/features/hogar/screens/seleccionar_hogar_screen.dart';
import 'package:nfc_foodtech_app/features/inventario/screens/inventario_screen.dart';
import 'package:nfc_foodtech_app/features/compras/screens/lista_compras_screen.dart';
import 'package:nfc_foodtech_app/features/indicadores/screens/indicadores_screen.dart';
import 'package:nfc_foodtech_app/features/hogar/screens/hogar_form_screen.dart';
import 'package:nfc_foodtech_app/features/hogar/screens/invitaciones_hogar_screen.dart';
import 'package:nfc_foodtech_app/features/alertas/screens/alertas_caducidad_screen.dart';
import 'package:nfc_foodtech_app/shared/widgets/acceso_hogar.dart';
import 'package:nfc_foodtech_app/services/notificaciones_locales.dart';
import 'package:nfc_foodtech_app/shared/models/texto_notificacion.dart';
import 'package:nfc_foodtech_app/features/home/models/resumen_hogar.dart';
import 'package:nfc_foodtech_app/shared/services/lectura_movimientos.dart';
import 'package:nfc_foodtech_app/features/home/widgets/resumen_hogar_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  static const Color verde = Color(0xFF236B4A);
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String? _nombrePerfil;
  Map<String, dynamic>? _hogarSeleccionado;
  bool _cargandoHogar = true;
  bool _abriendoHogar = false;
  String? _errorHogar;
  String? _usuarioHogarId;
  int _revisionHogar = 0;
  int? _cantidadAlimentos;
  bool _cargandoResumen = false;
  bool _errorResumen = false;
  int _pestana = 0;
  List<MesResumenHogar>? _meses;
  bool _cargandoAnalisis = false;
  bool _errorAnalisis = false;
  bool _analisisSucio = true;
  int _revisionAnalisis = 0;
  final _visitadas = <int>{0};
  final _claves = <int, GlobalKey<AccesoHogarState>>{};
  GlobalKey<InventarioScreenState> _inventarioKey = GlobalKey();
  GlobalKey<AlertasCaducidadScreenState> _alertasKey = GlobalKey();
  bool _inventarioSucio = false;
  bool _alertasSucias = false;
  bool _volviendo = false;
  bool _atendiendoAviso = false;
  List<Map<String, dynamic>> _notificaciones = [];
  Map<int, Map<String, dynamic>> _plantillas = {};
  bool _cargandoNotificaciones = true;
  bool _errorNotificaciones = false;
  int _revisionNotificaciones = 0;
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificacionesLocales.instancia.destino.addListener(_atenderAviso);
    _usuarioHogarId = Supabase.instance.client.auth.currentUser?.id;
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      _,
    ) {
      if (!mounted) return;
      final usuario = Supabase.instance.client.auth.currentUser?.id;
      if (usuario != _usuarioHogarId) {
        _usuarioHogarId = usuario;
        _revisionNotificaciones++;
        setState(() {
          _nombrePerfil = null;
          _hogarSeleccionado = null;
          _notificaciones = [];
          _plantillas = {};
          _pestana = 0;
          _descartarModulos();
        });
        _cargarNombrePerfil();
        _cargarHogar();
        _cargarNotificaciones();
      }
    });
    _cargarNombrePerfil();
    _cargarHogar();
    _cargarNotificaciones();
  }

  void _descartarModulos() {
    _revisionAnalisis++;
    _meses = null;
    _cargandoAnalisis = false;
    _errorAnalisis = false;
    _analisisSucio = true;
    _inventarioKey = GlobalKey();
    _alertasKey = GlobalKey();
    _inventarioSucio = false;
    _alertasSucias = false;
    _claves.clear();
    _visitadas.removeAll([1, 2, 3]);
    if (_pestana >= 1 && _pestana <= 3) _visitadas.add(_pestana);
  }

  @override
  void dispose() {
    _revisionHogar++;
    _revisionNotificaciones++;
    WidgetsBinding.instance.removeObserver(this);
    NotificacionesLocales.instancia.destino.removeListener(_atenderAviso);
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (state == AppLifecycleState.resumed &&
        (_pestana == 0 || _pestana == 4)) {
      _invalidarAnalisis();
      _cargarHogar();
      if (_pestana == 0) _cargarNotificaciones();
    }
  }

  void _invalidarAnalisis({bool refrescar = false}) {
    _revisionAnalisis++;
    _analisisSucio = true;
    _cargandoAnalisis = false;
    _meses = null;
    if (refrescar &&
        _pestana == 0 &&
        !_cargandoHogar &&
        !_abriendoHogar &&
        ModalRoute.of(context)?.isCurrent == true) {
      unawaited(_cargarAnalisis());
    }
  }

  Future<Map<String, dynamic>?> _cargarHogar({
    bool actualizarResumen = true,
  }) async {
    if (!mounted) return null;
    final revision = ++_revisionHogar;
    final usuario = Supabase.instance.client.auth.currentUser?.id;
    bool vigente() =>
        mounted &&
        revision == _revisionHogar &&
        Supabase.instance.client.auth.currentUser?.id == usuario;
    setState(() {
      _cargandoHogar = true;
      _errorHogar = null;
      _cantidadAlimentos = null;
      _cargandoResumen = false;
      _errorResumen = false;
    });
    try {
      if (usuario == null) throw StateError('Debes iniciar sesión nuevamente.');
      final datos = await Supabase.instance.client
          .rpc('m14_listar_hogares')
          .timeout(const Duration(seconds: 15));
      if (!vigente()) return null;
      if (datos is! List)
        throw StateError('La respuesta del hogar no es válida.');
      if (datos.length > 1)
        throw StateError(
          'Se encontró más de un hogar activo. Contacta a soporte.',
        );
      final hogar = datos.isEmpty
          ? null
          : Map<String, dynamic>.from(datos.single as Map);
      if (hogar != null &&
          (hogar['id'] is! String || (hogar['id'] as String).trim().isEmpty)) {
        throw StateError('No se pudo identificar tu hogar.');
      }
      setState(() {
        if (!mapEquals(hogar, _hogarSeleccionado)) _descartarModulos();
        _hogarSeleccionado = hogar;
      });
      NotificacionesLocales.instancia.contextoVerificado(
        usuario,
        hogar?['id'] as String?,
      );
      if (hogar != null && actualizarResumen) {
        unawaited(_cargarResumen(hogar['id'] as String, revision, usuario));
        if (_analisisSucio) unawaited(_cargarAnalisis());
      }
      return hogar;
    } catch (e) {
      if (vigente())
        setState(() {
          _hogarSeleccionado = null;
          _descartarModulos();
          _errorHogar = e is StateError
              ? e.message.toString()
              : 'No se pudo consultar tu hogar. Reintenta.';
        });
      return null;
    } finally {
      if (vigente()) {
        setState(() => _cargandoHogar = false);
        WidgetsBinding.instance.addPostFrameCallback((_) => _atenderAviso());
      }
    }
  }

  Future<void> _cargarResumen(
    String hogarId,
    int revision,
    String usuarioId,
  ) async {
    bool vigente() =>
        mounted &&
        revision == _revisionHogar &&
        Supabase.instance.client.auth.currentUser?.id == usuarioId &&
        _hogarSeleccionado?['id'] == hogarId;
    if (!vigente() || _cargandoResumen) return;
    setState(() {
      _cargandoResumen = true;
      _errorResumen = false;
    });
    try {
      final alimentos = <int>{};
      for (var inicio = 0; ; inicio += 1000) {
        final registros = await Supabase.instance.client
            .from('despensa_item')
            .select('alimento_id')
            .eq('hogar_id', hogarId)
            .eq('estado', 'DISPONIBLE')
            .gt('cantidad_restante', 0)
            .order('id')
            .range(inicio, inicio + 999)
            .timeout(const Duration(seconds: 15));
        if (!vigente()) return;
        for (final registro in registros) {
          final id = registro['alimento_id'];
          if (id is! int) throw StateError('Alimento no válido.');
          alimentos.add(id);
        }
        if (registros.length < 1000) break;
      }
      if (vigente()) setState(() => _cantidadAlimentos = alimentos.length);
    } catch (_) {
      if (vigente()) setState(() => _errorResumen = true);
    } finally {
      if (vigente()) setState(() => _cargandoResumen = false);
    }
  }

  Future<void> _cargarAnalisis() async {
    if (_cargandoAnalisis || _hogarSeleccionado == null || _errorHogar != null)
      return;
    final revision = ++_revisionAnalisis;
    final hogarId = _hogarSeleccionado!['id'] as String;
    final cliente = Supabase.instance.client;
    final usuarioId = cliente.auth.currentUser?.id;
    bool vigente() =>
        mounted &&
        revision == _revisionAnalisis &&
        cliente.auth.currentUser?.id == usuarioId &&
        _hogarSeleccionado?['id'] == hogarId &&
        _errorHogar == null;
    setState(() {
      _cargandoAnalisis = true;
      _errorAnalisis = false;
    });
    try {
      final ahora = DateTime.now();
      final lectura = LecturaMovimientos(cliente, vigente);
      final ingresos = await lectura.leer(
        'despensa_item',
        'id, alimento_id, cantidad_inicial, precio_clp',
        hogarId: hogarId,
      );
      final items = {for (final item in ingresos) item['id'].toString(): item};
      final movimientos = await lectura.leer(
        'movimiento',
        'id, despensa_item_id, tipo, cantidad, fecha',
        columnaIds: 'despensa_item_id',
        ids: items.keys.toList(),
        desde: DateTime(ahora.year, ahora.month - 2),
        hasta: DateTime(ahora.year, ahora.month + 1),
        tipos: ['CONSUMO', 'DESCARTE'],
      );
      final ids = ingresos
          .map((i) => (i['alimento_id'] as num).toInt())
          .toSet()
          .toList();
      final lista = await lectura.leer(
        'alimento',
        'id, nombre, unidad_base, categoria_id',
        columnaIds: 'id',
        ids: ids,
      );
      final meses = calcularResumenHogar(
        items: items,
        movimientos: movimientos,
        alimentos: {for (final a in lista) (a['id'] as num).toInt(): a},
        ahora: ahora,
      );
      if (vigente())
        setState(() {
          _meses = meses;
          _analisisSucio = false;
        });
    } catch (_) {
      if (vigente())
        setState(() {
          _meses = null;
          _errorAnalisis = true;
        });
    } finally {
      if (vigente()) setState(() => _cargandoAnalisis = false);
    }
  }

  // Obtener el nombre real desde la tabla perfil.
  Future<void> _cargarNombrePerfil() async {
    final usuario = Supabase.instance.client.auth.currentUser;

    if (usuario == null) return;

    final usuarioId = usuario.id;

    try {
      final datos = await Supabase.instance.client
          .from('perfil')
          .select('nombre')
          .eq('id', usuarioId)
          .maybeSingle();

      if (!mounted) return;

      // Evitar mostrar información de otra cuenta.
      if (Supabase.instance.client.auth.currentUser?.id != usuarioId) {
        return;
      }

      final nombre = (datos?['nombre'] as String?)?.trim();

      setState(() {
        _nombrePerfil = nombre;
      });
    } catch (error) {
      debugPrint('Error al cargar el nombre del perfil: $error');
    }
  }

  void _mostrarMensaje(BuildContext context, String mensaje) {
    if (context.mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _abrirPantalla(Widget pantalla) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => pantalla));
    if (mounted) _atenderAviso();
  }

  Future<void> _abrirPerfil() async {
    await _abrirPantalla(const PerfilScreen());
    if (mounted) await _cargarNombrePerfil();
  }

  Future<void> _abrirCentro() async {
    await _abrirPantalla(const NotificacionesScreen());
    if (mounted) await _cargarNotificaciones();
  }

  Future<void> _cargarNotificaciones() async {
    final revision = ++_revisionNotificaciones;
    final usuario = Supabase.instance.client.auth.currentUser?.id;
    bool vigente() =>
        mounted &&
        revision == _revisionNotificaciones &&
        Supabase.instance.client.auth.currentUser?.id == usuario;
    setState(() {
      _cargandoNotificaciones = true;
      _errorNotificaciones = false;
    });
    try {
      if (usuario == null) throw StateError('Sin sesión');
      final filas = await Supabase.instance.client
          .from('notificacion')
          .select('id, plantilla_id, datos, estado, created_at, leida_en')
          .eq('perfil_id', usuario)
          .neq('estado', 'CANCELADA')
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(3)
          .timeout(const Duration(seconds: 8));
      if (!vigente()) return;
      final avisos = filas
          .take(3)
          .map((f) => Map<String, dynamic>.from(f))
          .toList();
      final ids = avisos
          .map((n) => int.tryParse(n['plantilla_id'].toString()))
          .whereType<int>()
          .toSet()
          .toList();
      final plantillas = <int, Map<String, dynamic>>{};
      if (ids.isNotEmpty) {
        final lista = await Supabase.instance.client
            .from('plantilla_notificacion')
            .select('id, titulo_tpl, cuerpo_tpl')
            .inFilter('id', ids)
            .timeout(const Duration(seconds: 8));
        for (final fila in lista) {
          plantillas[(fila['id'] as num).toInt()] = Map<String, dynamic>.from(
            fila,
          );
        }
      }
      if (vigente())
        setState(() {
          _notificaciones = avisos;
          _plantillas = plantillas;
        });
    } catch (_) {
      if (vigente())
        setState(() {
          _errorNotificaciones = true;
          _notificaciones = [];
          _plantillas = {};
        });
    } finally {
      if (vigente()) setState(() => _cargandoNotificaciones = false);
    }
  }

  void _seleccionar(int indice) {
    if (indice == _pestana || _abriendoHogar) return;
    setState(() {
      _pestana = indice;
      _visitadas.add(indice);
    });
    if (indice == 1 && _inventarioSucio) {
      _inventarioSucio = false;
      unawaited(
        _inventarioKey.currentState?.actualizarDatos() ?? Future<void>.value(),
      );
    }
    if (indice == 3 && _alertasSucias) {
      _alertasSucias = false;
      unawaited(
        _alertasKey.currentState?.actualizarDatos() ?? Future<void>.value(),
      );
    }
    if (indice == 0) {
      _cargarHogar();
      _cargarNotificaciones();
    }
  }

  Future<void> _volver() async {
    if (_volviendo) return;
    _volviendo = true;
    try {
      final modulo = _claves[_pestana]?.currentState;
      if (modulo != null && modulo.puedeVolver) {
        await modulo.volver();
      } else {
        _seleccionar(0);
      }
    } finally {
      _volviendo = false;
    }
  }

  void _salirModulo(bool revocado) {
    if (!mounted) return;
    if (revocado) {
      setState(() {
        _hogarSeleccionado = null;
        _descartarModulos();
      });
      _mostrarMensaje(context, 'Ya no tienes acceso a ese hogar.');
    }
    if (_pestana != 0) {
      _seleccionar(0);
    } else {
      _cargarHogar();
    }
  }

  Future<void> _abrirRutaHogar({bool registro = false}) async {
    if (_cargandoHogar || _abriendoHogar) return;
    final usuario = Supabase.instance.client.auth.currentUser?.id;
    setState(() => _abriendoHogar = true);
    try {
      final hogar = await _cargarHogar(actualizarResumen: false);
      if (!mounted ||
          hogar == null ||
          Supabase.instance.client.auth.currentUser?.id != usuario)
        return;
      final resultado = await Navigator.of(context).push<Object?>(
        MaterialPageRoute(
          builder: (_) => registro
              ? CatalogoAlimentosScreen(hogar: hogar)
              : AccesoHogar(
                  hogarId: hogar['id'] as String,
                  child: IndicadoresScreen(hogar: hogar),
                ),
        ),
      );
      if (mounted && registro && resultado == true) {
        _inventarioSucio = true;
        _alertasSucias = true;
        _invalidarAnalisis();
      }
      if (mounted && resultado == SalidaAccesoHogar.revocado) {
        setState(() {
          _hogarSeleccionado = null;
          _descartarModulos();
          _pestana = 0;
        });
      }
    } finally {
      if (mounted) {
        await _cargarHogar();
        if (mounted) setState(() => _abriendoHogar = false);
        if (mounted) _atenderAviso();
      }
    }
  }

  void _atenderAviso() {
    if (!mounted ||
        _atendiendoAviso ||
        _cargandoHogar ||
        _abriendoHogar ||
        ModalRoute.of(context)?.isCurrent != true)
      return;
    final destino = NotificacionesLocales.instancia.destino.value;
    if (destino == null) return;
    NotificacionesLocales.instancia.destino.value = null;
    if (Supabase.instance.client.auth.currentUser?.id != destino.usuarioId)
      return;
    _atendiendoAviso = true;
    unawaited(
      _abrirAviso(destino).whenComplete(() => _atendiendoAviso = false),
    );
  }

  Future<void> _abrirAviso(DestinoAviso destino) async {
    final hogar = await _cargarHogar(actualizarResumen: false);
    if (!mounted ||
        Supabase.instance.client.auth.currentUser?.id != destino.usuarioId ||
        hogar == null)
      return;
    if (hogar['id'] != destino.hogarId) {
      _mostrarMensaje(context, 'El aviso ya no corresponde a tu hogar activo.');
      return;
    }
    _seleccionar(3);
  }

  Future<void> _abrirGestionHogar(
    Widget pantalla, {
    bool sinHogar = false,
  }) async {
    if (_cargandoHogar || _abriendoHogar) return;
    final usuarioId = Supabase.instance.client.auth.currentUser?.id;
    setState(() => _abriendoHogar = true);
    try {
      if (sinHogar) {
        final hogar = await _cargarHogar();
        if (!mounted ||
            _cargandoHogar ||
            _errorHogar != null ||
            Supabase.instance.client.auth.currentUser?.id != usuarioId)
          return;
        if (hogar != null) {
          _mostrarMensaje(context, 'Ya perteneces a un hogar activo.');
          return;
        }
      }
      if (!mounted ||
          usuarioId == null ||
          Supabase.instance.client.auth.currentUser?.id != usuarioId)
        return;
      await Navigator.of(
        context,
      ).push<Object?>(MaterialPageRoute(builder: (_) => pantalla));
    } finally {
      if (mounted) {
        await _cargarHogar();
        if (mounted) setState(() => _abriendoHogar = false);
      }
    }
  }

  Future<void> _abrirMisHogares() =>
      _abrirGestionHogar(const SeleccionarHogarScreen());

  Widget _estadoHogar() {
    final esquema = Theme.of(context).colorScheme;
    final habilitado = !_cargandoHogar && !_abriendoHogar;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_cargandoHogar)
              const Column(
                children: [
                  LinearProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Consultando tu hogar...'),
                ],
              )
            else if (_errorHogar != null) ...[
              Text(_errorHogar!, style: TextStyle(color: esquema.error)),
              TextButton.icon(
                onPressed: _abriendoHogar ? null : _cargarHogar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ] else if (_hogarSeleccionado == null) ...[
              const Text('Todavía no perteneces a ningún hogar.'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: habilitado
                    ? () => _abrirGestionHogar(
                        const HogarFormScreen(),
                        sinHogar: true,
                      )
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('Crear hogar'),
              ),
              OutlinedButton.icon(
                onPressed: habilitado
                    ? () => _abrirGestionHogar(
                        const InvitacionesHogarScreen(),
                        sinHogar: true,
                      )
                    : null,
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Unirse mediante código'),
              ),
            ] else
              Text('Mi hogar: ${_hogarSeleccionado!['nombre'] ?? 'Hogar'}'),
          ],
        ),
      ),
    );
  }

  Future<void> _cerrarSesion(BuildContext context) async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (error) {
      if (!context.mounted) return;

      _mostrarMensaje(
        context,
        'No se pudo cerrar sesión. '
        'Inténtalo nuevamente.',
      );

      debugPrint('Error al cerrar sesión: $error');
    }
  }

  Widget _modulo(int indice) {
    if (!_visitadas.contains(indice)) return const SizedBox.shrink();
    final hogar = _hogarSeleccionado;
    if (hogar == null || _errorHogar != null)
      return SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _estadoHogar(),
          ),
        ),
      );
    return AccesoHogar(
      key: _claves.putIfAbsent(indice, () => GlobalKey<AccesoHogarState>()),
      hogarId: hogar['id'] as String,
      activo: _pestana == indice,
      onSalir: _salirModulo,
      child: indice == 1
          ? InventarioScreen(
              key: _inventarioKey,
              hogar: hogar,
              onDatosActualizados: () {
                _alertasSucias = true;
                _invalidarAnalisis(refrescar: true);
              },
            )
          : indice == 2
          ? ListaComprasScreen(
              hogar: hogar,
              onCompraConfirmada: () {
                _inventarioSucio = true;
                _alertasSucias = true;
                _invalidarAnalisis(refrescar: true);
              },
            )
          : AlertasCaducidadScreen(key: _alertasKey, hogar: hogar),
    );
  }

  Widget _inicio() {
    final esquema = Theme.of(context).colorScheme;
    final nombre = _nombrePerfil?.trim().isNotEmpty == true
        ? _nombrePerfil!
        : (Supabase.instance.client.auth.currentUser?.email ?? 'Usuario')
              .split('@')
              .first;
    final disponible =
        !_cargandoHogar &&
        !_abriendoHogar &&
        _hogarSeleccionado != null &&
        _errorHogar == null;
    final valor = _cargandoHogar || _cargandoResumen
        ? '…'
        : _errorHogar != null || _errorResumen
        ? 'Error'
        : _cantidadAlimentos?.toString() ?? 'Sin datos';
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: ListView(
            key: const PageStorageKey('inicio'),
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Icon(Icons.eco_rounded, color: esquema.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'NFC-FoodTech',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: esquema.primary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Notificaciones',
                    onPressed: _abrirCentro,
                    icon: const Icon(Icons.notifications_outlined),
                  ),
                  IconButton(
                    tooltip: 'Mi perfil',
                    onPressed: _abrirPerfil,
                    icon: const Icon(Icons.person_outline),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '¡Hola, $nombre!',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              if (_cargandoHogar)
                const LinearProgressIndicator()
              else if (_errorHogar != null) ...[
                Text(_errorHogar!, style: TextStyle(color: esquema.error)),
                TextButton(
                  onPressed: _cargarHogar,
                  child: const Text('Reintentar'),
                ),
              ] else if (_hogarSeleccionado == null)
                _estadoHogar()
              else
                TextButton.icon(
                  onPressed: _abriendoHogar ? null : _abrirMisHogares,
                  icon: const Icon(Icons.home_outlined),
                  label: Text(
                    'Mi hogar: ${_hogarSeleccionado!['nombre'] ?? 'Hogar'}',
                  ),
                ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Alimentos disponibles',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        valor,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: esquema.primary,
                        ),
                      ),
                      if (_cantidadAlimentos == 0 &&
                          !_cargandoHogar &&
                          !_cargandoResumen &&
                          !_errorResumen &&
                          _errorHogar == null)
                        const Text('Todavía no hay alimentos disponibles.'),
                      if (_errorResumen)
                        TextButton(
                          onPressed: _cargarHogar,
                          child: const Text('Reintentar resumen'),
                        ),
                      Text(
                        'Alimentos distintos con existencias en tu hogar.',
                        style: TextStyle(color: esquema.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ResumenHogarCard(
                meses: _meses,
                cargando: _cargandoHogar || _cargandoAnalisis,
                error: _errorAnalisis || _errorHogar != null,
                onReintentar: _errorHogar != null
                    ? _cargarHogar
                    : _cargarAnalisis,
                onAnalisis: disponible ? () => _abrirRutaHogar() : null,
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  const Text(
                    'Últimas notificaciones',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: _abrirCentro,
                    child: const Text('Ver todas'),
                  ),
                ],
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      if (_cargandoNotificaciones)
                        const LinearProgressIndicator()
                      else if (_errorNotificaciones) ...[
                        const Text('No se pudieron cargar las notificaciones.'),
                        TextButton(
                          onPressed: _cargarNotificaciones,
                          child: const Text('Reintentar notificaciones'),
                        ),
                      ] else if (_notificaciones.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('No tienes notificaciones recientes.'),
                        )
                      else
                        for (final aviso in _notificaciones) _aviso(aviso),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Registro rápido de alimentos',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: disponible
                    ? () => _abrirRutaHogar(registro: true)
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('Registrar alimento'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aviso(Map<String, dynamic> aviso) {
    final plantilla =
        _plantillas[int.tryParse(aviso['plantilla_id'].toString())];
    final titulo = plantilla?['titulo_tpl']?.toString() ?? '';
    final cuerpo = plantilla?['cuerpo_tpl']?.toString() ?? '';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(
        aviso['leida_en'] == null
            ? Icons.notifications_active_outlined
            : Icons.notifications_none,
      ),
      title: Text(
        titulo.isEmpty
            ? 'Notificación'
            : completarTextoNotificacion(titulo, aviso['datos']),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        cuerpo.isEmpty
            ? 'No hay un mensaje disponible para esta notificación.'
            : completarTextoNotificacion(cuerpo, aviso['datos']),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: _abrirCentro,
    );
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: _pestana == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_volver());
    },
    child: Scaffold(
      body: IndexedStack(
        index: _pestana,
        children: [
          _inicio(),
          for (final indice in [1, 2, 3])
            TickerMode(enabled: _pestana == indice, child: _modulo(indice)),
          ConfiguracionScreen(
            integrada: true,
            onCerrarSesion: () => _cerrarSesion(context),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pestana,
        onDestinationSelected: _seleccionar,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Inventario',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            selectedIcon: Icon(Icons.shopping_cart),
            label: 'Compras',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alertas',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ajustes',
          ),
        ],
      ),
    ),
  );
}
