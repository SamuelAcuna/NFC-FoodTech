import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/theme/app_colors.dart';
import '../data/hogares_repository.dart';
import '../domain/hogar_resumen.dart';

class HogaresTotal extends Notifier<int> {
  @override
  int build() => 0;
  void update(int value) {
    state = value;
  }
}

final hogaresTotalProvider = NotifierProvider<HogaresTotal, int>(
  HogaresTotal.new,
);

class HogaresTab extends ConsumerStatefulWidget {
  const HogaresTab({super.key});
  @override
  ConsumerState<HogaresTab> createState() => _HogaresTabState();
}

class _HogaresTabState extends ConsumerState<HogaresTab> {
  List<HogarResumen> rows = [];
  String search = '';
  String? actividad, error;
  bool busy = false, more = false;
  int generation = 0;
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
          .read(hogaresRepositoryProvider)
          .listar(
            busqueda: search.isEmpty ? null : search,
            actividad: actividad,
            offset: append ? rows.length : 0,
          );
      if (!mounted || request != generation) {
        return;
      }
      setState(() {
        rows = append ? [...rows, ...page] : page;
        more = page.length == 50;
      });
      ref
          .read(hogaresTotalProvider.notifier)
          .update(
            page.isEmpty
                ? (append ? ref.read(hogaresTotalProvider) : 0)
                : page.first.total,
          );
    } catch (e) {
      if (mounted && request == generation) {
        setState(() => error = AppError.message(e));
      }
    } finally {
      if (mounted && request == generation) {
        setState(() => busy = false);
      }
    }
  }

  String date(DateTime d) => DateFormat('dd-MM-yyyy').format(d.toLocal());
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hogares (${ref.watch(hogaresTotalProvider)})',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 250,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar hogar',
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
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    initialValue: '',
                    decoration: const InputDecoration(
                      labelText: 'Nivel de actividad',
                    ),
                    items: [
                      for (final e in const {
                        '': 'Todos',
                        'ALTA': 'Alta',
                        'MEDIA': 'Media',
                        'BAJA': 'Baja',
                        'SIN_ACTIVIDAD': 'Sin actividad',
                      }.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) {
                      actividad = v == '' ? null : v;
                      load();
                    },
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
                columns: [
                  for (final c in [
                    'Hogar',
                    'Ubicación',
                    'Integrantes',
                    'Composición',
                    'Registro',
                    'Actividad (30 días)',
                    'Último movimiento',
                    'Productos disponibles',
                  ])
                    DataColumn(label: Text(c)),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(
                      cells: [
                        DataCell(
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.nombre),
                              Text(
                                r.ref,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        DataCell(
                          Text(
                            r.comuna == null
                                ? '—'
                                : '${r.comuna}, ${r.region ?? '—'}',
                          ),
                        ),
                        DataCell(
                          Text(
                            '${r.integrantes} activos${r.invitados > 0 ? ' +${r.invitados} invitados' : ''}',
                          ),
                        ),
                        DataCell(
                          Text(
                            r.adultos == null || r.menores == null
                                ? '—'
                                : '${r.adultos} adultos · ${r.menores} menores',
                          ),
                        ),
                        DataCell(Text(date(r.creado))),
                        DataCell(
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: switch (r.nivel) {
                                    'ALTA' => AppColors.primary,
                                    'MEDIA' => AppColors.primarySoft,
                                    'BAJA' => AppColors.warningSoft,
                                    _ => AppColors.bg,
                                  },
                                ),
                                child: Text(
                                  const {
                                        'ALTA': 'Alta',
                                        'MEDIA': 'Media',
                                        'BAJA': 'Baja',
                                        'SIN_ACTIVIDAD': 'Sin actividad',
                                      }[r.nivel] ??
                                      r.nivel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: r.nivel == 'ALTA'
                                        ? AppColors.surfaceAlt
                                        : AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              Text('${r.movimientos} movimientos'),
                            ],
                          ),
                        ),
                        DataCell(
                          Text(r.ultimo == null ? 'Nunca' : date(r.ultimo!)),
                        ),
                        DataCell(Text('${r.productos}')),
                      ],
                    ),
                ],
              ),
            ),
            if (!busy && error == null && rows.isEmpty)
              const Text('No hay hogares para estos filtros.'),
            if (more)
              TextButton(
                onPressed: busy ? null : () => load(append: true),
                child: const Text('Cargar más'),
              ),
            const Text(
              'Solo se muestran datos agregados; el detalle de la despensa de cada hogar es privado.',
            ),
          ],
        ),
      ),
    ),
  );
}
