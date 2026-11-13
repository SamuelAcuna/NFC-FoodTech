import 'fake_auth_repository.dart';
import 'package:admin/core/theme/app_colors.dart';
import 'package:admin/core/widgets/admin_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:admin/features/auth/presentation/auth_providers.dart';
import 'package:admin/features/propuestos/data/propuestos_repository.dart';
import 'fake_propuestos_repository.dart';

Widget _buildShell({
  required String location,
  Widget child = const Text('Contenido Vista'),
}) {
  return ProviderScope(overrides: [
    adminContextProvider.overrideWithValue(adminContext()),
    propuestosRepositoryProvider.overrideWithValue(FakePropuestosRepository()),
  ], child: MaterialApp(
    home: AdminShell(
      location: location,
      adminContext: adminContext(), userLabel: 'Admin Demo', onLogout: () {},
      child: child,
    ),
  ));
}

void main() {
  group('AdminShell - responsividad y componentes visuales', () {
    testWidgets('ancho 500 px (móvil): usa Drawer y oculta sidebar fija', (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildShell(location: '/'));
      await tester.pumpAndSettle();

      // En móvil, la sidebar en la fila no existe
      expect(find.byKey(const ValueKey('expanded-sidebar')), findsNothing);
      expect(find.byKey(const ValueKey('collapsed-sidebar')), findsNothing);

      // Existe Scaffold con Drawer
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.drawer, isNotNull);
      expect(scaffold.drawer, isA<Drawer>());

      // Contenido hijo visible
      expect(find.text('Contenido Vista'), findsOneWidget);

      // Al abrir el drawer, se muestran las opciones de navegación y la marca
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('Catálogo'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.textSpan?.toPlainText().contains('FoodTech Admin') ?? false),
        ),
        findsOneWidget,
      );
    });

    testWidgets('ancho 800 px (tablet): usa NavigationRail colapsado a 72 px sin Drawer', (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildShell(location: '/catalogo'));
      await tester.pumpAndSettle();

      // No tiene Drawer en el Scaffold
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.drawer, isNull);

      // Sidebar colapsada de 72 px presente
      final sidebarFinder = find.byKey(const ValueKey('collapsed-sidebar'));
      expect(sidebarFinder, findsOneWidget);
      expect(tester.getSize(sidebarFinder).width, 72.0);

      // Contiene NavigationRail
      expect(find.byType(NavigationRail), findsOneWidget);

      // En modo colapsado no se muestra el texto completo de marca
      expect(find.text('FoodTech '), findsNothing);

      // Topbar refleja el título de la ruta
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Catálogo')),
        findsOneWidget,
      );

      // Contenido hijo visible
      expect(find.text('Contenido Vista'), findsOneWidget);
    });

    testWidgets('ancho 1200 px (escritorio): menú expandido de 240 px con marca y usuario', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildShell(location: '/usuarios'));
      await tester.pumpAndSettle();

      // No tiene Drawer
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.drawer, isNull);

      // Sidebar expandida de 240 px presente
      final sidebarFinder = find.byKey(const ValueKey('expanded-sidebar'));
      expect(sidebarFinder, findsOneWidget);
      expect(tester.getSize(sidebarFinder).width, 240.0);

      // No usa NavigationRail en modo expandido
      expect(find.byType(NavigationRail), findsNothing);

      // Contiene marca completa
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.textSpan?.toPlainText().contains('FoodTech Admin') ?? false),
        ),
        findsOneWidget,
      );

      // Contiene bloque de usuario de ejemplo
      expect(find.text('Admin Demo'), findsOneWidget);
      expect(find.text('Administrador'), findsOneWidget);
      expect(find.text('AD'), findsOneWidget);

      // Verifica ítem activo ('Usuarios y hogares')
      final activeItemFinder = find.ancestor(
        of: find.text('Usuarios y hogares'),
        matching: find.byType(Material),
      ).first;
      final materialWidget = tester.widget<Material>(activeItemFinder);
      expect(materialWidget.color, AppColors.primary);

      // Topbar muestra el título
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Usuarios y hogares')),
        findsOneWidget,
      );

      // Contenido hijo visible
      expect(find.text('Contenido Vista'), findsOneWidget);
    });
  });
}
