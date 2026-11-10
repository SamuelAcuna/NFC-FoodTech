import 'dart:convert';

import 'package:admin/core/errors/app_error.dart';
import 'package:admin/core/format/formatters.dart';
import 'package:admin/features/propuestos/data/propuestos_repository.dart';
import 'package:admin/features/propuestos/domain/propuesta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> propuestaJson(int id) => {
  'id': id,
  'nombre': 'Plátano sugerido',
  'categoria_id': 2,
  'unidad_base': 'un',
  'es_perecible': true,
  'vida_util_dias_ref': null,
  'hogar_ref': 'hogar_123456',
  'propuesto_en': '2026-10-19T12:00:00Z',
};
Future<void> main() async {
  await initializeDateFormatting('es_CL');
  test('Propuesta.fromJson, fecha y filtro sin tildes', () {
    final p = Propuesta.fromJson(propuestaJson(1));
    expect(p.id, 1);
    expect(p.vidaUtilDiasRef, isNull);
    expect(p.hogarRef, 'hogar_123456');
    expect(p.editable.unidadLabel, 'Unidad');
    expect(fecha(p.propuestoEn), '19-10-2026');
    expect(filtrarPropuestas([p], 'PLATANO').single, p);
    expect(filtrarPropuestas([p], 'arroz'), isEmpty);
  });
  test(
    'Repositorio usa exclusivamente las cuatro RPC y parámetros corregidos',
    () async {
      final calls = <http.Request>[];
      final client = SupabaseClient(
        'https://propuestos.example.invalid',
        'clave-ficticia-test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          calls.add(request);
          final value = switch (request.url.path.split('/').last) {
            'admin_listar_propuestos' => [propuestaJson(10)],
            'admin_contar_propuestos' => 1,
            'admin_aprobar_propuesto' => 10,
            'admin_rechazar_propuesto' => null,
            _ => throw StateError('RPC inesperada'),
          };
          return http.Response(
            jsonEncode(value),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final repo = SupabasePropuestosRepository(client);
      expect((await repo.listar()).single.id, 10);
      expect(await repo.contar(), 1);
      expect(
        await repo.aprobar(
          id: 10,
          nombre: '  Plátano corregido  ',
          categoriaId: 1,
          unidadBase: 'g',
          esPerecible: false,
          vidaUtilDiasRef: 3,
        ),
        10,
      );
      await repo.rechazar(10);
      expect(
        calls.every((r) => r.url.path.startsWith('/rest/v1/rpc/admin_')),
        isTrue,
      );
      expect(jsonDecode(calls[2].body), {
        'p_id': 10,
        'p_nombre': 'Plátano corregido',
        'p_categoria_id': 1,
        'p_unidad_base': 'g',
        'p_es_perecible': false,
        'p_vida_util_dias_ref': 3,
      });
      expect(jsonDecode(calls[3].body), {'p_id': 10});
      expect(calls[0].url.queryParameters['limit'], '500');
    },
  );
  test('Errores de negocio exactos, duplicado y permisos; mensajes técnicos no salen', () {
    for (final message in [
      'El producto ya no está pendiente de revisión.',
      'El nombre debe tener entre 2 y 80 caracteres.',
      'La categoría no existe o está inactiva.',
      'La duración debe estar entre 1 y 3650 días.',
    ]) {
      expect(
        AppError.propuestoMessage(
          PostgrestException(message: message, code: 'P0001'),
        ),
        message,
      );
    }
    expect(
      AppError.propuestoMessage(
        const PostgrestException(message: 'RAW SECRET', code: 'P0001'),
      ),
      isNot(contains('RAW')),
    );
    expect(
      AppError.propuestoMessage(
        const PostgrestException(message: 'RAW', code: '23505'),
      ),
      'Ya existe un alimento con ese nombre en el catálogo. Cámbialo o rechaza la propuesta.',
    );
    expect(
      AppError.propuestoMessage(
        const PostgrestException(message: 'RAW', code: '42501'),
      ),
      'No tienes permisos para realizar esta acción.',
    );
  });
  test(
    'Antigravity: Propuesta mapeo completo editable, duraciones y filtrado exhaustivo',
    () {
      final p = Propuesta.fromJson({
        'id': 42,
        'nombre': 'Piña Colada',
        'categoria_id': 5,
        'unidad_base': 'ml',
        'es_perecible': false,
        'vida_util_dias_ref': 30,
        'hogar_ref': 'hogar_fedcba',
        'propuesto_en': '2026-11-05T08:30:00Z',
      });

      expect(p.id, 42);
      expect(p.nombre, 'Piña Colada');
      expect(p.categoriaId, 5);
      expect(p.unidadBase, 'ml');
      expect(p.esPerecible, isFalse);
      expect(p.vidaUtilDiasRef, 30);
      expect(p.hogarRef, 'hogar_fedcba');
      expect(fecha(p.propuestoEn), '05-11-2026');

      final a = p.editable;
      expect(a.id, 42);
      expect(a.nombre, 'Piña Colada');
      expect(a.categoriaId, 5);
      expect(a.unidadBase, 'ml');
      expect(a.esPerecible, isFalse);
      expect(a.vidaUtilDiasRef, 30);
      expect(a.activo, isTrue);
      expect(a.unidadLabel, 'Mililitro');

      // Filtrado exhaustivo con tildes, mayúsculas y query vacío
      final lista = [
        p,
        Propuesta.fromJson(propuestaJson(1)),
      ];
      expect(filtrarPropuestas(lista, '').length, 2);
      expect(filtrarPropuestas(lista, 'PINA').single.id, 42);
      expect(filtrarPropuestas(lista, 'sugerido').single.id, 1);
      expect(filtrarPropuestas(lista, 'inexistente'), isEmpty);

      // Error genérico sin código Postgrest
      expect(
        AppError.propuestoMessage(Exception('Fallo de red inesperado')),
        'Ocurrió un problema. Inténtalo nuevamente.',
      );
    },
  );
}
