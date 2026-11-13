import 'package:admin/core/errors/app_error.dart';
import 'package:admin/features/categorias/domain/categoria.dart';
import 'package:admin/features/categorias/presentation/catalogo_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('Categoria.fromJson y dominio', () {
    test('Categoria.fromJson conserva columnas, nulos y estado', () {
      final c = Categoria.fromJson({
        'id': 7,
        'nombre': 'Prueba',
        'parent_id': 1,
        'temp_conservacion': 'CONGELADO',
        'activa': false,
        'vida_util_dias_ref': 2,
        'vida_util_refrigerado_dias': 8,
        'vida_util_congelado_dias': 30,
      });
      expect(c.id, 7);
      expect(c.parentId, 1);
      expect(c.activa, isFalse);
      expect([c.despensaDias, c.refrigeradorDias, c.congeladorDias], [2, 8, 30]);
      expect(c.conservacionLabel, 'Congelado');
      final empty = Categoria.fromJson({
        'id': 8,
        'nombre': 'Sin días',
        'activa': true,
      });
      expect(
        [empty.despensaDias, empty.refrigeradorDias, empty.congeladorDias],
        [null, null, null],
      );
      expect(empty.conservacionLabel, 'Sin definir');
    });

    test('conservacionLabel mapea todos los valores y desconocidos', () {
      expect(
        const Categoria(id: 1, nombre: 'A', conservacion: 'AMBIENTE').conservacionLabel,
        'Ambiente',
      );
      expect(
        const Categoria(id: 2, nombre: 'B', conservacion: 'REFRIGERADO').conservacionLabel,
        'Refrigerado',
      );
      expect(
        const Categoria(id: 3, nombre: 'C', conservacion: 'CONGELADO').conservacionLabel,
        'Congelado',
      );
      expect(
        const Categoria(id: 4, nombre: 'D', conservacion: null).conservacionLabel,
        'Sin definir',
      );
      expect(
        const Categoria(id: 5, nombre: 'E', conservacion: 'OTRO').conservacionLabel,
        'Sin definir',
      );
    });

    test('activa toma true por defecto si no viene en el json', () {
      final c = Categoria.fromJson({'id': 1, 'nombre': 'Por defecto'});
      expect(c.activa, isTrue);
    });
  });

  group('Validaciones de días y nombre', () {
    test('Días: vacío y límites válidos, rechaza decimales y fuera de rango', () {
      for (final value in ['', ' ', null, '1', '3650', ' 25 ']) {
        expect(validarDias(value), isNull, reason: '$value debería ser válido');
      }
      for (final value in ['0', '-1', '3651', '1.5', '1,5', 'abc', '1e2', '+3', '  -10  ']) {
        expect(validarDias(value), isNotNull, reason: '$value debería ser inválido');
      }
      expect(diasDesdeTexto(' '), isNull);
      expect(diasDesdeTexto(''), isNull);
      expect(diasDesdeTexto(' 3650 '), 3650);
      expect(diasDesdeTexto('1'), 1);
    });

    test('Nombre exige 2 a 60 caracteres tras trim', () {
      expect(validarNombre(null), isNotNull);
      expect(validarNombre(''), isNotNull);
      expect(validarNombre('   '), isNotNull);
      expect(validarNombre(' A '), isNotNull);
      expect(validarNombre(' Ab '), isNull);
      expect(validarNombre('a' * 60), isNull);
      expect(validarNombre('a' * 61), isNotNull);
      expect(validarNombre('  ${'b' * 60}  '), isNull);
    });
  });

  group('ordenarArbol', () {
    test(
      'Orden del árbol: raíz seguida de hijas, nombres y sin perder huérfanas',
      () {
        final data = [
          const Categoria(id: 4, nombre: 'Zanahorias', parentId: 3),
          const Categoria(id: 3, nombre: 'Verduras'),
          const Categoria(id: 2, nombre: 'Cítricos', parentId: 1),
          const Categoria(id: 1, nombre: 'Frutas'),
          const Categoria(id: 5, nombre: 'Legado', parentId: 99),
        ];
        expect(ordenarArbol(data).map((c) => c.id), [1, 2, 3, 4, 5]);
        expect(data.first.id, 4);
      },
    );

    test('ordenarArbol maneja lista vacía y raíces sin hijas', () {
      expect(ordenarArbol([]), isEmpty);

      final raices = [
        const Categoria(id: 2, nombre: 'Bebidas'),
        const Categoria(id: 1, nombre: 'Abarrotes'),
      ];
      expect(ordenarArbol(raices).map((c) => c.id), [1, 2]);
    });

    test('ordenarArbol ordena subcategorías bajo la misma raíz alfabéticamente', () {
      final data = [
        const Categoria(id: 1, nombre: 'Frutas'),
        const Categoria(id: 3, nombre: 'Plátanos', parentId: 1),
        const Categoria(id: 2, nombre: 'Manzanas', parentId: 1),
        const Categoria(id: 4, nombre: 'Arándanos', parentId: 1),
      ];
      expect(ordenarArbol(data).map((c) => c.nombre), [
        'Frutas',
        'Arándanos',
        'Manzanas',
        'Plátanos',
      ]);
    });
  });
  test('Tabs y elección respetan permisos y URL', () {
    expect(tabsVisibles(true, true), ['alimentos', 'categorias', 'duraciones']);
    expect(tabsVisibles(false, true), ['categorias', 'duraciones']);
    expect(tabsVisibles(true, false), ['alimentos']);
    expect(tabsVisibles(false, false), isEmpty);
    expect(
      seleccionarTab(['categorias', 'duraciones'], 'alimentos'),
      'categorias',
    );
    expect(
      seleccionarTab(['categorias', 'duraciones'], 'duraciones'),
      'duraciones',
    );
  });
  test('Errores FK, unicidad, CHECK y árbol nunca muestran detalles SQL', () {
    expect(
      AppError.categoriaMessage(
        const PostgrestException(message: 'RAW FK', code: '23503'),
        deleting: true,
      ),
      'No se puede eliminar: la categoría tiene alimentos o subcategorías. Desactívala en su lugar.',
    );
    for (final code in ['23505', '23514', 'P0001', '22P02', '42501', 'XX000']) {
      expect(
        AppError.categoriaMessage(
          PostgrestException(message: 'RAW SQL SECRET', code: code),
        ),
        isNot(contains('RAW')),
      );
    }
  });
}
