import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dastak/core/repository.dart';

/// Opt-in staging only. Never uses a production user or submits a real payment.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const environment = String.fromEnvironment('APP_ENV');
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  const email = String.fromEnvironment('TEST_CUSTOMER_EMAIL');
  const password = String.fromEnvironment('TEST_CUSTOMER_PASSWORD');
  testWidgets('staging auth, schema capability, catalog and ownership', (tester) async {
    expect(environment, 'staging', reason: 'This suite must never run on production');
    expect(email, isNotEmpty, reason: 'Provide staging accounts securely with dart defines');
    final client = SupabaseClient(url, key);
    final repo = DastakRepository(client);
    try {
      await client.auth.signInWithPassword(email: email, password: password);
      final account = await repo.account();
      expect(account?.role, 'customer');
      final capability = await repo.rpc('mobile_checkout_capabilities');
      expect(capability['version'], 1);
      await repo.stores();
      final orders = await repo.rows('orders');
      expect(orders.every((order) => order['customer_id'] == client.auth.currentUser!.id), true);
      await expectLater(repo.rpc('mobile_admin_metrics'), throwsA(isA<PostgrestException>()));
      await client.auth.signOut();
      expect(client.auth.currentSession, isNull);
    } finally {
      await client.dispose();
    }
  });
}
