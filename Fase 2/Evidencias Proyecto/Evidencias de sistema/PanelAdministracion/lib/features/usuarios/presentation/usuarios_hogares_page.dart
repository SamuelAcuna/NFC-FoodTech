import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../hogares/presentation/hogares_tab.dart';
import 'usuarios_page.dart';

class UsuariosHogaresPage extends ConsumerWidget {
  const UsuariosHogaresPage({this.tab, super.key});
  final String? tab;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final can = ref.watch(puedeProvider);
    final tabs = [
      if (can('USUARIOS_VER')) 'usuarios',
      if (can('HOGARES_VER')) 'hogares',
    ];
    if (tabs.isEmpty) {
      return const Center(
        child: Text('No tienes permisos para acceder a usuarios y hogares.'),
      );
    }
    final selected = tabs.contains(tab) ? tab! : tabs.first;
    return DefaultTabController(
      key: ValueKey('${tabs.join()}/$selected'),
      length: tabs.length,
      initialIndex: tabs.indexOf(selected),
      child: Column(
        children: [
          TabBar(
            tabs: [
              for (final t in tabs)
                Tab(
                  text: t == 'usuarios'
                      ? 'Usuarios'
                      : 'Hogares (${ref.watch(hogaresTotalProvider)})',
                ),
            ],
            onTap: (i) => context.go('/usuarios?tab=${tabs[i]}'),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: selected == 'usuarios'
                ? const UsuariosPage()
                : const HogaresTab(),
          ),
        ],
      ),
    );
  }
}
