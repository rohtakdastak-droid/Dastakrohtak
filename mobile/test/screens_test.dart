import 'package:dastak/core/models.dart';
import 'package:dastak/core/providers.dart';
import 'package:dastak/core/widgets.dart';
import 'package:dastak/features/auth/auth_screen.dart';
import 'package:dastak/features/cart/cart_controller.dart';
import 'package:dastak/features/cart/cart_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('sign-in validates before contacting backend', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: AuthScreen())));
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Use at least 8 characters'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer cannot render admin workspace', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      accountProvider.overrideWith((ref) async => Account({
        'id':'test','role':'customer','status':'active','display_name':'Test'
      }))
    ], child: const MaterialApp(home: RoleGuard(roles: ['admin'], child: Text('Privileged controls')))));
    await tester.pumpAndSettle();
    expect(find.text('Privileged controls'), findsNothing);
    expect(find.text('This workspace is not available to your account.'), findsOneWidget);
  });

  testWidgets('bag quantity and empty state update at phone width', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cart = CartController(prefs);
    await cart.add(Product({'id':'p','vendor_id':'v','name':'Milk','price_paise':6500,'stock':2,'is_available':true}), []);
    final router = GoRouter(initialLocation:'/cart',routes:[GoRoute(path:'/cart',builder:(c,s)=>const CartScreen())]);
    tester.view.physicalSize = const Size(360,780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(overrides:[preferencesProvider.overrideWithValue(prefs),cartProvider.overrideWith((ref)=>cart)],child:MaterialApp.router(routerConfig:router)));
    await tester.pumpAndSettle();
    expect(find.text('₹65.00'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pumpAndSettle();
    expect(find.text('₹130.00'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pump();
    expect(find.text('Requested quantity is unavailable'), findsOneWidget);
    await tester.tap(find.text('Clear bag'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your bag is empty'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
}
