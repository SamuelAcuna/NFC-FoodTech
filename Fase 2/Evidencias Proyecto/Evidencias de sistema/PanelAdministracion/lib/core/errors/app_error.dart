import 'dart:async';

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class AppError {
  static String administradorMessage(Object error) =>
      businessMessage(error, const {
        'No existe un usuario registrado con ese correo.',
        'La cuenta del usuario no está activa.',
        'El rol no existe.',
        'El usuario ya tiene ese rol.',
        'No puedes quitarte tus propios roles.',
        'El usuario no tiene ese rol.',
        'No se puede quitar el último administrador activo de la plataforma.',
      });
  static String soporteMessage(Object error) => businessMessage(error, const {
    'La solicitud no existe.',
    'La solicitud no se puede asignar en su estado actual.',
    'El agente no tiene permisos de soporte.',
    'La respuesta debe tener entre 5 y 2000 caracteres.',
    'La solicitud está cerrada.',
    'La solicitud ya está cerrada.',
  });
  static String usuarioMessage(Object error) => businessMessage(error, const {
    'Estado no válido.',
    'El motivo debe tener entre 5 y 500 caracteres.',
    'No puedes cambiar el estado de tu propia cuenta.',
    'El usuario no existe.',
    'La cuenta ya está en ese estado.',
    'No se puede suspender al último administrador activo.',
  });
  static String businessMessage(Object error, Set<String> allowed) {
    if (error is PostgrestException &&
        error.code == 'P0001' &&
        allowed.contains(error.message)) {
      return error.message;
    }
    return message(error);
  }

  static String propuestoMessage(Object error) {
    if (error is PostgrestException) {
      if (error.code == '23505') {
        return 'Ya existe un alimento con ese nombre en el catálogo. Cámbialo o rechaza la propuesta.';
      }
      // Solo los mensajes de negocio definidos por las RPC T05 pueden mostrarse tal cual.
      const businessMessages = {
        'El producto ya no está pendiente de revisión.',
        'El nombre debe tener entre 2 y 80 caracteres.',
        'La categoría no existe o está inactiva.',
        'La duración debe estar entre 1 y 3650 días.',
      };
      if (error.code == 'P0001' && businessMessages.contains(error.message)) {
        return error.message;
      }
    }
    return message(error);
  }

  static String alimentoMessage(Object error, {bool deleting = false}) {
    if (error is PostgrestException) {
      if (error.code == '23505') {
        return 'Ya existe un alimento con ese nombre en el catálogo.';
      }
      if (deleting && error.code == '23503') {
        return 'No se puede eliminar: el alimento está en uso en despensas o listas de compra. Dalo de baja en su lugar.';
      }
    }
    return message(error);
  }

  static String categoriaMessage(Object error, {bool deleting = false}) {
    if (error is PostgrestException) {
      if (deleting && error.code == '23503') {
        return 'No se puede eliminar: la categoría tiene alimentos o subcategorías. Desactívala en su lugar.';
      }
      if (error.code == '23505') {
        return 'Ya existe una categoría con ese nombre bajo el mismo padre.';
      }
      if (error.code == '23514' || error.code == '22P02') {
        return 'Ingresa días enteros entre 1 y 3650 o deja el campo vacío.';
      }
      if (error.code == 'P0001') {
        return 'Solo se permiten dos niveles. Revisa que el padre sea raíz, que no sea la misma categoría y que esta no tenga subcategorías.';
      }
    }
    return message(error);
  }

  static String authMessage(
    Object error, {
    bool login = false,
    bool mfa = false,
  }) {
    if (error is AuthRetryableFetchException ||
        error is TimeoutException ||
        error is ClientException) {
      return 'No se pudo conectar. Revisa tu conexión.';
    }
    if (error is AuthException) {
      if (error.code == 'invalid_credentials' ||
          (login && error.statusCode == '400')) {
        return 'Correo o contraseña incorrectos.';
      }
      if (error.code == 'mfa_verification_failed' ||
          error.code == 'mfa_challenge_expired' ||
          (mfa && error.statusCode == '400')) {
        return 'Código incorrecto o vencido, intenta de nuevo.';
      }
    }
    return message(error);
  }

  static String message(Object error) {
    if (error is AuthRetryableFetchException ||
        error is TimeoutException ||
        error is ClientException) {
      return 'No se pudo conectar. Revisa tu conexión.';
    }
    if (error is AuthException) {
      return 'No se pudo validar tu sesión. Vuelve a iniciar sesión.';
    }
    if (error is PostgrestException) {
      return switch (error.code) {
        '42501' => 'No tienes permisos para realizar esta acción.',
        '23505' => 'Ya existe un registro con esos datos.',
        '23503' => 'El registro está relacionado con otros datos.',
        _ => 'No se pudo completar la operación. Inténtalo nuevamente.',
      };
    }
    return 'Ocurrió un problema. Inténtalo nuevamente.';
  }
}
