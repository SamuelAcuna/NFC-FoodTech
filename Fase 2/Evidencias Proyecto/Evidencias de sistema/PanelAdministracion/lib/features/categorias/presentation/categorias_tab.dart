import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/theme/app_colors.dart';
import '../data/categorias_repository.dart';
import '../domain/categoria.dart';
import 'categoria_dialog.dart';
import 'categorias_providers.dart';

class CategoriasTab extends ConsumerStatefulWidget {
  const CategoriasTab({super.key});
  @override
  ConsumerState<CategoriasTab> createState() => _CategoriasTabState();
}

class _CategoriasTabState extends ConsumerState<CategoriasTab> {
  String _query = '';
  bool _busy = false;
  String? _error;
  Future<void> _reload() async {
    ref.invalidate(categoriasProvider);
    ref.invalidate(conteoAlimentosProvider);
    await ref.read(categoriasProvider.future);
  }

  Future<void> _edit(List<Categoria> categories, [Categoria? category]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          CategoriaDialog(categorias: categories, categoria: category),
    );
    if (saved == true && mounted) {
      try {
        await _reload();
      } catch (error) {
        if (mounted) setState(() => _error = AppError.categoriaMessage(error));
      }
    }
  }

  Future<void> _action(
    Future<void> Function() action, {
    bool deleting = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _reload();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = AppError.categoriaMessage(error, deleting: deleting),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Categoria category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text('¿Eliminar «${category.nombre}»?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _action(
        () => ref.read(categoriasRepositoryProvider).eliminar(category.id),
        deleting: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(categoriasProvider);
    final counts = ref.watch(conteoAlimentosProvider).asData?.value;
    return data.when(
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
      data: (categories) {
        final filtered = categories
            .where(
              (c) =>
                  c.nombre.toLowerCase().contains(_query.trim().toLowerCase()),
            )
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 12,
              alignment: WrapAlignment.spaceBetween,
              children: [
                SizedBox(
                  width: 280,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar categoría',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _edit(categories),
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva categoría'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: SingleChildScrollView(
                child: Card(
                  margin: EdgeInsets.zero,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingTextStyle: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      dataTextStyle: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13.5,
                      ),
                      dividerThickness: 1,
                      columns: const [
                        DataColumn(label: Text('Nombre')),
                        DataColumn(label: Text('Conservación')),
                        DataColumn(label: Text('N° de alimentos')),
                        DataColumn(label: Text('Estado')),
                        DataColumn(label: Text('Acciones')),
                      ],
                      rows: [
                        for (final c in filtered)
                          DataRow(
                            cells: [
                              DataCell(
                                Padding(
                                  padding: EdgeInsets.only(
                                    left: c.parentId == null ? 0 : 24,
                                  ),
                                  child: Text(c.nombre),
                                ),
                              ),
                              DataCell(Text(c.conservacionLabel)),
                              DataCell(
                                Text(
                                  counts == null ? '—' : '${counts[c.id] ?? 0}',
                                ),
                              ),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: c.activa
                                        ? AppColors.primarySoft
                                        : AppColors.border,
                                  ),
                                  child: Text(
                                    c.activa ? 'Activa' : 'Inactiva',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: c.activa
                                          ? AppColors.primary
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Row(
                                  children: [
                                    IconButton(
                                      tooltip: 'Editar ${c.nombre}',
                                      onPressed: _busy
                                          ? null
                                          : () => _edit(categories, c),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip:
                                          '${c.activa ? 'Desactivar' : 'Activar'} ${c.nombre}',
                                      onPressed: _busy
                                          ? null
                                          : () => _action(
                                              () => ref
                                                  .read(
                                                    categoriasRepositoryProvider,
                                                  )
                                                  .cambiarEstado(
                                                    c.id,
                                                    !c.activa,
                                                  ),
                                            ),
                                      icon: Icon(
                                        c.activa
                                            ? Icons.pause_circle_outline
                                            : Icons.play_circle_outline,
                                        size: 18,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Eliminar ${c.nombre}',
                                      onPressed: _busy
                                          ? null
                                          : () => _delete(c),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: AppColors.danger,
                                        size: 18,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No hay categorías para mostrar.'),
              ),
          ],
        );
      },
    );
  }
}
