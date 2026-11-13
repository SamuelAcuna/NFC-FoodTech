import 'package:admin/core/format/formatters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_CL'));

  group('fecha', () {
    test('formatea con ceros a la izquierda en día y mes (dd-MM-yyyy)', () {
      expect(fecha(DateTime(2026, 1, 5)), '05-01-2026');
      expect(fecha(DateTime(2026, 9, 8)), '08-09-2026');
    });

    test('formatea fin de año y años bisiestos correctamente', () {
      expect(fecha(DateTime(2026, 12, 31)), '31-12-2026');
      expect(fecha(DateTime(2024, 2, 29)), '29-02-2024');
    });
  });

  group('clp', () {
    test('no tiene decimales y antepone signo peso', () {
      expect(clp(0), r'$0');
      expect(clp(990), r'$990');
      expect(clp(12990), r'$12.990');
    });

    test('separa miles y millones con punto según convención chilena', () {
      expect(clp(1000), r'$1.000');
      expect(clp(1000000), r'$1.000.000');
      expect(clp(25490990), r'$25.490.990');
    });
  });
}

