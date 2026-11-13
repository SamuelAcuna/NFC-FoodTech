import 'package:admin/features/soporte/data/soporte_repository.dart';
import 'package:admin/features/soporte/domain/solicitud_soporte.dart';

class FakeSoporteRepository implements SoporteRepository {
  List<SolicitudSoporte> rows = [];
  final calls = <String?>[];
  final operations = <List<String>>[];
  @override
  Future<List<SolicitudSoporte>> listar({
    String? estado = 'ABIERTAS',
    int offset = 0,
  }) async {
    calls.add(estado);
    return rows.skip(offset).take(50).toList();
  }

  @override
  Future<List<AgenteSoporte>> agentes() async => [
    AgenteSoporte.fromJson({'id': 'a', 'email': 'agente@test'}),
  ];
  @override
  Future<void> asignar(String id, String agente) async {
    operations.add(['ASIGNAR', id, agente]);
  }

  @override
  Future<void> responder(String id, String respuesta) async {
    operations.add(['RESPONDER', id, respuesta]);
  }

  @override
  Future<void> cerrar(String id) async {
    operations.add(['CERRAR', id]);
  }
}
