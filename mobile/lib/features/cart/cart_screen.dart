import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models.dart';
import '../../core/widgets.dart';
import 'cart_controller.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(cartProvider);
    return PageFrame('Your bag',
        child: lines.isEmpty
            ? const Empty(
                'Your bag is empty. Discover a local store to get started.')
            : ListView(padding: const EdgeInsets.all(20), children: [
                for (final l in lines)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.product.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                if (l.options.isNotEmpty)
                                  Text(
                                      l.options.map((o) => o.label).join(', ')),
                                Row(children: [
                                  Expanded(child: Text(money(l.total))),
                                  IconButton(
                                      tooltip: 'Decrease quantity',
                                      onPressed: () => perform(
                                          context,
                                          () => ref
                                              .read(cartProvider.notifier)
                                              .quantity(l.product.id,
                                                  l.quantity - 1)),
                                      icon: const Icon(
                                          Icons.remove_circle_outline)),
                                  Text('${l.quantity}'),
                                  IconButton(
                                      tooltip: 'Increase quantity',
                                      onPressed: () => perform(
                                          context,
                                          () => ref
                                              .read(cartProvider.notifier)
                                              .quantity(l.product.id,
                                                  l.quantity + 1)),
                                      icon:
                                          const Icon(Icons.add_circle_outline))
                                ])
                              ]))),
                const SizedBox(height: 20),
                ListTile(
                    title: const Text('Items subtotal'),
                    trailing:
                        Text(money(lines.fold(0, (s, l) => s + l.total)))),
                const Text(
                    'Final prices, availability, delivery and tax are checked at checkout.'),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: () => context.push('/checkout'),
                    child: const Text('Review checkout')),
                TextButton(
                    onPressed: () => perform(
                        context, () => ref.read(cartProvider.notifier).clear()),
                    child: const Text('Clear bag'))
              ]));
  }
}
