import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/theme/app_colors.dart';
import '../../auditoria/presentation/auditoria_page.dart' show fechaChile;
import '../data/soporte_repository.dart';
import '../domain/solicitud_soporte.dart';

class SoportePage extends ConsumerStatefulWidget {
  const SoportePage({super.key});
  @override
  ConsumerState<SoportePage> createState() => _SoportePageState();
}

class _SoportePageState extends ConsumerState<SoportePage> {
  List<SolicitudSoporte> rows = [];
  String? estado = 'ABIERTAS', error;
  bool busy = false, more = false;
  int total = 0, generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool append = false}) async {
    final request = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final page = await ref
          .read(soporteRepositoryProvider)
          .listar(estado: estado, offset: append ? rows.length : 0);
      if (!mounted || request != generation) {
        return;
      }
      setState(() {
        rows = append ? [...rows, ...page] : page;
        total = page.isEmpty ? (append ? total : 0) : page.first.total;
        more = page.length == 50;
      });
    } catch (e) {
      if (mounted && request == generation) {
        setState(() => error = AppError.soporteMessage(e));
      }
    } finally {
      if (mounted && request == generation) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> open(SolicitudSoporte row) async {
    await showDialog<void>(
      context: context,
      builder: (c) => _SoporteDialog(
        row: row,
        repository: ref.read(soporteRepositoryProvider),
      ),
    );
    if (mounted) {
      await load();
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Solicitudes de soporte ($total)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in const {
                  'ABIERTAS': 'Abiertas',
                  'RESPONDIDA': 'Respondidas',
                  'CERRADA': 'Cerradas',
                  '': 'Todas',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: (estado ?? '') == entry.key,
                    onSelected: (_) {
                      setState(
                        () => estado = entry.key.isEmpty ? null : entry.key,
                      );
                      load();
                    },
                  ),
              ],
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Text(error!, style: const TextStyle(color: AppColors.danger)),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(color: AppColors.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onTap: () => open(row),
                  title: Text(row.asunto),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${row.tipoTexto} · ${row.hogar ?? row.email}'),
                      Text(
                        '${fechaChile(row.fecha)} · Prioridad ${row.prioridad}',
                      ),
                      Chip(
                        backgroundColor: row.estado == 'RESPONDIDA'
                            ? AppColors.primarySoft
                            : row.estado == 'CERRADA'
                            ? AppColors.bg
                            : AppColors.warningSoft,
                        label: Text(
                          row.estadoTexto,
                          style: TextStyle(
                            color: row.estado == 'CERRADA'
                                ? AppColors.textSecondary
                                : row.estado == 'RESPONDIDA'
                                ? AppColors.primary
                                : AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
            if (!busy && rows.isEmpty && error == null)
              const Text('No hay solicitudes para este filtro.'),
            if (more)
              TextButton(
                onPressed: busy ? null : () => load(append: true),
                child: const Text('Cargar más'),
              ),
          ],
        ),
      ),
    ),
  );
}

class _SoporteDialog extends StatefulWidget {
  const _SoporteDialog({required this.row, required this.repository});
  final SolicitudSoporte row;
  final SoporteRepository repository;
  @override
  State<_SoporteDialog> createState() => _SoporteDialogState();
}

class _SoporteDialogState extends State<_SoporteDialog> {
  final response = TextEditingController();
  final form = GlobalKey<FormState>();
  List<AgenteSoporte> agents = [];
  String? selected, error;
  bool busy = false, loading = true;
  @override
  void initState() {
    super.initState();
    selected = widget.row.agente;
    response.text = widget.row.respuesta ?? '';
    loadAgents();
  }

  Future<void> loadAgents() async {
    try {
      final list = await widget.repository.agentes();
      if (mounted) {
        setState(() => agents = list);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = AppError.soporteMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  void dispose() {
    response.dispose();
    super.dispose();
  }

  Future<void> action(Future<void> Function() operation) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await operation();
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = AppError.soporteMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> close() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Cerrar solicitud?'),
        content: const Text('La solicitud quedará cerrada.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirmar cierre'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await action(() => widget.repository.cerrar(widget.row.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final closed = widget.row.estado == 'CERRADA';
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(widget.row.asunto),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.row.mensaje),
                const SizedBox(height: 16),
                if (widget.row.respondidoEmail != null)
                  Text('Respondió: ${widget.row.respondidoEmail}'),
                if (loading) const LinearProgressIndicator(),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: agents.any((a) => a.id == selected)
                      ? selected
                      : null,
                  key: ValueKey(agents.length),
                  decoration: const InputDecoration(
                    labelText: 'Agente asignado',
                  ),
                  items: [
                    for (final a in agents)
                      DropdownMenuItem(value: a.id, child: Text(a.email)),
                  ],
                  onChanged: busy || closed
                      ? null
                      : (v) => setState(() => selected = v),
                ),
                TextButton(
                  onPressed:
                      busy ||
                          closed ||
                          selected == null ||
                          !['PENDIENTE', 'ASIGNADA'].contains(widget.row.estado)
                      ? null
                      : () => action(
                          () => widget.repository.asignar(
                            widget.row.id,
                            selected!,
                          ),
                        ),
                  child: const Text('Asignar'),
                ),
                Form(
                  key: form,
                  child: TextFormField(
                    controller: response,
                    enabled: !busy && !closed,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: 2000,
                    decoration: const InputDecoration(labelText: 'Respuesta'),
                    validator: (v) => (v ?? '').trim().length < 5
                        ? 'Ingresa una respuesta entre 5 y 2000 caracteres.'
                        : null,
                  ),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: AppColors.danger)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Volver'),
          ),
          OutlinedButton(
            onPressed: busy || closed ? null : close,
            child: const Text('Cerrar solicitud'),
          ),
          FilledButton(
            onPressed: busy || closed
                ? null
                : () {
                    if (form.currentState!.validate()) {
                      action(
                        () => widget.repository.responder(
                          widget.row.id,
                          response.text,
                        ),
                      );
                    }
                  },
            child: const Text('Responder'),
          ),
        ],
      ),
    );
  }
}
