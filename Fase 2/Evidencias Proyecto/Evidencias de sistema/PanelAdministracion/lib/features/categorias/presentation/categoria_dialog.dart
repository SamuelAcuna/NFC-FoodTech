import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error.dart';
import '../data/categorias_repository.dart';
import '../domain/categoria.dart';

class CategoriaDialog extends ConsumerStatefulWidget {
  const CategoriaDialog({required this.categorias, this.categoria, super.key});
  final List<Categoria> categorias;
  final Categoria? categoria;
  @override
  ConsumerState<CategoriaDialog> createState() => _CategoriaDialogState();
}

class _CategoriaDialogState extends ConsumerState<CategoriaDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.categoria?.nombre ?? '',
  );
  late int? _parent = widget.categoria?.parentId;
  late String? _conservacion = widget.categoria?.conservacion;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(categoriasRepositoryProvider)
          .guardar(
            id: widget.categoria?.id,
            nombre: _name.text.trim(),
            parentId: _parent,
            conservacion: _conservacion,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = AppError.categoriaMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(
        widget.categoria == null ? 'Nueva categoría' : 'Editar categoría',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: validarNombre,
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<int>(
                  initialValue: _parent,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Categoría padre',
                  ),
                  items: [
                    const DropdownMenuItem<int>(
                      value: null,
                      child: Text('Sin padre'),
                    ),
                    for (final root in widget.categorias.where(
                      (c) => c.parentId == null && c.id != widget.categoria?.id,
                    ))
                      DropdownMenuItem(
                        value: root.id,
                        child: Text(root.nombre),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _parent = value),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: _conservacion,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Conservación'),
                  items: const [
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text('Sin definir'),
                    ),
                    DropdownMenuItem(
                      value: 'AMBIENTE',
                      child: Text('Ambiente'),
                    ),
                    DropdownMenuItem(
                      value: 'REFRIGERADO',
                      child: Text('Refrigerado'),
                    ),
                    DropdownMenuItem(
                      value: 'CONGELADO',
                      child: Text('Congelado'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _conservacion = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
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
  );
}
