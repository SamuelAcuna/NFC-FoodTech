import '../../features/configuracion/presentation/configuracion_save.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../../features/auth/domain/admin_context.dart';
import '../../features/propuestos/presentation/propuestos_badge.dart';

const adminDestinations = <({String path, String title, IconData icon})>[
  (path: '/', title: 'Dashboard', icon: Icons.dashboard_outlined),
  (path: '/catalogo', title: 'Catálogo', icon: Icons.table_chart_outlined),
  (
    path: '/propuestos',
    title: 'Productos sugeridos',
    icon: Icons.check_box_outlined,
  ),
  (path: '/usuarios', title: 'Usuarios y hogares', icon: Icons.people_outline),
  (
    path: '/administradores',
    title: 'Administradores',
    icon: Icons.shield_outlined,
  ),
  (path: '/soporte', title: 'Soporte', icon: Icons.chat_bubble_outline),
  (path: '/auditoria', title: 'Auditoría y monitoreo', icon: Icons.history),
  (path: '/reportes', title: 'Reportes', icon: Icons.insights_outlined),
  (
    path: '/configuracion',
    title: 'Configuración',
    icon: Icons.settings_outlined,
  ),
];

class AdminShell extends StatelessWidget {
  const AdminShell({
    required this.location,
    required this.child,
    required this.adminContext,
    required this.userLabel,
    required this.onLogout,
    super.key,
  });
  final String location;
  final Widget child;
  final AdminContext adminContext;
  final String userLabel;
  final VoidCallback? onLogout;
  List<({String path, String title, IconData icon})> get destinations =>
      adminDestinations
          .where(
            (item) => switch (item.path) {
              '/' => true,
              '/catalogo' =>
                adminContext.puede('CATALOGO_GESTIONAR') ||
                    adminContext.puede('CATEGORIAS_GESTIONAR'),
              '/propuestos' => adminContext.puede('PROPUESTOS_REVISAR'),
              '/usuarios' =>
                adminContext.puede('USUARIOS_VER') ||
                    adminContext.puede('HOGARES_VER'),
              '/administradores' => adminContext.puede('ROLES_GESTIONAR'),
              '/soporte' => adminContext.puede('SOPORTE_GESTIONAR'),
              '/auditoria' => adminContext.puede('AUDITORIA_VER'),
              '/configuracion' => adminContext.puede('PARAMETROS_GESTIONAR'),
              '/reportes' => adminContext.puede('REPORTES_VER'),
              _ => false,
            },
          )
          .toList();
  String get initials {
    final words = userLabel
        .split(RegExp(r'[\s@._-]+'))
        .where((word) => word.isNotEmpty)
        .take(2);
    return words.map((word) => word[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final selected = adminDestinations.indexWhere(
      (item) => item.path == location,
    );
    final index = selected < 0 ? 0 : selected;
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 600;
        final expanded = constraints.maxWidth >= 1024;
        final content = Scaffold(
          drawer: mobile
              ? Drawer(width: 240, child: _sidebar(context, true, true))
              : null,
          appBar: AppBar(
            title: Text(adminDestinations[index].title),
            actions: [
              if (location == '/configuracion' &&
                  adminContext.puede('PARAMETROS_GESTIONAR'))
                const ConfiguracionSaveButton(),
            ],
            titleSpacing: mobile ? 0 : 28,
            shape: const Border(bottom: BorderSide(color: AppColors.border)),
          ),
          body: Padding(padding: const EdgeInsets.all(28), child: child),
        );
        return Row(
          children: [
            if (!mobile)
              SizedBox(
                key: ValueKey(
                  expanded ? 'expanded-sidebar' : 'collapsed-sidebar',
                ),
                width: expanded ? 240 : 72,
                child: _sidebar(context, expanded, false),
              ),
            Expanded(child: content),
          ],
        );
      },
    );
  }

  Widget _sidebar(BuildContext context, bool expanded, bool drawer) => Material(
    color: AppColors.sidebarBg,
    child: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 20 : 16,
              vertical: 22,
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.accentMint,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.shopping_bag_outlined,
                    size: 17,
                    color: AppColors.sidebarBg,
                  ),
                ),
                if (expanded) ...[
                  const SizedBox(width: 10),
                  const Flexible(
                    child: Text.rich(
                      TextSpan(
                        text: 'FoodTech ',
                        children: [
                          TextSpan(
                            text: 'Admin',
                            style: TextStyle(color: AppColors.accentMint),
                          ),
                        ],
                      ),
                      style: TextStyle(
                        color: AppColors.surfaceAlt,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: !expanded && destinations.length > 1
                ? NavigationRail(
                    backgroundColor: AppColors.sidebarBg,
                    minWidth: 72,
                    labelType: NavigationRailLabelType.none,
                    scrollable: true,
                    useIndicator: true,
                    indicatorColor: AppColors.primary,
                    indicatorShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    selectedIconTheme: const IconThemeData(
                      color: AppColors.surfaceAlt,
                      size: 17,
                    ),
                    unselectedIconTheme: const IconThemeData(
                      color: AppColors.sidebarText,
                      size: 17,
                    ),
                    selectedIndex: destinations.indexWhere(
                      (item) => item.path == location,
                    ),
                    onDestinationSelected: (index) =>
                        context.go(destinations[index].path),
                    destinations: [
                      for (final item in destinations)
                        NavigationRailDestination(
                          icon: Tooltip(
                            message: item.title,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                SizedBox(
                                  height: 30,
                                  width: 32,
                                  child: Icon(item.icon),
                                ),
                                if (item.path == '/propuestos')
                                  const Positioned(
                                    right: -12,
                                    top: -4,
                                    child: PropuestosBadge(),
                                  ),
                              ],
                            ),
                          ),
                          label: Text(item.title),
                        ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final item in destinations)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Tooltip(
                            message: expanded ? '' : item.title,
                            child: Material(
                              color: location == item.path
                                  ? AppColors.primary
                                  : AppColors.sidebarBg,
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  if (drawer) Navigator.of(context).pop();
                                  context.go(item.path);
                                },
                                child: Semantics(
                                  selected: location == item.path,
                                  button: true,
                                  label: expanded ? null : item.title,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: expanded ? 14 : 0,
                                      vertical: 11,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: expanded
                                          ? MainAxisAlignment.start
                                          : MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          item.icon,
                                          size: 17,
                                          color: location == item.path
                                              ? AppColors.surfaceAlt
                                              : AppColors.sidebarText,
                                        ),
                                        if (expanded) ...[
                                          const SizedBox(width: 12),
                                          Flexible(
                                            child: Text(
                                              item.title,
                                              style: TextStyle(
                                                color: location == item.path
                                                    ? AppColors.surfaceAlt
                                                    : AppColors.sidebarText,
                                                fontSize: 13.5,
                                                fontWeight:
                                                    location == item.path
                                                    ? FontWeight.w700
                                                    : FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          if (item.path == '/propuestos') ...[
                                            const SizedBox(width: 6),
                                            const PropuestosBadge(),
                                          ],
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 20 : 19,
              vertical: 16,
            ),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.sidebarDivider)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.surfaceAlt,
                    ),
                  ),
                ),
                if (expanded)
                  Flexible(
                    child: Padding(
                      padding: EdgeInsets.only(left: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userLabel,
                            style: TextStyle(
                              color: AppColors.surfaceAlt,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            adminContext.nombreRol,
                            style: TextStyle(
                              color: AppColors.accentMint,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: onLogout,
            icon: const Icon(Icons.logout, color: AppColors.accentMint),
          ),
        ],
      ),
    ),
  );
}
