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
              seedColor: const Color(0xFFFF6B00),
              primary: const Color(0xFFFF6B00),
              secondary: const Color(0xFF10B981),
              error: const Color(0xFFEF4444),
              background: Colors.white,
              surface: Colors.white,
              onPrimary: Colors.white,
              onBackground: const Color(0xFF1F2937),
              onSurface: const Color(0xFF1F2937),
              brightness: Brightness.light),
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Color(0xFF1F2937),
              centerTitle: false,
              elevation: 0,
              scrolledUnderElevation: 0,
              titleTextStyle: TextStyle(
                  color: Color(0xFF1F2937),
                  fontWeight: FontWeight.w800,
                  fontSize: 20)),
          textTheme: const TextTheme(
              headlineLarge: TextStyle(
                  color: Color(0xFF1F2937),
                  fontWeight: FontWeight.w800,
                  fontSize: 32,
                  height: 1.15),
              headlineMedium: TextStyle(
                  color: Color(0xFF1F2937),
                  fontWeight: FontWeight.w800,
                  fontSize: 24),
              titleLarge: TextStyle(
                  color: Color(0xFF1F2937),
                  fontWeight: FontWeight.w700,
                  fontSize: 18),
              titleMedium: TextStyle(
                  color: Color(0xFF1F2937),
                  fontWeight: FontWeight.w700,
                  fontSize: 15),
              bodyMedium: TextStyle(color: Color(0xFF374151))),
          inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                      color: Color(0xFFFF6B00), width: 1.5))),
          cardTheme: CardTheme(
              elevation: 0,
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0xFFEEF2F6)))),
          filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B00),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)))),
          outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  foregroundColor: const Color(0xFF1F2937),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)))),
          navigationBarTheme: const NavigationBarThemeData(
              backgroundColor: Colors.white,
              indicatorColor: Color(0xFFFFF4E8),
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              labelTextStyle: WidgetStatePropertyAll(TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937))),
              iconTheme: WidgetStatePropertyAll(
                  IconThemeData(color: Color(0xFF1F2937))))));
}
