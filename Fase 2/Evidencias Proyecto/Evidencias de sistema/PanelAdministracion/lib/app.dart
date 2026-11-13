import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/presentation/auth_providers.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class AdminApp extends ConsumerStatefulWidget {
  const AdminApp({this.configurationError, super.key});
  final String? configurationError;

  @override
  ConsumerState<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends ConsumerState<AdminApp> {
  GoRouter? router;

  @override
  void dispose() {
    router?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const delegates = GlobalMaterialLocalizations.delegates;
    const locale = Locale('es', 'CL');
    if (widget.configurationError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: locale,
        supportedLocales: const [locale],
        localizationsDelegates: delegates,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Error de configuración',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.configurationError!,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return MaterialApp.router(
      title: 'FoodTech Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: locale,
      supportedLocales: const [locale],
      localizationsDelegates: delegates,
      routerConfig: router ??= createAppRouter(
        ref.read(authControllerProvider),
      ),
    );
  }
}
