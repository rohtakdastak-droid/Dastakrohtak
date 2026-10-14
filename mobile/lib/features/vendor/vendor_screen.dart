import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../../core/editor.dart';
import '../../core/location.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../customer/profile_menu.dart';

const storeFields = [
  EditField('description', 'Description', type: 'multiline', optional: true),
  EditField('cuisine', 'Cuisine / type (e.g. North Indian, Cafe)', optional: true),
  EditField('dispatch_address', 'Pickup address'),
  EditField('contact_phone', 'Contact number', optional: true),
  EditField('contact_email', 'Contact email', optional: true),
  EditField('min_order_paise', 'Minimum order', type: 'money'),
  EditField('prep_time_minutes', 'Preparation time (minutes)', type: 'int'),
  EditField('service_radius_km', 'Delivery radius (km)', type: 'decimal'),
];
const productFields = [
  EditField('name', 'Item name'),
  EditField('description', 'Description', type: 'multiline', optional: true),
  EditField('price_paise', 'Price', type: 'money'),
  EditField('sale_price_paise', 'Sale price (optional)', type: 'money', optional: true),
  EditField('stock', 'Stock (blank = unlimited)', type: 'int', optional: true),
  EditField('diet', 'Diet', choices: ['veg', 'non_veg', 'egg', 'unknown']),
  EditField('is_available', 'Available', type: 'bool')
];

class VendorScreen extends ConsumerWidget {
  const VendorScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => RemoteList(
      title: 'Your restaurants',
      customerNav: false,
      actions: const [ThemeToggle()],
      emptyText: 'No restaurant is linked to your account yet.',
      load: (p) => p == 0 ? ref.read(repositoryProvider).myStores() : Future.value([]),
      header: [
        _ApplicationStatus(),
        Row(children: [
          Expanded(
              child: OutlinedButton.icon(
                  onPressed: () => context.push('/notifications'),
                  icon: const Icon(Icons.notifications_outlined),
                  label: const Text('Notifications'))),
          const SizedBox(width: 8),
          Expanded(
              child: OutlinedButton.icon(
                  onPressed: () => context.push('/support'),
                  icon: const Icon(Icons.support_agent),
                  label: const Text('Support'))),
        ]),
        const SizedBox(height: 12),
      ],
      item: (j, reload) => Card(
          child: ListTile(
              leading: const Icon(Icons.storefront),
              title: Text(j['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(j['dispatch_address']),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/vendor/store/${j['id']}'))));
}

class _ApplicationStatus extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    return FutureBuilder<List<Json>>(
        future: repo.rows('vendor_applications', filters: {'applicant_id': repo.uid}),
        builder: (c, s) {
          final open = (s.data ?? []).where((a) => a['status'] != 'approved').toList();
          if (open.isEmpty) return const SizedBox();
          final a = open.first;
          return Notice(
              'Application "${a['restaurant_name']}": ${statusLabel(a['status'])}${a['review_reason'] == null ? '' : ' — ${a['review_reason']}'}',
              icon: Icons.assignment_outlined,
              color: statusColor(a['status']),
              action: a['status'] == 'action_required'
                  ? TextButton(onPressed: () => context.push('/vendor/apply'), child: const Text('Fix'))
                  : null);
        });
  }
}

class VendorStoreScreen extends ConsumerStatefulWidget {
  final String id;
  const VendorStoreScreen(this.id, {super.key});
  @override
  ConsumerState<VendorStoreScreen> createState() => _VendorStoreScreenState();
}

class _VendorStoreScreenState extends ConsumerState<VendorStoreScreen> {
  Range range = Range.today();
  int generation = 0;

  Future<void> update(Json patch) async {
    await ref.read(repositoryProvider).save('vendors', {...patch, 'updated_at': DateTime.now().toUtc().toIso8601String()},
        id: widget.id);
    if (mounted) setState(() => generation++);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final isAdmin = ref.watch(accountProvider).valueOrNull?.role == 'admin';
    return RemoteList(
        key: ValueKey('${range.label}/$generation'),
        title: 'Restaurant dashboard',
        watch: 'orders',
        customerNav: false,
        showUpdated: true,
        actions: const [ThemeToggle()],
        load: (p) async => p > 0 ? [] : [await repo.rpcJson('vendor_dashboard', {'p_vendor': widget.id, ...range.params})],
        header: [RangeChips(range, (r) => setState(() => range = r)), const SizedBox(height: 12)],
        item: (d, reload) {
          final v = Map<String, dynamic>.from(d['vendor'] as Map);
          final open = d['is_open'] == true;
          String m(String k) => money(integer(d[k] ?? 0));
          final popular = (d['popular_items'] as List?) ?? [];
          final deliveries = (d['active_deliveries'] as List?) ?? [];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(v['name'], style: context.text.headlineMedium)),
              StatusChip(open ? 'open' : 'closed', label: open ? 'Open now' : 'Closed'),
            ]),
            Text(v['dispatch_address'], style: TextStyle(color: context.muted)),
            const SizedBox(height: 8),
            Card(
                child: Column(children: [
              SwitchListTile(
                  title: const Text('Accept new orders'),
                  subtitle: Text(v['is_active'] == true
                      ? 'Your restaurant is listed for customers'
                      : 'Hidden from customers until you switch this on'),
                  value: v['is_active'] == true,
                  onChanged: (on) => perform(context, () => update({'is_active': on}))),
              const Divider(height: 1),
              SwitchListTile(
                  title: const Text('Temporarily closed'),
                  subtitle: Text(v['temporarily_closed'] == true
                      ? 'Closed${(v['closed_reason'] ?? '').toString().isEmpty ? '' : ': ${v['closed_reason']}'} — customers can browse but not order'
                      : 'Use for a short break, rush or stock-out'),
                  value: v['temporarily_closed'] == true,
                  onChanged: (on) async {
                    String? reason;
                    if (on) {
                      reason = await askText(context, 'Reason shown to customers (optional)',
                          hint: 'e.g. Back at 7 pm', minLength: 0, action: 'Close now');
                      if (reason == null) return;
                    }
                    if (context.mounted) {
                      await perform(context, () => update({'temporarily_closed': on, 'closed_reason': on && reason!.isNotEmpty ? reason : null}));
                    }
                  }),
            ])),
            const SectionTitle('Orders'),
            StatGrid([
              StatTile('Orders', '${d['orders']}', Icons.receipt_long, onTap: () => context.push('/vendor/store/${widget.id}/orders')),
              StatTile('New (to accept)', '${d['new_orders']}', Icons.fiber_new, color: warning,
                  onTap: () => context.push('/vendor/store/${widget.id}/orders')),
              StatTile('Preparing', '${d['preparing']}', Icons.restaurant, color: brandBlue),
              StatTile('Ready for pickup', '${d['ready_for_pickup']}', Icons.takeout_dining, color: const Color(0xFF7C3AED)),
              StatTile('Out for delivery', '${d['in_delivery']}', Icons.delivery_dining, color: const Color(0xFF2563EB)),
              StatTile('Completed', '${d['completed']}', Icons.check_circle_outline, color: success),
              StatTile('Cancelled / rejected', '${d['cancelled']}', Icons.cancel_outlined, color: danger),
              StatTile('Awaiting payment', '${d['awaiting_payment']}', Icons.hourglass_top),
            ]),
            const SectionTitle('Sales (completed orders)'),
            StatGrid([
              StatTile('Food sales', m('sales_paise'), Icons.payments_outlined, color: success, hint: 'Item subtotal, excl. delivery'),
              StatTile('Average order', m('average_order_paise'), Icons.analytics_outlined),
              StatTile('Platform commission', m('commission_paise'), Icons.percent, color: warning),
              StatTile('Rating', integer(d['rating_count'] ?? 0) == 0 ? 'No ratings' : '${d['rating_avg']} ★ (${d['rating_count']})',
                  Icons.star_outline, color: const Color(0xFFF59E0B), onTap: () => context.push('/vendor/store/${widget.id}/reviews')),
            ]),
            if (popular.isNotEmpty) ...[
              const SectionTitle('Popular items'),
              Panel([
                for (final p in popular)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(flex: 3, child: Text('${p['name']}')),
                        const SizedBox(width: 8),
                        Expanded(
                            flex: 2,
                            child: Text('${p['quantity']} sold\n${money(integer(p['sales_paise']))}',
                                textAlign: TextAlign.end, style: TextStyle(color: context.muted))),
                      ]))
              ]),
            ],
            if (deliveries.isNotEmpty) ...[
              const SectionTitle('Active deliveries'),
              for (final a in deliveries)
                Card(
                    child: ListTile(
                        title: Text('${a['order_number']} • ${a['partner']}'),
                        subtitle: Text('${statusLabel('${a['status']}')}${a['vehicle'] == null ? '' : ' • ${a['vehicle']}'}'
                            '${a['partner_phone'] == null ? '' : ' • ${a['partner_phone']}'}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/orders/${a['order_id']}'))),
            ],
            const SectionTitle('Manage'),
            Card(
                child: Column(children: [
              for (final (icon, label, action) in [
                (Icons.receipt_long, 'Incoming orders', () => context.push('/vendor/store/${widget.id}/orders')),
                (Icons.menu_book_outlined, 'Menu & item availability', () => context.push('/vendor/store/${widget.id}/menu')),
                (Icons.schedule, 'Business hours & holidays', () => context.push('/vendor/store/${widget.id}/hours')),
                (Icons.place_outlined, 'Location on map', () => context.push('/vendor/store/${widget.id}/location')),
                (Icons.star_outline, 'Ratings & reviews', () => context.push('/vendor/store/${widget.id}/reviews')),
                (Icons.photo_outlined, 'Change cover photo', () => perform(context, () async {
                      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
                      if (file == null) return;
                      final path = await repo.upload('vendor-images', widget.id, await file.readAsBytes());
                      await update({'cover_image_path': path});
                    })),
                (Icons.edit_outlined, 'Business details', () async {
                  await editRecord(context, title: 'Business details', fields: storeFields, initial: v, save: (x) async {
                    if (x['service_radius_km'] <= 0 || x['service_radius_km'] > 30) {
                      throw StateError('Delivery radius must be between 0.5 and 30 km');
                    }
                    await update(x);
                  });
                }),
                if (!isAdmin) (Icons.logout, 'Log out', () => signOut(context, ref)),
              ]) ...[
                ListTile(
                    leading: Icon(icon, color: label == 'Log out' ? danger : context.colors.primary),
                    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: action),
                const Divider(height: 1),
              ]
            ])),
          ]);
        });
  }
}

class StoreHoursScreen extends ConsumerStatefulWidget {
  final String id;
  const StoreHoursScreen(this.id, {super.key});
  @override
  ConsumerState<StoreHoursScreen> createState() => _StoreHoursScreenState();
}

class HoursModel {
  final Map<int, List<(TimeOfDay, TimeOfDay)>> weekly = {for (var i = 1; i <= 7; i++) i: []};
  final List<String> holidays = [];
  HoursModel();
  factory HoursModel.from(dynamic j) {
    final m = HoursModel();
    if (j is Map && j['weekly'] is Map) {
      for (var i = 1; i <= 7; i++) {
        for (final s in ((j['weekly']['$i'] as List?) ?? [])) {
          m.weekly[i]!.add((_t('${s[0]}'), _t('${s[1]}')));
        }
      }
    }
    if (j is Map && j['holidays'] is List) m.holidays.addAll((j['holidays'] as List).map((e) => '$e'));
    return m;
  }
  static TimeOfDay _t(String s) {
    final p = s.split(':');
    return TimeOfDay(hour: int.parse(p[0]) % 24, minute: int.parse(p[1]));
  }

  static String fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  bool get configured => weekly.values.any((s) => s.isNotEmpty);
  Json toJson() => configured
      ? {
          'timezone': 'Asia/Kolkata',
          'weekly': {
            for (final e in weekly.entries) '${e.key}': [for (final s in e.value) [fmt(s.$1), fmt(s.$2)]]
          },
          'holidays': holidays
        }
      : {};
}

class _StoreHoursScreenState extends ConsumerState<StoreHoursScreen> {
  HoursModel? hours;
  Object? error;

  @override
  void initState() {
    super.initState();
    ref.read(repositoryProvider).one('vendors', widget.id).then((v) {
      if (mounted) setState(() => hours = HoursModel.from(v['opening_hours']));
    }).catchError((Object e) {
      if (mounted) setState(() => error = e);
    });
  }

  Future<void> addSlot(int day) async {
    final open = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 10, minute: 0), helpText: 'Opens at');
    if (open == null || !mounted) return;
    final close = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 22, minute: 0), helpText: 'Closes at');
    if (close == null) return;
    setState(() => hours!.weekly[day]!.add((open, close)));
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) return Scaffold(appBar: AppBar(), body: Failure(error!, () => Navigator.pop(context)));
    if (hours == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final h = hours!;
    return Scaffold(
        appBar: AppBar(title: const Text('Business hours')),
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(16), children: [
          const Notice(
              'Times are India Standard Time. A closing time earlier than the opening time means you stay open past midnight (e.g. 18:00–02:00). '
              'If no hours are set, the restaurant follows only the "Accept new orders" and "Temporarily closed" switches.'),
          for (var day = 1; day <= 7; day++)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][day - 1],
                            style: const TextStyle(fontWeight: FontWeight.w700))),
                        if (h.weekly[day]!.isEmpty) Text('Closed', style: TextStyle(color: context.muted)),
                        if (h.weekly[day]!.length < 4)
                          IconButton(tooltip: 'Add opening hours', onPressed: () => addSlot(day), icon: const Icon(Icons.add_circle_outline)),
                        if (day > 1 && h.weekly[day - 1]!.isNotEmpty)
                          TextButton(
                              onPressed: () => setState(() => h.weekly[day] = [...h.weekly[day - 1]!]),
                              child: const Text('Same as above')),
                      ]),
                      Wrap(spacing: 8, children: [
                        for (final s in h.weekly[day]!)
                          InputChip(
                              label: Text('${HoursModel.fmt(s.$1)}–${HoursModel.fmt(s.$2)}'
                                  '${s.$2.hour * 60 + s.$2.minute <= s.$1.hour * 60 + s.$1.minute ? ' (overnight)' : ''}'),
                              onDeleted: () => setState(() => h.weekly[day]!.remove(s)))
                      ])
                    ]))),
          SectionTitle('Holidays (closed all day)',
              trailing: IconButton(
                  tooltip: 'Add holiday',
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (d != null) {
                      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                      if (!h.holidays.contains(key)) setState(() => h.holidays.add(key));
                    }
                  },
                  icon: const Icon(Icons.add))),
          if (h.holidays.isEmpty) Text('No holidays added', style: TextStyle(color: context.muted)),
          Wrap(spacing: 8, children: [
            for (final d in h.holidays) InputChip(label: Text(d), onDeleted: () => setState(() => h.holidays.remove(d)))
          ]),
          const SizedBox(height: 20),
          ActionButton('Save hours', () async {
            await ref.read(repositoryProvider).save('vendors', {'opening_hours': h.toJson()}, id: widget.id);
            if (context.mounted) {
              toast(context, 'Hours saved');
              Navigator.pop(context);
            }
          }, icon: Icons.check),
        ])));
  }
}

class StoreLocationScreen extends ConsumerStatefulWidget {
  final String id;
  const StoreLocationScreen(this.id, {super.key});
  @override
  ConsumerState<StoreLocationScreen> createState() => _StoreLocationScreenState();
}

class _StoreLocationScreenState extends ConsumerState<StoreLocationScreen> {
  final address = TextEditingController();
  LatLng? pin;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    ref.read(repositoryProvider).one('vendors', widget.id).then((v) {
      if (!mounted) return;
      setState(() {
        address.text = v['dispatch_address'] ?? '';
        pin = LatLng(decimal(v['latitude']), decimal(v['longitude']));
        loaded = true;
      });
    });
  }

  @override
  void dispose() {
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Restaurant location')),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(padding: const EdgeInsets.all(16), children: [
              Field(address, 'Pickup address', lines: 2, validate: (v) => v.length < 10 ? 'Enter the full address' : null),
              const SizedBox(height: 8),
              LocationPicker(
                  initial: pin,
                  height: 320,
                  hint: 'Stand at your restaurant and use current location, or tap the exact entrance on the map. '
                      'Coordinates are what you set — they are not independently verified.',
                  onChanged: (p) => setState(() => pin = p)),
              const SizedBox(height: 16),
              ActionButton('Save location', () async {
                if (address.text.trim().length < 10) throw StateError('Enter the full pickup address');
                if (pin == null) throw StateError('Set the location on the map');
                await ref.read(repositoryProvider).save(
                    'vendors',
                    {
                      'dispatch_address': address.text.trim(),
                      'latitude': double.parse(pin!.latitude.toStringAsFixed(6)),
                      'longitude': double.parse(pin!.longitude.toStringAsFixed(6))
                    },
                    id: widget.id);
                if (context.mounted) {
                  toast(context, 'Location saved');
                  Navigator.pop(context);
                }
              }, icon: Icons.check),
            ])));
}

class VendorReviewsScreen extends ConsumerWidget {
  final String id;
  const VendorReviewsScreen(this.id, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    return RemoteList(
        title: 'Ratings & reviews',
        customerNav: false,
        emptyText: 'No reviews yet.',
        load: (p) => repo.rpcList('store_reviews', {'p_vendor': id, 'p_page': p}),
        item: (r, reload) => Card(
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('${'★' * integer(r['rating'])}${'☆' * (5 - integer(r['rating']))}',
                        style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${r['author']} • ${ago(r['created_at'])}', style: TextStyle(color: context.muted, fontSize: 12))),
                    if (r['moderation_status'] == 'hidden') const StatusChip('hidden'),
                  ]),
                  if ((r['comment'] ?? '').toString().isNotEmpty) Text(r['comment']),
                  if (r['vendor_reply'] != null)
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text('Your reply: ${r['vendor_reply']}', style: const TextStyle(fontStyle: FontStyle.italic))),
                  if (r['reported_reason'] != null) Text('Reported: ${r['reported_reason']}', style: const TextStyle(color: warning, fontSize: 12)),
                  Row(children: [
                    TextButton(
                        onPressed: () async {
                          final reply = await askText(context, 'Reply publicly', initial: r['vendor_reply'], minLength: 2);
                          if (reply != null && context.mounted) {
                            await perform(context, () => repo.rpc('vendor_reply_review', {'p_review': r['id'], 'p_reply': reply}), success: 'Reply posted');
                            reload();
                          }
                        },
                        child: Text(r['vendor_reply'] == null ? 'Reply' : 'Edit reply')),
                    if (r['reported_reason'] == null)
                      TextButton(
                          onPressed: () async {
                            final reason = await askText(context, 'Report this review', hint: 'Why should an admin look at it?', minLength: 3);
                            if (reason != null && context.mounted) {
                              await perform(context, () => repo.rpc('report_review', {'p_kind': 'vendor', 'p_review': r['id'], 'p_reason': reason}),
                                  success: 'Reported to admin');
                              reload();
                            }
                          },
                          child: const Text('Report')),
                  ])
                ]))));
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
  Future<void> portions(Json row) async {
    final product = Product(row);
    final portion = product.choiceGroups['Portion'];
    final half = portion?.where((o) => o.label == 'Half plate').firstOrNull;
    final full = portion?.where((o) => o.label == 'Full plate').firstOrNull;
    bool enabled = portion != null;
    final halfCtl = TextEditingController(text: half == null ? '' : rupeesText(product.price + half.delta));
    final fullCtl = TextEditingController(text: rupeesText(full == null ? product.price : product.price + full.delta));
    String? problem;
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, set) => AlertDialog(
                    title: Text('${product.name}: Half / Full plate'),
                    content: SingleChildScrollView(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Sell as Half plate & Full plate'),
                          subtitle: const Text('Customers must choose one when adding this item'),
                          value: enabled,
                          onChanged: (v) => set(() => enabled = v)),
                      if (enabled)
                        TextField(
                            controller: halfCtl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Half plate price', prefixText: '₹ ')),
                      const SizedBox(height: 8),
                      TextField(
                          controller: fullCtl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(labelText: enabled ? 'Full plate price' : 'Item price', prefixText: '₹ ')),
                      if (problem != null)
                        Padding(padding: const EdgeInsets.only(top: 8), child: Text(problem!, style: const TextStyle(color: danger))),
                    ])),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                          onPressed: () {
                            final h = parsePaise(halfCtl.text), f = parsePaise(fullCtl.text);
                            if (f == null || f <= 0 || (enabled && (h == null || h <= 0))) {
                              set(() => problem = 'Enter prices in rupees, e.g. 120 or 120.50');
                            } else if (enabled && h! >= f) {
                              set(() => problem = 'Half plate must cost less than full plate');
                            } else {
                              Navigator.pop(ctx, true);
                            }
                          },
                          child: const Text('Save'))
                    ])));
    if (ok == true && mounted) {
      await perform(
          context,
          () => ref.read(repositoryProvider).rpc('set_item_portions', {
                'p_product': row['id'],
                'p_enabled': enabled,
                'p_half_paise': enabled ? parsePaise(halfCtl.text) : null,
                'p_full_paise': parsePaise(fullCtl.text)
              }),
          success: enabled ? 'Half & full plate prices saved' : 'Single price saved');
      if (mounted) setState(() => generation++);
    }
    Future<void>.delayed(const Duration(seconds: 1), () {
      halfCtl.dispose();
      fullCtl.dispose();
    });
  }

  Future<void> edit([Json? row]) async {
    final repo = ref.read(repositoryProvider);
    final hasPortions = row != null && Product(row).choiceGroups.isNotEmpty;
    await editRecord(context,
        title: row == null ? 'Add menu item' : 'Edit menu item',
        fields: hasPortions
            ? productFields.where((f) => f.key != 'price_paise' && f.key != 'sale_price_paise').toList()
            : productFields,
        initial: row ?? {'is_available': true, 'diet': 'veg'}, save: (d) async {
      if (d['sale_price_paise'] != null && d['sale_price_paise'] > d['price_paise']) {
        throw StateError('Sale price cannot exceed regular price');
      }
      await repo.save('products', {...d, 'vendor_id': widget.vendor}, id: row?['id']);
    });
    if (mounted) setState(() => generation++);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    return RemoteList(
        key: ValueKey(generation),
        title: 'Menu & availability',
        customerNav: false,
        emptyText: 'No items yet. Add your first menu item.',
        load: (p) => repo.rows('products',
            select: '*,product_options(*)', filters: {'vendor_id': widget.vendor}, sort: 'sort_priority', ascending: true, page: p),
        header: [
          ActionButton('Add menu item', () => edit(), icon: Icons.add),
          const SizedBox(height: 6),
          Text('For dishes sold as half and full plate, add the item, then tap "Half / Full".',
              style: TextStyle(fontSize: 12, color: context.muted)),
          const SizedBox(height: 12)
        ],
        item: (j, reload) => Card(
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 72, child: Photo(repo.imageUrl(j['image_path']), height: 72, radius: 12, placeholder: Icons.restaurant)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(j['name'], style: context.text.titleMedium),
                      Text(Product(j).priceText, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${human(j['diet'] ?? 'unknown')} • stock ${j['stock'] ?? 'unlimited'}',
                          style: TextStyle(color: context.muted, fontSize: 12)),
                    ])),
                    Switch(
                        value: j['is_available'] == true,
                        onChanged: (v) async {
                          if (await perform(context, () => repo.save('products', {'is_available': v}, id: j['id']),
                              success: v ? 'Item available' : 'Item marked unavailable')) {
                            reload();
                          }
                        }),
                  ]),
                  Wrap(spacing: 4, children: [
                    TextButton(onPressed: () => edit(j), child: const Text('Edit')),
                    TextButton(onPressed: () => portions(j), child: const Text('Half / Full')),
                    TextButton(onPressed: () => context.push('/vendor/product/${j['id']}/options'), child: const Text('Options')),
                    TextButton(
                        onPressed: () => perform(context, () async {
                              final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1400);
                              if (file == null) return;
                              final path = await repo.upload('product-images', widget.vendor, await file.readAsBytes());
                              await repo.save('products', {'image_path': path}, id: j['id']);
                              reload();
                            }),
                        child: const Text('Photo')),
                  ]),
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
        title: 'Item option',
        initial: j ?? {'is_available': true, 'price_delta_paise': 0},
        fields: const [
          EditField('group_name', 'Group (for example Size)'),
          EditField('label', 'Option name'),
          EditField('price_delta_paise', 'Extra price', type: 'money'),
          EditField('selection', 'How customers pick from this group', choices: ['multi', 'single_required']),
          EditField('is_available', 'Available', type: 'bool')
        ],
        save: (d) => ref.read(repositoryProvider).save('product_options', {...d, 'product_id': widget.product}, id: j?['id']));
    if (mounted) setState(() => generation++);
  }

  @override
  Widget build(BuildContext context) => RemoteList(
      key: ValueKey(generation),
      title: 'Item options',
      customerNav: false,
      load: (p) => ref.read(repositoryProvider).rows('product_options', filters: {'product_id': widget.product}, sort: 'sort_priority', page: p),
      header: [ActionButton('Add option', () => edit(), icon: Icons.add), const SizedBox(height: 12)],
      item: (j, reload) => Card(
          child: ListTile(
              title: Text('${j['group_name']}: ${j['label']}'),
              subtitle: Text('+ ${money(integer(j['price_delta_paise']))} • ${j['selection'] == 'single_required' ? 'choose exactly one' : 'optional add-on'} • ${j['is_available'] ? 'Available' : 'Unavailable'}'),
              trailing: IconButton(tooltip: 'Edit option', onPressed: () => edit(j), icon: const Icon(Icons.edit)))));
}

class VendorApplicationScreen extends ConsumerStatefulWidget {
  const VendorApplicationScreen({super.key});
  @override
  ConsumerState<VendorApplicationScreen> createState() => _VendorApplicationScreenState();
}

class _VendorApplicationScreenState extends ConsumerState<VendorApplicationScreen> {
  final form = GlobalKey<FormState>();
  final c = {
    for (final k in ['restaurant_name', 'owner_name', 'phone', 'email', 'address', 'city', 'postal_code', 'cuisine', 'notes'])
      k: TextEditingController()
  };
  final prep = TextEditingController(text: '20'), radius = TextEditingController(text: '5'), minimum = TextEditingController(text: '0');
  LatLng? pin;
  String source = 'manual';
  TimeOfDay open = const TimeOfDay(hour: 10, minute: 0), close = const TimeOfDay(hour: 22, minute: 0);
  Json? existing;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(repositoryProvider);
    repo.rows('vendor_applications', filters: {'applicant_id': repo.uid}).then((rows) {
      if (!mounted) return;
      final a = rows.where((r) => r['status'] == 'pending' || r['status'] == 'action_required').firstOrNull;
      setState(() {
        existing = a;
        if (a != null) {
          for (final e in c.entries) {
            e.value.text = '${a[e.key] ?? ''}';
          }
          prep.text = '${a['prep_time_minutes']}';
          radius.text = '${a['service_radius_km']}';
          minimum.text = '${integer(a['min_order_paise']) ~/ 100}';
          if (a['latitude'] != null) pin = LatLng(decimal(a['latitude']), decimal(a['longitude']));
        } else {
          c['email']!.text = repo.client.auth.currentUser?.email ?? '';
          c['city']!.text = 'Rohtak';
        }
        loaded = true;
      });
    }).catchError((Object _) {
      if (mounted) setState(() => loaded = true);
    });
  }

  @override
  void dispose() {
    for (final x in [...c.values, prep, radius, minimum]) {
      x.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final locked = existing?['status'] == 'pending';
    return Scaffold(
        appBar: AppBar(title: const Text('Register your restaurant')),
        body: SafeArea(
            child: Form(
                key: form,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  if (existing != null)
                    Notice(
                        locked
                            ? 'Your application is under review. We will notify you after an admin checks it.'
                            : 'Changes requested: ${existing!['review_reason'] ?? ''}',
                        color: statusColor(existing!['status'])),
                  const SectionTitle('Restaurant'),
                  Field(c['restaurant_name']!, 'Restaurant / cafe name', enabled: !locked, capitalization: TextCapitalization.words),
                  Field(c['cuisine']!, 'Type / cuisine', requiredValue: false, enabled: !locked, hint: 'e.g. North Indian, Cafe, Bakery'),
                  Field(c['owner_name']!, 'Owner name', enabled: !locked, capitalization: TextCapitalization.words),
                  Row(children: [
                    Expanded(
                        child: Field(c['phone']!, 'Contact number', enabled: !locked, keyboard: TextInputType.phone, maxLength: 10,
                            validate: (v) => RegExp(r'^\d{10}$').hasMatch(v) ? null : '10 digits')),
                    const SizedBox(width: 10),
                    Expanded(child: Field(c['email']!, 'Email', requiredValue: false, enabled: !locked, keyboard: TextInputType.emailAddress)),
                  ]),
                  const SectionTitle('Address & location'),
                  Field(c['address']!, 'Full address', enabled: !locked, lines: 2, validate: (v) => v.length < 10 ? 'Enter the full address' : null),
                  Row(children: [
                    Expanded(child: Field(c['city']!, 'City', enabled: !locked)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Field(c['postal_code']!, 'PIN code', enabled: !locked, keyboard: TextInputType.number, maxLength: 6,
                            validate: (v) => RegExp(r'^\d{6}$').hasMatch(v) ? null : '6 digits')),
                  ]),
                  if (!locked)
                    LocationPicker(
                        initial: pin,
                        hint: 'Use current location at the restaurant, or tap its entrance on the map.',
                        onChanged: (p) => setState(() {
                              pin = p;
                              source = 'map_pin';
                            })),
                  const SectionTitle('Operations'),
                  Row(children: [
                    Expanded(child: Field(prep, 'Prep time (min)', enabled: !locked, keyboard: TextInputType.number)),
                    const SizedBox(width: 10),
                    Expanded(child: Field(radius, 'Delivery radius (km)', enabled: !locked, keyboard: const TextInputType.numberWithOptions(decimal: true))),
                    const SizedBox(width: 10),
                    Expanded(child: Field(minimum, 'Min order (₹)', enabled: !locked, keyboard: TextInputType.number)),
                  ]),
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Daily hours'),
                      subtitle: Text('${HoursModel.fmt(open)} – ${HoursModel.fmt(close)} (edit per day after approval)'),
                      trailing: const Icon(Icons.schedule),
                      onTap: locked
                          ? null
                          : () async {
                              final o = await showTimePicker(context: context, initialTime: open, helpText: 'Opens at');
                              if (o == null || !context.mounted) return;
                              final cl = await showTimePicker(context: context, initialTime: close, helpText: 'Closes at');
                              if (cl != null) setState(() {
                                open = o;
                                close = cl;
                              });
                            }),
                  Field(c['notes']!, 'Anything else we should know?', requiredValue: false, enabled: !locked, lines: 2),
                  const SizedBox(height: 12),
                  if (!locked)
                    ActionButton(existing == null ? 'Submit restaurant for approval' : 'Resubmit', () async {
                      if (!form.currentState!.validate()) throw StateError('Please fix the highlighted fields');
                      if (pin == null) throw StateError('Set the restaurant location on the map');
                      final slot = [HoursModel.fmt(open), HoursModel.fmt(close)];
                      await ref.read(repositoryProvider).rpc('submit_vendor_application', {
                        'p': {
                          for (final e in c.entries) e.key: e.value.text.trim(),
                          'latitude': double.parse(pin!.latitude.toStringAsFixed(6)),
                          'longitude': double.parse(pin!.longitude.toStringAsFixed(6)),
                          'location_source': source,
                          'prep_time_minutes': int.tryParse(prep.text) ?? 20,
                          'service_radius_km': double.tryParse(radius.text) ?? 5,
                          'min_order_paise': ((double.tryParse(minimum.text) ?? 0) * 100).round(),
                          'opening_hours': {
                            'timezone': 'Asia/Kolkata',
                            'weekly': {for (var i = 1; i <= 7; i++) '$i': [slot]},
                            'holidays': []
                          }
                        }
                      });
                      if (context.mounted) {
                        toast(context, 'Submitted. We will notify you after review.');
                        Navigator.pop(context);
                      }
                    }, icon: Icons.send),
                  const SizedBox(height: 24),
                ]))));
  }
}
