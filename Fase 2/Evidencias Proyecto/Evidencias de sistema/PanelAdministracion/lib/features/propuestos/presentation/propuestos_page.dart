import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/format/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../alimentos/domain/alimento.dart';
import '../../alimentos/presentation/alimento_dialog.dart';
import '../../alimentos/presentation/alimentos_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../categorias/presentation/categorias_providers.dart';
import '../data/propuestos_repository.dart';
import '../domain/propuesta.dart';
import 'propuestos_providers.dart';

class PropuestosPage extends ConsumerStatefulWidget {
  const PropuestosPage({super.key});
  @override
  ConsumerState<PropuestosPage> createState() => _PropuestosPageState();
}

class _PropuestosPageState extends ConsumerState<PropuestosPage> {
  final _search = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(contarPropuestosProvider);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload({bool approved = false}) async {
    ref.invalidate(propuestosDataProvider);
    ref.invalidate(contarPropuestosProvider);
    if (approved) {
      ref.invalidate(catalogoAlimentosProvider);
      ref.invalidate(conteoAlimentosProvider);
    }
    await ref.read(propuestosDataProvider.future);
  }

  Future<void> _approve(Propuesta p, PropuestosData data) async {
    setState(() => _error = null);
    final repository = ref.read(propuestosRepositoryProvider);
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlimentoDialog(
        categorias: data.categorias,
        alimento: p.editable,
        title: 'Aprobar propuesta',
        submitLabel: 'Aprobar',
        requireActiveCategory: true,
        errorMessage: AppError.propuestoMessage,
        onSave: (values) async {
          await repository.aprobar(
            id: p.id,
            nombre: values.nombre,
            categoriaId: values.categoriaId,
            unidadBase: values.unidadBase,
            esPerecible: values.esPerecible,
            vidaUtilDiasRef: values.vidaUtilDiasRef,
          );
        },
      ),
    );
    if (saved == true && mounted) {
      try {
        await _reload(approved: true);
      } catch (error) {
        if (mounted) setState(() => _error = AppError.propuestoMessage(error));
      }
    }
  }

  Future<void> _reject(Propuesta p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rechazar «${p.nombre}»'),
        content: const Text(
          'El producto seguirá disponible solo para el hogar que lo propuso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(propuestosRepositoryProvider).rechazar(p.id);
      await _reload();
    } catch (error) {
      if (mounted) setState(() => _error = AppError.propuestoMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(adminContextProvider)?.puede('PROPUESTOS_REVISAR') != true) {
      return const Center(
        child: Text('No tienes permisos para revisar productos sugeridos.'),
      );
    }
    return ref
        .watch(propuestosDataProvider)
        .when(
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Column(
            children: [
              Text(AppError.propuestoMessage(error)),
              TextButton(
                onPressed: () {
                  ref.invalidate(propuestosDataProvider);
                  ref.invalidate(contarPropuestosProvider);
                },
                child: const Text('Reintentar'),
              ),
            ],
          ),
          data: (data) {
            final filtered = filtrarPropuestas(data.propuestas, _search.text);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.attentionSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${data.propuestas.length} productos propuestos por hogares esperan revisión antes de aparecer en el catálogo.',
                    style: const TextStyle(
                      color: AppColors.attention,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      labelText: 'Buscar producto',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                if (_busy) const LinearProgressIndicator(),
                if (data.propuestas.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text('No hay productos pendientes de revisión.'),
                    ),
                  )
                else
                  Expanded(
                    child: SingleChildScrollView(
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columnSpacing: 24,
                            horizontalMargin: 20,
                            headingTextStyle: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            dataTextStyle: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.5,
                            ),
                            columns: const [
                              DataColumn(label: Text('Producto')),
                              DataColumn(label: Text('Categoría')),
                              DataColumn(label: Text('Unidad')),
                              DataColumn(label: Text('Propuesto por')),
                              DataColumn(label: Text('Fecha')),
                              DataColumn(label: Text('Acciones')),
                            ],
                            rows: [
                              for (final p in filtered)
                                DataRow(
                                  cells: [
                                    DataCell(Text(p.nombre)),
                                    DataCell(
                                      Text(
                                        nombreCategoria(
                                          p.categoriaId,
                                          data.categorias,
                                        ),
                                      ),
                                    ),
                                    DataCell(Text(p.editable.unidadLabel)),
                                    DataCell(Text(p.hogarRef)),
                                    DataCell(Text(fecha(p.propuestoEn))),
                                    DataCell(
                                      Row(
                                        children: [
                                          FilledButton(
                                            onPressed: _busy
                                                ? null
                                                : () => _approve(p, data),
                                            child: const Text('Aprobar'),
                                          ),
                                          const SizedBox(width: 8),
                                          TextButton(
                                            style: TextButton.styleFrom(
                                              foregroundColor: AppColors.danger,
                                              backgroundColor:
                                                  AppColors.dangerSoft,
                                            ),
                                            onPressed: _busy
                                                ? null
                                                : () => _reject(p),
                                            child: const Text('Rechazar'),
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
                if (data.propuestas.isNotEmpty && filtered.isEmpty)
                  const Text('No hay productos que coincidan con la búsqueda.'),
              ],
            );
          },
        );
  }
}
