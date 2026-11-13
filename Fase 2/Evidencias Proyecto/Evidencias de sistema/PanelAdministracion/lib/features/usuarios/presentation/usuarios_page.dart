import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/data/auth_repository.dart';
import '../../auditoria/presentation/auditoria_page.dart' show fechaChile;
import '../data/usuarios_repository.dart';
import '../domain/usuario_admin.dart';

class UsuariosPage extends ConsumerStatefulWidget {
  const UsuariosPage({super.key});
  @override
  ConsumerState<UsuariosPage> createState() => _UsuariosPageState();
}

class _UsuariosPageState extends ConsumerState<UsuariosPage> {
  List<UsuarioAdmin> rows = [];
  String search = '';
  String? estado, desde, hasta, actividad, error;
  bool busy = false, more = false;
  int total = 0, generation = 0;
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  Future<void> load({bool append = false}) async {
    final request = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final page = await ref
          .read(usuariosRepositoryProvider)
          .listar(
            busqueda: search.isEmpty ? null : search,
            estado: estado,
            desde: desde,
            hasta: hasta,
            actividad: actividad,
            offset: append ? rows.length : 0,
          );
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
        setState(() => error = AppError.usuarioMessage(e));
      }
    } finally {
      if (mounted && request == generation) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> pick(bool start) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) {
      return;
    }
    setState(() {
      if (start) {
        desde = DateFormat('yyyy-MM-dd').format(d);
      } else {
        hasta = DateFormat('yyyy-MM-dd').format(d);
      }
    });
    await load();
  }

  Future<void> change(UsuarioAdmin row) async {
    final target = row.estado == 'ACTIVA' ? 'SUSPENDIDA' : 'ACTIVA';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => _EstadoDialog(
        usuario: row,
        estado: target,
        repository: ref.read(usuariosRepositoryProvider),
      ),
    );
    if (ok == true && mounted) {
      await load();
    }
  }

  Widget dropdown(
    String label,
    Map<String, String> options,
    String? value,
    ValueChanged<String?> onChange,
  ) => SizedBox(
    width: 230,
    child: DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: value ?? '',
      decoration: InputDecoration(labelText: label),
      items: [
        for (final e in options.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value)),
      ],
      onChanged: (v) {
        onChange(v == '' ? null : v);
        load();
      },
    ),
  );
  @override
  Widget build(BuildContext context) {
    final can = ref.watch(puedeProvider)('USUARIOS_SUSPENDER');
    final own = ref.watch(authRepositoryProvider).userId;
    return SingleChildScrollView(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Usuarios ($total)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 250,
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Buscar usuario',
                      ),
                      onChanged: (v) {
                        search = v;
                        debounce?.cancel();
                        generation++;
                        debounce = Timer(
                          const Duration(milliseconds: 300),
                          () => load(),
                        );
                      },
                    ),
                  ),
                  dropdown(
                    'Estado',
                    const {
                      '': 'Todos',
                      'ACTIVA': 'Activa',
                      'SUSPENDIDA': 'Suspendida',
                      'BANEADA': 'Baneada',
                    },
                    estado,
                    (v) => setState(() => estado = v),
                  ),
                  dropdown(
                    'Actividad',
                    const {
                      '': 'Todos',
                      'ACTIVOS_30': 'Activos últimos 30 días',
                      'INACTIVOS_30': 'Sin actividad 30 días',
                    },
                    actividad,
                    (v) => setState(() => actividad = v),
                  ),
                  OutlinedButton(
                    onPressed: () => pick(true),
                    child: Text(
                      desde == null
                          ? 'Registro desde'
                          : DateFormat('dd-MM-yyyy')
                                .format(DateTime.parse(desde!)),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => pick(false),
                    child: Text(
                      hasta == null
                          ? 'Registro hasta'
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
                ],
              ),
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Text(error!, style: const TextStyle(color: AppColors.danger)),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    for (final c in [
                      'Usuario',
                      'Correo',
                      'Hogar',
                      'Rol en hogar',
                      'Registro',
                      'Último acceso',
                      'Estado',
                      'Acciones',
                    ])
                      DataColumn(label: Text(c)),
                  ],
                  rows: [
                    for (final row in rows)
                      DataRow(
                        cells: [
                          DataCell(
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: AppColors.primarySoft,
                                  child: Text(row.iniciales),
                                ),
                                const SizedBox(width: 8),
                                Text(row.etiqueta),
                              ],
                            ),
                          ),
                          DataCell(Text(row.email)),
                          DataCell(Text(row.hogar ?? '—')),
                          DataCell(
                            Text(
                              row.rolHogar == 'ADMIN'
                                  ? 'Admin'
                                  : row.rolHogar == 'MIEMBRO'
                                  ? 'Miembro'
                                  : '—',
                            ),
                          ),
                          DataCell(Text(fechaChile(row.registro, time: false))),
                          DataCell(
                            Text(
                              row.acceso == null
                                  ? 'Nunca'
                                  : fechaChile(row.acceso!, time: false),
                            ),
                          ),
                          DataCell(
                            Chip(
                              backgroundColor: row.estado == 'ACTIVA'
                                  ? AppColors.primarySoft
                                  : AppColors.dangerSoft,
                              label: Text(
                                {
                                      'ACTIVA': 'Activa',
                                      'SUSPENDIDA': 'Suspendida',
                                      'BANEADA': 'Baneada',
                                    }[row.estado] ??
                                    row.estado,
                              ),
                            ),
                          ),
                          DataCell(
                            can && row.id != own && row.estado != 'BANEADA'
                                ? TextButton(
                                    onPressed: busy ? null : () => change(row),
                                    child: Text(
                                      row.estado == 'ACTIVA'
                                          ? 'Suspender'
                                          : 'Reactivar',
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (!busy && rows.isEmpty && error == null)
                const Text('No hay usuarios para estos filtros.'),
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
}

class _EstadoDialog extends StatefulWidget {
  const _EstadoDialog({
    required this.usuario,
    required this.estado,
    required this.repository,
  });
  final UsuarioAdmin usuario;
  final String estado;
  final UsuariosRepository repository;
  @override
  State<_EstadoDialog> createState() => _EstadoDialogState();
}

class _EstadoDialogState extends State<_EstadoDialog> {
  final form = GlobalKey<FormState>();
  final motivo = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    motivo.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.cambiarEstado(
        widget.usuario.id,
        widget.estado,
        motivo.text,
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = AppError.usuarioMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(
        '${widget.estado == 'ACTIVA' ? 'Reactivar' : 'Suspender'} cuenta',
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.usuario.email),
              TextFormField(
                controller: motivo,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Motivo obligatorio',
                ),
                maxLength: 500,
                validator: (v) => (v ?? '').trim().length < 5
                    ? 'Ingresa un motivo entre 5 y 500 caracteres.'
                    : null,
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
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: const Text('Confirmar'),
        ),
      ],
    ),
  );
}
