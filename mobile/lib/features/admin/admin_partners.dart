import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/editor.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class AdminPartnersScreen extends ConsumerStatefulWidget {
  final String? initialStatus;
  const AdminPartnersScreen({this.initialStatus, super.key});
  @override
  ConsumerState<AdminPartnersScreen> createState() => _AdminPartnersScreenState();
}

class _AdminPartnersScreenState extends ConsumerState<AdminPartnersScreen> {
  late String? status = widget.initialStatus;
  String search = '';
  bool onlineOnly = false, pendingPayOnly = false;
  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    return RemoteList(
        key: ValueKey('$status/$search/$onlineOnly/$pendingPayOnly'),
        title: 'Delivery partners',
        customerNav: false,
        watch: 'delivery_partner_profiles',
        showUpdated: true,
        emptyText: 'No partners match these filters.',
        load: (p) async {
          if (p > 0) return [];
          final rows = await repo.rpcList('admin_partners', {'p_search': search, 'p_status': status});
          return rows
              .where((r) => !onlineOnly || r['is_online'] == true)
              .where((r) => !pendingPayOnly || integer(r['pending_paise'] ?? 0) > 0)
              .toList();
        },
        header: [
          TextField(
              decoration: const InputDecoration(hintText: 'Search name, phone, vehicle or city', prefixIcon: Icon(Icons.search)),
              onSubmitted: (v) => setState(() => search = v.trim())),
          const SizedBox(height: 8),
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final s in [null, 'pending_verification', 'approved', 'action_required', 'draft', 'rejected', 'suspended'])
                  Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                          label: Text(s == null ? 'All' : statusLabel(s)), selected: status == s, onSelected: (_) => setState(() => status = s))),
              ])),
          Wrap(spacing: 6, children: [
            FilterChip(label: const Text('Online now'), selected: onlineOnly, onSelected: (v) => setState(() => onlineOnly = v)),
            FilterChip(label: const Text('Has unpaid earnings'), selected: pendingPayOnly, onSelected: (v) => setState(() => pendingPayOnly = v)),
          ]),
          const SizedBox(height: 8),
        ],
        item: (j, reload) => Card(
            child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () async {
                  await context.push('/admin/partners/${j['user_id']}');
                  reload();
                },
                child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        _PartnerAvatar(j['photo_path'], '${j['name']}'),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${j['name']}', style: context.text.titleMedium),
                          Text('${j['phone'] ?? '—'} • ${vehicleLabel(j['vehicle_type'])} ${j['vehicle_number'] ?? ''}',
                              style: TextStyle(color: context.muted, fontSize: 12)),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          StatusChip('${j['verification_status']}'),
                          const SizedBox(height: 4),
                          Text(j['is_online'] == true ? '● Online' : '○ Offline',
                              style: TextStyle(fontSize: 11, color: j['is_online'] == true ? success : context.muted, fontWeight: FontWeight.w700)),
                        ]),
                      ]),
                      const SizedBox(height: 8),
                      Wrap(spacing: 14, runSpacing: 4, children: [
                        _kv('Today', '${j['today_deliveries']} • ${money(integer(j['today_earnings_paise']))}'),
                        _kv('Total', '${j['total_deliveries']} • ${money(integer(j['total_earnings_paise']))}'),
                        _kv('Paid', money(integer(j['paid_paise']))),
                        _kv('Pending', money(integer(j['pending_paise']))),
                        if (j['active_order'] != null) _kv('Active', '${j['active_order']}'),
                        _kv('City', '${j['city'] ?? '—'}'),
                        _kv('Joined', stamp(j['registered_at']).split(',').first),
                      ]),
                    ])))));
  }
}

Widget _kv(String k, String v) => Text.rich(TextSpan(children: [
      TextSpan(text: '$k: ', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      TextSpan(text: v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    ]));

String vehicleLabel(dynamic v) => switch (v) {
      'bicycle' => 'Bicycle',
      'e_bike' => 'E-bike',
      'scooter' => 'Scooter',
      'motorcycle' => 'Motorcycle',
      'car' => 'Car',
      _ => 'Vehicle'
    };

class _PartnerAvatar extends ConsumerWidget {
  final String? path;
  final String name;
  const _PartnerAvatar(this.path, this.name);
  @override
  Widget build(BuildContext context, WidgetRef ref) => path == null
      ? InitialAvatar(name, radius: 22)
      : FutureBuilder<String>(
          future: ref.read(repositoryProvider).signedUrl('partner-docs', path!, seconds: 300),
          builder: (c, s) => InitialAvatar(name, radius: 22, imageUrl: s.data));
}

Future<void> showPrivateImage(BuildContext context, WidgetRef ref, String path, String title) async {
  final url = await ref.read(repositoryProvider).signedUrl('partner-docs', path, seconds: 60);
  if (!context.mounted) return;
  await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                title: Text(title),
                subtitle: const Text('Private file • link expires in 60 seconds'),
                trailing: IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close))),
            Flexible(
                child: InteractiveViewer(
                    maxScale: 5,
                    child: Image.network(url,
                        fit: BoxFit.contain,
                        errorBuilder: (a, b, c) => const Padding(padding: EdgeInsets.all(24), child: Text('Could not load the file'))))),
          ])));
}

class AdminPartnerDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const AdminPartnerDetailScreen(this.id, {super.key});
  @override
  ConsumerState<AdminPartnerDetailScreen> createState() => _AdminPartnerDetailScreenState();
}

class _AdminPartnerDetailScreenState extends ConsumerState<AdminPartnerDetailScreen> {
  late Future<Json> future;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() => future = ref.read(repositoryProvider).rpcJson('admin_partner_detail', {'p_partner': widget.id});
  void refresh() => setState(load);

  Future<void> decide(String decision, String label) async {
    String? reason;
    if (['reject', 'request_changes', 'suspend'].contains(decision)) {
      reason = await askText(context, '$label — reason (sent to the partner)', minLength: 3);
      if (reason == null) return;
    }
    if (!mounted) return;
    if (!await confirm(
        context,
        '$label?',
        switch (decision) {
          'approve' => 'The partner can go online and accept orders. Only approve after checking every document. This is a manual review, not a government verification.',
          'suspend' => 'The partner goes offline immediately and cannot accept or progress deliveries.',
          'reject' => 'The partner is told the application was rejected.',
          'reactivate' => 'The partner can work again.',
          _ => 'The partner is asked to correct and resubmit.',
        },
        yes: label,
        destructive: decision == 'reject' || decision == 'suspend')) {
      return;
    }
    if (mounted &&
        await perform(context,
            () => ref.read(repositoryProvider).rpc('admin_review_partner', {'p_partner': widget.id, 'p_decision': decision, 'p_reason': reason}),
            success: 'Saved')) {
      refresh();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
      future: future,
      builder: (c, s) {
        if (s.hasError) return Scaffold(appBar: AppBar(), body: Failure(s.error!, refresh));
        if (!s.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final d = s.data!;
        final p = Map<String, dynamic>.from(d['profile'] as Map);
        final acc = Map<String, dynamic>.from(d['account'] as Map);
        final name = '${p['legal_name'] ?? acc['display_name'] ?? 'Partner'}';
        const tabs = ['Overview', 'Personal', 'Vehicle', 'Documents', 'Verification', "Today's orders", 'All orders', 'Earnings & payouts', 'Ratings', 'Notifications', 'Audit'];
        return DefaultTabController(
            length: tabs.length,
            child: Scaffold(
                appBar: AppBar(
                    title: Text(name),
                    actions: [IconButton(tooltip: 'Refresh', onPressed: refresh, icon: const Icon(Icons.refresh))],
                    bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in tabs) Tab(text: t)])),
                body: SafeArea(
                    child: TabBarView(children: [
                  _overview(p, acc, d),
                  _personal(p, acc),
                  _vehicle(p),
                  _documents(p, d),
                  _list(d['events'], (e) => ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(statusLabel('${e['event']}')),
                      subtitle: Text([
                        if (e['to_status'] != null) '→ ${statusLabel('${e['to_status']}')}',
                        if (e['reason'] != null) '${e['reason']}',
                        '${e['actor'] ?? 'Partner'} • ${stamp(e['created_at'])}'
                      ].join('\n')))),
                  _PartnerOrders(widget.id, today: true),
                  _PartnerOrders(widget.id, today: false),
                  _PayoutsTab(partner: widget.id, unsettled: integer(d['unsettled_paise'] ?? 0), payouts: d['payouts'], onChanged: refresh),
                  _list(d['reviews'], (r) => ListTile(
                      title: Text('${'★' * integer(r['rating'])}  ${r['comment'] ?? ''}'),
                      subtitle: Text('${stamp(r['created_at'])}${r['reported_reason'] == null ? '' : ' • reported: ${r['reported_reason']}'}'),
                      trailing: StatusChip('${r['moderation_status']}'),
                      onTap: () => context.push('/orders/${r['order_id']}'))),
                  _list(d['notifications'], (n) => ListTile(
                      leading: Icon(n['read_at'] == null ? Icons.mark_email_unread_outlined : Icons.drafts_outlined),
                      title: Text('${n['title']}'),
                      subtitle: Text('${n['body'] ?? ''}\n${stamp(n['created_at'])}'))),
                  _list(d['audit'], (a) => ListTile(
                      leading: const Icon(Icons.gavel_outlined),
                      title: Text(statusLabel('${a['action']}')),
                      subtitle: Text('${a['reason'] ?? ''}\n${a['actor'] ?? ''} • ${stamp(a['created_at'])}'))),
                ]))));
      });

  Widget _list(dynamic rows, Widget Function(Json) item) {
    final list = List<Json>.from(((rows as List?) ?? []).map((e) => Map<String, dynamic>.from(e)));
    if (list.isEmpty) return const Empty('Nothing recorded yet.');
    return ListView(padding: const EdgeInsets.all(12), children: [for (final r in list) Card(child: item(r))]);
  }

  Widget _overview(Json p, Json acc, Json d) {
    final st = '${p['verification_status']}';
    final loc = d['location'] as Map?;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        _PartnerAvatar(p['profile_photo_path'], '${p['legal_name'] ?? acc['display_name']}'),
        const SizedBox(width: 12),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p['legal_name'] ?? acc['display_name']}', style: context.text.titleLarge),
          Text('Account: ${statusLabel('${acc['status']}')} • ${p['is_online'] == true ? 'Online' : 'Offline'}'),
        ])),
        StatusChip(st),
      ]),
      if (p['review_reason'] != null) Padding(padding: const EdgeInsets.only(top: 10), child: Notice('Last review note: ${p['review_reason']}')),
      const SectionTitle('Decision'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (['pending_verification', 'action_required', 'rejected'].contains(st))
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: success),
              onPressed: () => decide('approve', 'Approve partner'), child: const Text('Approve')),
        if (['pending_verification', 'approved'].contains(st))
          OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => decide('request_changes', 'Request corrections'), child: const Text('Request corrections')),
        if (['pending_verification', 'action_required', 'draft'].contains(st))
          OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: danger),
              onPressed: () => decide('reject', 'Reject application'), child: const Text('Reject')),
        if (st == 'approved')
          OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: danger),
              onPressed: () => decide('suspend', 'Suspend partner'), child: const Text('Suspend')),
        if (st == 'suspended')
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => decide('reactivate', 'Reactivate partner'), child: const Text('Reactivate')),
      ]),
      const SectionTitle('Payout QR'),
      Panel([
        Row(children: [
          const Expanded(child: Text('Submitted payout QR')),
          StatusChip('${p['qr_status']}', label: p['qr_status'] == 'none' ? 'Not submitted' : null)
        ]),
        if (p['qr_review_reason'] != null) Text('Note: ${p['qr_review_reason']}', style: TextStyle(color: context.muted)),
        if (p['qr_image_path'] != null) ...[
          TextButton.icon(
              onPressed: () => perform(context, () => showPrivateImage(context, ref, p['qr_image_path'], 'Payout QR')),
              icon: const Icon(Icons.qr_code_2),
              label: const Text('View QR (private)')),
          if (p['qr_status'] == 'pending')
            Row(children: [
              Expanded(
                  child: ActionButton('Approve QR', () async {
                await ref.read(repositoryProvider).rpc('admin_review_partner_qr', {'p_partner': widget.id, 'p_approved': true, 'p_reason': null});
                refresh();
              }, icon: Icons.check)),
              const SizedBox(width: 8),
              Expanded(
                  child: OutlinedButton(
                      onPressed: () async {
                        final reason = await askText(context, 'Why should the partner replace this QR?', minLength: 3);
                        if (reason == null || !mounted) return;
                        if (await perform(context, () => ref.read(repositoryProvider).rpc('admin_review_partner_qr',
                            {'p_partner': widget.id, 'p_approved': false, 'p_reason': reason}))) {
                          refresh();
                        }
                      },
                      child: const Text('Request new QR'))),
            ]),
        ],
      ]),
      if (loc != null) ...[
        const SectionTitle('Last shared location'),
        Panel([InfoRow('Coordinates', '${loc['latitude']}, ${loc['longitude']}'), InfoRow('Updated', ago(loc['updated_at']))]),
      ],
      const SectionTitle('Money'),
      Panel([
        InfoRow('Unpaid (not in a payout)', money(integer(d['unsettled_paise'] ?? 0))),
        InfoRow('Payouts recorded', '${(d['payouts'] as List).length}'),
      ]),
    ]);
  }

  Widget _personal(Json p, Json acc) => ListView(padding: const EdgeInsets.all(16), children: [
        Panel([
          InfoRow('Full name', p['legal_name']),
          InfoRow('Mobile', p['phone'] ?? acc['phone'], copyable: true),
          InfoRow('Email', p['email']),
          InfoRow('Address', p['residential_address']),
          InfoRow('City', p['city']),
          InfoRow('Service area', p['service_area']),
          InfoRow('Emergency contact', '${p['emergency_contact_name'] ?? '—'} • ${p['emergency_contact_phone'] ?? '—'}'),
          InfoRow('Aadhaar', p['aadhaar_last4'] == null ? null : '•••• •••• ${p['aadhaar_last4']}'),
          InfoRow('Payout UPI', p['payout_upi_vpa']),
          InfoRow('Bank', p['bank_account_last4'] == null ? null : 'A/c •••• ${p['bank_account_last4']} • ${p['bank_ifsc'] ?? ''}'),
          InfoRow('Terms accepted', stamp(p['terms_accepted_at'])),
          InfoRow('Submitted', stamp(p['submitted_at'])),
          InfoRow('Registered', stamp(p['created_at'])),
        ]),
        ActionButton('Edit permitted details', () async {
          await editRecord(context,
              title: 'Partner details',
              initial: p,
              fields: const [
                EditField('city', 'City'),
                EditField('service_area', 'Service area'),
                EditField('emergency_contact_name', 'Emergency contact name'),
                EditField('emergency_contact_phone', 'Emergency contact phone'),
              ],
              save: (x) => ref.read(repositoryProvider).save('delivery_partner_profiles', x, id: widget.id, key: 'user_id'));
          refresh();
        }, icon: Icons.edit, tonal: true),
      ]);

  Widget _vehicle(Json p) => ListView(padding: const EdgeInsets.all(16), children: [
        Panel([
          InfoRow('Vehicle type', vehicleLabel(p['vehicle_type'])),
          InfoRow('Registration', p['vehicle_number']),
          InfoRow('Driving licence', p['licence_last4'] == null ? null : 'Ending ${p['licence_last4']}'),
        ]),
        ActionButton('Correct vehicle details', () async {
          await editRecord(context,
              title: 'Vehicle details',
              initial: p,
              fields: const [
                EditField('vehicle_type', 'Vehicle type', choices: ['motorcycle', 'scooter', 'e_bike', 'bicycle', 'car']),
                EditField('vehicle_number', 'Registration number', optional: true),
              ],
              save: (x) => ref.read(repositoryProvider).save('delivery_partner_profiles',
                  {...x, 'vehicle_number': (x['vehicle_number'] as String?)?.toUpperCase().replaceAll(RegExp(r'[\s-]'), '')},
                  id: widget.id, key: 'user_id'));
          refresh();
        }, icon: Icons.edit, tonal: true),
      ]);

  Widget _documents(Json p, Json d) {
    final docs = List<Json>.from(((d['documents'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)));
    return ListView(padding: const EdgeInsets.all(12), children: [
      const Notice('Documents are private. Links open for 60 seconds. Approving a document records your manual check — it is not an official Aadhaar/licence verification.',
          icon: Icons.privacy_tip_outlined, color: warning),
      if (docs.isEmpty) const Empty('No documents uploaded.'),
      for (final doc in docs)
        Card(
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text(statusLabel('${doc['doc_type']}'), style: const TextStyle(fontWeight: FontWeight.w700))),
                    StatusChip('${doc['status']}', label: doc['status'] == 'active' ? 'Accepted' : null)
                  ]),
                  if (doc['masked_reference'] != null) Text('Ending •••• ${doc['masked_reference']}'),
                  Text('Uploaded ${stamp(doc['created_at'])}', style: TextStyle(color: context.muted, fontSize: 12)),
                  if (doc['review_reason'] != null) Text('Reason: ${doc['review_reason']}', style: const TextStyle(color: danger)),
                  Wrap(spacing: 8, children: [
                    TextButton.icon(
                        onPressed: () => perform(context, () => showPrivateImage(context, ref, doc['file_path'], statusLabel('${doc['doc_type']}'))),
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('View')),
                    if (doc['status'] == 'pending') ...[
                      TextButton(
                          onPressed: () async {
                            if (await perform(context, () => ref.read(repositoryProvider).rpc('admin_review_partner_document',
                                {'p_id': doc['id'], 'p_approved': true, 'p_reason': null}), success: 'Document accepted')) {
                              refresh();
                            }
                          },
                          child: const Text('Accept')),
                      TextButton(
                          style: TextButton.styleFrom(foregroundColor: danger),
                          onPressed: () async {
                            final reason = await askText(context, 'What must the partner fix?', hint: 'e.g. photo is blurred', minLength: 3);
                            if (reason == null || !mounted) return;
                            if (await perform(context, () => ref.read(repositoryProvider).rpc('admin_review_partner_document',
                                {'p_id': doc['id'], 'p_approved': false, 'p_reason': reason}))) {
                              refresh();
                            }
                          },
                          child: const Text('Reject')),
                    ]
                  ])
                ]))),
    ]);
  }
}

class _PartnerOrders extends ConsumerStatefulWidget {
  final String partner;
  final bool today;
  const _PartnerOrders(this.partner, {required this.today});
  @override
  ConsumerState<_PartnerOrders> createState() => _PartnerOrdersState();
}

class _PartnerOrdersState extends ConsumerState<_PartnerOrders> with AutomaticKeepAliveClientMixin {
  late Range range = widget.today ? Range.today() : Range.days(30);
  late Future<List<Json>> future = load();
  Future<List<Json>> load() => ref.read(repositoryProvider).rpcList('admin_partner_orders', {'p_partner': widget.partner, ...range.params});
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<Json>>(
        future: future,
        builder: (c, s) => ListView(padding: const EdgeInsets.all(12), children: [
              if (!widget.today)
                RangeChips(range, (r) => setState(() {
                      range = r;
                      future = load();
                    })),
              if (s.hasError) Failure(s.error!, () => setState(() => future = load())),
              if (!s.hasData && !s.hasError) const LinearProgressIndicator(),
              if (s.hasData) ...[
                Row(children: [
                  Expanded(
                      child: Text(
                          '${s.data!.length} orders • earned ${money(s.data!.fold<int>(0, (t, o) => t + integer(o['partner_earning_paise'] ?? 0)))}',
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                  TextButton.icon(
                      onPressed: () => copyText(
                          context,
                          csv([
                            ['order', 'created', 'restaurant', 'items', 'customer', 'destination', 'status', 'payment', 'total_inr', 'fee_inr', 'earning_inr', 'delivered'],
                            for (final o in s.data!)
                              [o['order_number'], o['created_at'], o['restaurant'], o['items'], o['customer'], o['destination'], o['status'],
                                '${o['payment_method']}/${o['payment_status']}', integer(o['total_paise']) / 100, integer(o['delivery_fee_paise']) / 100,
                                o['partner_earning_paise'] == null ? '' : integer(o['partner_earning_paise']) / 100, o['delivered_at']]
                          ]),
                          'Orders CSV'),
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Export CSV')),
                ]),
                if (s.data!.isEmpty) const Empty('No orders in this period.'),
                for (final o in s.data!)
                  Card(
                      child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => context.push('/orders/${o['order_id']}'),
                          child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                Row(children: [
                                  Expanded(child: Text('${o['order_number']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                                  StatusChip('${o['status']}')
                                ]),
                                InfoRow('Created', stamp(o['created_at'])),
                                InfoRow('Restaurant', '${o['restaurant']}\n${o['restaurant_address']}'),
                                InfoRow('Items', o['items']),
                                InfoRow('Customer', '${o['customer']} • ${o['customer_phone'] ?? 'no phone'}'),
                                InfoRow('Deliver to', o['destination']),
                                InfoRow('Payment', '${statusLabel('${o['payment_method']}')} • ${statusLabel('${o['payment_status']}')}'),
                                InfoRow('Order total', money(integer(o['total_paise']))),
                                InfoRow('Delivery fee', money(integer(o['delivery_fee_paise']))),
                                InfoRow('Partner earning',
                                    o['partner_earning_paise'] == null ? 'Not earned (not delivered)' : '${money(integer(o['partner_earning_paise']))}${o['settled'] == true ? ' • paid' : ''}'),
                                InfoRow('Completed', stamp(o['delivered_at'])),
                              ])))),
              ]
            ]));
  }
}

class _PayoutsTab extends ConsumerWidget {
  final String partner;
  final int unsettled;
  final dynamic payouts;
  final VoidCallback onChanged;
  const _PayoutsTab({required this.partner, required this.unsettled, required this.payouts, required this.onChanged});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = List<Json>.from(((payouts as List?) ?? []).map((e) => Map<String, dynamic>.from(e)));
    return ListView(padding: const EdgeInsets.all(12), children: [
      Panel([
        Text('Unpaid earnings: ${money(unsettled)}', style: context.text.titleMedium),
        const SizedBox(height: 4),
        Text('Creating a payout groups all unpaid earnings. It stays Pending until you record the actual bank/UPI transaction reference.',
            style: TextStyle(fontSize: 12, color: context.muted)),
        const SizedBox(height: 8),
        if (unsettled > 0) _CreatePayoutButton(partner: partner, amount: unsettled, onDone: onChanged),
      ]),
      if (list.isEmpty) const Empty('No payouts yet.'),
      for (final po in list) _PayoutCard(po, onChanged),
    ]);
  }
}

class _CreatePayoutButton extends ConsumerStatefulWidget {
  final String partner;
  final int amount;
  final VoidCallback onDone;
  const _CreatePayoutButton({required this.partner, required this.amount, required this.onDone});
  @override
  ConsumerState<_CreatePayoutButton> createState() => _CreatePayoutButtonState();
}

class _CreatePayoutButtonState extends ConsumerState<_CreatePayoutButton> {
  // One key per screen visit: retries after a lost response reuse it and never double-create.
  final key = const Uuid().v4();
  @override
  Widget build(BuildContext context) => ActionButton('Create payout of ${money(widget.amount)}', () async {
        String method = 'upi';
        final notes = TextEditingController();
        final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => StatefulBuilder(
                builder: (ctx, set) => AlertDialog(
                        title: const Text('Create payout'),
                        content: Column(mainAxisSize: MainAxisSize.min, children: [
                          DropdownButtonFormField<String>(
                              initialValue: method,
                              decoration: const InputDecoration(labelText: 'Method'),
                              items: const [
                                DropdownMenuItem(value: 'upi', child: Text('UPI')),
                                DropdownMenuItem(value: 'bank_transfer', child: Text('Bank transfer')),
                                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                                DropdownMenuItem(value: 'other', child: Text('Other')),
                              ],
                              onChanged: (v) => set(() => method = v!)),
                          const SizedBox(height: 8),
                          TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes / settlement period')),
                        ]),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          FilledButton(
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Create'))
                        ])));
        if (ok != true) return;
        await ref.read(repositoryProvider).rpc('admin_create_payout',
            {'p_partner': widget.partner, 'p_until': null, 'p_method': method, 'p_notes': notes.text.trim(), 'p_key': key});
        widget.onDone();
      }, icon: Icons.add_card);
}

class _PayoutCard extends ConsumerWidget {
  final Json po;
  final VoidCallback onChanged;
  const _PayoutCard(this.po, this.onChanged);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    Future<void> move(String status) async {
      String? reference, notes;
      if (status == 'paid') {
        reference = await askText(context, 'Transaction reference (UTR / bank ref)', minLength: 4);
        if (reference == null) return;
        if (!context.mounted) return;
        if (!await confirm(context, 'Mark ${money(integer(po['amount_paise']))} as paid?',
            'Only confirm after the money has actually been sent. Reference: $reference',
            yes: 'Mark paid')) {
          return;
        }
      }
      if (status == 'failed') {
        if (!context.mounted) return;
        notes = await askText(context, 'Why did the payout fail?', minLength: 3);
        if (notes == null) return;
      }
      if (context.mounted &&
          await perform(context, () => repo.rpc('admin_update_payout', {'p_id': po['id'], 'p_status': status, 'p_reference': reference, 'p_notes': notes}))) {
        onChanged();
      }
    }

    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(money(integer(po['amount_paise'])), style: context.text.titleMedium)),
                StatusChip('${po['status']}')
              ]),
              InfoRow('Method', statusLabel('${po['method']}')),
              InfoRow('Period', '${stamp(po['period_start']).split(',').first} – ${stamp(po['period_end']).split(',').first}'),
              InfoRow('Created', stamp(po['created_at'])),
              if (po['reference'] != null) InfoRow('Reference', po['reference'], copyable: true),
              if (po['paid_at'] != null) InfoRow('Paid', stamp(po['paid_at'])),
              if (po['notes'] != null) InfoRow('Notes', po['notes']),
              if (po['failed_reason'] != null) InfoRow('Failure', po['failed_reason']),
              if (po['status'] == 'pending' || po['status'] == 'processing')
                Wrap(spacing: 8, children: [
                  if (po['status'] == 'pending') TextButton(onPressed: () => move('processing'), child: const Text('Mark processing')),
                  TextButton(onPressed: () => move('paid'), child: const Text('Mark paid…')),
                  TextButton(style: TextButton.styleFrom(foregroundColor: danger), onPressed: () => move('failed'), child: const Text('Mark failed')),
                ]),
            ])));
  }
}

class AdminPayoutsScreen extends ConsumerStatefulWidget {
  const AdminPayoutsScreen({super.key});
  @override
  ConsumerState<AdminPayoutsScreen> createState() => _AdminPayoutsScreenState();
}

class _AdminPayoutsScreenState extends ConsumerState<AdminPayoutsScreen> {
  String? status;
  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    return RemoteList(
        key: ValueKey(status),
        title: 'Partner payouts',
        customerNav: false,
        watch: 'partner_payouts',
        emptyText: 'No payouts in this list. Create payouts from a partner profile.',
        load: (p) async {
          var q = repo.client.from('partner_payouts').select();
          if (status != null) q = q.eq('status', status!);
          final data = await q.order('created_at', ascending: false).range(p * 30, p * 30 + 29);
          return data.map((j) => Map<String, dynamic>.from(j)).toList();
        },
        header: [
          Wrap(spacing: 6, children: [
            for (final s in [null, 'pending', 'processing', 'paid', 'failed'])
              ChoiceChip(label: Text(s == null ? 'All' : statusLabel(s)), selected: status == s, onSelected: (_) => setState(() => status = s))
          ]),
          TextButton.icon(
              onPressed: () => context.push('/admin/partners'), icon: const Icon(Icons.pedal_bike), label: const Text('Open partners to create a payout')),
        ],
        item: (po, reload) => Column(children: [
              _PayoutCard(po, reload),
              Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => context.push('/admin/partners/${po['partner_id']}'), child: const Text('Partner profile'))),
            ]));
  }
}
