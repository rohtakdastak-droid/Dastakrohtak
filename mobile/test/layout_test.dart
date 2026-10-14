import 'package:dastak/core/models.dart';
import 'package:dastak/core/providers.dart';
import 'package:dastak/core/repository.dart';
import 'package:dastak/core/theme.dart';
import 'package:dastak/features/admin/admin_screen.dart';
import 'package:dastak/features/auth/auth_screen.dart';
import 'package:dastak/features/customer/discovery.dart';
import 'package:dastak/features/delivery_partner/delivery_screen.dart';
import 'package:dastak/features/vendor/vendor_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Serves fixed dashboard data so layouts can be checked without a backend.
class FakeRepository extends DastakRepository {
  final Map<String, dynamic> data;
  FakeRepository(this.data)
      : super(SupabaseClient('http://localhost:9', 'test-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false)));
  @override
  String get uid => 'user';
  @override
  Future<dynamic> rpc(String name, [Json params = const {}]) async => data[name];
  @override
  Future<List<Json>> rows(String table,
          {String select = '*',
          String sort = 'created_at',
          bool ascending = false,
          Map<String, Object> filters = const {},
          int page = 0}) async =>
      [];
  @override
  RealtimeChannel watch(String table, void Function() changed, {String? column, String? value}) =>
      client.channel('test-$table');
}

const long = 'A very long restaurant or partner name that keeps going';

final fixtures = <String, dynamic>{
  'admin_dashboard': {
    'restaurants_total': 12345, 'restaurants_active': 12000, 'restaurants_open_now': 9876,
    'restaurant_applications_pending': 999, 'partners_total': 54321, 'partners_pending_verification': 4321,
    'partners_online': 1234, 'partner_qr_pending': 77, 'customers_total': 987654, 'orders': 123456,
    'orders_active_now': 4567, 'orders_awaiting_payment': 890, 'orders_completed': 120000, 'orders_cancelled': 3456,
    'gross_order_value_paise': 9999999999, 'restaurant_sales_paise': 8888888888, 'delivery_fees_paise': 777777777,
    'platform_commission_paise': 66666666, 'partner_earnings_paise': 555555555, 'payouts_pending_paise': 44444444,
    'payouts_completed_paise': 333333333, 'payments_pending_verification': 222, 'restaurant_rating_avg': 4.56,
    'partner_rating_avg': 4.78, 'reviews_reported': 11,
  },
  'vendor_dashboard': {
    'vendor': {
      'id': 'v', 'name': long, 'dispatch_address': '$long, Sector 3, Delhi Road, Rohtak - 124001',
      'is_active': true, 'temporarily_closed': true, 'closed_reason': 'Back at 7 pm after the evening rush is over',
    },
    'is_open': false, 'orders': 12345, 'awaiting_payment': 123, 'new_orders': 456, 'preparing': 789,
    'ready_for_pickup': 1011, 'in_delivery': 1213, 'completed': 14151, 'cancelled': 1617,
    'sales_paise': 9999999999, 'commission_paise': 888888888, 'average_order_paise': 77777777,
    'rating_avg': 4.56, 'rating_count': 12345,
    'popular_items': [
      {'name': long, 'quantity': 12345, 'sales_paise': 9999999999}
    ],
    'active_deliveries': [
      {'order_id': 'o', 'order_number': 'DST-ABCDEFGH', 'status': 'out_for_delivery', 'partner': long, 'partner_phone': '9876543210', 'vehicle': 'HR12AB1234'}
    ],
  },
  'my_partner_dashboard': {
    'verification_status': 'action_required', 'review_reason': 'Licence photo is blurred, please upload again',
    'block_reason': 'Corrections are required: Licence photo is blurred, please upload a clearer photo', 'is_online': false,
    'qr_status': 'pending', 'legal_name': long, 'can_accept': false, 'deliveries_today': 1234, 'deliveries_week': 5678,
    'deliveries_month': 91011, 'deliveries_total': 121314, 'active_orders': 1, 'accepted_total': 151617,
    'cancelled_or_failed': 1819, 'earned_today_paise': 999999999, 'earned_total_paise': 8888888888,
    'paid_paise': 777777777, 'in_payout_paise': 66666666, 'pending_payout_paise': 555555555,
    'rating_avg': 4.95, 'rating_count': 12345,
  },
  'my_active_delivery': [
    {'order_id': 'o', 'order_number': 'DST-ABCDEFGH', 'status': 'out_for_delivery', 'vendor_name': long,
      'pickup_address': '$long, Rohtak', 'destination_address': 'H.No 214, 2nd floor, Sector 3, near Tilak Nagar park, Rohtak - 124001',
      'item_count': 12, 'customer_note': 'Please ring the bell twice and call when you reach the gate'}
  ],
  'list_available_orders': [
    {'id': 'o2', 'order_number': 'DST-ZYXWVUTS', 'vendor_name': long, 'pickup_address': '$long, Rohtak',
      'destination_address': 'H.No 214, 2nd floor, Sector 3, near Tilak Nagar park, Rohtak - 124001',
      'delivery_distance_km': 12.75, 'delivery_fee_paise': 1234500}
  ],
  'active_posters': [],
  'discover_stores': [
    for (final open in [true, false])
      {
        'id': 'v$open', 'name': long, 'cuisine': 'North Indian, Chinese, Fast food, Desserts', 'is_open': open,
        'temporarily_closed': !open, 'closed_reason': 'Back at 7 pm after the evening rush is over',
        'distance_km': 12.34, 'prep_time_minutes': 45, 'min_order_paise': 99900, 'rating_avg': 4.56, 'rating_count': 12345,
        'dispatch_address': '$long, Rohtak', 'opening_hours': {},
        'preview': [
          for (var i = 0; i < 4; i++)
            {'id': 'p$i', 'name': long, 'price_paise': 99999, 'has_choices': i.isEven, 'diet': 'veg', 'available': i != 3}
        ],
      }
  ],
};

Future<void> pumpScreen(WidgetTester tester, Widget screen, double width) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        preferencesProvider.overrideWithValue(prefs),
        repositoryProvider.overrideWithValue(FakeRepository(fixtures)),
        accountProvider.overrideWith((ref) async =>
            Account({'id': 'user', 'display_name': long, 'phone': '9876543210', 'role': 'admin', 'status': 'active'})),
      ],
      child: MaterialApp(
          theme: buildTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.6)), child: child!),
          home: screen)));
  await tester.pumpAndSettle();
}

/// Scrolls through the whole page so every tile is laid out and painted.
Future<void> scrollAll(WidgetTester tester) async {
  final list = find.byType(Scrollable).first;
  for (var i = 0; i < 25; i++) {
    await tester.drag(list, const Offset(0, -500));
    await tester.pump();
  }
}

void main() {
  for (final width in [360.0, 320.0]) {
    for (final (name, screen) in [
      ('admin dashboard', const AdminScreen()),
      ('restaurant dashboard', const VendorStoreScreen('v')),
      ('delivery partner dashboard', const DeliveryScreen()),
      ('sign in', const AuthScreen()),
      ('customer home', const DiscoveryScreen()),
    ]) {
      testWidgets('$name fits at ${width.toInt()} px with large phone text', (tester) async {
        final errors = <String>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (details) => errors.add(TextTreeRenderer()
            .render(details.toDiagnosticsNode(style: DiagnosticsTreeStyle.error))
            .split('\n')
            .where((l) => l.contains('overflowed') || l.contains('lib/features') || l.contains('lib/core'))
            .take(4)
            .join(' | '));
        try {
          await pumpScreen(tester, screen, width);
          await scrollAll(tester);
        } finally {
          FlutterError.onError = previous;
        }
        expect(errors.toSet(), isEmpty);
      });
    }
  }
}
