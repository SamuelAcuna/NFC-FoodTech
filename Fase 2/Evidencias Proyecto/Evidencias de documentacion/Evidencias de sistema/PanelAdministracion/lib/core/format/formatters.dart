import 'package:intl/intl.dart';

String fecha(DateTime value) => DateFormat('dd-MM-yyyy', 'es_CL').format(value);

String clp(int value) => NumberFormat.currency(
  locale: 'es_CL',
  symbol: r'$',
  decimalDigits: 0,
  customPattern: '¤#,##0',
).format(value);
