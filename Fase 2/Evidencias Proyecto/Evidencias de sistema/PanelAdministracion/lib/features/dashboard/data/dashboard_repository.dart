import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/client.dart';
import '../domain/dashboard_data.dart';

abstract class DashboardRepository {
  Future<DashboardData> cargar();
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => SupabaseDashboardRepository(ref.watch(supabaseClientProvider)),
);

class SupabaseDashboardRepository implements DashboardRepository {
  SupabaseDashboardRepository(this.client);
  final SupabaseClient client;
  @override
  Future<DashboardData> cargar() async => DashboardData.fromJson(
    Map<String, dynamic>.from(await client.rpc('admin_dashboard') as Map),
  );
}
