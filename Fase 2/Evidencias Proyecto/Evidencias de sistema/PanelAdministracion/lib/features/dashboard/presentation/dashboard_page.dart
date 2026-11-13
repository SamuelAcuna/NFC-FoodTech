import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/dashboard_repository.dart';
import '../domain/dashboard_data.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});
  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  DashboardData? data;
  String? error;
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await ref.read(dashboardRepositoryProvider).cargar();
      if (mounted) {
        setState(() => data = result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = AppError.message(e));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Widget kpi(
    String title,
    int value,
    IconData icon, {
    String? subtitle,
    String? link,
    String? route,
  }) => SizedBox(
    width: 245,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: AppColors.primarySoft,
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(height: 12),
            Text(title),
            Text(
              '$value',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            if (link != null && route != null)
              TextButton(onPressed: () => context.go(route), child: Text(link)),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final d = data;
    final can = ref.watch(puedeProvider);
    if (busy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error!),
          TextButton(onPressed: load, child: const Text('Reintentar')),
        ],
      );
    }
    if (d == null) {
      return const SizedBox.shrink();
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              kpi('Hogares registrados', d.hogares, Icons.home_outlined),
              kpi(
                'Usuarios registrados',
                d.usuarios,
                Icons.people_outline,
                subtitle: '${d.activos} activos en 30 días',
              ),
              kpi(
                'Productos por revisar',
                d.propuestos,
                Icons.fact_check_outlined,
                link: can('PROPUESTOS_REVISAR') ? 'Revisar ahora →' : null,
                route: '/propuestos',
              ),
              kpi(
                'Solicitudes abiertas',
                d.solicitudes,
                Icons.chat_bubble_outline,
                link: can('SOPORTE_GESTIONAR') ? 'Ver soporte →' : null,
                route: '/soporte',
              ),
            ],
          ),
          const SizedBox(height: 22),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aprovechamiento agregado, últimos 6 meses',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 22),
                  if (d.meses.every((m) => m.porcentaje == null))
                    const Text('Aún no hay registros de consumo o descarte.'),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final m in d.meses)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Column(
                              children: [
                                Text(
                                  m.porcentaje == null
                                      ? '—'
                                      : '${(m.porcentaje! * 100).round()}%',
                                ),
                                const SizedBox(height: 8),
                                Semantics(
                                  label:
                                      '${m.etiqueta}: ${m.porcentaje == null ? 'sin registros' : '${(m.porcentaje! * 100).round()}%'}',
                                  child: Container(
                                    width: 36,
                                    height: 150,
                                    alignment: Alignment.bottomCenter,
                                    decoration: BoxDecoration(
                                      color: AppColors.bg,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Container(
                                      key: ValueKey('barra-${m.mes}'),
                                      width: 36,
                                      height: 150 * (m.porcentaje ?? 0),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(m.etiqueta),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Calculado por cantidad de registros de consumo y descarte.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Accesos rápidos',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (can('REPORTES_VER'))
                TextButton(
                  onPressed: () => context.go('/reportes'),
                  child: const Text('Generar reporte administrativo →'),
                ),
              if (can('PROPUESTOS_REVISAR'))
                TextButton(
                  onPressed: () => context.go('/propuestos'),
                  child: Text('${d.propuestos} productos esperando revisión'),
                ),
              if (can('SOPORTE_GESTIONAR'))
                TextButton(
                  onPressed: () => context.go('/soporte'),
                  child: Text(
                    '${d.solicitudes} solicitudes de soporte abiertas',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
