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

class VendorStoreScreen extends ConsumerWidget {
  final String id;
  const VendorStoreScreen(this.id, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    return RemoteList(
        title: 'Store workspace',
        load: (p) async => p == 0 ? [await repo.one('vendors', id)] : [],
        item: (j, reload) =>
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(j['name'],
                  style: Theme.of(context).textTheme.headlineMedium),
              Text(j['dispatch_address']),
              const SizedBox(height: 20),
              FilledButton(
                  onPressed: () => context.push('/vendor/store/$id/menu'),
                  child: const Text('Manage menu & inventory')),
              FilledButton(
                  onPressed: () => context.push('/orders'),
                  child: const Text('Incoming orders')),
              ActionButton('Edit store details', () async {
                await editRecord(context,
                    title: 'Store details',
                    fields: storeFields,
                    initial: j, save: (d) async {
                  if (!validCoordinates(d['latitude'], d['longitude']) ||
                      d['service_radius_km'] <= 0) {
                    throw StateError('Invalid coordinates or service radius');
                  }
                  await repo.save('vendors', d, id: id);
                });
                reload();
              })
            ]));
  }
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
