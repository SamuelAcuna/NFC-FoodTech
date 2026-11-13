import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/theme/app_colors.dart';
import '../data/auditoria_repository.dart';
import '../domain/registro_auditoria.dart';

String fechaChile(DateTime date, {bool time = true}) => DateFormat(
  time ? 'dd-MM-yyyy HH:mm' : 'dd-MM-yyyy',
  'es_CL',
).format(date.toLocal());

class AuditoriaPage extends ConsumerStatefulWidget {
  const AuditoriaPage({super.key});
  @override
  ConsumerState<AuditoriaPage> createState() => _AuditoriaPageState();
}

class _AuditoriaPageState extends ConsumerState<AuditoriaPage> {
  List<RegistroAuditoria> rows = [];
  String? desde, hasta, entidad, accion, error;
  String search = '';
  bool busy = false, more = false;
  int generation = 0;
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
          .read(auditoriaRepositoryProvider)
          .listar(
            desde: desde,
            hasta: hasta,
            entidad: entidad,
            accion: accion,
            offset: append ? rows.length : 0,
          );
      if (!mounted || request != generation) return;
      setState(() {
        rows = append ? [...rows, ...page] : page;
        more = page.length == 50;
      });
    } catch (e) {
      if (mounted && request == generation) {
        setState(() => error = AppError.message(e));
      }
    } finally {
      if (mounted && request == generation) setState(() => busy = false);
    }
  }

  Future<void> pick(bool start) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    setState(() {
      if (start) {
        desde = DateFormat('yyyy-MM-dd').format(date);
      } else {
        hasta = DateFormat('yyyy-MM-dd').format(date);
      }
    });
    await load();
  }

  Widget filter(
    String label,
    Map<String, String> options,
    String? value,
    ValueChanged<String?> change,
  ) => SizedBox(
    width: 200,
    child: DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: value ?? '',
      decoration: InputDecoration(labelText: label),
      items: [
        for (final e in options.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value)),
      ],
      onChanged: (v) {
        change(v == '' ? null : v);
        load();
      },
    ),
  );
  void detail(RegistroAuditoria row) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Detalle de auditoría'),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${row.entidad} #${row.entidadId}'),
              if (row.motivo != null) Text('Motivo: ${row.motivo}'),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Campo')),
                    DataColumn(label: Text('Antes')),
                    DataColumn(label: Text('Después')),
                  ],
                  rows: [
                    for (final key in row.camposCambiados)
                      DataRow(
                        cells: [
                          DataCell(Text(key)),
                          DataCell(Text('${row.antes?[key] ?? '—'}')),
                          DataCell(Text('${row.despues?[key] ?? '—'}')),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Card(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bitácora de auditoría',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  onPressed: () => pick(true),
                  child: Text(
                    desde == null
                        ? 'Desde'
                        : DateFormat('dd-MM-yyyy')
                              .format(DateTime.parse(desde!)),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => pick(false),
                  child: Text(
                    hasta == null
                        ? 'Hasta'
                        : DateFormat('dd-MM-yyyy')
                              .format(DateTime.parse(hasta!)),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      desde = null;
                      hasta = null;
                    });
                    load();
                  },
                  child: const Text('Limpiar fechas'),
                ),
                filter(
                  'Módulo',
                  const {
                    '': 'Todos',
                    'categoria': 'Categorías',
                    'alimento': 'Alimentos',
                    'parametro': 'Parámetros',
                    'rol': 'Roles',
                    'rol_permiso': 'Permisos de rol',
                    'perfil_rol': 'Asignación de roles',
                    'perfil': 'Usuarios',
                    'solicitud_soporte': 'Soporte',
                  },
                  entidad,
                  (v) => setState(() => entidad = v),
                ),
                filter(
                  'Acción',
                  const {
                    '': 'Todas',
                    'INSERT': 'INSERT',
                    'UPDATE': 'UPDATE',
                    'DELETE': 'DELETE',
                    'APROBAR': 'APROBAR',
                    'RECHAZAR': 'RECHAZAR',
                    'SUSPENDER': 'SUSPENDER',
                    'REACTIVAR': 'REACTIVAR',
                  },
                  accion,
                  (v) => setState(() => accion = v),
                ),
                SizedBox(
                  width: 240,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar en registros cargados',
                    ),
                    onChanged: (v) => setState(() => search = v.toLowerCase()),
                  ),
                ),
              ],
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Text(error!, style: const TextStyle(color: AppColors.danger)),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Fecha')),
                  DataColumn(label: Text('Administrador')),
                  DataColumn(label: Text('Acción')),
                  DataColumn(label: Text('Detalle')),
                ],
                rows: [
                  for (final row in rows.where(
                    (r) => '${r.texto} ${r.actor ?? ''} ${fechaChile(r.fecha)}'
                        .toLowerCase()
                        .contains(search),
                  ))
                    DataRow(
                      cells: [
                        DataCell(Text(fechaChile(row.fecha))),
                        DataCell(Text(row.actor ?? '—')),
                        DataCell(Text(row.texto)),
                        DataCell(
                          TextButton(
                            onPressed: () => detail(row),
                            child: const Text('Ver'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (!busy && rows.isEmpty && error == null)
              const Text('No hay registros para estos filtros.'),
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
