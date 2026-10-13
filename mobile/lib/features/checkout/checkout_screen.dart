import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../addresses/addresses_screen.dart';
import '../cart/cart_controller.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  List<Address> addresses = [];
  Address? selected;
  Json? quote, pending;
  Object? error;
  bool loading = true;
  final note = TextEditingController();
  String get attemptKey => 'checkout.${ref.read(repositoryProvider).uid}';
  @override
  void initState() {
    super.initState();
    load();
    final saved = ref.read(preferencesProvider).getString(attemptKey);
    if (saved != null) {
      try {
        pending = Map<String, dynamic>.from(jsonDecode(saved));
      } catch (_) {
        error = StateError(
            'Saved checkout could not be read. Contact support before creating another order.');
      }
    }
  }

  Future<void> load() async {
    try {
      final repo = ref.read(repositoryProvider);
      final rows =
          await repo.rows('user_addresses', filters: {'user_id': repo.uid});
      if (mounted) {
        setState(() {
          addresses = rows.map(Address.new).toList();
          selected = addresses.firstOrNull;
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          loading = false;
        });
      }
    }
  }

  Json request() {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty || selected == null) {
      throw StateError('Add items and select a saved address');
    }
    return {
      'vendor_id': cart.first.product.vendorId,
      'dest_address': selected!.text,
      'dest_lat': selected!.lat,
      'dest_lng': selected!.lng,
      'customer_note': note.text.trim(),
      'items': cart.map((l) => l.request).toList()
    };
  }

  Future<void> place() async {
    if (pending == null) {
      if (quote == null) throw StateError('Review a delivery quote first');
      pending = {
        ...request(),
        'request_id': const Uuid().v4(),
        'expected_total_paise': quote!['total_payable_paise']
      };
      if (!await ref
          .read(preferencesProvider)
          .setString(attemptKey, jsonEncode(pending))) {
        pending = null;
        throw StateError('Could not save checkout attempt. Please retry.');
      }
      setState(() {});
    }
    final result = await ref.read(repositoryProvider).checkout(pending!);
    await ref.read(preferencesProvider).remove(attemptKey);
    await ref.read(cartProvider.notifier).clear();
    if (mounted) context.go('/orders/${result['order_id']}');
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame('Review checkout',
      child: ListView(padding: const EdgeInsets.all(20), children: [
        if (loading) const LinearProgressIndicator(),
        if (error != null) Failure(error!, load),
        if (pending != null) ...[
          const Text(
              'An order attempt is saved. Retry to recover its result safely, including after a lost connection. Your original items and address are preserved.'),
          Text(pending!['dest_address']),
          ActionButton('Retry saved order', place),
          const SizedBox(height: 16),
          const Text(
              'If the server rejected this attempt (for example a price change), check order history before discarding it.'),
          TextButton(
              onPressed: () async {
                context.push('/orders');
              },
              child: const Text('Check order history')),
          TextButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                            title: const Text('Discard saved attempt?'),
                            content: const Text(
                                'Only discard after checking order history. A timed-out request may already have created an order.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Keep')),
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Discard'))
                            ]));
                if (confirm == true) {
                  await ref.read(preferencesProvider).remove(attemptKey);
                  if (mounted) {
                    setState(() {
                      pending = null;
                      quote = null;
                    });
                  }
                }
              },
              child: const Text('Discard rejected attempt'))
        ] else ...[
          Text('Deliver to', style: Theme.of(context).textTheme.titleLarge),
          for (final a in addresses)
            RadioListTile<String>(
                value: a.id,
                groupValue: selected?.id,
                title: Text(a.label),
                subtitle: Text(a.text),
                onChanged: (_) => setState(() {
                      selected = a;
                      quote = null;
                    })),
          ActionButton('Add an address', () async {
            await showAddressEditor(context, ref);
            await load();
          }),
          Field(note, 'Delivery note', requiredValue: false),
          const SizedBox(height: 20),
          ActionButton('Get current total', () async {
            final result = await ref
                .read(repositoryProvider)
                .checkout({...request(), 'quote_only': true});
            if (mounted) setState(() => quote = result);
          }),
          if (quote != null) ...[
            const SizedBox(height: 20),
            for (final pair in [
              ('Items', 'items_subtotal_paise'),
              ('Delivery', 'delivery_fee_paise'),
              ('Tax', 'tax_paise'),
              ('Discount', 'discount_paise'),
              ('Total', 'total_payable_paise')
            ])
              ListTile(
                  title: Text(pair.$1),
                  trailing: Text(money(integer(quote![pair.$2])))),
            const Text(
                'Pay by UPI after placing your order. Payment is confirmed only after review. Cash on delivery is unavailable.'),
            const SizedBox(height: 16),
            ActionButton(
                'Place order • ${money(integer(quote!['total_payable_paise']))}',
                place)
          ],
        ],
      ]));
}
