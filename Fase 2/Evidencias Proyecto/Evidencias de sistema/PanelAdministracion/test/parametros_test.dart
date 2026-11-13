import 'package:admin/features/configuracion/domain/parametro.dart';
import 'package:admin/features/configuracion/data/parametros_repository.dart';
import 'package:admin/features/configuracion/presentation/configuracion_page.dart';
import 'package:admin/features/configuracion/presentation/configuracion_save.dart';
import 'package:admin/features/auth/presentation/auth_providers.dart';
import 'package:admin/core/errors/app_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_repository.dart';

class FakeParametros implements ParametrosRepository {
  final calls = <String>[];
  @override
  Future<List<Parametro>> listar() async => [
    for (final e in {
      'hogar.max_miembros': ('8', 'ENTERO'),
      'notif.hora_envio': ('09:00', 'TEXTO'),
      'otro': ('original', 'TEXTO'),
    }.entries)
      Parametro.fromJson({
        'clave': e.key,
        'valor': e.value.$1,
        'tipo_dato': e.value.$2,
        'actualizado_en': '2026-10-20T12:00:00Z',
      }),
  ];
  @override
  Future<void> actualizar(String clave, String valor) async {
    calls.add(clave);
    if (clave == 'otro') {
      throw const PostgrestException(message: 'SQL privado', code: 'XX000');
    }
  }
}

void main() {
  test('validaciones de tipos, límites, hora y canales', () {
    for (final c in [
      ('x', 'ENTERO', '1.5'),
      ('x', 'DECIMAL', '1,5'),
      ('x', 'BOOLEANO', 'TRUE'),
      ('x', 'JSON', '{'),
      ('x', 'TEXTO', ''),
      ('hogar.max_miembros', 'ENTERO', '0'),
      ('hogar.invitacion_vigencia_horas', 'ENTERO', '721'),
      ('notif.vencimiento.dias_anticipacion', 'ENTERO', '31'),
      ('notif.hora_envio', 'TEXTO', '24:00'),
      ('notif.vencimiento.canales', 'JSON', '[]'),
      ('notif.vencimiento.canales', 'JSON', '["PUSH","PUSH"]'),
      ('notif.vencimiento.canales', 'JSON', '["SMS"]'),
      ('notif.vencimiento.canales', 'JSON', '{}'),
    ]) {
      expect(
        parametroMessages,
        contains(validateParametro(c.$1, c.$2, c.$3)),
        reason: '${c.$1}: ${c.$3}',
      );
    }
    expect(validateParametro('hogar.max_miembros', 'ENTERO', '20'), isNull);
    expect(validateParametro('notif.hora_envio', 'TEXTO', '23:59'), isNull);
    expect(
      validateParametro('a.canales', 'JSON', '["EMAIL","IN_APP"]'),
      isNull,
    );
    expect(
      AppError.businessMessage(
        const PostgrestException(message: 'SQL privado', code: 'P0001'),
        parametroMessages,
      ),
      isNot(contains('SQL privado')),
    );
  });
  testWidgets('guarda solo cambios y resume éxito y fallo sin exponer SQL', (
    t,
  ) async {
    final repo = FakeParametros();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          adminContextProvider.overrideWithValue(adminContext()),
          parametrosRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(
          home: Scaffold(
            appBar: null,
            body: Column(
              children: [
                ConfiguracionSaveButton(),
                Expanded(child: ConfiguracionPage()),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Otros parámetros'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextFormField, '8'), '10');
    await t.enterText(
      find.widgetWithText(TextFormField, 'original'),
      'modificado',
    );
    await t.tap(find.text('Guardar cambios'));
    await t.pumpAndSettle();
    expect(repo.calls, ['hogar.max_miembros', 'otro']);
    expect(
      find.textContaining('Guardadas: hogar.max_miembros. Fallaron: otro:'),
      findsOneWidget,
    );
    expect(find.textContaining('SQL privado'), findsNothing);
    await t.tap(find.text('Guardar cambios'));
    await t.pumpAndSettle();
    expect(repo.calls, ['hogar.max_miembros', 'otro', 'otro']);
  });
  test('normalizeParametro y límites válidos', () {
    expect(normalizeParametro('ENTERO', '  42  '), '42');
    expect(normalizeParametro('TEXTO', '  hola  '), 'hola');
    expect(normalizeParametro('JSON', ' { "b": 2, "a": 1 } '), '{"b":2,"a":1}');

    expect(validateParametro('notif.vencimiento.dias_anticipacion', 'ENTERO', '0'), isNull);
    expect(validateParametro('notif.vencimiento.dias_anticipacion', 'ENTERO', '30'), isNull);
    expect(validateParametro('hogar.max_miembros', 'ENTERO', '1'), isNull);
    expect(validateParametro('hogar.max_miembros', 'ENTERO', '20'), isNull);
    expect(validateParametro('hogar.invitacion_vigencia_horas', 'ENTERO', '1'), isNull);
    expect(validateParametro('hogar.invitacion_vigencia_horas', 'ENTERO', '720'), isNull);
    expect(validateParametro('notif.hora_envio', 'TEXTO', '00:00'), isNull);
    expect(validateParametro('notif.hora_envio', 'TEXTO', '12:00'), isNull);
  });
  testWidgets('pantalla sin permiso PARAMETROS_GESTIONAR', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          adminContextProvider.overrideWithValue(
            adminContext(permissions: {}),
          ),
          parametrosRepositoryProvider.overrideWithValue(FakeParametros()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ConfiguracionPage()),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.text('No tienes permisos para acceder a configuración.'),
      findsOneWidget,
    );
  });
}
