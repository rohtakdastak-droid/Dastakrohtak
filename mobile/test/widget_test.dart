import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dastak/core/models.dart';
import 'package:dastak/core/repository.dart';
import 'package:dastak/core/widgets.dart';
import 'package:dastak/features/cart/cart_controller.dart';
import 'package:dastak/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Product product({String id = 'p', String vendor = 'v', int stock = 3}) =>
    Product({
      'id': id,
      'vendor_id': vendor,
      'name': 'Paneer',
      'price_paise': 10025,
      'stock': stock,
      'is_available': true,
      'diet': 'veg'
    });
void main() {
  test('Image content type follows bytes and unsupported files fail', () {
    expect(DastakRepository.imageFormat(Uint8List.fromList([255,216,255])), ('jpg','image/jpeg'));
    expect(DastakRepository.imageFormat(Uint8List.fromList([137,80,78,71,13,10,26,10])), ('png','image/png'));
    expect(() => DastakRepository.imageFormat(Uint8List.fromList([1,2,3])), throwsStateError);
  });
  test('Legacy backend cannot receive a quote request', () async {
    var edgeCalls = 0;
    final client = SupabaseClient('https://example.supabase.co','public-test-key',httpClient:MockClient((request) async {
      if(request.url.path.contains('/functions/')) edgeCalls++;
      return http.Response('{"version":0}',200,request:request,headers:{'content-type':'application/json'});
    }));
    await expectLater(DastakRepository(client).checkout({'quote_only':true}), throwsStateError);
    expect(edgeCalls,0);
    await client.dispose();
  });
  test('Paise stay exact and options apply per quantity', () {
    final line = CartLine(product(), 3, [
      ProductOption({
        'id': 'o',
        'group_name': 'Extra',
        'label': 'Cheese',
        'price_delta_paise': 125
      })
    ]);
    expect(line.total, 30450);
    expect(money(line.total), '₹304.50');
    expect(line.request['options'], [
      {'option_id': 'o'}
    ]);
    expect(line.request.containsKey('price_paise'), false);
  });
  test('Reject invalid quantity', () {
    expect(() => CartLine(product(), 0, []), throwsArgumentError);
    expect(() => CartLine(product(), 100, []), throwsArgumentError);
  });
  test('Coordinate validation never invents locations', () {
    expect(validCoordinates(null, null), false);
    expect(validCoordinates(double.nan, 76), false);
    expect(validCoordinates(91, 76), false);
    expect(validCoordinates(28.89, 76.60), true);
    expect(validCoordinates(0, 0), true);
  });
  test('Only valid vendor and partner steps are offered', () {
    expect(vendorTransitions('vendor_confirmation'), ['preparing', 'rejected']);
    expect(vendorTransitions('delivered'), isEmpty);
    expect(deliveryTransition('assigned'), 'picked_up');
    expect(deliveryTransition('preparing'), null);
    expect(deliveryTransition('delivered'), null);
  });
  test('Persist cart, enforce single store, validate stock and clear',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cart = CartController(prefs);
    await cart.add(product(), []);
    await cart.quantity('p', 3);
    expect(cart.state.single.quantity, 3);
    await expectLater(cart.add(product(), []), throwsStateError);
    await expectLater(
        cart.add(product(id: 'b', vendor: 'other'), []), throwsStateError);
    final restored = CartController(prefs);
    expect(restored.state.single.total, 30075);
    await cart.add(product(id: 'b', vendor: 'other'), [], replace: true);
    expect(cart.state.single.product.vendorId, 'other');
    await cart.quantity('b', 0);
    expect(cart.state, isEmpty);
    expect(CartController(prefs).state, isEmpty);
  });
  test('Corrupt persisted bag recovers safely', () async {
    SharedPreferences.setMockInitialValues({'cart': '{bad'});
    final cart = CartController(await SharedPreferences.getInstance());
    expect(cart.state, isEmpty);
  });
  test('Repository paginates and scopes product requests', () async {
    late Uri request;
    final client =
        SupabaseClient('https://example.supabase.co', 'public-test-key',
            httpClient: MockClient((r) async {
      request = r.url;
      return http.Response('[]', 200,
          request: r, headers: {'content-type': 'application/json'});
    }));
    final repo = DastakRepository(client);
    expect(await repo.products('vendor-id', page: 2), isEmpty);
    expect(request.queryParameters['vendor_id'], 'eq.vendor-id');
    expect(request.queryParameters['offset'], '60');
    expect(request.queryParameters['limit'], '30');
    await client.dispose();
  });
  test('Checkout keeps attempt id and exposes server rejection', () async {
    Json? body;
    final client =
        SupabaseClient('https://example.supabase.co', 'public-test-key',
            httpClient: MockClient((r) async {
      if (r.url.path.contains('mobile_checkout_capabilities')) {
        return http.Response('{"version":1}', 200,
            request: r, headers: {'content-type': 'application/json'});
      }
      body = jsonDecode(r.body);
      return http.Response('{"error":"Price changed"}', 400,
          headers: {'content-type': 'application/json'});
    }));
    final repo = DastakRepository(client);
    await expectLater(
        repo.checkout({'request_id': 'same-attempt'}), throwsStateError);
    expect(body!['request_id'], 'same-attempt');
    await client.dispose();
  });
  testWidgets('Missing environment is explicit rather than fake data',
      (tester) async {
    await tester.pumpWidget(const SetupApp());
    expect(find.text('Dastak'), findsOneWidget);
    expect(find.textContaining('Supabase is not configured'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Action locks duplicate taps until request completes',
      (tester) async {
    var calls = 0;
    final completer = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ActionButton('Place order', () async {
      calls++;
      await completer.future;
    }))));
    await tester.tap(find.text('Place order'));
    await tester.pump();
    await tester.tap(find.text('Please wait…'));
    expect(calls, 1);
    completer.complete();
    await tester.pumpAndSettle();
    expect(find.text('Place order'), findsOneWidget);
  });
  testWidgets('Failed request shows actionable error and unlocks button',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ActionButton('Retry', () async {
      throw StateError('Insufficient stock');
    }))));
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.text('Insufficient stock'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
