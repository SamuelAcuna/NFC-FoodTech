import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/categorias_repository.dart';
import '../domain/categoria.dart';

final categoriasProvider = FutureProvider.autoDispose<List<Categoria>>((
  ref,
) async {
  final context = ref.watch(adminContextProvider);
  if (context?.puede('CATEGORIAS_GESTIONAR') != true) return [];
  return ordenarArbol(await ref.watch(categoriasRepositoryProvider).listar());
});
final conteoAlimentosProvider = FutureProvider.autoDispose<Map<int, int>?>((
  ref,
) {
  if (ref.watch(adminContextProvider)?.puede('CATEGORIAS_GESTIONAR') != true) {
    return null;
  }
  return ref.watch(categoriasRepositoryProvider).contarAlimentos();
});
