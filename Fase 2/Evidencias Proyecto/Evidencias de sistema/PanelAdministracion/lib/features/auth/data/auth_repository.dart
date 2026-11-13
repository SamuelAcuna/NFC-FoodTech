import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/client.dart';
import '../domain/admin_context.dart';

abstract class AuthRepository {
  bool get hasSession;
  String? get userId;
  String get userLabel;
  Stream<AuthState> get onAuthStateChange;
  Future<void> login(String email, String password);
  Future<void> logout();
  Future<AdminContext> obtenerContexto();
  Future<List<String>> listarFactores();
  Future<TotpEnrollment> enrolarTotp();
  Future<void> verificarTotp(String factorId, String code);
  String nivelAal();
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(ref.watch(supabaseClientProvider)),
);

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this.client);
  final SupabaseClient client;
  @override
  bool get hasSession => client.auth.currentSession != null;
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  String get userLabel => client.auth.currentUser?.email ?? 'Administrador';
  @override
  Stream<AuthState> get onAuthStateChange => client.auth.onAuthStateChange;
  @override
  Future<void> login(String email, String password) async {
    await client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> logout() => client.auth.signOut(scope: SignOutScope.local);
  @override
  Future<AdminContext> obtenerContexto() async => AdminContext.fromJson(
    Map<String, dynamic>.from(await client.rpc('mi_contexto_admin') as Map),
  );
  @override
  Future<List<String>> listarFactores() async {
    final response = await client.auth.mfa.listFactors();
    return response.totp.map((factor) => factor.id).toList();
  }

  @override
  Future<TotpEnrollment> enrolarTotp() async {
    final response = await client.auth.mfa.enroll(factorType: FactorType.totp);
    final totp = response.totp!;
    return TotpEnrollment(
      factorId: response.id,
      qrCode: totp.qrCode,
      secret: totp.secret,
    );
  }

  @override
  Future<void> verificarTotp(String factorId, String code) async {
    await client.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  }

  @override
  String nivelAal() =>
      client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel?.name ?? '';
}
