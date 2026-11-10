import '../../auth/data/auth_repository.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/theme/app_colors.dart';
import '../data/administradores_repository.dart';
import '../domain/administrador.dart';

class AdministradoresPage extends ConsumerStatefulWidget {
  const AdministradoresPage({super.key});
  @override
  ConsumerState<AdministradoresPage> createState() =>
      _AdministradoresPageState();
}

class _AdministradoresPageState extends ConsumerState<AdministradoresPage> {
  AdministradoresData? data;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await ref.read(administradoresRepositoryProvider).cargar();
      if (mounted) {
        setState(() => data = result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = AppError.administradorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> remove(Administrador admin, String code, String name) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Quitar rol?'),
        content: Text('Quitar $name a ${admin.email}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(administradoresRepositoryProvider).quitar(admin.id, code);
      if (mounted) {
        await load();
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = AppError.administradorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> add() async {
    final d = data;

    if (d == null) {
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => _NuevoAdministrador(
        roles: d.roles,
        repository: ref.read(administradoresRepositoryProvider),
      ),
    );
    if (saved == true && mounted) {
      await load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final own = ref.watch(authRepositoryProvider).userId;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 20,
                    runSpacing: 12,
                    children: [
                      Text(
                        'Administradores',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      FilledButton.icon(
                        onPressed: busy || d == null ? null : add,
                        icon: const Icon(Icons.add),
                        label: const Text('Nuevo administrador'),
                      ),
                    ],
                  ),
                  if (busy) const LinearProgressIndicator(),
                  if (error != null)
                    Text(
                      error!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  if (d != null)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: [
                          for (final c in [
                            'Administrador',
                            'Correo',
                            'Roles',
                            'MFA',
                            'Estado',
                          ])
                            DataColumn(label: Text(c)),
                        ],
                        rows: [
                          for (final a in d.administradores)
                            DataRow(
                              cells: [
                                DataCell(
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: AppColors.primarySoft,
                                        child: Text(a.iniciales),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(a.etiqueta),
                                    ],
                                  ),
                                ),
                                DataCell(Text(a.email)),
                                DataCell(
                                  Wrap(
                                    spacing: 6,
                                    children: [
                                      for (final code in a.roles)
                                        InputChip(
                                          deleteIcon: const Icon(Icons.close),
                                          label: Text(
                                            d.roles
                                                    .where(
                                                      (r) => r.codigo == code,
                                                    )
                                                    .firstOrNull
                                                    ?.nombre ??
                                                code,
                                          ),
                                          onDeleted: busy || a.id == own
                                              ? null
                                              : () => remove(
                                                  a,
                                                  code,
                                                  d.roles
                                                          .where(
                                                            (r) =>
                                                                r.codigo ==
                                                                code,
                                                          )
                                                          .firstOrNull
                                                          ?.nombre ??
                                                      code,
                                                ),
                                        ),
                                    ],
                                  ),
                                ),
                                DataCell(Text(a.mfa ? 'Activo' : 'Pendiente')),
                                DataCell(
                                  Chip(
                                    backgroundColor: a.estado == 'ACTIVA'
                                        ? AppColors.primarySoft
                                        : AppColors.dangerSoft,
                                    label: Text(
                                      {
                                            'ACTIVA': 'Activa',
                                            'SUSPENDIDA': 'Suspendida',
                                            'BANEADA': 'Baneada',
                                          }[a.estado] ??
                                          a.estado,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  if (d != null && d.administradores.isEmpty && !busy)
                    const Text('No hay administradores.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          if (d != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Permisos administrativos por rol',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final role in d.roles)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              role.nombre,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final p in role.permisos)
                                  Chip(label: Text(p)),
                                if (role.permisos.isEmpty)
                                  const Text('Sin permisos asignados'),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NuevoAdministrador extends StatefulWidget {
  const _NuevoAdministrador({required this.roles, required this.repository});
  final List<RolAdministrativo> roles;
  final AdministradoresRepository repository;
  @override
  State<_NuevoAdministrador> createState() => _NuevoAdministradorState();
}

class _NuevoAdministradorState extends State<_NuevoAdministrador> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  String? code, error;
  bool busy = false;
  @override
  void dispose() {
    email.dispose();
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
      await widget.repository.asignar(email.text, code!);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = AppError.administradorMessage(e));
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
      title: const Text('Nuevo administrador'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: email,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Correo'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Ingresa un correo.' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: code,
                decoration: const InputDecoration(labelText: 'Rol'),
                items: [
                  for (final r in widget.roles)
                    DropdownMenuItem(value: r.codigo, child: Text(r.nombre)),
                ],
                onChanged: busy ? null : (v) => setState(() => code = v),
                validator: (v) => v == null ? 'Selecciona un rol.' : null,
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
          child: const Text('Asignar rol'),
        ),
      ],
    ),
  );
}
