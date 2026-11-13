import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import 'propuestos_providers.dart';

class PropuestosBadge extends ConsumerWidget {
  const PropuestosBadge({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(contarPropuestosProvider).asData?.value ?? 0;
    if (count <= 0) return const SizedBox.shrink();
    return Semantics(
      label: '$count productos pendientes de revisión',
      child: Container(
        key: const ValueKey('propuestos-badge'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.attentionSoft,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '$count',
          style: const TextStyle(
            color: AppColors.attention,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
