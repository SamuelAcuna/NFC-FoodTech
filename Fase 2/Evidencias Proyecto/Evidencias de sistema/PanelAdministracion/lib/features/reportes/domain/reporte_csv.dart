import 'dart:convert';

import 'reporte.dart';

const usoHeaders = [
  'Período',
  'Altas',
  'Usuarios activos',
  'Retención (%)',
  'Productos registrados',
  'Alertas emitidas',
];
const desperdicioHeaders = [
  'Período',
  'Categoría',
  'Registros de descarte',
  'Hogares',
];
String csvCell(String v) =>
    RegExp('[;"\r\n]').hasMatch(v) ? '"${v.replaceAll('"', '""')}"' : v;
List<int> buildCsv(
  List<String> headers,
  Iterable<List<String>> rows,
) => utf8.encode(
  '\uFEFF${[headers, ...rows].map((r) => r.map(csvCell).join(';')).join('\r\n')}\r\n',
);
List<int> usoCsv(List<UsoPeriodo> rows, String agrupacion) => buildCsv(
  usoHeaders,
  rows.map(
    (r) => [
      periodoLabel(r.periodo, agrupacion),
      '${r.altas}',
      '${r.activos}',
      r.retencion?.toStringAsFixed(1).replaceAll('.', ',') ?? '',
      '${r.productos}',
      '${r.alertas}',
    ],
  ),
);
List<int> desperdicioCsv(List<DesperdicioPeriodo> rows, String agrupacion) =>
    buildCsv(
      desperdicioHeaders,
      rows.map(
        (r) => [
          periodoLabel(r.periodo, agrupacion),
          r.categoria,
          '${r.descartes}',
          '${r.hogares}',
        ],
      ),
    );
