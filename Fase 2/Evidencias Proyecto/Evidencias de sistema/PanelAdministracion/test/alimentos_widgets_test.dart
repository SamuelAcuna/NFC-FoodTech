import 'package:admin/features/alimentos/data/alimentos_repository.dart';
import 'package:admin/features/alimentos/presentation/alimento_dialog.dart';
import 'package:admin/features/alimentos/presentation/alimentos_tab.dart';
import 'package:admin/features/auth/presentation/auth_providers.dart';
import 'package:admin/features/categorias/data/categorias_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_alimentos_repository.dart';
import 'fake_auth_repository.dart';
import 'fake_categorias_repository.dart';

Future<void> openFoods(
  WidgetTester tester,
  FakeAlimentosRepository repo, {
  double width = 1400,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        alimentosRepositoryProvider.overrideWithValue(repo),
        categoriasRepositoryProvider.overrideWithValue(
          FakeCategoriasRepository(),
        ),
        adminContextProvider.overrideWithValue(adminContext()),
      ],
      child: const MaterialApp(home: Scaffold(body: AlimentosTab())),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> chooseState(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Lista, total real y filtro inicial Activos', (tester) async {
    await openFoods(tester, FakeAlimentosRepository());
    expect(find.text('3 alimentos en el catálogo'), findsOneWidget);
    expect(find.text('Plátano'), findsOneWidget);
    expect(find.text('Arroz'), findsNothing);
    expect(find.text('Frutas › Cítricos'), findsOneWidget);
    expect(find.text('Según categoría'), findsOneWidget);
    expect(find.text('5 días'), findsOneWidget);
    expect(find.text('Unidad'), findsOneWidget);
    expect(find.text('Gramo'), findsOneWidget);
    expect(find.text('Propuesto'), findsNothing);
    await chooseState(tester, 'Inactivos');
    expect(find.text('Arroz'), findsOneWidget);
    expect(find.text('Plátano'), findsNothing);
    await chooseState(tester, 'Todos');
    expect(find.text('Arroz'), findsOneWidget);
    expect(find.text('Plátano'), findsOneWidget);
  });
  testWidgets('Buscador sin tildes y filtro raíz con subcategorías', (
    tester,
  ) async {
    await openFoods(tester, FakeAlimentosRepository());
    await tester.enterText(
      find.byKey(const ValueKey('buscar-alimento')),
      'PLATANO',
    );
    await tester.pump();
    expect(find.text('Plátano'), findsOneWidget);
    expect(find.text('Limón'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('buscar-alimento')), '');
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Frutas').last);
    await tester.pumpAndSettle();
    expect(find.text('Limón'), findsOneWidget);
    expect(find.text('Plátano'), findsOneWidget);
  });
  testWidgets(
    'Crear valida obligatorios, trim y duración; recarga sin refrescar página',
    (tester) async {
      final repo = FakeAlimentosRepository();
      await openFoods(tester, repo);
      await tester.tap(find.text('Nuevo alimento'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pump();
      expect(
        find.text('Ingresa un nombre de 2 a 80 caracteres.'),
        findsOneWidget,
      );
      expect(find.text('Selecciona una categoría.'), findsOneWidget);
      expect(find.text('Selecciona una unidad base.'), findsOneWidget);
      expect(repo.saves, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('alimento-nombre')),
        '  Manzana  ',
      );
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
      await tester.tap(find.text('Unidad').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      await tester.enterText(
        find.byKey(const ValueKey('alimento-dias')),
        '1.5',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pump();
      expect(
        find.text('Ingresa un entero de 1 a 3650 o deja vacío.'),
        findsOneWidget,
      );
      expect(repo.saves, isEmpty);
      await tester.enterText(find.byKey(const ValueKey('alimento-dias')), '');
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();
      expect(repo.saves.single, {
        'id': null,
        'nombre': 'Manzana',
        'categoria_id': 1,
        'unidad_base': 'un',
        'es_perecible': true,
        'vida_util_dias_ref': null,
      });
      expect(find.text('Manzana'), findsOneWidget);
      expect(find.text('4 alimentos en el catálogo'), findsOneWidget);
    },
  );
  testWidgets(
    'Editar conserva categoría inactiva marcada, pero crear no la ofrece',
    (tester) async {
      final repo = FakeAlimentosRepository();
      await openFoods(tester, repo);
      await chooseState(tester, 'Inactivos');
      await tester.tap(find.byTooltip('Editar Arroz'));
      await tester.pumpAndSettle();
      expect(find.text('Verduras (inactiva)'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('alimento-nombre')),
        'Arroz integral',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();
      expect(repo.saves.single['id'], 3);
      expect(repo.saves.single['categoria_id'], 3);
      expect(repo.saves.single['es_perecible'], isFalse);
      expect(find.text('Arroz integral'), findsOneWidget);
      await tester.tap(find.text('Nuevo alimento'));
      await tester.pumpAndSettle();
      final dropdown = find.descendant(
        of: find.byType(AlimentoDialog),
        matching: find.byType(DropdownButton<int>),
      );
      expect(
        tester.widget<DropdownButton<int>>(dropdown).items!.map((i) => i.value),
        [1, 2],
      );
    },
  );
  testWidgets('Baja confirma, desaparece con Activos, Reactivar no confirma', (
    tester,
  ) async {
    final repo = FakeAlimentosRepository();
    await openFoods(tester, repo);
    await tester.tap(find.byTooltip('Dar de baja Plátano'));
    await tester.pumpAndSettle();
    expect(repo.toggles, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Dar de baja'));
    await tester.pumpAndSettle();
    expect(repo.toggles, [false]);
    expect(find.text('Plátano'), findsNothing);
    await chooseState(tester, 'Inactivos');
    expect(find.text('Plátano'), findsOneWidget);
    await tester.tap(find.byTooltip('Reactivar Plátano'));
    await tester.pumpAndSettle();
    expect(repo.toggles, [false, true]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Plátano'), findsNothing);
  });
  testWidgets(
    'Duplicado en diálogo y FK al borrar usan mensajes exactos, sin texto crudo',
    (tester) async {
      final repo = FakeAlimentosRepository()
        ..saveError = const PostgrestException(
          message: 'RAW SQL SECRET',
          code: '23505',
        );
      await openFoods(tester, repo);
      await tester.tap(find.byTooltip('Editar Plátano'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ya existe un alimento con ese nombre en el catálogo.'),
        findsOneWidget,
      );
      expect(find.textContaining('RAW'), findsNothing);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      repo.deleteError = const PostgrestException(
        message: 'RAW PRIVATE TABLE',
        code: '23503',
      );
      await tester.tap(find.byTooltip('Eliminar Plátano'));
      await tester.pumpAndSettle();
      expect(repo.deletes, 0);
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'No se puede eliminar: el alimento está en uso en despensas o listas de compra. Dalo de baja en su lugar.',
        ),
        findsOneWidget,
      );
      expect(find.text('Plátano'), findsOneWidget);
      expect(find.textContaining('RAW'), findsNothing);
    },
  );
  testWidgets('Eliminar sin relaciones se refleja sin recargar', (
    tester,
  ) async {
    final repo = FakeAlimentosRepository();
    await openFoods(tester, repo);
    await tester.tap(find.byTooltip('Eliminar Limón'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();
    expect(repo.deletes, 1);
    expect(find.text('Limón'), findsNothing);
    expect(find.text('2 alimentos en el catálogo'), findsOneWidget);
  });
  testWidgets('Pantalla a 500 px permite tabla horizontal sin overflow', (
    tester,
  ) async {
    await openFoods(tester, FakeAlimentosRepository(), width: 500);
    expect(find.text('Nuevo alimento'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Antigravity: Cancelar confirmación no ejecuta acción y filtro vacío muestra mensaje',
    (tester) async {
      final repo = FakeAlimentosRepository();
      await openFoods(tester, repo);

      // Cancelar dar de baja
      await tester.tap(find.byTooltip('Dar de baja Plátano'));
      await tester.pumpAndSettle();
      expect(find.text('¿Dar de baja «Plátano»?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.toggles, isEmpty);
      expect(find.text('Plátano'), findsOneWidget);

      // Cancelar eliminar
      await tester.tap(find.byTooltip('Eliminar Plátano'));
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar «Plátano» del catálogo?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.deletes, 0);
      expect(find.text('Plátano'), findsOneWidget);

      // Búsqueda sin coincidencias muestra mensaje vacío
      await tester.enterText(
        find.byKey(const ValueKey('buscar-alimento')),
        'InexistenteXYZ',
      );
      await tester.pump();
      expect(find.text('No hay alimentos para mostrar.'), findsOneWidget);
    },
  );
}
