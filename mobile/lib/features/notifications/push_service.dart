import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../core/providers.dart';
import '../../core/repository.dart';

final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(ref.watch(repositoryProvider));
  ref.onDispose(service.dispose);
  return service;
});
@pragma('vm:entry-point')
Future<void> backgroundPush(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushService {
  static const configured = bool.fromEnvironment('PUSH_ENABLED');
  final DastakRepository repo;
  StreamSubscription<String>? refresh;
  String? token;
  PushService(this.repo);
  Future<void> restore() async {
    if (!configured || repo.client.auth.currentUser == null) return;
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    final permission =
        await FirebaseMessaging.instance.getNotificationSettings();
    if ([AuthorizationStatus.authorized, AuthorizationStatus.provisional]
        .contains(permission.authorizationStatus)) {
      await enable();
    }
  }

  Future<void> enable() async {
    if (!configured) {
      throw StateError(
          'Push is unavailable until Firebase and APNs are configured for this build. In-app notifications are available.');
    }
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(backgroundPush);
    final permission = await FirebaseMessaging.instance.requestPermission();
    if (![AuthorizationStatus.authorized, AuthorizationStatus.provisional]
        .contains(permission.authorizationStatus)) {
      throw StateError('Notification permission was not granted');
    }
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
            alert: false, badge: true, sound: false);
    token = await FirebaseMessaging.instance.getToken();
    if (token == null) {
      throw StateError(
          'Device token is not ready. Retry on a configured device.');
    }
    await register(token!);
    await refresh?.cancel();
    refresh = FirebaseMessaging.instance.onTokenRefresh.listen((v) {
      if (repo.client.auth.currentUser == null) return;
      register(v).catchError((Object _) {});
    });
  }

  Future<void> register(String value) async {
    await repo.client.from('fcm_tokens').upsert({
      'user_id': repo.uid,
      'token': value,
      'platform':
          defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'
    }, onConflict: 'token');
    token = value;
  }

  Future<void> disable() async {
    await refresh?.cancel();
    refresh = null;
    if (!configured || Firebase.apps.isEmpty) return;
    token ??= await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await repo.client
          .from('fcm_tokens')
          .delete()
          .eq('user_id', repo.uid)
          .eq('token', token!);
    }
    await FirebaseMessaging.instance.deleteToken();
    token = null;
  }

  void dispose() {
    refresh?.cancel();
  }
}
