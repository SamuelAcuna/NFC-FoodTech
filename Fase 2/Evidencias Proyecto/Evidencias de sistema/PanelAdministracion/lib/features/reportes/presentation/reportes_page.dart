import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/reportes_repository.dart';
import '../data/csv_download.dart';
import '../domain/reporte.dart';
import '../domain/reporte_csv.dart';

class ReportesPage extends ConsumerStatefulWidget {
  const ReportesPage({super.key});
  @override
  ConsumerState<ReportesPage> createState() => _ReportesPageState();
}

class _ReportesPageState extends ConsumerState<ReportesPage> {
  late DateTime desde, hasta;
  String agrupacion = 'MES';
  String? error, generatedDesde, generatedHasta, generatedGrouping;
  bool busy = false;
  List<UsoPeriodo> usos = [];
  List<DesperdicioPeriodo> desperdicios = [];
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    desde = DateTime(now.year, now.month - 6);
    hasta = DateTime(now.year, now.month + 1, 0);
  }

  Future<void> pick(bool start) async {
    final d = await showDatePicker(
      context: context,
      initialDate: start ? desde : hasta,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null && mounted) {
      setState(() {
        if (start) {
          desde = d;
        } else {
          hasta = d;
        }
      });
    }
  }

  Future<void> generate() async {
    final validation = validateReporte(desde, hasta, agrupacion);
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    final d = isoDate(desde), h = isoDate(hasta), g = agrupacion;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(reportesRepositoryProvider);
      final result = await Future.wait([
        repo.uso(d, h, g),
        repo.desperdicio(d, h, g),
      ]);
      if (mounted) {
        setState(() {
          usos = result[0].cast<UsoPeriodo>();
          desperdicios = result[1].cast<DesperdicioPeriodo>();
          generatedDesde = d;
          generatedHasta = h;
          generatedGrouping = g;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = AppError.businessMessage(e, reporteMessages));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  void export(bool uso) {
    try {
      downloadCsv(
        uso
            ? usoCsv(usos, generatedGrouping!)
            : desperdicioCsv(desperdicios, generatedGrouping!),
        'nfc-foodtech_${uso ? 'uso' : 'desperdicio'}_${generatedDesde}_$generatedHasta.csv',
      );
    } catch (e) {
      setState(() => error = AppError.message(e));
    }
  }

  Widget card(
    String title,
    List<String> headers,
    List<List<String>> rows,
    bool uso,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              OutlinedButton(
                onPressed: busy || generatedDesde == null
                    ? null
                    : () => export(uso),
                child: const Text('Exportar CSV'),
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [for (final h in headers) DataColumn(label: Text(h))],
              rows: [
                for (final r in rows)
                  DataRow(cells: [for (final v in r) DataCell(Text(v))]),
              ],
            ),
          ),
          if (generatedDesde != null && rows.isEmpty)
            const Text('No hay datos en el rango seleccionado.'),
          if (!uso)
            const Text(
              'Se omiten los grupos con menos de 3 hogares para resguardar la privacidad. Se cuentan registros, no cantidades.',
            ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (!ref.watch(puedeProvider)('REPORTES_VER')) {
      return const Center(
        child: Text('No tienes permisos para acceder a reportes.'),
      );
    }
    final g = generatedGrouping ?? agrupacion;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton(
                onPressed: busy ? null : () => pick(true),
                child: Text('Desde: ${DateFormat('dd-MM-yyyy').format(desde)}'),
              ),
              OutlinedButton(
                onPressed: busy ? null : () => pick(false),
                child: Text('Hasta: ${DateFormat('dd-MM-yyyy').format(hasta)}'),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  initialValue: agrupacion,
                  decoration: const InputDecoration(labelText: 'Agrupación'),
                  items: const [
                    DropdownMenuItem(value: 'MES', child: Text('Mes')),
                    DropdownMenuItem(value: 'SEMANA', child: Text('Semana')),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => agrupacion = v!),
                ),
              ),
              FilledButton(
                onPressed: busy ? null : generate,
                child: const Text('Generar'),
              ),
            ],
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(error!, style: const TextStyle(color: AppColors.danger)),
          card('Uso de la plataforma', usoHeaders, [
            for (final r in usos)
              [
                periodoLabel(r.periodo, g),
                '${r.altas}',
                '${r.activos}',
                porcentaje(r.retencion),
                '${r.productos}',
                '${r.alertas}',
              ],
          ], true),
          card('Desperdicio por categoría', desperdicioHeaders, [
            for (final r in desperdicios)
              [
                periodoLabel(r.periodo, g),
                r.categoria,
                '${r.descartes}',
                '${r.hogares}',
              ],
          ], false),
        ],
      ),
    );
  }
}
