import 'package:admin/features/dashboard/data/dashboard_repository.dart';
import 'fake_dashboard_repository.dart';
import 'package:admin/features/propuestos/data/propuestos_repository.dart';
import 'fake_propuestos_repository.dart';
import 'package:admin/features/alimentos/data/alimentos_repository.dart';
import 'fake_alimentos_repository.dart';
import 'package:admin/app.dart';
import 'package:admin/features/auth/data/auth_repository.dart';
import 'package:admin/features/auth/presentation/auth_providers.dart';
import 'package:admin/features/categorias/data/categorias_repository.dart';
import 'package:admin/features/categorias/presentation/catalogo_page.dart';
import 'package:admin/features/categorias/presentation/categoria_dialog.dart';
import 'package:admin/features/categorias/presentation/duraciones_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_auth_repository.dart';
import 'fake_categorias_repository.dart';

Future<GoRouter> openCatalog(
  WidgetTester tester,
  FakeCategoriasRepository repo, {
  String query = 'categorias',
  Set<String> permissions = allPermissions,
  double width = 1200,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/catalogo?tab=$query',
    routes: [
      GoRoute(
        path: '/catalogo',
        builder: (_, state) =>
            Scaffold(body: CatalogoPage(tab: state.uri.queryParameters['tab'])),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
    dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
        categoriasRepositoryProvider.overrideWithValue(repo),
        alimentosRepositoryProvider.overrideWithValue(FakeAlimentosRepository()),
        propuestosRepositoryProvider.overrideWithValue(FakePropuestosRepository()),
        adminContextProvider.overrideWithValue(
          adminContext(permissions: permissions),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets(
    'Categorías filtra por nombre, muestra árbol y conteos desconocidos',
    (tester) async {
      final repo = FakeCategoriasRepository();
      await openCatalog(tester, repo);
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('—'), findsNWidgets(3));
      expect(find.text('Activa'), findsNWidgets(2));
      expect(find.text('Inactiva'), findsOneWidget);
      final parentY = tester.getTopLeft(find.text('Frutas')).dy;
      final childPos = tester.getTopLeft(find.text('Cítricos'));
      expect(childPos.dy, greaterThan(parentY));
      expect(
        childPos.dx,
        greaterThan(tester.getTopLeft(find.text('Frutas')).dx),
      );
      await tester.enterText(find.byType(TextField), 'CÍTR');
      await tester.pump();
      expect(find.text('Frutas'), findsNothing);
      expect(find.text('Cítricos'), findsOneWidget);
    },
  );
  testWidgets('Crear y editar categoría validan nombre y recargan tabla', (
    tester,
  ) async {
    final repo = FakeCategoriasRepository();
    await openCatalog(tester, repo);
    await tester.tap(find.text('Nueva categoría'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(
      find.text('Ingresa un nombre de 2 a 60 caracteres.'),
      findsOneWidget,
    );
    expect(repo.saves, 0);
    await tester.enterText(find.byType(TextFormField), 'Semillas');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Semillas'), findsOneWidget);
    expect(repo.saves, 1);
    await tester.tap(find.byTooltip('Editar Semillas'));
    await tester.pumpAndSettle();
    expect(find.byType(CategoriaDialog), findsOneWidget);
    final parentField = tester.widget<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    );
    expect(parentField.initialValue, isNull);
    await tester.enterText(find.byType(TextFormField), 'Semillas varias');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Semillas varias'), findsOneWidget);
    expect(repo.saves, 2);
  });
  testWidgets('Padres del diálogo: solo raíces y nunca la misma categoría', (
    tester,
  ) async {
    final repo = FakeCategoriasRepository();
    await openCatalog(tester, repo);
    await tester.tap(find.byTooltip('Editar Frutas'));
    await tester.pumpAndSettle();
    final dropdown = tester.widget<DropdownButton<int>>(
      find.byType(DropdownButton<int>),
    );
    // Sin padre o Verduras: excluye tanto Frutas (ella misma) como Cítricos (hija).
    expect(dropdown.items!.map((item) => item.value), [null, 3]);
  });
  testWidgets(
    'Activar/desactivar y borrar sin relaciones actualizan el listado',
    (tester) async {
      final repo = FakeCategoriasRepository();
      await openCatalog(tester, repo);
      await tester.tap(find.byTooltip('Desactivar Frutas'));
      await tester.pumpAndSettle();
      expect(repo.items.first.activa, isFalse);
      expect(find.byTooltip('Activar Frutas'), findsOneWidget);
      await tester.tap(find.byTooltip('Activar Frutas'));
      await tester.pumpAndSettle();
      expect(repo.items.first.activa, isTrue);
      await tester.tap(find.byTooltip('Eliminar Verduras'));
      await tester.pumpAndSettle();
      expect(repo.deletes, 0);
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      expect(repo.deletes, 1);
      expect(find.text('Verduras'), findsNothing);
    },
  );
  testWidgets('FK al borrar mantiene datos y muestra mensaje exacto saneado', (
    tester,
  ) async {
    final repo = FakeCategoriasRepository()
      ..deleteError = const PostgrestException(
        message: 'RAW INTERNAL',
        code: '23503',
      );
    await openCatalog(tester, repo);
    await tester.tap(find.byTooltip('Eliminar Frutas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No se puede eliminar: la categoría tiene alimentos o subcategorías. Desactívala en su lugar.',
      ),
      findsOneWidget,
    );
    expect(find.text('Frutas'), findsOneWidget);
    expect(repo.items.length, 3);
    expect(find.textContaining('RAW'), findsNothing);
  });
  testWidgets(
    'Duraciones guarda tres columnas y vacío como null; valida antes de escribir',
    (tester) async {
      final repo = FakeCategoriasRepository();
      await openCatalog(tester, repo, query: 'duraciones');
      expect(
        find.text(
          'Duración referencial: se usa solo para recordatorios, no es una fecha de vencimiento exacta.',
        ),
        findsOneWidget,
      );
      final row = find.byType(DuracionRow).first;
      final fields = find.descendant(
        of: row,
        matching: find.byType(TextFormField),
      );
      await tester.enterText(fields.at(0), '3651');
      await tester.enterText(fields.at(1), '1.5');
      await tester.tap(
        find.descendant(of: row, matching: find.text('Guardar')),
      );
      await tester.pump();
      expect(repo.durationSaves, 0);
      expect(
        find.text('Ingresa un entero de 1 a 3650 o deja vacío.'),
        findsNWidgets(2),
      );
      await tester.enterText(fields.at(0), '1');
      await tester.enterText(fields.at(1), '3650');
      await tester.enterText(fields.at(2), '');
      await tester.tap(
        find.descendant(of: row, matching: find.text('Guardar')),
      );
      await tester.pumpAndSettle();
      expect(repo.durationSaves, 1);
      final c = repo.items.first;
      expect(
        [c.despensaDias, c.refrigeradorDias, c.congeladorDias],
        [1, 3650, null],
      );
      final reloaded = find.descendant(
        of: find.byType(DuracionRow).first,
        matching: find.byType(TextFormField),
      );
      expect(
        tester.widget<TextFormField>(reloaded.at(0)).controller!.text,
        '1',
      );
      expect(
        tester.widget<TextFormField>(reloaded.at(1)).controller!.text,
        '3650',
      );
      expect(tester.widget<TextFormField>(reloaded.at(2)).controller!.text, '');
    },
  );
  testWidgets('Tabs respetan permisos y query; click cambia la URL', (
    tester,
  ) async {
    final repo = FakeCategoriasRepository();
    final router = await openCatalog(
      tester,
      repo,
      query: 'duraciones',
      permissions: {'CATEGORIAS_GESTIONAR'},
    );
    expect(find.text('Alimentos'), findsNothing);
    expect(find.byType(DuracionesTab), findsOneWidget);
    await tester.tap(find.text('Categorías'));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.queryParameters['tab'],
      'categorias',
    );
    expect(find.byType(DataTable), findsOneWidget);
  });
  testWidgets(
    'Solo catálogo muestra alimentos y sin permisos no carga datos',
    (tester) async {
      final repo = FakeCategoriasRepository();
      await openCatalog(
        tester,
        repo,
        query: 'categorias',
        permissions: {'CATALOGO_GESTIONAR'},
      );
      expect(find.text('3 alimentos en el catálogo'), findsOneWidget);
      expect(find.text('Categorías'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await openCatalog(tester, repo, permissions: {});
      expect(
        find.text('No tienes permisos para acceder al catálogo.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'Recarga de ruta con tab conserva destino durante validación de sesión',
    (tester) async {
      final repo = FakeCategoriasRepository();
      final auth = FakeAuthRepository();
      addTearDown(auth.events.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
    dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
            authRepositoryProvider.overrideWithValue(auth),
            categoriasRepositoryProvider.overrideWithValue(repo),
        alimentosRepositoryProvider.overrideWithValue(FakeAlimentosRepository()),
        propuestosRepositoryProvider.overrideWithValue(FakePropuestosRepository()),
          ],
          child: const AdminApp(),
        ),
      );
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      router.go('/catalogo?tab=duraciones');
      await tester.pumpAndSettle();
      await container.read(authControllerProvider).refresh();
      await tester.pumpAndSettle();
      expect(find.byType(DuracionesTab), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/catalogo?tab=duraciones',
      );
    },
  );
}
