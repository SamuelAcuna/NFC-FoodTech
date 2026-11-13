import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/theme/app_colors.dart';
import '../../categorias/domain/categoria.dart';
import '../data/alimentos_repository.dart';
import '../domain/alimento.dart';

typedef AlimentoFormValues = ({
  String nombre,
  int categoriaId,
  String unidadBase,
  bool esPerecible,
  int? vidaUtilDiasRef,
});

class AlimentoDialog extends ConsumerStatefulWidget {
  const AlimentoDialog({
    required this.categorias,
    this.alimento,
    this.onSave,
    this.title,
    this.submitLabel = 'Guardar',
    this.errorMessage,
    this.requireActiveCategory = false,
    super.key,
  });
  final List<Categoria> categorias;
  final Alimento? alimento;
  final Future<void> Function(AlimentoFormValues)? onSave;
  final String? title;
  final String submitLabel;
  final String Function(Object)? errorMessage;
  final bool requireActiveCategory;
  @override
  ConsumerState<AlimentoDialog> createState() => _AlimentoDialogState();
}

class _AlimentoDialogState extends ConsumerState<AlimentoDialog> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(
    text: widget.alimento?.nombre ?? '',
  );
  late final _dias = TextEditingController(
    text: widget.alimento?.vidaUtilDiasRef?.toString() ?? '',
  );
  late int? _categoria = widget.alimento?.categoriaId;
  late String? _unidad = widget.alimento?.unidadBase;
  late bool _perecible = widget.alimento?.esPerecible ?? true;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _nombre.dispose();
    _dias.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final values = (
        nombre: _nombre.text.trim(),
        categoriaId: _categoria!,
        unidadBase: _unidad!,
        esPerecible: _perecible,
        vidaUtilDiasRef: diasDesdeTexto(_dias.text),
      );
      if (widget.onSave != null) {
        await widget.onSave!(values);
      } else {
        await ref
            .read(alimentosRepositoryProvider)
            .guardar(
              id: widget.alimento?.id,
              nombre: _nombre.text.trim(),
              categoriaId: _categoria!,
              unidadBase: _unidad!,
              esPerecible: _perecible,
              vidaUtilDiasRef: diasDesdeTexto(_dias.text),
            );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              widget.errorMessage?.call(error) ??
              AppError.alimentoMessage(error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(
        widget.title ??
            (widget.alimento == null ? 'Nuevo alimento' : 'Editar alimento'),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                TextFormField(
                  key: const ValueKey('alimento-nombre'),
                  controller: _nombre,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: validarNombreAlimento,
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<int>(
                  initialValue: _categoria,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: [
                    for (final c in widget.categorias.where(
                      (c) => c.activa || c.id == widget.alimento?.categoriaId,
                    ))
                      DropdownMenuItem(
                        value: c.id,
                        child: Text(
                          '${nombreCategoria(c.id, widget.categorias)}${c.activa ? '' : ' (inactiva)'}',
                        ),
                      ),
                  ],
                  validator: (value) {
                    if (value == null) return 'Selecciona una categoría.';
                    if (widget.requireActiveCategory &&
                        !widget.categorias.any(
                          (c) => c.id == value && c.activa,
                        )) {
                      return 'Selecciona una categoría activa.';
                    }
                    return null;
                  },
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _categoria = value),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: _unidad,
                  decoration: const InputDecoration(labelText: 'Unidad base'),
                  items: const [
                    DropdownMenuItem(value: 'g', child: Text('Gramo')),
                    DropdownMenuItem(value: 'ml', child: Text('Mililitro')),
                    DropdownMenuItem(value: 'un', child: Text('Unidad')),
                  ],
                  validator: (value) =>
                      value == null ? 'Selecciona una unidad base.' : null,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _unidad = value),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Perecible'),
                  value: _perecible,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _perecible = value!),
                ),
                TextFormField(
                  key: const ValueKey('alimento-dias'),
                  controller: _dias,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  validator: validarDias,
                  decoration: const InputDecoration(
                    labelText: 'Duración referencial propia (días)',
                    helperText: 'Si lo dejas vacío, se usa la duración de la categoría.',
                    helperMaxLines: 2,
                    errorMaxLines: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _guardar,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.submitLabel),
        ),
      ],
    ),
  );
}
