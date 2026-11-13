import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../alimentos/presentation/alimentos_tab.dart';
import 'categorias_tab.dart';
import 'duraciones_tab.dart';

List<String> tabsVisibles(bool catalogo, bool categorias) => [
  if (catalogo) 'alimentos',
  if (categorias) ...['categorias', 'duraciones'],
];
String seleccionarTab(List<String> tabs, String? requested) =>
    tabs.contains(requested) ? requested! : tabs.first;

class CatalogoPage extends ConsumerWidget {
  const CatalogoPage({this.tab, super.key});
  final String? tab;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puede = ref.watch(puedeProvider);
    final tabs = tabsVisibles(
      puede('CATALOGO_GESTIONAR'),
      puede('CATEGORIAS_GESTIONAR'),
    );
    if (tabs.isEmpty) {
      return const Center(
        child: Text('No tienes permisos para acceder al catálogo.'),
      );
    }
    final selected = seleccionarTab(tabs, tab);
    const labels = {
      'alimentos': 'Alimentos',
      'categorias': 'Categorías',
      'duraciones': 'Duraciones referenciales',
    };
    return DefaultTabController(
      length: tabs.length,
      initialIndex: tabs.indexOf(selected),
      key: ValueKey('${tabs.join()}/$selected'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              tabs: [for (final value in tabs) Tab(text: labels[value])],
              onTap: (index) => context.go('/catalogo?tab=${tabs[index]}'),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: switch (selected) {
              'categorias' => const CategoriasTab(),
              'duraciones' => const DuracionesTab(),
              _ => const AlimentosTab(),
            },
          ),
        ],
      ),
    );
  }
}
