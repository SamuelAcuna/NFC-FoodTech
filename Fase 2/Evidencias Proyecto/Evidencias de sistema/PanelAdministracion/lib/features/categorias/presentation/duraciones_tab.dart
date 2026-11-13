import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/theme/app_colors.dart';
import '../data/categorias_repository.dart';
import '../domain/categoria.dart';
import 'categorias_providers.dart';

class DuracionesTab extends ConsumerWidget {
  const DuracionesTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(categoriasProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'Duración referencial: se usa solo para recordatorios, no es una fecha de vencimiento exacta.',
            style: TextStyle(color: AppColors.primary),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: data.when(
            skipLoadingOnRefresh: false,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Column(
              children: [
                Text(AppError.categoriaMessage(error)),
                TextButton(
                  onPressed: () => ref.invalidate(categoriasProvider),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
            data: (categories) => SingleChildScrollView(
              child: Card(
                margin: EdgeInsets.zero,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 850,
                    child: Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Row(
                            children: [
                              SizedBox(width: 230, child: Text('Categoría')),
                              SizedBox(
                                width: 145,
                                child: Text('Despensa (días)'),
                              ),
                              SizedBox(
                                width: 145,
                                child: Text('Refrigerador (días)'),
                              ),
                              SizedBox(
                                width: 145,
                                child: Text('Congelador (días)'),
                              ),
                              Text('Acciones'),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        if (categories.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('No hay categorías para mostrar.'),
                          ),
                        for (final c in categories)
                          DuracionRow(
                            key: ValueKey(
                              '${c.id}/${c.despensaDias}/${c.refrigeradorDias}/${c.congeladorDias}',
                            ),
                            categoria: c,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class DuracionRow extends ConsumerStatefulWidget {
  const DuracionRow({required this.categoria, super.key});
  final Categoria categoria;
  @override
  ConsumerState<DuracionRow> createState() => _DuracionRowState();
}

class _DuracionRowState extends ConsumerState<DuracionRow> {
  final _form = GlobalKey<FormState>();
  late final _despensa = TextEditingController(
    text: widget.categoria.despensaDias?.toString() ?? '',
  );
  late final _refrigerador = TextEditingController(
    text: widget.categoria.refrigeradorDias?.toString() ?? '',
  );
  late final _congelador = TextEditingController(
    text: widget.categoria.congeladorDias?.toString() ?? '',
  );
  bool _busy = false;
  String? _message;
  bool _failed = false;
  @override
  void dispose() {
    _despensa.dispose();
    _refrigerador.dispose();
    _congelador.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref
          .read(categoriasRepositoryProvider)
          .guardarDuraciones(
            widget.categoria.id,
            despensa: diasDesdeTexto(_despensa.text),
            refrigerador: diasDesdeTexto(_refrigerador.text),
            congelador: diasDesdeTexto(_congelador.text),
          );
      ref.invalidate(categoriasProvider);
      await ref.read(categoriasProvider.future);
      if (mounted) {
        setState(() {
          _failed = false;
          _message = 'Duraciones guardadas.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = AppError.categoriaMessage(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String label, TextEditingController controller) => SizedBox(
    width: 145,
    child: Padding(
      padding: const EdgeInsets.only(right: 12),
      child: TextFormField(
        controller: controller,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: '$label · ${widget.categoria.nombre}',
          errorMaxLines: 3,
          isDense: true,
        ),
        validator: validarDias,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    padding: const EdgeInsets.all(16),
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 230,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: widget.categoria.parentId == null ? 0 : 24,
                    top: 10,
                  ),
                  child: Text(
                    widget.categoria.nombre,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
              ),
              _field('Despensa', _despensa),
              _field('Refrigerador', _refrigerador),
              _field('Congelador', _congelador),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar'),
              ),
            ],
          ),
          if (_message != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _message!,
                style: TextStyle(
                  color: _failed ? AppColors.danger : AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
