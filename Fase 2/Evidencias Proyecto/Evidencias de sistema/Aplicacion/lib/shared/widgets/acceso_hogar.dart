import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nfc_foodtech_app/services/notificaciones_locales.dart';

enum _EstadoAcceso { verificando, activo, error, revocado }

enum SalidaAccesoHogar { revocado }

class _ControlAcceso extends ChangeNotifier {
  final String hogarId;
  final String? usuarioId;
  final SupabaseClient supabase;
  _EstadoAcceso estado = _EstadoAcceso.verificando;
  Future<bool>? _consulta;
  bool _cerrado = false;

  _ControlAcceso(this.hogarId, this.supabase)
    : usuarioId = supabase.auth.currentUser?.id;

  void _cambiar(_EstadoAcceso nuevo) {
    if (_cerrado) return;
    estado = nuevo;
    scheduleMicrotask(() {
      if (!_cerrado) notifyListeners();
    });
  }

  Future<bool> verificar() {
    if (_cerrado || estado == _EstadoAcceso.revocado)
      return Future.value(false);
    if (usuarioId == null || supabase.auth.currentUser?.id != usuarioId) {
      _cambiar(_EstadoAcceso.revocado);
      return Future.value(false);
    }
    return _consulta ??= _consultar().whenComplete(() => _consulta = null);
  }

  Future<bool> _consultar() async {
    _cambiar(_EstadoAcceso.verificando);
    try {
      final datos = await supabase
          .rpc('m14_listar_hogares')
          .timeout(const Duration(seconds: 10));
      if (_cerrado) return false;
      if (supabase.auth.currentUser?.id != usuarioId ||
          estado == _EstadoAcceso.revocado) {
        _cambiar(_EstadoAcceso.revocado);
        return false;
      }
      if (datos is! List ||
          datos.length > 1 ||
          (datos.isNotEmpty &&
              (datos.single is! Map ||
                  datos.single['id'] is! String ||
                  (datos.single['id'] as String).isEmpty))) {
        throw StateError('Respuesta de membresía inválida.');
      }
      if (datos.isEmpty || datos.single['id'] != hogarId) {
        NotificacionesLocales.instancia.contextoVerificado(usuarioId!, null);
        _cambiar(_EstadoAcceso.revocado);
        return false;
      }
      _cambiar(_EstadoAcceso.activo);
      NotificacionesLocales.instancia.contextoVerificado(usuarioId!, hogarId);
      return true;
    } catch (_) {
      if (!_cerrado && estado != _EstadoAcceso.revocado) {
        _cambiar(
          supabase.auth.currentUser?.id == usuarioId
              ? _EstadoAcceso.error
              : _EstadoAcceso.revocado,
        );
      }
      return false;
    }
  }

  @override
  void dispose() {
    _cerrado = true;
    super.dispose();
  }
}

class _AmbitoAcceso extends InheritedWidget {
  final _ControlAcceso control;
  final VoidCallback salir;

  const _AmbitoAcceso({
    required this.control,
    required this.salir,
    required super.child,
  });

  @override
  bool updateShouldNotify(_AmbitoAcceso oldWidget) =>
      control != oldWidget.control;
}

class AccesoHogar extends StatefulWidget {
  final String hogarId;
  final Widget child;
  final bool activo;
  final void Function(bool revocado)? onSalir;

  const AccesoHogar({
    super.key,
    required this.hogarId,
    required this.child,
    this.activo = true,
    this.onSalir,
  });

  static Future<bool> verificar(BuildContext context) {
    if (!context.mounted) return Future.value(false);
    return context
            .getInheritedWidgetOfExactType<_AmbitoAcceso>()
            ?.control
            .verificar() ??
        Future.value(true);
  }

  static Widget? botonVolver(BuildContext context) {
    final ambito = context.getInheritedWidgetOfExactType<_AmbitoAcceso>();
    return ambito == null ? null : BackButton(onPressed: ambito.salir);
  }

  @override
  State<AccesoHogar> createState() => AccesoHogarState();
}

class _ObservadorHogar extends NavigatorObserver {
  final VoidCallback verificar;

  _ObservadorHogar(this.verificar);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) verificar();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) verificar();
  }
}

class AccesoHogarState extends State<AccesoHogar> with WidgetsBindingObserver {
  final _navegador = GlobalKey<NavigatorState>();
  late final _ControlAcceso _control;
  late final _ObservadorHogar _observador;
  late final StreamSubscription<AuthState> _authSubscription;
  ModalRoute<dynamic>? _ruta;
  bool _saliendo = false;
  bool _iniciado = false;

  bool get puedeVolver => _navegador.currentState?.canPop() ?? false;
  Future<bool> volver() async =>
      await _navegador.currentState?.maybePop() ?? false;

  @override
  void didUpdateWidget(AccesoHogar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activo && !oldWidget.activo) _control.verificar();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _control = _ControlAcceso(widget.hogarId, Supabase.instance.client);
    _control.addListener(_actualizar);
    _observador = _ObservadorHogar(() {
      if (widget.activo) _control.verificar();
    });
    _authSubscription = _control.supabase.auth.onAuthStateChange.listen((_) {
      if (widget.activo &&
          _control.supabase.auth.currentUser?.id != _control.usuarioId) {
        _control.verificar();
      }
    });
    if (widget.activo) _control.verificar();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ruta = ModalRoute.of(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.activo && state == AppLifecycleState.resumed)
      _control.verificar();
  }

  void _actualizar() {
    if (!mounted) return;
    if (_control.estado == _EstadoAcceso.revocado) {
      _salir(revocado: true);
    } else {
      if (_control.estado == _EstadoAcceso.activo) _iniciado = true;
      setState(() {});
    }
  }

  void _salir({bool revocado = false}) {
    if (_saliendo || !mounted) return;
    if (!revocado && widget.onSalir != null) {
      widget.onSalir!(false);
      return;
    }
    _saliendo = true;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.onSalir != null) {
        widget.onSalir!(revocado);
        return;
      }
      if (!mounted || _ruta?.isActive != true) return;
      Navigator.of(
        context,
      ).removeRoute(_ruta!, revocado ? SalidaAccesoHogar.revocado : null);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription.cancel();
    _control.removeListener(_actualizar);
    _control.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bloqueado = _control.estado != _EstadoAcceso.activo;
    final esquema = Theme.of(context).colorScheme;
    return _AmbitoAcceso(
      control: _control,
      salir: _salir,
      child: NavigatorPopHandler<Object?>(
        enabled: widget.activo && widget.onSalir == null,
        onPopWithResult: (_) => _navegador.currentState?.maybePop(),
        child: Stack(
          children: [
            if (!_saliendo && _iniciado)
              ExcludeFocus(
                excluding: bloqueado,
                child: ExcludeSemantics(
                  excluding: bloqueado,
                  child: IgnorePointer(
                    ignoring: bloqueado,
                    child: Navigator(
                      key: _navegador,
                      observers: [_observador],
                      onGenerateRoute: (_) => MaterialPageRoute<Object?>(
                        builder: (_) => widget.child,
                      ),
                    ),
                  ),
                ),
              ),
            if (bloqueado || _saliendo)
              Positioned.fill(
                child: Material(
                  color: esquema.surface,
                  child: SafeArea(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_control.estado == _EstadoAcceso.error) ...[
                              const Text(
                                'No se pudo verificar el acceso al hogar. Comprueba tu conexión.',
                                textAlign: TextAlign.center,
                              ),
                              TextButton.icon(
                                onPressed: _control.verificar,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Reintentar acceso'),
                              ),
                            ] else ...[
                              const CircularProgressIndicator(),
                              const SizedBox(height: 16),
                              const Text('Verificando acceso al hogar...'),
                            ],
                            TextButton(
                              onPressed: _salir,
                              child: const Text('Volver al inicio'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
