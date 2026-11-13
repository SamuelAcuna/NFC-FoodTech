import 'package:admin/features/administradores/data/administradores_repository.dart';
import 'package:admin/features/administradores/domain/administrador.dart';

class FakeAdministradoresRepository implements AdministradoresRepository {
  final operations = <List<String>>[];
  List<Administrador> admins = [
    Administrador.fromJson({
      'perfil_id': 'a',
      'email': 'a@test',
      'nombre': 'Ana',
      'apellido': 'Pérez',
      'estado_cuenta': 'ACTIVA',
      'roles': ['ADMIN'],
      'mfa_activo': true,
    }),
  ];
  @override
  Future<AdministradoresData> cargar() async => AdministradoresData(admins, [
    RolAdministrativo(
      id: 1,
      codigo: 'ADMIN',
      nombre: 'Administrador',
      permisos: ['Gestionar roles'],
    ),
    RolAdministrativo(
      id: 2,
      codigo: 'EDITOR_CATALOGO',
      nombre: 'Editor de catálogo',
      permisos: ['Gestionar catálogo'],
    ),
  ]);
  @override
  Future<void> asignar(String email, String codigo) async {
    operations.add(['ASIGNAR', email, codigo]);
  }

  @override
  Future<void> quitar(String id, String codigo) async {
    operations.add(['QUITAR', id, codigo]);
  }
}
