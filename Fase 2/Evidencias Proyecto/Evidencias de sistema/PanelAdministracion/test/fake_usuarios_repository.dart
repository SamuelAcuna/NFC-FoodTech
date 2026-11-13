import 'package:admin/features/usuarios/data/usuarios_repository.dart';
import 'package:admin/features/usuarios/domain/usuario_admin.dart';

class FakeUsuariosRepository implements UsuariosRepository {
  List<UsuarioAdmin> rows = [];
  final calls = <Map<String, dynamic>>[];
  final changes = <List<String>>[];
  @override
  Future<List<UsuarioAdmin>> listar({
    String? busqueda,
    String? estado,
    String? desde,
    String? hasta,
    String? actividad,
    int offset = 0,
  }) async {
    calls.add({
      'busqueda': busqueda,
      'estado': estado,
      'desde': desde,
      'hasta': hasta,
      'actividad': actividad,
      'offset': offset,
    });
    return rows.skip(offset).take(50).toList();
  }

  @override
  Future<void> cambiarEstado(String id, String estado, String motivo) async {
    changes.add([id, estado, motivo]);
  }
}
