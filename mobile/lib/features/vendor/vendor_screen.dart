import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../core/editor.dart';

const storeFields = [
  EditField('description', 'Description', type: 'multiline', optional: true),
  EditField('dispatch_address', 'Pickup address'),
  EditField('latitude', 'Latitude', type: 'decimal'),
  EditField('longitude', 'Longitude', type: 'decimal'),
  EditField('min_order_paise', 'Minimum order (paise)', type: 'int'),
  EditField('prep_time_minutes', 'Preparation time (minutes)', type: 'int'),
  EditField('service_radius_km', 'Service radius (km)', type: 'decimal'),
  EditField('is_active', 'Accept new orders', type: 'bool')
];
const productFields = [
  EditField('name', 'Product name'),
  EditField('description', 'Description', type: 'multiline', optional: true),
  EditField('price_paise', 'Price (paise, ₹1 = 100)', type: 'int'),
  EditField('sale_price_paise', 'Sale price (paise)',
      type: 'int', optional: true),
  EditField('stock', 'Stock (blank = unlimited)', type: 'int', optional: true),
  EditField('diet', 'Diet', choices: ['veg', 'non_veg', 'egg', 'unknown']),
  EditField('is_available', 'Available', type: 'bool')
];

class VendorScreen extends ConsumerWidget {
  const VendorScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => RemoteList(
      title: 'Your stores',
      load: (p) =>
          p == 0 ? ref.read(repositoryProvider).myStores() : Future.value([]),
      header: [
        FilledButton(
            onPressed: () => context.push('/orders'),
            child: const Text('Manage orders'))
      ],
      item: (j, reload) => Card(
          child: ListTile(
              title: Text(j['name']),
              subtitle: Text(j['dispatch_address']),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/vendor/store/${j['id']}'))));
}

class VendorStoreScreen extends ConsumerStatefulWidget {
  final String id;
  const VendorStoreScreen(this.id, {super.key});
  @override
  ConsumerState<VendorStoreScreen> createState() => _VendorStoreScreenState();
}

class _VendorStoreScreenState extends ConsumerState<VendorStoreScreen> {
  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    return RemoteList(
        title: 'Store workspace',
        watch: 'orders',
        load: (p) async {
          if (p > 0) return [];
          final vendor = await repo.one('vendors', widget.id);
          final today = DateTime.now()
              .toUtc()
              .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0);
          final orders = await repo.client
              .from('orders')
              .select('status,total_payable_paise,created_at')
              .eq('vendor_id', widget.id)
              .gte('created_at', today.toIso8601String());
          int todayCount = 0, delivered = 0, preparing = 0, cancelled = 0;
          int revenue = 0;
          for (final o in (orders as List)) {
            todayCount++;
            final s = o['status'];
            if (s == 'delivered') {
              delivered++;
              revenue += (o['total_payable_paise'] ?? 0) as int;
            } else if (s == 'preparing' ||
                s == 'ready_for_pickup' ||
                s == 'vendor_confirmation') {
              preparing++;
            } else if (s == 'cancelled' || s == 'rejected') {
              cancelled++;
            }
          }
          return [
            {
              'vendor': vendor,
              'stats': {
                'today': todayCount,
                'delivered': delivered,
                'preparing': preparing,
                'cancelled': cancelled,
                'revenue': revenue
              }
            }
          ];
        },
        item: (row, reload) {
          final j = row['vendor'] as Json;
          final s = row['stats'] as Json;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(j['name'],
                    style: Theme.of(context).textTheme.headlineMedium),
                Text(j['dispatch_address']),
                const SizedBox(height: 16),
                // Live stats
                Row(children: [
                  const Icon(Icons.circle, size: 8, color: Color(0xFF059669)),
                  const SizedBox(width: 6),
                  const Text('LIVE',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF059669))),
                  const SizedBox(width: 10),
                  const Text("Today's activity",
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700))
                ]),
                const SizedBox(height: 10),
                GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 2.1,
                    children: [
                      _statTile(context, 'Orders today', '${s['today']}',
                          Icons.receipt_long_outlined),
                      _statTile(context, 'Revenue', money(integer(s['revenue'])),
                          Icons.payments_outlined,
                          color: const Color(0xFF059669)),
                      _statTile(context, 'Preparing', '${s['preparing']}',
                          Icons.restaurant_outlined,
                          color: const Color(0xFFEA580C)),
                      _statTile(context, 'Delivered', '${s['delivered']}',
                          Icons.check_circle_outlined,
                          color: const Color(0xFF2563EB))
                    ]),
                const SizedBox(height: 16),
                FilledButton.icon(
                    onPressed: () =>
                        context.push('/vendor/store/${widget.id}/menu'),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Manage menu & inventory')),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                    onPressed: () => context.push('/orders'),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Incoming orders')),
                const SizedBox(height: 8),
                ActionButton('Edit store details', () async {
                  await editRecord(context,
                      title: 'Store details',
                      fields: storeFields,
                      initial: j, save: (d) async {
                    if (!validCoordinates(d['latitude'], d['longitude']) ||
                        d['service_radius_km'] <= 0) {
                      throw StateError('Invalid coordinates or service radius');
                    }
                    await ref.read(repositoryProvider).save('vendors', d, id: widget.id);
                  });
                  reload();
                })
              ]);
        });
  }
}

Widget _statTile(BuildContext context, String label, String value, IconData icon,
    {Color color = const Color(0xFF374151)}) {
  return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280))),
              Text(value,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: color))
            ]))
      ]));
}

class MenuScreen extends ConsumerStatefulWidget {
  final String vendor;
  const MenuScreen(this.vendor, {super.key});
  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  int generation = 0;
  Future<void> edit([Json? row]) async {
    final repo = ref.read(repositoryProvider);
    await editRecord(context,
        title: row == null ? 'Add product' : 'Edit product',
        fields: productFields,
        initial: row ?? {'is_available': true, 'diet': 'veg'}, save: (d) async {
      if (d['sale_price_paise'] != null &&
          d['sale_price_paise'] > d['price_paise']) {
        throw StateError('Sale price cannot exceed regular price');
      }
      await repo.save('products', {...d, 'vendor_id': widget.vendor},
          id: row?['id']);
    });
    if (mounted) setState(() => generation++);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    return RemoteList(
        key: ValueKey(generation),
        title: 'Menu & inventory',
        load: (p) => repo.rows('products',
            filters: {'vendor_id': widget.vendor},
            sort: 'sort_priority',
            ascending: true,
            page: p),
        header: [ActionButton('Add product', () => edit(), icon: Icons.add)],
        item: (j, reload) => Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(j['name'],
                          style: Theme.of(context).textTheme.titleLarge),
                      Text(
                          '${money(integer(j['sale_price_paise'] ?? j['price_paise']))} · Stock ${j['stock'] ?? 'unlimited'}'),
                      Wrap(spacing: 8, children: [
                        TextButton(
                            onPressed: () => edit(j),
                            child: const Text('Edit')),
                        TextButton(
                            onPressed: () => context
                                .push('/vendor/product/${j['id']}/options'),
                            child: const Text('Options')),
                        ActionButton(j['is_available'] ? 'Disable' : 'Enable',
                            () async {
                          await repo.save(
                              'products', {'is_available': !j['is_available']},
                              id: j['id']);
                          reload();
                        }),
                        ActionButton('Upload photo', () async {
                          final file = await ImagePicker().pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 80,
                              maxWidth: 1400);
                          if (file == null) return;
                          final path = await repo.upload('product-images',
                              widget.vendor, await file.readAsBytes());
                          await repo.save('products', {'image_path': path},
                              id: j['id']);
                          reload();
                        })
                      ]),
                      const Text(
                          'Disable products to retain historical order references.',
                          style: TextStyle(fontSize: 12))
                    ]))));
  }
}

class OptionsScreen extends ConsumerStatefulWidget {
  final String product;
  const OptionsScreen(this.product, {super.key});
  @override
  ConsumerState<OptionsScreen> createState() => _OptionsScreenState();
}

class _OptionsScreenState extends ConsumerState<OptionsScreen> {
  int generation = 0;
  Future<void> edit([Json? j]) async {
    await editRecord(context,
        title: 'Product option',
        initial: j ?? {'is_available': true, 'price_delta_paise': 0},
        fields: const [
          EditField('group_name', 'Group (for example Size)'),
          EditField('label', 'Option name'),
          EditField('price_delta_paise', 'Additional price (paise)',
              type: 'int'),
          EditField('is_available', 'Available', type: 'bool')
        ],
        save: (d) => ref.read(repositoryProvider).save(
            'product_options', {...d, 'product_id': widget.product},
            id: j?['id']));
    if (mounted) setState(() => generation++);
  }

  @override
  Widget build(BuildContext context) => RemoteList(
      key: ValueKey(generation),
      title: 'Product options',
      load: (p) => ref.read(repositoryProvider).rows('product_options',
          filters: {'product_id': widget.product},
          sort: 'sort_priority',
          page: p),
      header: [ActionButton('Add option', () => edit())],
      item: (j, reload) => ListTile(
          title: Text('${j['group_name']}: ${j['label']}'),
          subtitle: Text(
              '${money(integer(j['price_delta_paise']))} · ${j['is_available'] ? 'Available' : 'Disabled'}'),
          trailing: IconButton(
              tooltip: 'Edit option',
              onPressed: () => edit(j),
              icon: const Icon(Icons.edit))));
}
