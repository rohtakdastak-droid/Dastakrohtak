import 'package:dastak/core/models.dart';
import 'package:dastak/features/cart/cart_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Product thali({int? stock}) => Product({
      'id': 't',
      'vendor_id': 'v',
      'name': 'Paneer thali',
      'price_paise': 12000,
      'stock': stock,
      'is_available': true,
      'product_options': [
        {'id': 'h', 'group_name': 'Portion', 'label': 'Half plate', 'price_delta_paise': 0, 'selection': 'single_required'},
        {'id': 'f', 'group_name': 'Portion', 'label': 'Full plate', 'price_delta_paise': 8000, 'selection': 'single_required'},
        {'id': 'x', 'group_name': 'Add-ons', 'label': 'Extra paneer', 'price_delta_paise': 3000},
      ]
    });

void main() {
  test('half/full items show both prices and expose one required group', () {
    final p = thali();
    expect(p.priceText, 'Half plate ₹120.00 • Full plate ₹200.00');
    expect(p.choiceGroups.keys, ['Portion']);
    expect(p.options.firstWhere((o) => o.id == 'x').required, isFalse);
  });

  test('half and full plates of one dish are separate bag lines with shared stock', () async {
    SharedPreferences.setMockInitialValues({});
    final cart = CartController(await SharedPreferences.getInstance());
    final p = thali(stock: 3);
    final half = p.options.firstWhere((o) => o.id == 'h');
    final full = p.options.firstWhere((o) => o.id == 'f');
    await cart.add(p, [half]);
    await cart.add(p, [full]);
    await cart.add(p, [half]);
    expect(cart.state.length, 2);
    expect(cart.state.map((l) => l.quantity), [2, 1]);
    expect(cart.state.fold<int>(0, (s, l) => s + l.total), 12000 * 2 + 20000);
    await expectLater(cart.add(p, [full]), throwsStateError);
    await expectLater(cart.quantity(cart.state.last.key, 2), throwsStateError);
    await cart.quantity(cart.state.first.key, 1);
    await cart.quantity(cart.state.last.key, 2);
    expect(cart.state.map((l) => l.quantity), [1, 2]);
    final restored = CartController(await SharedPreferences.getInstance());
    expect(restored.state.map((l) => l.key), cart.state.map((l) => l.key));
    expect(restored.state.last.request['options'], [
      {'option_id': 'f'}
    ]);
  });
}
