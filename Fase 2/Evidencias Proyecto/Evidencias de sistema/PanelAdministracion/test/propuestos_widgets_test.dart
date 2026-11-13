import 'package:admin/features/dashboard/data/dashboard_repository.dart';
import 'fake_dashboard_repository.dart';
import 'package:admin/app.dart';
import 'package:admin/features/alimentos/presentation/alimento_dialog.dart';
import 'package:admin/features/alimentos/presentation/alimentos_providers.dart';
import 'package:admin/features/auth/data/auth_repository.dart';
import 'package:admin/features/auth/presentation/auth_providers.dart';
import 'package:admin/features/categorias/data/categorias_repository.dart';
import 'package:admin/features/propuestos/data/propuestos_repository.dart';
import 'package:admin/features/propuestos/presentation/propuestos_badge.dart';
import 'package:admin/features/propuestos/presentation/propuestos_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_auth_repository.dart';
import 'fake_categorias_repository.dart';
import 'fake_propuestos_repository.dart';

Future<void> openPropuestos(
  WidgetTester tester,
  FakePropuestosRepository repo, {
  Set<String> permissions = allPermissions,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
    dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
        adminContextProvider.overrideWithValue(
          adminContext(permissions: permissions),
        ),
        propuestosRepositoryProvider.overrideWithValue(repo),
        categoriasRepositoryProvider.overrideWithValue(
          FakeCategoriasRepository(),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              PropuestosBadge(),
              Expanded(child: PropuestosPage()),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> main() async {
  await initializeDateFormatting('es_CL');
  testWidgets(
    'Lista banner seudónimo fecha y buscador, sin datos privados ni Marca',
    (tester) async {
      final repo = FakePropuestosRepository();
      await openPropuestos(tester, repo);
      expect(
        find.text(
          '1 productos propuestos por hogares esperan revisión antes de aparecer en el catálogo.',
        ),
        findsOneWidget,
      );
      expect(find.text('Frutas › Cítricos'), findsOneWidget);
      expect(find.text('hogar_abcdef'), findsOneWidget);
      expect(find.text('19-10-2026'), findsOneWidget);
      expect(find.text('Marca'), findsNothing);
      expect(find.byKey(const ValueKey('propuestos-badge')), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'PLATANO');
      await tester.pump();
      expect(find.text('Plátano sugerido'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'otro');
      await tester.pump();
      expect(find.text('Plátano sugerido'), findsNothing);
    },
  );
  testWidgets(
    'Aprobación reutiliza formulario precargado y envía campos corregidos',
    (tester) async {
      final repo = FakePropuestosRepository();
      await openPropuestos(tester, repo);
      await tester.tap(find.text('Aprobar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlimentoDialog), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('alimento-nombre')),
            )
            .controller!
            .text,
        'Plátano sugerido',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('alimento-dias')))
            .controller!
            .text,
        '5',
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      await tester.enterText(
        find.byKey(const ValueKey('alimento-nombre')),
        '  Plátano editado  ',
      );
      await tester.enterText(find.byKey(const ValueKey('alimento-dias')), '7');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      final dialog = find.byType(AlimentoDialog);
      await tester.tap(
        find.descendant(
          of: dialog,
          matching: find.byType(DropdownButtonFormField<int>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Frutas').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: dialog,
          matching: find.byType(DropdownButtonFormField<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gramo').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: dialog,
          matching: find.widgetWithText(FilledButton, 'Aprobar'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.approvals.single, {
        'p_id': 10,
        'p_nombre': 'Plátano editado',
        'p_categoria_id': 1,
        'p_unidad_base': 'g',
        'p_es_perecible': false,
        'p_vida_util_dias_ref': 7,
      });
      expect(
        find.text('No hay productos pendientes de revisión.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('propuestos-badge')), findsNothing);
      expect(repo.countCalls, greaterThan(1));
    },
  );
  testWidgets('Rechazo requiere confirmación y recarga listado/badge', (
    tester,
  ) async {
    final repo = FakePropuestosRepository();
    await openPropuestos(tester, repo);
    await tester.tap(find.text('Rechazar'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'El producto seguirá disponible solo para el hogar que lo propuso.',
      ),
      findsOneWidget,
    );
    expect(repo.rejections, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Rechazar'));
    await tester.pumpAndSettle();
    expect(repo.rejections, [10]);
    expect(
      find.text('No hay productos pendientes de revisión.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('propuestos-badge')), findsNothing);
  });
  testWidgets(
    'Duplicado no cierra diálogo ni elimina propuesta; mensaje saneado',
    (tester) async {
      final repo = FakePropuestosRepository()
        ..approveError = const PostgrestException(
          message: 'RAW PRIVATE',
          code: '23505',
        );
      await openPropuestos(tester, repo);
      await tester.tap(find.text('Aprobar'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlimentoDialog),
          matching: find.widgetWithText(FilledButton, 'Aprobar'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Ya existe un alimento con ese nombre en el catálogo. Cámbialo o rechaza la propuesta.',
        ),
        findsOneWidget,
      );
      expect(repo.items.length, 1);
      expect(find.byType(AlimentoDialog), findsOneWidget);
      expect(find.textContaining('RAW'), findsNothing);
    },
  );
  testWidgets('P0001 de negocio visible tal cual en rechazo', (tester) async {
    final repo = FakePropuestosRepository()
      ..rejectError = const PostgrestException(
        message: 'El producto ya no está pendiente de revisión.',
        code: 'P0001',
      );
    await openPropuestos(tester, repo);
    await tester.tap(find.text('Rechazar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Rechazar'));
    await tester.pumpAndSettle();
    expect(
      find.text('El producto ya no está pendiente de revisión.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'Cero, error o falta de permiso ocultan badge; sin permiso no llama RPC',
    (tester) async {
      for (final mode in ['zero', 'error', 'denied']) {
        final repo = FakePropuestosRepository();
        if (mode == 'zero') repo.items = [];
        if (mode == 'error') repo.countError = Exception('RAW COUNT');
        await openPropuestos(
          tester,
          repo,
          permissions: mode == 'denied' ? {} : allPermissions,
        );
        expect(find.byKey(const ValueKey('propuestos-badge')), findsNothing);
        if (mode == 'denied') {
          expect(repo.countCalls, 0);
          expect(repo.listCalls, 0);
        }
        if (mode == 'zero') {
          expect(
            find.text('No hay productos pendientes de revisión.'),
            findsOneWidget,
          );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );
  testWidgets(
    'Volver a la página refresca el badge sin polling e invalida alimentos al aprobar',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakePropuestosRepository();
      final auth = FakeAuthRepository();
      addTearDown(auth.events.close);
      var foodLoads = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
    dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
            authRepositoryProvider.overrideWithValue(auth),
            propuestosRepositoryProvider.overrideWithValue(repo),
            categoriasRepositoryProvider.overrideWithValue(
              FakeCategoriasRepository(),
            ),
            catalogoAlimentosProvider.overrideWith((ref) {
              foodLoads++;
              return const CatalogoAlimentos([], []);
            }),
          ],
          child: const AdminApp(),
        ),
      );
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(Scaffold).first);
      final container = ProviderScope.containerOf(element);
      final subscription = container.listen(
        catalogoAlimentosProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await tester.pumpAndSettle();
      final router = GoRouter.of(element);
      router.go('/propuestos');
      await tester.pumpAndSettle();
      final before = repo.countCalls;
      await tester.pump(const Duration(seconds: 30));
      expect(repo.countCalls, before);
      router.go('/');
      await tester.pumpAndSettle();
      router.go('/propuestos');
      await tester.pumpAndSettle();
      expect(repo.countCalls, greaterThan(before));
      final foodBefore = foodLoads;
      await tester.ensureVisible(find.text('Aprobar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aprobar'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlimentoDialog),
          matching: find.widgetWithText(FilledButton, 'Aprobar'),
        ),
      );
      await tester.pumpAndSettle();
      expect(foodLoads, greaterThan(foodBefore));
    },
  );
  testWidgets(
    'Antigravity: Cancelar diálogo de rechazo no ejecuta acción',
    (tester) async {
      final repo = FakePropuestosRepository();
      await openPropuestos(tester, repo);
      await tester.tap(find.text('Rechazar'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'El producto seguirá disponible solo para el hogar que lo propuso.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.rejections, isEmpty);
      expect(find.text('Plátano sugerido'), findsOneWidget);
    },
  );
}
