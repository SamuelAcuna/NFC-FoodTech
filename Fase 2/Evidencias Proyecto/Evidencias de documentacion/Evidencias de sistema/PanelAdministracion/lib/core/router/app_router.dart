import '../../features/reportes/presentation/reportes_page.dart';
import '../../features/configuracion/presentation/configuracion_page.dart';
import '../../features/administradores/presentation/administradores_page.dart';
import '../../features/soporte/presentation/soporte_page.dart';
import '../../features/usuarios/presentation/usuarios_hogares_page.dart';
import '../../features/auditoria/presentation/auditoria_page.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/mfa_enroll_page.dart';
import '../../features/auth/presentation/mfa_verify_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/categorias/presentation/catalogo_page.dart';
import '../../features/propuestos/presentation/propuestos_page.dart';
import '../widgets/admin_shell.dart';
import 'auth_redirect.dart';

GoRouter createAppRouter(AuthController auth) => GoRouter(
  refreshListenable: auth,
  redirect: (context, state) {
    final redirect = resolverRedireccion(
      auth.ready && auth.hasSession,
      auth.aal,
      auth.factores,
      auth.ready ? auth.contexto : null,
      state.uri.path,
    );
    final requested = state.uri.queryParameters['from'];
    final parsed = requested == null ? null : Uri.tryParse(requested);
    final from =
        parsed != null &&
            !parsed.hasScheme &&
            !parsed.hasAuthority &&
            adminDestinations.any((item) => item.path == parsed.path)
        ? parsed.toString()
        : adminDestinations.any((item) => item.path == state.uri.path)
        ? state.uri.toString()
        : null;
    if (redirect == '/' && from != null) return from;
    if (redirect != null &&
        from != null &&
        (redirect == '/login' || redirect.startsWith('/mfa/'))) {
      return Uri(path: redirect, queryParameters: {'from': from}).toString();
    }
    return redirect;
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
    GoRoute(
      path: '/mfa/enrolar',
      builder: (context, state) => const MfaEnrollPage(),
    ),
    GoRoute(
      path: '/mfa/verificar',
      builder: (context, state) => const MfaVerifyPage(),
    ),
    ShellRoute(
      builder: (context, state, child) => auth.canEnter
          ? AdminShell(
              location: state.uri.path,
              adminContext: auth.contexto!,
              userLabel: auth.repository.userLabel,
              onLogout: auth.busy ? null : auth.logout,
              child: child,
            )
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
      routes: [
        for (final item in adminDestinations)
          GoRoute(
            path: item.path,
            builder: (context, state) => item.path == '/'
                ? const DashboardPage()
                : item.path == '/catalogo'
                ? CatalogoPage(tab: state.uri.queryParameters['tab'])
                : item.path == '/propuestos'
                ? const PropuestosPage()
                : item.path == '/auditoria'
                ? const AuditoriaPage()
                : item.path == '/usuarios'
                ? UsuariosHogaresPage(tab: state.uri.queryParameters['tab'])
                : item.path == '/soporte'
                ? const SoportePage()
                : item.path == '/administradores'
                ? const AdministradoresPage()
                : item.path == '/configuracion'
                ? const ConfiguracionPage()
                : item.path == '/reportes'
                ? const ReportesPage()
                : const SizedBox.shrink(),
          ),
      ],
    ),
  ],
);
