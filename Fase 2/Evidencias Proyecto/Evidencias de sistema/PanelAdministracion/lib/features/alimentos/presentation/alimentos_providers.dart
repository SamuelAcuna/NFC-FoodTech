import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../categorias/data/categorias_repository.dart';
import '../../categorias/domain/categoria.dart';
import '../data/alimentos_repository.dart';
import '../domain/alimento.dart';

class CatalogoAlimentos {
  const CatalogoAlimentos(this.alimentos, this.categorias);
  final List<Alimento> alimentos;
  final List<Categoria> categorias;
}

final catalogoAlimentosProvider = FutureProvider.autoDispose<CatalogoAlimentos>(
  (ref) async {
    if (ref.watch(adminContextProvider)?.puede('CATALOGO_GESTIONAR') != true) {
      return const CatalogoAlimentos([], []);
    }
    final alimentosRepository = ref.watch(alimentosRepositoryProvider);
    final categoriasRepository = ref.watch(categoriasRepositoryProvider);
    final alimentos = await alimentosRepository.listar();
    final categorias = await categoriasRepository.listar();
    return CatalogoAlimentos(alimentos, ordenarArbol(categorias));
  },
);
