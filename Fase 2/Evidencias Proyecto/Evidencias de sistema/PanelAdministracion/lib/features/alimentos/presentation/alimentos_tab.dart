import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/theme/app_colors.dart';
import '../../categorias/domain/categoria.dart';
import '../../categorias/presentation/categorias_providers.dart';
import '../data/alimentos_repository.dart';
import '../domain/alimento.dart';
import 'alimento_dialog.dart';
import 'alimentos_providers.dart';

class AlimentosTab extends ConsumerStatefulWidget {
  const AlimentosTab({super.key});
  @override
  ConsumerState<AlimentosTab> createState() => _AlimentosTabState();
}

class _AlimentosTabState extends ConsumerState<AlimentosTab> {
  String _busqueda = '';
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  int? _categoria;
  String _estado = 'activos';
  bool _busy = false;
  String? _error;
  Future<void> _reload() async {
    ref.invalidate(catalogoAlimentosProvider);
    ref.invalidate(conteoAlimentosProvider);
    await ref.read(catalogoAlimentosProvider.future);
  }

  Future<void> _edit(List<Categoria> categorias, [Alimento? alimento]) async {
    setState(() => _error = null);
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          AlimentoDialog(categorias: categorias, alimento: alimento),
    );
    if (saved == true && mounted) {
      try {
        await _reload();
      } catch (error) {
        if (mounted) setState(() => _error = AppError.alimentoMessage(error));
      }
    }
  }

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(title),
            ),
          ],
        ),
      ) ??
      false;
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
          () => _error = AppError.alimentoMessage(error, deleting: deleting),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(Alimento a) async {
    if (a.activo &&
        !await _confirm('Dar de baja', '¿Dar de baja «${a.nombre}»?')) {
      return;
    }
    if (mounted) {
      await _action(
        () => ref
            .read(alimentosRepositoryProvider)
            .cambiarEstado(a.id, !a.activo),
      );
    }
  }

  Future<void> _delete(Alimento a) async {
    if (await _confirm('Eliminar', '¿Eliminar «${a.nombre}» del catálogo?') &&
        mounted) {
      await _action(
        () => ref.read(alimentosRepositoryProvider).eliminar(a.id),
        deleting: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(catalogoAlimentosProvider)
      .when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Column(
          children: [
            Text(AppError.alimentoMessage(error)),
            TextButton(
              onPressed: () => ref.invalidate(catalogoAlimentosProvider),
              child: const Text('Reintentar'),
            ),
          ],
        ),
        data: (data) {
          final filtered = filtrarAlimentos(
            data.alimentos,
            data.categorias,
            busqueda: _busqueda,
            categoriaId: _categoria,
            activo: _estado == 'todos' ? null : _estado == 'activos',
          );
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      Text(
                        '${data.alimentos.length} alimentos en el catálogo',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _edit(data.categorias),
                        icon: const Icon(Icons.add),
                        label: const Text('Nuevo alimento'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 240,
                        child: TextField(
                          controller: _search,
                          key: const ValueKey('buscar-alimento'),
                          decoration: const InputDecoration(
                            labelText: 'Buscar alimento',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (value) =>
                              setState(() => _busqueda = value),
                        ),
                      ),
                      SizedBox(
                        width: 230,
                        child: DropdownButtonFormField<int>(
                          initialValue: _categoria,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Categoría',
                          ),
                          items: [
                            const DropdownMenuItem<int>(
                              value: null,
                              child: Text('Todas'),
                            ),
                            for (final c in data.categorias)
                              DropdownMenuItem(
                                value: c.id,
                                child: Text(
                                  '${c.parentId == null ? '' : '  ↳ '}${c.nombre}',
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _categoria = value),
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _estado,
                          decoration: const InputDecoration(
                            labelText: 'Estado',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'todos',
                              child: Text('Todos'),
                            ),
                            DropdownMenuItem(
                              value: 'activos',
                              child: Text('Activos'),
                            ),
                            DropdownMenuItem(
                              value: 'inactivos',
                              child: Text('Inactivos'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _estado = value!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
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
                            DataColumn(label: Text('Alimento')),
                            DataColumn(label: Text('Categoría')),
                            DataColumn(label: Text('Duración referencial')),
                            DataColumn(label: Text('Unidad base')),
                            DataColumn(label: Text('Estado')),
                            DataColumn(label: Text('Acciones')),
                          ],
                          rows: [
                            for (final a in filtered)
                              DataRow(
                                cells: [
                                  DataCell(Text(a.nombre)),
                                  DataCell(
                                    Text(
                                      nombreCategoria(
                                        a.categoriaId,
                                        data.categorias,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      a.vidaUtilDiasRef == null
                                          ? 'Según categoría'
                                          : '${a.vidaUtilDiasRef} días',
                                      style: TextStyle(
                                        color: a.vidaUtilDiasRef == null
                                            ? AppColors.textMuted
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(a.unidadLabel)),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color: a.activo
                                            ? AppColors.primarySoft
                                            : AppColors.bg,
                                      ),
                                      child: Text(
                                        a.activo ? 'Activo' : 'Inactivo',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: a.activo
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
                                          tooltip: 'Editar ${a.nombre}',
                                          onPressed: _busy
                                              ? null
                                              : () => _edit(data.categorias, a),
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 18,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip:
                                              '${a.activo ? 'Dar de baja' : 'Reactivar'} ${a.nombre}',
                                          onPressed: _busy
                                              ? null
                                              : () => _toggle(a),
                                          icon: Icon(
                                            a.activo
                                                ? Icons.pause_circle_outline
                                                : Icons.play_circle_outline,
                                            size: 18,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Eliminar ${a.nombre}',
                                          onPressed: _busy
                                              ? null
                                              : () => _delete(a),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                            color: AppColors.danger,
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
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No hay alimentos para mostrar.'),
                    ),
                ],
              ),
            ),
          );
        },
      );
}
