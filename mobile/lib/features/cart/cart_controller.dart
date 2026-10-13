import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models.dart';
import '../../core/providers.dart';

final cartProvider = StateNotifierProvider<CartController, List<CartLine>>(
    (ref) => CartController(ref.watch(preferencesProvider)));

class CartController extends StateNotifier<List<CartLine>> {
  final SharedPreferences prefs;
  CartController(this.prefs) : super([]) {
    try {
      state = (jsonDecode(prefs.getString('cart') ?? '[]') as List)
          .map((j) => CartLine.fromJson(Map<String, dynamic>.from(j)))
          .toList();
      if (state.map((l) => l.product.vendorId).toSet().length > 1) state = [];
    } catch (_) {
      state = [];
    }
  }
  Future<void> _save() async {
    await prefs.setString(
        'cart', jsonEncode(state.map((l) => l.toJson()).toList()));
  }

  Future<void> add(Product p, List<ProductOption> options,
      {bool replace = false}) async {
    if (!p.available || p.stock == 0) throw StateError('Item is unavailable');
    if (state.isNotEmpty && state.first.product.vendorId != p.vendorId) {
      if (!replace) {
        throw StateError(
            'Your bag contains another store. Clear it to switch stores.');
      }
      state = [];
    }
    final probe = CartLine(p, 1, options);
    final index = state.indexWhere((l) => l.key == probe.key);
    final qty = index < 0 ? 1 : state[index].quantity + 1;
    _checkStock(p, probe.key, qty);
    final next = CartLine(p, qty, options);
    state = index < 0
        ? [...state, next]
        : [
            for (var i = 0; i < state.length; i++)
              if (i == index) next else state[i]
          ];
    await _save();
  }

  /// Stock is shared by every line of the same product (e.g. half and full plates).
  void _checkStock(Product p, String key, int quantity) {
    final others = state
        .where((l) => l.product.id == p.id && l.key != key)
        .fold<int>(0, (s, l) => s + l.quantity);
    if (quantity > 99 || (p.stock != null && quantity + others > p.stock!)) {
      throw StateError('Requested quantity is unavailable');
    }
  }

  Future<void> quantity(String key, int quantity) async {
    final line = state.firstWhere((l) => l.key == key);
    _checkStock(line.product, key, quantity);
    state = [
      for (final l in state)
        if (l.key != key)
          l
        else if (quantity > 0)
          CartLine(l.product, quantity, l.options)
    ];
    await _save();
  }

  Future<void> clear() async {
    state = [];
    await _save();
  }
}
