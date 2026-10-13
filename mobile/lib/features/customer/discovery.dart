import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
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
            const Icon(Icons.location_on_outlined, color: Color(0xFF0EA5E9)),
            const Expanded(
                child: Text('YOUR NEIGHBOURHOOD • ROHTAK',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
            IconButton(
                tooltip: 'Notifications',
                onPressed: () => context.push('/notifications'),
                icon: const Icon(Icons.notifications_outlined))
          ]),
          const SizedBox(height: 12),
          // Branded tagline card
          Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFE0F2FE), Color(0xFFF0F9FF)]),
                  borderRadius: BorderRadius.circular(18),
                  border:
                      Border.all(color: const Color(0xFFBAE6FD), width: 1)),
              child: Row(children: [
                Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: const Color(0xFF0EA5E9),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.doorbell_rounded,
                        color: Colors.white, size: 22)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Dastak',
                              style: GoogleFonts.playfairDisplay(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF0369A1),
                                  letterSpacing: 0.3,
                                  height: 1)),
                          const SizedBox(height: 2),
                          Row(children: [
                            Flexible(
                                child: Text('Dil Se Ghar Tak',
                                    style: GoogleFonts.dancingScript(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF0284C7),
                                        fontStyle: FontStyle.italic,
                                        height: 1.1))),
                            const SizedBox(width: 6),
                            Container(
                                width: 3,
                                height: 3,
                                decoration: const BoxDecoration(
                                    color: Color(0xFF0284C7),
                                    shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Flexible(
                                child: Text("Rohtak's Local Delivery",
                                    style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF075985),
                                        letterSpacing: 0.4)))
                          ])
                        ]))
              ])),
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
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final cart = ref.watch(cartProvider);
    final itemCount = cart.fold<int>(0, (s, l) => s + l.quantity);
    final cartTotal =
        cart.fold<int>(0, (s, l) => s + (l.product.price * l.quantity));
    return RemoteList(
        title: 'Shop the menu',
        watch: 'products',
        load: (p) async => (await repo.products(widget.id, page: p))
            .map((p) => {'product': p})
            .toList(),
        floatingBottom: itemCount == 0
            ? null
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Material(
                    color: const Color(0xFF0EA5E9),
                    borderRadius: BorderRadius.circular(16),
                    elevation: 6,
                    shadowColor: const Color(0xFF0EA5E9).withOpacity(0.4),
                    child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => context.push('/cart'),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 14),
                            child: Row(children: [
                              Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                      color: Colors.white24,
                                      borderRadius: BorderRadius.circular(10)),
                                  child: Text('$itemCount',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14))),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                    Text(
                                        '$itemCount item${itemCount == 1 ? '' : 's'} in bag',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14)),
                                    Text(money(cartTotal),
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12))
                                  ])),
                              const Text('View bag',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14)),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_forward_rounded,
                                  color: Colors.white, size: 18)
                            ]))))),
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
