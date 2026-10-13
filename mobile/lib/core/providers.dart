import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'repository.dart';
import 'models.dart';

final preferencesProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError());
final repositoryProvider = Provider<DastakRepository>(
    (ref) => DastakRepository(Supabase.instance.client));
final authProvider = StreamProvider<AuthState>(
    (ref) => ref.watch(repositoryProvider).client.auth.onAuthStateChange);
final accountProvider = FutureProvider<Account?>((ref) {
  ref.watch(authProvider);
  return ref.watch(repositoryProvider).account();
});
