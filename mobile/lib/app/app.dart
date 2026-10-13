import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../core/providers.dart';
import '../core/widgets.dart';
import '../features/auth/auth_screen.dart';
import '../features/customer/discovery.dart';
import '../features/cart/cart_screen.dart';
import '../features/checkout/checkout_screen.dart';
import '../features/addresses/addresses_screen.dart';
import '../features/orders/orders_screen.dart';
import '../features/vendor/vendor_screen.dart';
import '../features/delivery_partner/delivery_screen.dart';
import '../features/admin/admin_screen.dart';
import '../features/admin/settings_screen.dart';
import '../features/settings/profile_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/notifications/push_service.dart';

class DastakApp extends ConsumerStatefulWidget {
  const DastakApp({super.key});
  @override
  ConsumerState<DastakApp> createState() => _DastakAppState();
}

class _DastakAppState extends ConsumerState<DastakApp> {
  late GoRouter router;
  final messenger = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<AuthState>? auth;
  StreamSubscription<RemoteMessage>? opened, foreground;
  Widget guard(Widget child,
          [List<String> roles = const [
            'customer',
            'vendor',
            'delivery',
            'admin'
          ]]) =>
      RoleGuard(roles: roles, child: child);
  @override
  void initState() {
    super.initState();
    router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (c, s) => const DiscoveryScreen()),
          GoRoute(path: '/login', builder: (c, s) => const AuthScreen()),
          GoRoute(
              path: '/reset',
              builder: (c, s) => const AuthScreen(recovery: true)),
          GoRoute(
              path: '/store/:id',
              builder: (c, s) => StoreScreen(s.pathParameters['id']!)),
          GoRoute(path: '/cart', builder: (c, s) => const CartScreen()),
          GoRoute(
              path: '/checkout',
              builder: (c, s) => guard(const CheckoutScreen())),
          GoRoute(
              path: '/addresses',
              builder: (c, s) => guard(const AddressesScreen())),
          GoRoute(
              path: '/orders', builder: (c, s) => guard(const OrdersScreen())),
          GoRoute(
              path: '/orders/:id',
              builder: (c, s) => guard(OrderScreen(s.pathParameters['id']!))),
          GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
          GoRoute(
              path: '/notifications',
              builder: (c, s) => guard(const NotificationsScreen())),
          GoRoute(
              path: '/vendor',
              builder: (c, s) =>
                  guard(const VendorScreen(), ['vendor', 'admin'])),
          GoRoute(
              path: '/vendor/store/:id',
              builder: (c, s) => guard(
                  VendorStoreScreen(s.pathParameters['id']!),
                  ['vendor', 'admin'])),
          GoRoute(
              path: '/vendor/store/:id/menu',
              builder: (c, s) => guard(
                  MenuScreen(s.pathParameters['id']!), ['vendor', 'admin'])),
          GoRoute(
              path: '/vendor/product/:id/options',
              builder: (c, s) => guard(
                  OptionsScreen(s.pathParameters['id']!), ['vendor', 'admin'])),
          GoRoute(
              path: '/delivery',
              builder: (c, s) => guard(const DeliveryScreen(), ['delivery'])),
          GoRoute(
              path: '/delivery/profile',
              builder: (c, s) =>
                  guard(const DeliveryProfileScreen(), ['delivery'])),
          GoRoute(
              path: '/delivery/earnings',
              builder: (c, s) => guard(const EarningsScreen(), ['delivery'])),
          GoRoute(
              path: '/admin',
              builder: (c, s) => guard(const AdminScreen(), ['admin'])),
          GoRoute(
              path: '/admin/vendors',
              builder: (c, s) => guard(const AdminVendorsScreen(), ['admin'])),
          GoRoute(
              path: '/admin/payments',
              builder: (c, s) => guard(const AdminPaymentsScreen(), ['admin'])),
          GoRoute(
              path: '/admin/partners',
              builder: (c, s) => guard(const AdminPartnersScreen(), ['admin'])),
          GoRoute(
              path: '/admin/documents/:id',
              builder: (c, s) => guard(
                  AdminDocumentsScreen(s.pathParameters['id']!), ['admin'])),
          GoRoute(
              path: '/admin/settings',
              builder: (c, s) => guard(const AdminSettingsScreen(), ['admin'])),
          GoRoute(
              path: '/admin/audit',
              builder: (c, s) => guard(const AdminAuditScreen(), ['admin'])),
        ],
        errorBuilder: (c, s) => Scaffold(
            body: Center(
                child: FilledButton(
                    onPressed: () => c.go('/'),
                    child: const Text('Return to Dastak')))));
    auth = ref
        .read(repositoryProvider)
        .client
        .auth
        .onAuthStateChange
        .listen((event) {
      if (event.event == AuthChangeEvent.passwordRecovery) router.go('/reset');
      if (event.event == AuthChangeEvent.signedOut) router.go('/login');
      if (event.event == AuthChangeEvent.signedIn) {
        ref.read(pushServiceProvider).restore().catchError((Object _) {});
      }
    });
    if (PushService.configured) setupPush();
  }

  Future<void> setupPush() async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(backgroundPush);
      if (!mounted) return;
      opened = FirebaseMessaging.onMessageOpenedApp.listen(openNotification);
      foreground = FirebaseMessaging.onMessage.listen((message) {
        messenger.currentState?.showSnackBar(SnackBar(
          content: Text(message.notification?.title ?? 'New Dastak update'),
          action: SnackBarAction(
              label: 'View', onPressed: () => openNotification(message)),
        ));
      });
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) openNotification(initial);
      await ref.read(pushServiceProvider).restore();
    } catch (_) {
      /* Explicit enable action reports configuration errors to the user. */
    }
  }

  void openNotification(RemoteMessage message) {
    final id = message.data['order_id'];
    if (id is String && RegExp(r'^[0-9a-f-]{36}$').hasMatch(id)) {
      router.go('/orders/$id');
    } else {
      router.go('/notifications');
    }
  }

  @override
  void dispose() {
    auth?.cancel();
    opened?.cancel();
    foreground?.cancel();
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
      scaffoldMessengerKey: messenger,
      title: 'Dastak',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFEA580C),
              primary: const Color(0xFFC2410C)),
          scaffoldBackgroundColor: const Color(0xFFFFFBF7),
          appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFFFFBF7), centerTitle: false),
          inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
          cardTheme: CardTheme(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Color(0xFFF0E6DD)))),
          filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14)))));
}
