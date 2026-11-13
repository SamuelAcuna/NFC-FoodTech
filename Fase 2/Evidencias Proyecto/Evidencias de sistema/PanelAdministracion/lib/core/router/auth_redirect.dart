import '../../features/auth/domain/admin_context.dart';

String? resolverRedireccion(
  bool sesion,
  String aal,
  List<String> factores,
  AdminContext? contexto,
  String rutaDestino,
) {
  if (!sesion || contexto == null || !contexto.tieneAcceso) {
    return rutaDestino == '/login' ? null : '/login';
  }
  if (aal != 'aal2' || contexto.aal != 'aal2') {
    final destino = factores.isEmpty ? '/mfa/enrolar' : '/mfa/verificar';
    return rutaDestino == destino ? null : destino;
  }
  if (rutaDestino == '/login' || rutaDestino.startsWith('/mfa/')) return '/';
  return null;
}
