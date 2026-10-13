import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/app.dart';
import 'core/providers.dart';
import 'core/secure_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isEmpty || key.isEmpty) {
    runApp(const SetupApp());
    return;
  }
  try {
    await Supabase.initialize(
        url: url,
        anonKey: key,
        debug: false,
        authOptions: const FlutterAuthClientOptions(
            localStorage: SecureSessionStorage(),
            authFlowType: AuthFlowType.pkce));
    final prefs = await SharedPreferences.getInstance();
    runApp(ProviderScope(
        overrides: [preferencesProvider.overrideWithValue(prefs)],
        child: const DastakApp()));
  } catch (_) {
    runApp(const SetupApp(
        message:
            'Dastak could not initialize. Check the app configuration and restart.'));
  }
}

class SetupApp extends StatelessWidget {
  final String message;
  const SetupApp(
      {this.message =
          'Supabase is not configured for this build. Supply SUPABASE_URL and SUPABASE_ANON_KEY using the environment config, then rebuild.',
      super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
      home: Scaffold(
          body: SafeArea(
              child: Center(
                  child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.doorbell_rounded,
                            size: 64, color: Colors.deepOrange),
                        const SizedBox(height: 16),
                        const Text('Dastak',
                            style: TextStyle(
                                fontSize: 32, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Text(message, textAlign: TextAlign.center)
                      ]))))));
}
