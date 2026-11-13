import 'package:admin/features/hogares/data/hogares_repository.dart';
import 'package:admin/features/hogares/domain/hogar_resumen.dart';

import 'package:admin/features/usuarios/presentation/usuarios_hogares_page.dart';
import 'package:admin/features/auth/presentation/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_repository.dart';

class FakeHogares implements HogaresRepository {
  final searches = <String?>[];
  @override
  Future<List<HogarResumen>> listar({
    String? busqueda,
    String? actividad,
    int offset = 0,
  }) async {
    searches.add(busqueda);
    return [
      HogarResumen.fromJson({
        'hogar_ref': 'hogar_abcdef',
        'nombre': 'Hogar prueba',
        'integrantes': 2,
        'invitados': 1,
        'adultos': 2,
        'menores': 0,
        'creado_en': '2026-10-20',
        'movimientos_30d': 25,
        'ultimo_movimiento': null,
        'productos_disponibles': 4,
        'nivel_actividad': 'ALTA',
        'total': 1,
      }),
    ];
  }
}

void main() {
  testWidgets('hogares por permiso, privacidad y debounce servidor', (t) async {
    t.view.physicalSize = const Size(1800, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final repo = FakeHogares();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          adminContextProvider.overrideWithValue(
            adminContext(permissions: {'HOGARES_VER'}),
          ),
          hogaresRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: Scaffold(body: UsuariosHogaresPage())),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Usuarios'), findsNothing);
    expect(find.text('Hogar prueba'), findsOneWidget);
    expect(
      find.text(
        'Solo se muestran datos agregados; el detalle de la despensa de cada hogar es privado.',
      ),
      findsOneWidget,
    );
    expect(find.text('Nunca'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'literal%');
    await t.pump(const Duration(milliseconds: 299));
    expect(repo.searches.length, 1);
    await t.pump(const Duration(milliseconds: 1));
    await t.pumpAndSettle();
    expect(repo.searches.last, 'literal%');
  });

  test('HogarResumen parsing completo y valores nulos', () {
    final h1 = HogarResumen.fromJson({
      'hogar_ref': 'hogar_123456',
      'nombre': 'Hogar Completo',
      'comuna': 'Providencia',
      'region': 'Metropolitana',
      'integrantes': 3,
      'invitados': 2,
      'adultos': 2,
      'menores': 1,
      'creado_en': '2026-10-15T10:00:00Z',
      'movimientos_30d': 12,
      'ultimo_movimiento': '2026-10-20T18:30:00Z',
      'productos_disponibles': 8,
      'nivel_actividad': 'MEDIA',
      'total': 42,
    });
    expect(h1.ref, 'hogar_123456');
    expect(h1.comuna, 'Providencia');
    expect(h1.region, 'Metropolitana');
    expect(h1.integrantes, 3);
    expect(h1.invitados, 2);
    expect(h1.adultos, 2);
    expect(h1.menores, 1);
    expect(h1.nivel, 'MEDIA');
    expect(h1.ultimo, isNotNull);
    expect(h1.total, 42);

    final h2 = HogarResumen.fromJson({
      'hogar_ref': 'hogar_000000',
      'nombre': 'Hogar Mínimo',
      'comuna': null,
      'region': null,
      'integrantes': 1,
      'invitados': 0,
      'adultos': null,
      'menores': null,
      'creado_en': '2026-10-01T00:00:00Z',
      'movimientos_30d': 0,
      'ultimo_movimiento': null,
      'productos_disponibles': 0,
      'nivel_actividad': 'SIN_ACTIVIDAD',
      'total': 1,
    });
    expect(h2.comuna, isNull);
    expect(h2.region, isNull);
    expect(h2.adultos, isNull);
    expect(h2.menores, isNull);
    expect(h2.ultimo, isNull);
    expect(h2.nivel, 'SIN_ACTIVIDAD');
  });

  testWidgets('muestra mensaje sin permisos cuando falta HOGARES_VER y USUARIOS_VER', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          adminContextProvider.overrideWithValue(
            adminContext(permissions: {}),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: UsuariosHogaresPage())),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.text('No tienes permisos para acceder a usuarios y hogares.'),
      findsOneWidget,
    );
  });
}
