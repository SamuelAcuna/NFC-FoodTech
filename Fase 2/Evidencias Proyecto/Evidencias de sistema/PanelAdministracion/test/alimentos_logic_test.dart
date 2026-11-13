import 'dart:convert';
import 'dart:io';

import 'package:admin/core/errors/app_error.dart';
import 'package:admin/core/theme/app_colors.dart';
import 'package:admin/features/alimentos/data/alimentos_repository.dart';
import 'package:admin/features/alimentos/domain/alimento.dart';
import 'package:admin/features/categorias/data/categorias_repository.dart';
import 'package:admin/features/categorias/domain/categoria.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_auth_repository.dart';
import 'fake_alimentos_repository.dart';

Map<String, dynamic> foodJson(int id) => {
  'id': id,
  'nombre': 'Alimento $id',
  'categoria_id': 1,
  'vida_util_dias_ref': null,
  'unidad_base': 'ml',
  'es_perecible': true,
  'activo': false,
};
http.Response jsonResponse(Object value, [int code = 200]) => http.Response(
  jsonEncode(value),
  code,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
SupabaseClient testClient(
  Future<http.Response> Function(http.Request) handler,
) => SupabaseClient(
  'https://catalogo.example.invalid',
  'clave-ficticia-de-test',
  httpClient: MockClient((request) async {
    final response = await handler(request);
    return http.Response.bytes(
      response.bodyBytes,
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }),
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);
void main() {
  test('Alimento.fromJson: nulo, activo y nombres de unidades', () {
    final a = Alimento.fromJson(foodJson(9));
    expect(a.id, 9);
    expect(a.vidaUtilDiasRef, isNull);
    expect(a.activo, isFalse);
    expect(a.unidadLabel, 'Mililitro');
    for (final entry in {'g': 'Gramo', 'un': 'Unidad'}.entries) {
      expect(
        Alimento.fromJson({
          ...foodJson(1),
          'unidad_base': entry.key,
          'vida_util_dias_ref': 2,
        }).unidadLabel,
        entry.value,
      );
    }
  });
  test('Búsqueda ignora mayúsculas y tildes precompuestas o combinadas', () {
    expect(normalizarBusqueda('  PLÁTANO '), 'platano');
    expect(normalizarBusqueda('Pla\u0301tano'), 'platano');
    final data = FakeAlimentosRepository().items;
    expect(
      filtrarAlimentos(data, [], busqueda: 'PLATANO').single.nombre,
      'Plátano',
    );
  });
  test('Filtro raíz incluye hijas y estado por defecto solo activos', () {
    final data = FakeAlimentosRepository().items;
    const cats = [
      Categoria(id: 1, nombre: 'Frutas'),
      Categoria(id: 2, nombre: 'Cítricos', parentId: 1),
      Categoria(id: 3, nombre: 'Cereales'),
    ];
    expect(filtrarAlimentos(data, cats, categoriaId: 1).map((a) => a.id), [
      1,
      2,
    ]);
    expect(filtrarAlimentos(data, cats, categoriaId: 2).map((a) => a.id), [2]);
    expect(filtrarAlimentos(data, cats, activo: false).single.id, 3);
    expect(nombreCategoria(2, cats), 'Frutas › Cítricos');
  });
  test('Nombre obligatorio con trim y 2–80 caracteres', () {
    for (final text in [null, '', ' X ', 'a' * 81]) {
      expect(validarNombreAlimento(text), isNotNull);
    }
    expect(validarNombreAlimento('  Arroz  '), isNull);
    expect(validarNombreAlimento('a' * 80), isNull);
  });
  test(
    'Repositorio pagina catálogo global de 500 en 500 sin agregaciones',
    () async {
      final offsets = <String>[];
      final client = testClient((request) async {
        expect(request.url.path, '/rest/v1/alimento');
        final q = request.url.queryParameters;
        expect(q['hogar_id'], 'is.null');
        expect(q['order'], 'nombre.asc.nullslast,id.asc.nullslast');
        expect(q['limit'], '500');
        expect(q['select'], isNot(contains('count(')));
        offsets.add(q['offset']!);
        return jsonResponse(
          q['offset'] == '0' ? List.generate(500, foodJson) : [foodJson(500)],
        );
      });
      addTearDown(client.dispose);
      final result = await SupabaseAlimentosRepository(
        client,
        FakeAuthRepository(),
      ).listar();
      expect(result.length, 501);
      expect(offsets, ['0', '500']);
    },
  );
  test('Payload real: INSERT atribuido y UPDATE sin estado/hogar/creador; 0 filas falla', () async {
    final requests = <http.Request>[];
    final client = testClient((request) async {
      requests.add(request);
      return jsonResponse(
        request.method == 'POST' ? [] : {'id': 7},
        request.method == 'POST' ? 201 : 200,
      );
    });
    addTearDown(client.dispose);
    final auth = FakeAuthRepository();
    final repo = SupabaseAlimentosRepository(client, auth);
    await repo.guardar(
      nombre: '  Fruta  ',
      categoriaId: 1,
      unidadBase: 'un',
      esPerecible: true,
    );
    final insert = jsonDecode(requests[0].body) as Map;
    expect(insert['nombre'], 'Fruta');
    expect(insert['hogar_id'], isNull);
    expect(insert.containsKey('hogar_id'), isTrue);
    expect(insert['estado'], 'APROBADO');
    expect(insert['creado_por'], auth.userId);
    await repo.guardar(
      id: 7,
      nombre: 'Editado',
      categoriaId: 2,
      unidadBase: 'g',
      esPerecible: false,
      vidaUtilDiasRef: 4,
    );
    final update = jsonDecode(requests[1].body) as Map;
    for (final key in ['estado', 'hogar_id', 'creado_por']) {
      expect(update.containsKey(key), isFalse);
    }
    expect(requests[1].url.queryParameters['select'], 'id');
    expect(requests[1].url.queryParameters['hogar_id'], 'is.null');
    await repo.cambiarEstado(7, false);
    expect(jsonDecode(requests[2].body), {'activo': false});
    await repo.eliminar(7);
    expect(requests[3].method, 'DELETE');
    expect(requests[3].url.queryParameters['select'], 'id');
    final denied = testClient(
      (_) async =>
          jsonResponse({'code': 'PGRST116', 'message': 'RAW 0 ROWS'}, 406),
    );
    addTearDown(denied.dispose);
    await expectLater(
      SupabaseAlimentosRepository(denied, auth).cambiarEstado(7, true),
      throwsA(isA<PostgrestException>()),
    );
  });
  test('Sin usuario no se envía INSERT', () async {
    final client = testClient((_) async {
      fail('No debe enviar petición');
    });
    addTearDown(client.dispose);
    await expectLater(
      SupabaseAlimentosRepository(
        client,
        FakeAuthRepository(hasSession: false),
      ).guardar(
        nombre: 'Prueba',
        categoriaId: 1,
        unidadBase: 'g',
        esPerecible: true,
      ),
      throwsA(isA<AuthSessionMissingException>()),
    );
  });
  test('Conteo cliente pagina, filtra globales, incluye inactivos y devuelve ceros', () async {
    final offsets = <String>[];
    final client = testClient((request) async {
      final q = request.url.queryParameters;
      if (request.url.path.endsWith('/categoria')) {
        return jsonResponse([
          {'id': 1, 'nombre': 'Frutas'},
          {'id': 2, 'nombre': 'Sin alimentos'},
        ]);
      }
      expect(q['select'], 'categoria_id');
      expect(q['hogar_id'], 'is.null');
      expect(q.containsKey('activo'), isFalse);
      expect(q['limit'], '500');
      offsets.add(q['offset']!);
      return jsonResponse(
        q['offset'] == '0'
            ? List.generate(500, (_) => {'categoria_id': 1})
            : [
                {'categoria_id': 1},
              ],
      );
    });
    addTearDown(client.dispose);
    expect(await SupabaseCategoriasRepository(client).contarAlimentos(), {
      1: 501,
      2: 0,
    });
    expect(offsets, ['0', '500']);
  });
  test('Conteo vacío da cero y excepción da null', () async {
    for (final failure in [false, true]) {
      final client = testClient((request) async {
        if (request.url.path.endsWith('/categoria')) {
          return jsonResponse([
            {'id': 1, 'nombre': 'Frutas'},
          ]);
        }
        if (failure) throw http.ClientException('RAW NETWORK');
        return jsonResponse([]);
      });
      addTearDown(client.dispose);
      expect(
        await SupabaseCategoriasRepository(client).contarAlimentos(),
        failure ? null : {1: 0},
      );
    }
  });
  test(
    'Errores traducidos y token exacto sin colores manuales en auth_layout',
    () {
      expect(
        AppError.alimentoMessage(
          const PostgrestException(message: 'RAW', code: '23505'),
        ),
        'Ya existe un alimento con ese nombre en el catálogo.',
      );
      expect(
        AppError.alimentoMessage(
          const PostgrestException(message: 'RAW', code: '23503'),
          deleting: true,
        ),
        'No se puede eliminar: el alimento está en uso en despensas o listas de compra. Dalo de baja en su lugar.',
      );
      expect(
        AppError.alimentoMessage(
          const PostgrestException(message: 'RAW', code: '42501'),
        ),
        'No tienes permisos para realizar esta acción.',
      );
      expect(AppColors.gradientMid.toARGB32(), 0xFF1F3529);
      expect(
        File('lib/features/auth/presentation/auth_layout.dart')
            .readAsStringSync(),
        isNot(matches(r'\bColor\s*\(|\bColors\.')),
      );
    },
  );
  test(
    'Antigravity: Casos límite de normalización, validación y nombres de categoría',
    () {
      expect(normalizarBusqueda('Ñandú'), 'nandu');
      expect(normalizarBusqueda('PINGÜINO'), 'pinguino');
      expect(normalizarBusqueda('ÁÉÍÓÚ'), 'aeiou');
      expect(normalizarBusqueda('   '), '');

      expect(validarNombreAlimento('a'), isNotNull);
      expect(validarNombreAlimento('ab'), isNull);
      expect(validarNombreAlimento('a' * 80), isNull);
      expect(validarNombreAlimento('a' * 81), isNotNull);
      expect(validarNombreAlimento('   ab   '), isNull);
      expect(validarNombreAlimento('   a   '), isNotNull);

      const cats = [
        Categoria(id: 10, nombre: 'Lácteos'),
        Categoria(id: 11, nombre: 'Quesos', parentId: 10),
      ];
      expect(nombreCategoria(99, cats), 'Categoría no disponible');
      expect(nombreCategoria(10, cats), 'Lácteos');
      expect(nombreCategoria(11, cats), 'Lácteos › Quesos');

      final alimentoRaro = Alimento.fromJson({
        ...foodJson(99),
        'unidad_base': 'litro',
      });
      expect(alimentoRaro.unidadLabel, 'litro');

      final data = FakeAlimentosRepository().items;
      final hojas = filtrarAlimentos(data, cats, categoriaId: 99);
      expect(hojas, isEmpty);
    },
  );
}
