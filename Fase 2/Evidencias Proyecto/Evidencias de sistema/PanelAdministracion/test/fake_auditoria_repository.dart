import 'package:admin/features/auditoria/data/auditoria_repository.dart';
import 'package:admin/features/auditoria/domain/registro_auditoria.dart';

class FakeAuditoriaRepository implements AuditoriaRepository {
  final calls = <Map<String, dynamic>>[];
  List<RegistroAuditoria> rows = [];
  @override
  Future<List<RegistroAuditoria>> listar({
    String? desde,
    String? hasta,
    String? entidad,
    String? accion,
    int offset = 0,
  }) async {
    calls.add({
      'desde': desde,
      'hasta': hasta,
      'entidad': entidad,
      'accion': accion,
      'offset': offset,
    });
    return rows.skip(offset).take(50).toList();
  }
}
