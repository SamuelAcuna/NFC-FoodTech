import 'package:admin/core/errors/app_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('AppError - PostgrestException', () {
    test('mapea 42501 a mensaje comprensible de permisos', () {
      final msg = AppError.message(
        const PostgrestException(
          message: 'permission denied for table alimento',
          code: '42501',
          details: 'User does not have admin role',
          hint: 'Check RLS policies',
        ),
      );
      expect(msg, 'No tienes permisos para realizar esta acción.');
    });

    test('mapea 23505 a conflicto por duplicado', () {
      final msg = AppError.message(
        const PostgrestException(
          message: 'duplicate key value violates unique constraint',
          code: '23505',
          details: 'Key (nombre)=(Manzana) already exists',
        ),
      );
      expect(msg, 'Ya existe un registro con esos datos.');
    });

    test('mapea 23503 a conflicto por clave foránea', () {
      final msg = AppError.message(
        const PostgrestException(
          message: 'violates foreign key constraint',
          code: '23503',
          details: 'Key (id_categoria)=(99) is still referenced',
        ),
      );
      expect(msg, 'El registro está relacionado con otros datos.');
    });

    test('códigos desconocidos o null muestran mensaje genérico de operación', () {
      final msgUnknown = AppError.message(
        const PostgrestException(message: 'syntax error at or near SELECT', code: '42601'),
      );
      expect(msgUnknown, 'No se pudo completar la operación. Inténtalo nuevamente.');

      final msgNull = AppError.message(
        const PostgrestException(message: 'error sin código'),
      );
      expect(msgNull, 'No se pudo completar la operación. Inténtalo nuevamente.');
    });

    test('nunca expone detalles técnicos, hints, mensajes SQL ni códigos en el mensaje', () {
      for (final code in ['42501', '23505', '23503', '42601', 'XX000']) {
        final msg = AppError.message(
          PostgrestException(
            message: 'FATAL: select * from public.perfil where secret = 123',
            code: code,
            details: 'Internal connection closed at 192.168.1.1',
            hint: 'Run VACUUM FULL',
          ),
        );
        expect(msg, isNot(contains('FATAL')));
        expect(msg, isNot(contains('select')));
        expect(msg, isNot(contains('secret')));
        expect(msg, isNot(contains('192.168.1.1')));
        expect(msg, isNot(contains('VACUUM')));
        expect(msg, isNot(contains(code)));
      }
    });
  });

  group('AppError - AuthException y genéricos', () {
    test('mapea AuthException a mensaje de sesión sin exponer tokens ni detalles', () {
      final msg = AppError.message(
        const AuthException('JWT expired: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'),
      );
      expect(msg, 'No se pudo validar tu sesión. Vuelve a iniciar sesión.');
      expect(msg, isNot(contains('JWT')));
      expect(msg, isNot(contains('eyJ')));
    });

    test('excepciones estándar y objetos desconocidos tienen mensaje seguro', () {
      expect(
        AppError.message(Exception('SocketException: Connection refused to db.internal:5432')),
        'Ocurrió un problema. Inténtalo nuevamente.',
      );
      expect(
        AppError.message('Error de tipo String arbitrario'),
        'Ocurrió un problema. Inténtalo nuevamente.',
      );
    });
  });
}

