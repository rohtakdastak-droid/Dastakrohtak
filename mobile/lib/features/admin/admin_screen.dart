import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../core/editor.dart';
import '../../core/location.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../customer/profile_menu.dart';
import '../vendor/vendor_screen.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});
  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  Range range = Range.today();
  static const nav = [
    (Icons.storefront_outlined, 'Restaurants', '/admin/vendors'),
    (Icons.assignment_outlined, 'Restaurant applications', '/admin/vendor-applications'),
    (Icons.pedal_bike_outlined, 'Delivery partners', '/admin/partners'),
    (Icons.people_outline, 'Customers', '/admin/customers'),
    (Icons.receipt_long_outlined, 'Orders', '/orders'),
    (Icons.fact_check_outlined, 'Payment verification', '/admin/payments'),
    (Icons.account_balance_outlined, 'Partner payouts', '/admin/payouts'),
    (Icons.view_carousel_outlined, 'Promo posters', '/admin/posters'),
    (Icons.reviews_outlined, 'Reviews moderation', '/admin/reviews'),
    (Icons.support_agent, 'Support tickets', '/support'),
    (Icons.tune, 'Payments, fees & rules', '/admin/settings'),
    (Icons.history_outlined, 'Audit log', '/admin/audit'),
  ];

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    return RemoteList(
        key: ValueKey(range.label),
        title: 'Admin',
        customerNav: false,
        watch: 'orders',
        showUpdated: true,
        actions: [
          const ThemeToggle(),
          IconButton(tooltip: 'Notifications', onPressed: () => context.push('/notifications'), icon: const Icon(Icons.notifications_outlined)),
          IconButton(
              tooltip: 'Log out',
              onPressed: () async {
                if (await confirm(context, 'Log out?', 'You will need to sign in again.', yes: 'Log out') && context.mounted) {
                  await signOut(context, ref);
                }
              },
              icon: const Icon(Icons.logout)),
        ],
        load: (p) async => p > 0 ? [] : [await repo.rpcJson('admin_dashboard', range.params)],
        header: [
          LayoutBuilder(builder: (c, box) {
            final cols = box.maxWidth > 700 ? 6 : 3;
            return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.05 / MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0),
                children: [
                  for (final e in nav)
                    Material(
                        color: context.tint,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => context.push(e.$3),
                            child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Icon(e.$1, size: 24, color: context.colors.primary),
                                  const SizedBox(height: 6),
                                  Text(e.$2,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))
                                ]))))
                ]);
          }),
          const SizedBox(height: 16),
          RangeChips(range, (r) => setState(() => range = r)),
          const SizedBox(height: 8),
        ],
        item: (d, reload) {
          String m(String k) => money(integer(d[k] ?? 0));
          String n(String k) => '${d[k] ?? 0}';
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionTitle('Needs attention'),
            StatGrid([
              StatTile('Payments to verify', n('payments_pending_verification'), Icons.fact_check, color: warning,
                  onTap: () => context.push('/admin/payments')),
              StatTile('Partners to verify', n('partners_pending_verification'), Icons.how_to_reg, color: warning,
                  onTap: () => context.push('/admin/partners?status=pending_verification')),
              StatTile('Restaurant applications', n('restaurant_applications_pending'), Icons.assignment, color: warning,
                  onTap: () => context.push('/admin/vendor-applications')),
              StatTile('Partner QR to review', n('partner_qr_pending'), Icons.qr_code_2, color: warning,
                  onTap: () => context.push('/admin/partners')),
              StatTile('Reported reviews', n('reviews_reported'), Icons.flag_outlined, color: danger,
                  onTap: () => context.push('/admin/reviews')),
              StatTile('Unpaid partner earnings', m('payouts_pending_paise'), Icons.hourglass_bottom, color: danger,
                  hint: 'All time, not yet paid', onTap: () => context.push('/admin/payouts')),
            ]),
            SectionTitle('Orders • ${range.label}'),
            StatGrid([
              StatTile('Orders placed', n('orders'), Icons.receipt_long, onTap: () => context.push('/orders')),
              StatTile('Active right now', n('orders_active_now'), Icons.local_shipping_outlined, color: brandBlue, hint: 'Confirmed, not yet delivered'),
              StatTile('Awaiting payment', n('orders_awaiting_payment'), Icons.hourglass_top),
              StatTile('Delivered', n('orders_completed'), Icons.check_circle_outline, color: success),
              StatTile('Cancelled / rejected', n('orders_cancelled'), Icons.cancel_outlined, color: danger),
            ]),
            SectionTitle('Money • ${range.label}'),
            StatGrid([
              StatTile('Gross order value', m('gross_order_value_paise'), Icons.summarize_outlined,
                  hint: 'Customer totals with verified payment'),
              StatTile('Restaurant food sales', m('restaurant_sales_paise'), Icons.restaurant, color: success,
                  hint: 'Item subtotals of delivered orders'),
              StatTile('Delivery fees', m('delivery_fees_paise'), Icons.local_shipping, hint: 'Delivered orders'),
              StatTile('Platform commission', m('platform_commission_paise'), Icons.percent, color: const Color(0xFF7C3AED),
                  hint: 'Configured % of food sales'),
              StatTile('Partner earnings', m('partner_earnings_paise'), Icons.pedal_bike, color: warning),
              StatTile('Payouts completed', m('payouts_completed_paise'), Icons.verified, color: success),
            ]),
            Text('Gross order value is not platform revenue or cash in hand. Payments count only after manual verification.',
                style: TextStyle(fontSize: 11, color: context.muted)),
            const SectionTitle('Network'),
            StatGrid([
              StatTile('Restaurants', '${n('restaurants_active')} active / ${n('restaurants_total')}', Icons.storefront,
                  hint: '${n('restaurants_open_now')} open now', onTap: () => context.push('/admin/vendors')),
              StatTile('Delivery partners', n('partners_total'), Icons.pedal_bike, hint: '${n('partners_online')} online now',
                  onTap: () => context.push('/admin/partners')),
              StatTile('Customers', n('customers_total'), Icons.people_outline, onTap: () => context.push('/admin/customers')),
              StatTile('Ratings', 'Food ${d['restaurant_rating_avg'] ?? '—'} • Riders ${d['partner_rating_avg'] ?? '—'}',
                  Icons.star_outline, color: const Color(0xFFF59E0B)),
            ]),
          ]);
        });
  }
}

class AdminVendorsScreen extends ConsumerStatefulWidget {
  const AdminVendorsScreen({super.key});
  @override
  ConsumerState<AdminVendorsScreen> createState() => _AdminVendorsScreenState();
}

class _AdminVendorsScreenState extends ConsumerState<AdminVendorsScreen> {
  int generation = 0;
  String search = '';
  bool archived = false;
  Future<void> create() async {
    await editRecord(context,
        title: 'Add restaurant',
        initial: const {'min_order_paise': 0, 'prep_time_minutes': 20, 'service_radius_km': 5, 'sort_priority': 100, 'latitude': 28.8955, 'longitude': 76.6066},
        fields: const [
          EditField('name', 'Restaurant name'),
          EditField('category', 'Category', choices: ['food', 'groceries', 'medicine', 'accessories']),
          ...storeFields,
          EditField('latitude', 'Latitude (adjust later on the map)', type: 'decimal'),
          EditField('longitude', 'Longitude', type: 'decimal'),
          EditField('sort_priority', 'Display priority (lower first)', type: 'int')
        ], save: (d) async {
      if (!validCoordinates(d['latitude'], d['longitude'])) throw StateError('Enter valid coordinates');
      await ref.read(repositoryProvider).save('vendors', {...d, 'is_active': false});
    });
    if (mounted) setState(() => generation++);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    return RemoteList(
        key: ValueKey('$generation/$search/$archived'),
        title: 'Restaurants',
        customerNav: false,
        watch: 'vendors',
        load: (p) async {
          var q = repo.client.from('vendors').select();
          q = archived ? q.not('archived_at', 'is', null) : q.isFilter('archived_at', null);
          if (search.isNotEmpty) q = q.ilike('name', '%${search.replaceAll(RegExp(r'[%_]'), '')}%');
          final data = await q.order('sort_priority').range(p * 30, p * 30 + 29);
          return data.map((j) => Map<String, dynamic>.from(j)).toList();
        },
        header: [
          ActionButton('Add restaurant', create, icon: Icons.add),
          const SizedBox(height: 8),
          TextField(
              decoration: const InputDecoration(hintText: 'Search restaurants', prefixIcon: Icon(Icons.search)),
              onSubmitted: (v) => setState(() => search = v.trim())),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show archived'), value: archived, onChanged: (v) => setState(() => archived = v)),
        ],
        item: (j, reload) => Card(
            child: ListTile(
                leading: CircleAvatar(
                    backgroundColor: context.tint, child: Icon(Icons.storefront, color: j['is_active'] == true ? success : context.muted)),
                title: Text(j['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${j['dispatch_address']}\n${j['is_active'] == true ? 'Active' : 'Inactive'}'
                    '${j['temporarily_closed'] == true ? ' • temporarily closed' : ''} • ★ ${j['rating_avg']} (${j['rating_count']})'),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/admin/vendors/${j['id']}'))));
  }
}

class AdminVendorDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const AdminVendorDetailScreen(this.id, {super.key});
  @override
  ConsumerState<AdminVendorDetailScreen> createState() => _AdminVendorDetailScreenState();
}

class _AdminVendorDetailScreenState extends ConsumerState<AdminVendorDetailScreen> {
  Future<void> setState2(String state) async {
    String? reason;
    if (state == 'inactive' || state == 'archived') {
      reason = await askText(context, state == 'archived' ? 'Why archive this restaurant?' : 'Why deactivate?', minLength: 3);
      if (reason == null) return;
    }
    if (!mounted) return;
    if (!await confirm(context, 'Change restaurant status?',
        state == 'archived'
            ? 'Archived restaurants are hidden everywhere but their orders and financial records are kept.'
            : 'Status becomes "$state". Restaurant members are notified.',
        destructive: state == 'archived' || state == 'inactive')) {
      return;
    }
    if (mounted) {
      await perform(context, () => ref.read(repositoryProvider).rpc('admin_set_vendor_state', {'p_vendor': widget.id, 'p_state': state, 'p_reason': reason}),
          success: 'Status updated');
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    return Scaffold(
        appBar: AppBar(title: const Text('Restaurant')),
        body: SafeArea(
            child: FutureBuilder<Json>(
                future: repo.one('vendors', widget.id),
                builder: (c, s) {
                  if (s.hasError) return Failure(s.error!, () => setState(() {}));
                  if (!s.hasData) return const Center(child: CircularProgressIndicator());
                  final v = s.data!;
                  return ListView(padding: const EdgeInsets.all(16), children: [
                    Photo(repo.imageUrl(v['cover_image_path'], bucket: 'vendor-images'), height: 130),
                    const SizedBox(height: 10),
                    Text(v['name'], style: context.text.headlineMedium),
                    Wrap(spacing: 6, children: [
                      StatusChip(v['is_active'] == true ? 'active' : 'inactive', label: v['is_active'] == true ? 'Active' : 'Inactive'),
                      if (v['archived_at'] != null) const StatusChip('suspended', label: 'Archived'),
                      if (v['temporarily_closed'] == true) const StatusChip('closed', label: 'Temporarily closed'),
                    ]),
                    Panel([
                      InfoRow('Address', v['dispatch_address']),
                      InfoRow('Coordinates', '${v['latitude']}, ${v['longitude']}'),
                      InfoRow('Delivery radius', '${v['service_radius_km']} km'),
                      InfoRow('Contact', [v['contact_phone'], v['contact_email']].where((e) => e != null).join(' • ')),
                      InfoRow('Min order', money(integer(v['min_order_paise']))),
                      InfoRow('Prep time', '${v['prep_time_minutes']} min'),
                      InfoRow('Hours', hoursSummary(v['opening_hours']).isEmpty ? 'Not configured' : hoursSummary(v['opening_hours']).join('\n')),
                    ]),
                    Card(
                        child: Column(children: [
                      for (final (icon, label, route) in [
                        (Icons.dashboard_outlined, 'Sales, orders & deliveries dashboard', '/vendor/store/${widget.id}'),
                        (Icons.receipt_long, 'Order history', '/vendor/store/${widget.id}/orders'),
                        (Icons.menu_book_outlined, 'Menu', '/vendor/store/${widget.id}/menu'),
                        (Icons.schedule, 'Business hours', '/vendor/store/${widget.id}/hours'),
                        (Icons.place_outlined, 'Location', '/vendor/store/${widget.id}/location'),
                        (Icons.star_outline, 'Reviews', '/vendor/store/${widget.id}/reviews'),
                      ]) ...[
                        ListTile(leading: Icon(icon), title: Text(label), trailing: const Icon(Icons.chevron_right), onTap: () => context.push(route)),
                        const Divider(height: 1),
                      ],
                      ListTile(
                          leading: const Icon(Icons.edit_outlined),
                          title: const Text('Edit name, category & ranking'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await editRecord(context,
                                title: 'Restaurant identity',
                                initial: v,
                                fields: const [
                                  EditField('name', 'Restaurant name'),
                                  EditField('category', 'Category', choices: ['food', 'groceries', 'medicine', 'accessories']),
                                  EditField('is_featured', 'Featured', type: 'bool'),
                                  EditField('sort_priority', 'Display priority (lower first)', type: 'int'),
                                ],
                                save: (d) => repo.save('vendors', d, id: widget.id));
                            if (mounted) setState(() {});
                          }),
                      const Divider(height: 1),
                      ListTile(
                          leading: const Icon(Icons.person_add_alt),
                          title: const Text('Add an owner/manager by user ID'),
                          subtitle: const Text('The person must already have an account'),
                          onTap: () async {
                            final uid = await askText(context, 'User ID of the registered owner', minLength: 36);
                            if (uid == null || !context.mounted) return;
                            await perform(context,
                                () => repo.rpc('admin_add_vendor_member', {'p_user_id': uid, 'p_vendor_id': widget.id, 'p_role': 'manager'}),
                                success: 'Member added');
                          }),
                    ])),
                    const SectionTitle('Status'),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (v['is_active'] != true && v['archived_at'] == null)
                        FilledButton.tonal(onPressed: () => setState2('active'), child: const Text('Activate')),
                      if (v['is_active'] == true)
                        OutlinedButton(onPressed: () => setState2('inactive'), child: const Text('Deactivate / suspend')),
                      if (v['archived_at'] == null)
                        OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: danger),
                            onPressed: () => setState2('archived'),
                            child: const Text('Archive'))
                      else
                        FilledButton.tonal(onPressed: () => setState2('restore'), child: const Text('Restore from archive')),
                    ]),
                    const SizedBox(height: 24),
                  ]);
                })));
  }
}

class AdminVendorApplicationsScreen extends ConsumerStatefulWidget {
  const AdminVendorApplicationsScreen({super.key});
  @override
  ConsumerState<AdminVendorApplicationsScreen> createState() => _AdminVendorApplicationsScreenState();
}

class _AdminVendorApplicationsScreenState extends ConsumerState<AdminVendorApplicationsScreen> {
  String status = 'pending';
  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    return RemoteList(
        key: ValueKey(status),
        title: 'Restaurant applications',
        customerNav: false,
        emptyText: 'No applications in this list.',
        load: (p) => repo.rows('vendor_applications', filters: {'status': status}, page: p),
        header: [
          Wrap(spacing: 8, children: [
            for (final s in ['pending', 'action_required', 'approved', 'rejected'])
              ChoiceChip(label: Text(statusLabel(s)), selected: status == s, onSelected: (_) => setState(() => status = s))
          ]),
          const SizedBox(height: 8),
        ],
        item: (a, reload) => Card(
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [Expanded(child: Text(a['restaurant_name'], style: context.text.titleMedium)), StatusChip(a['status'])]),
                  InfoRow('Owner', a['owner_name']),
                  InfoRow('Phone', a['phone'], copyable: true),
                  InfoRow('Email', a['email']),
                  InfoRow('Address', '${a['address']}, ${a['city']} - ${a['postal_code']}'),
                  InfoRow('Location', a['latitude'] == null ? null : '${a['latitude']}, ${a['longitude']} (${a['location_source']})'),
                  InfoRow('Cuisine', a['cuisine']),
                  InfoRow('Hours', hoursSummary(a['opening_hours']).take(1).join()),
                  InfoRow('Prep / radius', '${a['prep_time_minutes']} min • ${a['service_radius_km']} km'),
                  if (a['notes'] != null) InfoRow('Notes', a['notes']),
                  InfoRow('Submitted', stamp(a['created_at'])),
                  if (a['review_reason'] != null) InfoRow('Review note', a['review_reason']),
                  if (a['latitude'] != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                                height: 140,
                                child: IgnorePointer(
                                    child: _MiniMap(LatLng(decimal(a['latitude']), decimal(a['longitude']))))))),
                  if (a['status'] == 'pending')
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                          onPressed: () async {
                            if (!await confirm(context, 'Approve ${a['restaurant_name']}?',
                                'A restaurant is created (initially not accepting orders) and the applicant becomes its owner.')) {
                              return;
                            }
                            if (context.mounted &&
                                await perform(context, () => repo.rpc('admin_review_vendor_application', {'p_id': a['id'], 'p_decision': 'approve', 'p_reason': null}),
                                    success: 'Approved')) {
                              reload();
                            }
                          },
                          child: const Text('Approve')),
                      for (final (decision, label) in [('request_changes', 'Request changes'), ('reject', 'Reject')])
                        OutlinedButton(
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: decision == 'reject' ? danger : null),
                            onPressed: () async {
                              final reason = await askText(context, '$label — reason for the applicant', minLength: 3);
                              if (reason == null || !context.mounted) return;
                              if (await perform(context,
                                  () => repo.rpc('admin_review_vendor_application', {'p_id': a['id'], 'p_decision': decision, 'p_reason': reason}))) {
                                reload();
                              }
                            },
                            child: Text(label)),
                    ]),
                ]))));
  }
}

class _MiniMap extends StatelessWidget {
  final LatLng point;
  const _MiniMap(this.point);
  @override
  Widget build(BuildContext context) => FlutterMap(
          options: MapOptions(initialCenter: point, initialZoom: 15),
          children: [
            osmTiles(),
            MarkerLayer(markers: [pinMarker(point, Icons.storefront, warning, label: 'Restaurant')]),
            osmAttribution()
          ]);
}

class AdminPaymentsScreen extends ConsumerStatefulWidget {
  const AdminPaymentsScreen({super.key});
  @override
  ConsumerState<AdminPaymentsScreen> createState() => _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends ConsumerState<AdminPaymentsScreen> {
  String status = 'submitted';
  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    return RemoteList(
        key: ValueKey(status),
        title: 'Payment verification',
        customerNav: false,
        watch: 'payments',
        showUpdated: true,
        emptyText: status == 'submitted' ? 'No payments waiting for verification.' : 'No payments in this list.',
        load: (p) async {
          final data = await repo.client
              .from('payments')
              .select('*,orders(order_number,total_payable_paise,status)')
              .eq('status', status)
              .order('created_at', ascending: status != 'submitted')
              .range(p * 30, p * 30 + 29);
          return data.map((j) => Map<String, dynamic>.from(j)).toList();
        },
        header: [
          Wrap(spacing: 8, children: [
            for (final s in ['submitted', 'verified', 'rejected'])
              ChoiceChip(label: Text(statusLabel(s)), selected: status == s, onSelected: (_) => setState(() => status = s))
          ]),
          const SizedBox(height: 8),
          const Notice('Approve only after you see the exact amount credited in the merchant bank/UPI account with the same reference.',
              icon: Icons.account_balance, color: warning),
        ],
        item: (j, reload) {
          final o = (j['orders'] as Map?) ?? {};
          final mismatch = o['total_payable_paise'] != null && integer(o['total_payable_paise']) != integer(j['amount_paise']);
          return Card(
              child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(child: Text('${o['order_number'] ?? 'Order'} • ${money(integer(j['amount_paise']))}', style: context.text.titleMedium)),
                      StatusChip(j['status'])
                    ]),
                    InfoRow('UPI reference', j['upi_reference'], copyable: true),
                    InfoRow('Submitted', stamp(j['created_at'])),
                    if (j['verified_at'] != null) InfoRow('Reviewed', stamp(j['verified_at'])),
                    if (j['rejection_reason'] != null) InfoRow('Reason', j['rejection_reason']),
                    if (mismatch) const Notice('Amount differs from the current order total. Check carefully.', color: danger),
                    TextButton(onPressed: () => context.push('/orders/${j['order_id']}'), child: const Text('View order')),
                    if (j['status'] == 'submitted')
                      Row(children: [
                        Expanded(
                            child: ActionButton('Verified in bank', () async {
                          if (!await confirm(context, 'Payment received?',
                              'Confirm ${money(integer(j['amount_paise']))} was credited with reference ${j['upi_reference']}. The order goes to the restaurant.',
                              yes: 'Yes, verified')) {
                            return;
                          }
                          await repo.rpc('verify_payment', {'p_payment_id': j['id'], 'p_approved': true, 'p_reason': null});
                          reload();
                        }, icon: Icons.verified)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: OutlinedButton(
                                style: OutlinedButton.styleFrom(foregroundColor: danger),
                                onPressed: () async {
                                  final reason = await askText(context, 'Reason for rejection', hint: 'Shown to the customer', minLength: 3);
                                  if (reason == null || !context.mounted) return;
                                  if (await perform(context,
                                      () => repo.rpc('verify_payment', {'p_payment_id': j['id'], 'p_approved': false, 'p_reason': reason}))) {
                                    reload();
                                  }
                                },
                                child: const Text('Reject'))),
                      ])
                  ])));
        });
  }
}

class AdminCustomersScreen extends ConsumerStatefulWidget {
  const AdminCustomersScreen({super.key});
  @override
  ConsumerState<AdminCustomersScreen> createState() => _AdminCustomersScreenState();
}

class _AdminCustomersScreenState extends ConsumerState<AdminCustomersScreen> {
  String search = '';
  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    return RemoteList(
        key: ValueKey(search),
        title: 'Customers',
        customerNav: false,
        emptyText: 'No customers found.',
        load: (p) => repo.rpcList('admin_customers', {'p_search': search, 'p_page': p}),
        header: [
          TextField(
              decoration: const InputDecoration(hintText: 'Search by name or phone', prefixIcon: Icon(Icons.search)),
              onSubmitted: (v) => setState(() => search = v.trim())),
          const SizedBox(height: 8),
          Text('Phone numbers are masked. Open an order to see delivery details.', style: TextStyle(fontSize: 12, color: context.muted)),
          const SizedBox(height: 8),
        ],
        item: (c, reload) => Card(
            child: ExpansionTile(
                leading: InitialAvatar('${c['name']}'),
                title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${c['phone'] ?? 'No phone'} • ${c['orders']} orders • ${money(integer(c['spent_paise']))} paid'),
                trailing: StatusChip('${c['status']}'),
                children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    InfoRow('Joined', stamp(c['created_at'])),
                    InfoRow('Delivered orders', '${c['delivered']}'),
                    InfoRow('Reviews written', '${c['reviews']}'),
                    InfoRow('Last order', stamp(c['last_order_at'])),
                    Row(children: [
                      TextButton(
                          onPressed: () => copyText(context, '${c['id']}', 'Customer ID'), child: const Text('Copy ID')),
                      const Spacer(),
                      TextButton(
                          style: TextButton.styleFrom(foregroundColor: c['status'] == 'active' ? danger : success),
                          onPressed: () async {
                            final next = c['status'] == 'active' ? 'suspended' : 'active';
                            final reason = await askText(context, next == 'suspended' ? 'Reason for suspension' : 'Reason for reactivation', minLength: 3);
                            if (reason == null || !context.mounted) return;
                            if (await perform(context,
                                () => repo.rpc('admin_set_customer_status', {'p_customer': c['id'], 'p_status': next, 'p_reason': reason}),
                                success: 'Customer ${statusLabel(next).toLowerCase()}')) {
                              reload();
                            }
                          },
                          child: Text(c['status'] == 'active' ? 'Suspend account' : 'Reactivate')),
                    ])
                  ]))
            ])));
  }
}

class AdminReviewsScreen extends ConsumerStatefulWidget {
  const AdminReviewsScreen({super.key});
  @override
  ConsumerState<AdminReviewsScreen> createState() => _AdminReviewsScreenState();
}

class _AdminReviewsScreenState extends ConsumerState<AdminReviewsScreen> {
  String kind = 'vendor';
  bool reportedOnly = true;
  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    final table = kind == 'vendor' ? 'reviews' : 'partner_reviews';
    return RemoteList(
        key: ValueKey('$kind/$reportedOnly'),
        title: 'Reviews moderation',
        customerNav: false,
        emptyText: reportedOnly ? 'No reported reviews.' : 'No reviews yet.',
        load: (p) async {
          var q = repo.client.from(table).select();
          if (reportedOnly) q = q.not('reported_reason', 'is', null);
          final data = await q.order('created_at', ascending: false).range(p * 30, p * 30 + 29);
          return data.map((j) => Map<String, dynamic>.from(j)).toList();
        },
        header: [
          SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'vendor', label: Text('Restaurants')), ButtonSegment(value: 'partner', label: Text('Partners'))],
              selected: {kind},
              onSelectionChanged: (v) => setState(() => kind = v.first)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Reported only'), value: reportedOnly, onChanged: (v) => setState(() => reportedOnly = v)),
        ],
        item: (r, reload) => Card(
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Text('${'★' * integer(r['rating'])}', style: const TextStyle(color: Color(0xFFF59E0B))),
                    const Spacer(),
                    StatusChip('${r['moderation_status']}'),
                  ]),
                  if ((r['comment'] ?? '').toString().isNotEmpty) Text(r['comment']),
                  if (r['vendor_reply'] != null) Text('Reply: ${r['vendor_reply']}', style: const TextStyle(fontStyle: FontStyle.italic)),
                  if (r['reported_reason'] != null) Text('Reported: ${r['reported_reason']}', style: const TextStyle(color: danger)),
                  Text(stamp(r['created_at']), style: TextStyle(fontSize: 12, color: context.muted)),
                  Row(children: [
                    TextButton(onPressed: () => context.push('/orders/${r['order_id']}'), child: const Text('Order')),
                    const Spacer(),
                    TextButton(
                        onPressed: () async {
                          final visible = r['moderation_status'] != 'visible';
                          if (await perform(context, () => repo.rpc('admin_moderate_review', {'p_kind': kind, 'p_review': r['id'], 'p_visible': visible}),
                              success: visible ? 'Review shown' : 'Review hidden')) {
                            reload();
                          }
                        },
                        child: Text(r['moderation_status'] == 'visible' ? 'Hide' : 'Show')),
                    if (r['reported_reason'] != null && r['moderation_status'] == 'visible')
                      TextButton(
                          onPressed: () async {
                            if (await perform(context, () => repo.rpc('admin_moderate_review', {'p_kind': kind, 'p_review': r['id'], 'p_visible': true}),
                                success: 'Report dismissed')) {
                              reload();
                            }
                          },
                          child: const Text('Dismiss report')),
                  ])
                ]))));
  }
}

class AdminAuditScreen extends ConsumerWidget {
  const AdminAuditScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => RemoteList(
      title: 'Audit log',
      customerNav: false,
      load: (p) => ref.read(repositoryProvider).rows('admin_audit_logs', page: p),
      item: (j, reload) => ListTile(
          leading: const Icon(Icons.history),
          title: Text(statusLabel('${j['action']}')),
          subtitle: Text('${j['entity']}${j['reason'] == null ? '' : ' • ${j['reason']}'}\n${stamp(j['created_at'])}')));
}
