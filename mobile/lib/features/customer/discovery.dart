import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../cart/cart_controller.dart';

class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});
  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  String search = '';
  int generation = 0;
  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    return RemoteList(
        key: ValueKey('$search/$generation'),
        title: 'Dastak',
        load: (p) async =>
            (await repo.stores(page: p, category: 'food', search: search))
                .map((s) => {'store': s})
                .toList(),
        header: [
          Row(children: [
            const Icon(Icons.location_on_outlined, color: Color(0xFFEA580C)),
            const Expanded(
                child: Text('YOUR NEIGHBOURHOOD • ROHTAK',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
            IconButton(
                tooltip: 'Notifications',
                onPressed: () => context.push('/notifications'),
                icon: const Icon(Icons.notifications_outlined))
          ]),
          const SizedBox(height: 16),
          Text('What are you\ncraving today?',
              style: Theme.of(context)
                  .textTheme
                  .headlineLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text('Order from your favourite restaurants & cafes.'),
          const SizedBox(height: 20),
          TextField(
              onSubmitted: (v) => setState(() => search = v),
              decoration: InputDecoration(
                  hintText: 'Search restaurants & cafes',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                      tooltip: 'Clear search',
                      onPressed: () => setState(() {
                            search = '';
                            generation++;
                          }),
                      icon: const Icon(Icons.close)))),
          const SizedBox(height: 24),
        ],
        item: (j, reload) {
          final s = j['store'] as Store;
          return Card(
              margin: const EdgeInsets.only(bottom: 18),
              child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => context.push('/store/${s.id}'),
                  child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Photo(repo.imageUrl(s.image,
                                bucket: 'vendor-images')),
                            const SizedBox(height: 14),
                            Text(s.name,
                                style: Theme.of(context).textTheme.titleLarge),
                            Text(
                                '${human(s.category)} · Minimum ${money(s.minimum)}'),
                            const SizedBox(height: 8),
                            Text(s.address,
                                maxLines: 2, overflow: TextOverflow.ellipsis)
                          ]))));
        });
  }
}

class StoreScreen extends ConsumerStatefulWidget {
  final String id;
  const StoreScreen(this.id, {super.key});
  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  String search = '';
  bool veg = false;
  Future<void> add(Product product) async {
    final selected = <String>{};
    if (product.options.isNotEmpty) {
      final result = await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
              builder: (ctx, set) => AlertDialog(
                      title: Text(product.name),
                      content: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text(
                            'Optional additions. These choices apply to all units of this product in your bag.'),
                        for (final o in product.options)
                          CheckboxListTile(
                              title: Text('${o.group}: ${o.label}'),
                              subtitle: Text(money(o.delta)),
                              value: selected.contains(o.id),
                              onChanged: (v) => set(() => v == true
                                  ? selected.add(o.id)
                                  : selected.remove(o.id)))
                      ])),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel')),
                        FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Add to bag'))
                      ])));
      if (result != true) return;
    }
    final cart = ref.read(cartProvider);
    bool replace = false;
    if (cart.isNotEmpty && cart.first.product.vendorId != product.vendorId) {
      if (!mounted) return;
      replace = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                      title: const Text('Start a new bag?'),
                      content: const Text(
                          'Orders can contain items from one store. Your current bag will be cleared.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Keep bag')),
                        FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Switch store'))
                      ])) ??
          false;
      if (!replace) return;
    }
    await ref.read(cartProvider.notifier).add(
        product, product.options.where((o) => selected.contains(o.id)).toList(),
        replace: replace);
    if (mounted) toast(context, 'Added to your bag');
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    return RemoteList(
        title: 'Shop the menu',
        watch: 'products',
        load: (p) async => (await repo.products(widget.id, page: p))
            .map((p) => {'product': p})
            .toList(),
        header: [
          FutureBuilder<Json>(
              future: repo.one('vendors', widget.id),
              builder: (c, s) => s.hasData
                  ? ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.data!['name'],
                          style: Theme.of(context).textTheme.headlineMedium),
                      subtitle: Text(
                          '${s.data!['description'] ?? ''}\n${s.data!['dispatch_address']}\nMinimum ${money(integer(s.data!['min_order_paise']))}'))
                  : const SizedBox()),
          TextField(
              decoration: const InputDecoration(
                  hintText: 'Filter loaded products',
                  prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => search = v.toLowerCase())),
          SwitchListTile(
              title: const Text('Vegetarian only'),
              value: veg,
              onChanged: (v) => setState(() => veg = v)),
        ],
        item: (j, reload) {
          final p = j['product'] as Product;
          if (!p.name.toLowerCase().contains(search) ||
              (veg && p.diet != 'veg')) return const SizedBox();
          return Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (p.image != null)
                          Photo(repo.imageUrl(p.image), height: 140),
                        Text(p.name,
                            style: Theme.of(context).textTheme.titleLarge),
                        Text(p.description),
                        Text('${money(p.price)} · ${human(p.diet)}'),
                        const SizedBox(height: 8),
                        if (p.stock == 0)
                          const Text('Out of stock')
                        else
                          ActionButton('Add to bag', () => add(p),
                              icon: Icons.add)
                      ])));
        });
  }
}
