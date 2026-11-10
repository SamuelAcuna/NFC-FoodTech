import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConfiguracionSave extends Notifier<VoidCallback?> {
  @override
  VoidCallback? build() => null;
  void update(VoidCallback? action) {
    state = action;
  }
}

final configuracionSaveProvider =
    NotifierProvider<ConfiguracionSave, VoidCallback?>(ConfiguracionSave.new);

class ConfiguracionSaveButton extends ConsumerWidget {
  const ConfiguracionSaveButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(right: 28),
    child: FilledButton(
      onPressed: ref.watch(configuracionSaveProvider),
      child: const Text('Guardar cambios'),
    ),
  );
}
