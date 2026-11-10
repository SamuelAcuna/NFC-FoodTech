
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  final SharedPreferencesAsync _preferencias =
      SharedPreferencesAsync();

  ThemeMode _modo = ThemeMode.light;

  String? _usuarioActualId;

  int _revisionCarga = 0;

  Future<void> _operacionPendiente = Future<void>.value();

  ThemeMode get modo => _modo;

  String? get usuarioActualId => _usuarioActualId;

  Future<T> _ejecutarEnOrden<T>(Future<T> Function() operacion) {
    final siguiente = _operacionPendiente.then((_) => operacion());
    _operacionPendiente = siguiente.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return siguiente;
  }

  // Cargar el tema de un usuario específico.
  Future<void> cargarParaUsuario(String? usuarioId) async {
    final revision = ++_revisionCarga;

    _usuarioActualId = usuarioId;

    await _ejecutarEnOrden<void>(() async {
      if (revision != _revisionCarga ||
          _usuarioActualId != usuarioId) {
        return;
      }

      try {
        final valorUsuario = usuarioId == null
            ? null
            : await _preferencias.getString('nfc_foodtech_tema_$usuarioId');
        final valor = valorUsuario ??
            await _preferencias.getString('nfc_foodtech_tema_dispositivo');

        if (revision != _revisionCarga ||
            _usuarioActualId != usuarioId) {
          return;
        }

        _modo = switch (valor) {
          'dark' => ThemeMode.dark,
          'system' => ThemeMode.system,
          _ => ThemeMode.light,
        };
        notifyListeners();

        if (usuarioId != null &&
            revision == _revisionCarga &&
            _usuarioActualId == usuarioId) {
          await _preferencias.setString(
            'nfc_foodtech_tema_dispositivo',
            _modo.name,
          );
        }
      } catch (error) {
        debugPrint('Error al cargar tema: $error');
      }
    });
  }

  // Guardar la preferencia de la cuenta activa.
  Future<bool> cambiar(ThemeMode nuevoModo) async {
    final usuarioId = _usuarioActualId;

    if (usuarioId == null) {
      return false;
    }

    final revision = ++_revisionCarga;

    return _ejecutarEnOrden<bool>(() async {
      if (revision != _revisionCarga ||
          _usuarioActualId != usuarioId) {
        return false;
      }

      try {
        final clave = 'nfc_foodtech_tema_$usuarioId';

        await _preferencias.setString(clave, nuevoModo.name);

        if (revision != _revisionCarga ||
            _usuarioActualId != usuarioId) {
          return false;
        }

        await _preferencias.setString(
          'nfc_foodtech_tema_dispositivo',
          nuevoModo.name,
        );

        if (revision != _revisionCarga ||
            _usuarioActualId != usuarioId) {
          return false;
        }

        _modo = nuevoModo;
        notifyListeners();

        return true;
      } catch (error) {
        debugPrint('Error al guardar tema: $error');
        return false;
      }
    });
  }
}

final appTheme = ThemeController();
