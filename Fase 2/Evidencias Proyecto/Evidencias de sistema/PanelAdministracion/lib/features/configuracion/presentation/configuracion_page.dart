import 'configuracion_save.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/parametros_repository.dart';
import '../domain/parametro.dart';

class ConfiguracionPage extends ConsumerStatefulWidget {
  const ConfiguracionPage({super.key});
  @override
  ConsumerState<ConfiguracionPage> createState() => _ConfiguracionPageState();
}

class _ConfiguracionPageState extends ConsumerState<ConfiguracionPage> {
  List<Parametro> rows = [];
  final editors = <String, TextEditingController>{};
  final saved = <String, String>{};
  final dates = <String, DateTime>{};
  bool busy = true;
  String? error, summary;
  final form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void dispose() {
    for (final e in editors.values) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    try {
      final data = await ref.read(parametrosRepositoryProvider).listar();
      if (!mounted) {
        return;
      }
      setState(() {
        rows = data;
        for (final p in rows) {
          editors[p.clave] = TextEditingController(text: p.valor);
          saved[p.clave] = p.valor;
          dates[p.clave] = p.actualizado;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = AppError.businessMessage(e, parametroMessages));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> save() async {
    if (!mounted || busy) {
      return;
    }
    if (!form.currentState!.validate()) {
      return;
    }
    setState(() {
      busy = true;
      summary = null;
    });
    final ok = <String>[], failed = <String>[];
    for (final p in rows) {
      final value = normalizeParametro(p.tipo, editors[p.clave]!.text);
      if (value == normalizeParametro(p.tipo, saved[p.clave]!)) {
        continue;
      }
      try {
        await ref.read(parametrosRepositoryProvider).actualizar(p.clave, value);
        saved[p.clave] = value;
        dates[p.clave] = DateTime.now();
        ok.add(p.clave);
      } catch (e) {
        failed.add(
          '${p.clave}: ${AppError.businessMessage(e, parametroMessages)}',
        );
      }
    }
    if (mounted) {
      setState(() {
        busy = false;
        summary =
            'Guardadas: ${ok.isEmpty ? 'ninguna' : ok.join(', ')}. Fallaron: ${failed.isEmpty ? 'ninguna' : failed.join('; ')}.';
      });
    }
  }

  Widget editor(Parametro p) {
    final controller = editors[p.clave]!;
    if (p.tipo == 'BOOLEANO') {
      return FormField<String>(
        validator: (_) => validateParametro(p.clave, p.tipo, controller.text),
        builder: (field) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                notificationKeys[p.clave] ?? p.descripcion ?? p.clave,
              ),
              subtitle: const Text('Habilitada'),
              value: controller.text == 'true',
              onChanged: busy
                  ? null
                  : (v) => setState(() => controller.text = '$v'),
            ),
            if (field.errorText != null)
              Text(
                field.errorText!,
                style: const TextStyle(color: AppColors.danger),
              ),
          ],
        ),
      );
    }
    if (p.clave.endsWith('.canales')) {
      List<dynamic> channels = [];
      try {
        final j = jsonDecode(controller.text);
        if (j is List) {
          channels = j;
        }
      } catch (_) {
        /* El validador informa el valor inválido. */
      }
      return FormField<String>(
        validator: (_) => validateParametro(p.clave, p.tipo, controller.text),
        builder: (field) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final e in const {
                  'PUSH': 'Push',
                  'EMAIL': 'Correo',
                  'IN_APP': 'En la app',
                }.entries)
                  FilterChip(
                    label: Text(e.value),
                    selected: channels.contains(e.key),
                    onSelected: busy
                        ? null
                        : (v) {
                            final next = [...channels];
                            if (v) {
                              next.add(e.key);
                            } else {
                              next.remove(e.key);
                            }
                            setState(() => controller.text = jsonEncode(next));
                          },
                  ),
              ],
            ),
            if (field.errorText != null)
              Text(
                field.errorText!,
                style: const TextStyle(color: AppColors.danger),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        enabled: !busy,
        maxLines: p.tipo == 'JSON' ? 3 : 1,
        decoration: InputDecoration(
          labelText: systemKeys[p.clave] ?? p.clave,
          helperText: parameterHelp[p.clave] ?? p.descripcion,
        ),
        validator: (v) => validateParametro(p.clave, p.tipo, v ?? ''),
      ),
    );
  }

  Widget card(String title, List<Parametro> params) {
    final updated = params
        .map((p) => dates[p.clave]!)
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            for (final p in params) editor(p),
            Text(
              'Última modificación: ${updated == null ? '—' : DateFormat('dd-MM-yyyy HH:mm').format(updated.toLocal())}',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(puedeProvider)('PARAMETROS_GESTIONAR')) {
      return const Center(
        child: Text('No tienes permisos para acceder a configuración.'),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(configuracionSaveProvider.notifier)
            .update(busy || error != null ? null : save);
      }
    });
    return Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(error!, style: const TextStyle(color: AppColors.danger)),
        if (summary != null) Text(summary!),
        Expanded(
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  card(
                    'Parámetros del sistema',
                    rows.where((p) => systemKeys.containsKey(p.clave)).toList(),
                  ),
                  card('Notificaciones globales', [
                    for (final k in notificationKeys.keys)
                      ...rows.where(
                        (p) => p.clave == k || p.clave == channelKey(k),
                      ),
                  ]),
                  card(
                    'Otros parámetros',
                    rows.where((p) => !contractKeys.contains(p.clave)).toList(),
                  ),
                  const Text(
                    'Estos valores se aplican a los hogares nuevos; no modifican las preferencias que cada usuario ya configuró.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
