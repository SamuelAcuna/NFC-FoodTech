import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../categorias/data/categorias_repository.dart';
import '../../categorias/domain/categoria.dart';
import '../data/propuestos_repository.dart';
import '../domain/propuesta.dart';

final contarPropuestosProvider = FutureProvider.autoDispose<int>((ref) {
  if (ref.watch(adminContextProvider)?.puede('PROPUESTOS_REVISAR') != true) {
    return 0;
  }
  return ref.watch(propuestosRepositoryProvider).contar();
});

class PropuestosData {
  const PropuestosData(this.propuestas, this.categorias);
  final List<Propuesta> propuestas;
  final List<Categoria> categorias;
}

final propuestosDataProvider = FutureProvider.autoDispose<PropuestosData>((
  ref,
) async {
  if (ref.watch(adminContextProvider)?.puede('PROPUESTOS_REVISAR') != true) {
    return const PropuestosData([], []);
  }
  final repository = ref.watch(propuestosRepositoryProvider);
  final categorias = ref.watch(categoriasRepositoryProvider);
  final propuestas = await repository.listar();
  return PropuestosData(propuestas, await categorias.listar());
});
