import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/location.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/repository.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  final String? vendorId;
  const OrdersScreen({this.vendorId, super.key});
  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String? status;
  static const groups = {
    'All': null,
    'New': ['vendor_confirmation'],
    'Preparing': ['preparing'],
    'Ready': ['ready_for_pickup'],
    'On the way': ['assigned', 'picked_up', 'out_for_delivery'],
    'Delivered': ['delivered'],
    'Payment': ['pending_payment', 'payment_review'],
    'Cancelled': ['cancelled', 'rejected', 'refunded'],
  };
  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final role = ref.watch(accountProvider).valueOrNull?.role;
    return RemoteList(
        key: ValueKey('$status/${widget.vendorId}'),
        title: widget.vendorId != null ? 'Restaurant orders' : 'Orders',
        watch: 'orders',
        showUpdated: true,
        customerNav: role == null || role == 'customer',
        emptyText: 'No orders here yet.',
        load: (p) async {
          var q = repo.client.from('orders').select('*,vendors(name)');
          if (widget.vendorId != null) q = q.eq('vendor_id', widget.vendorId!);
          final filter = groups[status];
          if (filter != null) q = q.inFilter('status', filter);
          final data = await q
              .order('created_at', ascending: false)
              .range(p * 30, p * 30 + 29)
              .timeout(const Duration(seconds: 20));
          return data.map((j) => Map<String, dynamic>.from(j)).toList();
        },
        header: [
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final g in groups.keys)
                  Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                          label: Text(g),
                          selected: (status ?? 'All') == g,
                          onSelected: (_) => setState(() => status = g == 'All' ? null : g)))
              ])),
          const SizedBox(height: 10),
        ],
        item: (j, reload) => Card(
            child: ListTile(
                title: Row(children: [
                  Expanded(child: Text(j['order_number'], style: const TextStyle(fontWeight: FontWeight.w800))),
                  StatusChip(j['status'])
                ]),
                subtitle: Text(
                    '${j['vendors']?['name'] ?? ''} • ${stamp(j['created_at'])}\nPayment: ${statusLabel(j['payment_status'])} • ${money(integer(j['total_payable_paise']))}'),
                isThreeLine: true,
                onTap: () => context.push('/orders/${j['id']}'))));
  }
}

class OrderScreen extends ConsumerStatefulWidget {
  final String id;
  const OrderScreen(this.id, {super.key});
  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  late Future<List<dynamic>> future;
  RealtimeChannel? channel;
  late final DastakRepository repo = ref.read(repositoryProvider);
  final utr = TextEditingController();
  @override
  void initState() {
    super.initState();
    reload();
    channel = repo.watch('orders', () {
      if (mounted) setState(reload);
    }, column: 'id', value: widget.id);
  }

  void reload() {
    final repo = ref.read(repositoryProvider);
    future = Future.wait([
      repo.one('orders', widget.id,
          select: '*,vendors(name,dispatch_address,latitude,longitude)'),
      repo.orderRows('order_items', widget.id, sort: 'id'),
      repo.orderRows('order_status_history', widget.id),
      repo.client.from('payment_settings').select().eq('id', true).single(),
      repo.orderRows('payments', widget.id),
      repo.client
          .from('delivery_assignments')
          .select('partner_id,status,responded_at')
          .eq('order_id', widget.id)
          .eq('status', 'accepted')
          .maybeSingle(),
    ]);
  }

  @override
  void dispose() {
    utr.dispose();
    if (channel != null) repo.client.removeChannel(channel!);
    super.dispose();
  }

  Future<void> run(String rpc, Json params) async {
    await ref.read(repositoryProvider).rpc(rpc, params);
    if (mounted) setState(reload);
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(accountProvider).valueOrNull?.role;
    return PageFrame('Order details',
        customerNav: role == null || role == 'customer',
        child: FutureBuilder<List<dynamic>>(
            future: future,
            builder: (ctx, s) {
              if (s.hasError) return Failure(s.error!, () => setState(reload));
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              final data = s.data!;
              final o = Order(data[0]);
              final settings = data[3] as Json;
              final payments = List<Json>.from(data[4] as List);
              final assignment = data[5] as Map?;
              final repo = ref.read(repositoryProvider);
              final account = ref.watch(accountProvider).valueOrNull;
              final own = o.data['customer_id'] == repo.uid;
              final myDelivery = account?.role == 'delivery' && assignment?['partner_id'] == repo.uid;
              final vendor = o.data['vendors'] as Map?;
              final inTransit = ['assigned', 'picked_up', 'out_for_delivery'].contains(o.status);
              final items = data[1] as List;
              return RefreshIndicator(
                  onRefresh: () async {
                    setState(reload);
                    await future;
                  },
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    _Header(o),
                    const SizedBox(height: 12),
                    Panel([
                      InfoRow('Restaurant', vendor?['name']),
                      InfoRow('Pickup', vendor?['dispatch_address']),
                      InfoRow('Deliver to', o.data['destination_address']),
                      if ((o.data['customer_note'] ?? '').toString().isNotEmpty)
                        InfoRow('Note', o.data['customer_note']),
                      InfoRow('Placed', stamp(o.data['created_at'])),
                      if (o.data['delivered_at'] != null) InfoRow('Delivered', stamp(o.data['delivered_at'])),
                    ]),
                    if (inTransit && (own || account?.role == 'admin' || account?.role == 'vendor'))
                      _Tracking(orderId: widget.id, order: o.data),
                    if (myDelivery)
                      _PartnerActions(
                          order: o.data,
                          itemCount: items.length,
                          onChanged: () => setState(reload)),
                    if ((account?.role == 'vendor' || account?.role == 'admin') && vendorTransitions(o.status).isNotEmpty)
                      _VendorActions(o, run),
                    const SectionTitle('Items'),
                    Panel([
                      for (final item in items)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${item['quantity']} × ${item['product_name']}',
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                if ((item['options'] as List).isNotEmpty)
                                  Text((item['options'] as List).map((o) => o['label']).join(', '),
                                      style: TextStyle(color: context.muted, fontSize: 12)),
                              ])),
                              Text(money(integer(item['line_total_paise'])))
                            ])),
                      const Divider(),
                      for (final pair in [
                        ('Items', 'items_subtotal_paise'),
                        ('Delivery fee', 'delivery_fee_paise'),
                        ('Tax', 'tax_paise'),
                        ('Discount', 'discount_paise'),
                      ])
                        if (integer(o.data[pair.$2]) != 0 || pair.$1 == 'Items' || pair.$1 == 'Delivery fee')
                          Row(children: [Expanded(child: Text(pair.$1)), Text(money(integer(o.data[pair.$2])))]),
                      const SizedBox(height: 4),
                      Row(children: [
                        const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w800))),
                        Text(money(o.total), style: const TextStyle(fontWeight: FontWeight.w800))
                      ]),
                    ]),
                    if (own) _PaymentSection(o: o, settings: settings, payments: payments, utr: utr, onDone: () => setState(reload)),
                    if (!own && account?.role == 'admin' && payments.isNotEmpty) ...[
                      const SectionTitle('Payments'),
                      for (final p in payments)
                        Panel([
                          Row(children: [Expanded(child: Text(money(integer(p['amount_paise'])))), StatusChip(p['status'])]),
                          InfoRow('UPI reference', p['upi_reference'], copyable: true),
                          InfoRow('Submitted', stamp(p['created_at'])),
                          if (p['rejection_reason'] != null) InfoRow('Reason', p['rejection_reason']),
                        ]),
                    ],
                    if (account?.role == 'admin' || account?.role == 'vendor' || myDelivery) _Breakdown(widget.id),
                    if (own && o.status == 'delivered') _RateOrder(widget.id),
                    if (account?.role == 'admin' &&
                        ['pending_payment', 'payment_review', 'vendor_confirmation', 'preparing', 'ready_for_pickup', 'assigned', 'picked_up', 'out_for_delivery']
                            .contains(o.status)) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: danger),
                          icon: const Icon(Icons.cancel_outlined),
                          label: Text(inTransit ? 'Cancel / mark delivery failed' : 'Cancel order'),
                          onPressed: () async {
                            final reason = await askText(context, 'Reason for cancellation',
                                hint: 'This is shown to the customer and recorded in the audit log', minLength: 3);
                            if (reason == null || !context.mounted) return;
                            if (!await confirm(context, 'Cancel ${o.number}?',
                                'The customer${inTransit ? ' and delivery partner' : ''} will be notified. Refunds, if any, must be handled separately.',
                                yes: 'Cancel order', destructive: true)) {
                              return;
                            }
                            if (context.mounted) {
                              await perform(context, () => run('admin_cancel_order', {'p_order_id': widget.id, 'p_reason': reason}),
                                  success: 'Order cancelled');
                            }
                          }),
                    ],
                    const SectionTitle('Status history'),
                    for (final h in data[2] as List)
                      ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.check_circle, color: statusColor(h['new_status']), size: 20),
                          title: Text(statusLabel(h['new_status'])),
                          subtitle: Text([if ((h['reason'] ?? '').toString().isNotEmpty) h['reason'], stamp(h['created_at'])].join(' • '))),
                  ]));
            }));
  }
}

class _Header extends StatelessWidget {
  final Order o;
  const _Header(this.o);
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0EA5E9), Color(0xFF0369A1)]),
          borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ORDER',
            style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
        SelectableText(o.number,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          _pill(statusLabel(o.status)),
          _pill('Payment: ${statusLabel(o.payment)}'),
          _pill(money(o.total)),
        ])
      ]));
  Widget _pill(String t) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(999)),
      child: Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)));
}

class _PaymentSection extends ConsumerWidget {
  final Order o;
  final Json settings;
  final List<Json> payments;
  final TextEditingController utr;
  final VoidCallback onDone;
  const _PaymentSection(
      {required this.o, required this.settings, required this.payments, required this.utr, required this.onDone});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    final latest = payments.isEmpty ? null : payments.last;
    final canPay = o.status == 'pending_payment' && ['unpaid', 'rejected'].contains(o.payment);
    if (!canPay && latest == null) return const SizedBox();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Payment'),
      if (latest != null)
        Notice(
            latest['status'] == 'submitted'
                ? 'Pending verification • UPI ref ${latest['upi_reference']}. Your order is confirmed only after our team verifies the money was received.'
                : latest['status'] == 'verified'
                    ? 'Payment verified • UPI ref ${latest['upi_reference']}'
                    : 'Payment could not be verified${latest['rejection_reason'] == null ? '' : ': ${latest['rejection_reason']}'}. Please pay again and submit the correct reference.',
            icon: latest['status'] == 'verified' ? Icons.verified : Icons.hourglass_top,
            color: statusColor(latest['status'])),
      if (canPay)
        Panel([
          Text('Pay ${money(o.total)} by UPI', style: context.text.titleLarge),
          const SizedBox(height: 4),
          InfoRow('Order reference', o.number, copyable: true),
          if (settings['upi_enabled'] == false)
            const Notice('Online payment is paused by the administrator. Please try again later.',
                icon: Icons.pause_circle_outline, color: warning)
          else ...[
            Text(settings['instructions'] ??
                'Pay the exact total, then enter the 12-digit UPI reference (UTR) from your payment app.'),
            if (settings['qr_image_path'] != null) ...[
              const SizedBox(height: 10),
              Center(
                  child: SizedBox(
                      width: 230,
                      child: Photo(repo.imageUrl(settings['qr_image_path'], bucket: 'payment-qr'),
                          height: 230, placeholder: Icons.qr_code_2))),
            ],
            if (settings['upi_vpa'] != null) ...[
              const SizedBox(height: 8),
              InfoRow('UPI ID', settings['upi_vpa'], copyable: true),
              InfoRow('Payee', settings['payee_name']),
              ActionButton('Open UPI app', () async {
                final uri = Uri(scheme: 'upi', host: 'pay', queryParameters: {
                  'pa': settings['upi_vpa'],
                  'pn': settings['payee_name'] ?? 'Dastak',
                  'am': (o.total / 100).toStringAsFixed(2),
                  'cu': 'INR',
                  'tn': o.number
                });
                if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                  throw StateError('No UPI app found. Pay manually using the UPI ID or QR above.');
                }
              }, icon: Icons.account_balance_wallet_outlined, tonal: true),
            ] else if (settings['qr_image_path'] == null)
              const Notice('UPI payment details are not configured yet. Contact support.', color: warning),
            const SizedBox(height: 8),
            Field(utr, '12-digit UPI reference (UTR)',
                keyboard: TextInputType.number,
                maxLength: 12,
                validate: (v) => RegExp(r'^\d{12}$').hasMatch(v) ? null : 'Enter exactly 12 digits'),
            ActionButton('Submit payment reference', () async {
              if (!RegExp(r'^\d{12}$').hasMatch(utr.text.trim())) {
                throw StateError('Enter a valid 12-digit UPI reference');
              }
              await repo.rpc('submit_payment_proof',
                  {'p_order_id': o.id, 'p_upi_reference': utr.text.trim(), 'p_proof_image_path': null});
              onDone();
            }, icon: Icons.send),
            const SizedBox(height: 4),
            Text('Submitting a reference does not mark the order as paid. It stays "Pending verification" until checked.',
                style: TextStyle(color: context.muted, fontSize: 12)),
          ]
        ]),
    ]);
  }
}

class _VendorActions extends StatelessWidget {
  final Order o;
  final Future<void> Function(String, Json) run;
  const _VendorActions(this.o, this.run);
  @override
  Widget build(BuildContext context) => Panel([
        Text('Restaurant actions', style: context.text.titleMedium),
        const SizedBox(height: 8),
        if (o.status == 'vendor_confirmation') ...[
          ActionButton('Accept & start preparing',
              () => run('vendor_set_order_status', {'p_order_id': o.id, 'p_new': 'preparing'}),
              icon: Icons.restaurant),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: danger),
              icon: const Icon(Icons.close),
              label: const Text('Reject order'),
              onPressed: () async {
                final reason = await askText(context, 'Why are you rejecting this order?',
                    hint: 'For example: item out of stock', minLength: 3);
                if (reason == null || !context.mounted) return;
                await perform(context,
                    () => run('vendor_set_order_status', {'p_order_id': o.id, 'p_new': 'rejected', 'p_reason': reason}));
              }),
        ],
        if (o.status == 'preparing')
          ActionButton('Mark ready for pickup',
              () => run('vendor_set_order_status', {'p_order_id': o.id, 'p_new': 'ready_for_pickup'}),
              icon: Icons.takeout_dining),
      ]);
}

class _PartnerActions extends ConsumerStatefulWidget {
  final Json order;
  final int itemCount;
  final VoidCallback onChanged;
  const _PartnerActions({required this.order, required this.itemCount, required this.onChanged});
  @override
  ConsumerState<_PartnerActions> createState() => _PartnerActionsState();
}

class _PartnerActionsState extends ConsumerState<_PartnerActions> {
  Timer? timer;
  late final DastakRepository repo = ref.read(repositoryProvider);
  bool sharing = false;
  String? shareProblem;
  DateTime? lastSent;

  String get status => widget.order['status'];
  bool get active => ['assigned', 'picked_up', 'out_for_delivery'].contains(status);

  @override
  void dispose() {
    timer?.cancel();
    if (sharing) repo.rpc('partner_stop_location').catchError((_) => null);
    super.dispose();
  }

  Future<void> sendOnce() async {
    try {
      final here = await currentPosition();
      await ref.read(repositoryProvider).rpc('partner_update_location', {
        'p_order_id': widget.order['id'],
        'p_lat': double.parse(here.latitude.toStringAsFixed(6)),
        'p_lng': double.parse(here.longitude.toStringAsFixed(6)),
        'p_accuracy': null
      });
      if (mounted) setState(() {
        lastSent = DateTime.now();
        shareProblem = null;
      });
    } catch (e) {
      if (mounted) setState(() => shareProblem = errorText(e));
    }
  }

  Future<void> toggleSharing(bool on) async {
    timer?.cancel();
    setState(() => sharing = on);
    if (on) {
      await sendOnce();
      timer = Timer.periodic(const Duration(seconds: 20), (_) => sendOnce());
    } else {
      await ref.read(repositoryProvider).rpc('partner_stop_location').catchError((_) => null);
    }
  }

  Future<void> advance(String next) async {
    await ref.read(repositoryProvider).rpc('partner_set_order_status', {'p_order_id': widget.order['id'], 'p_new': next});
    if (next == 'delivered') {
      timer?.cancel();
      sharing = false;
    }
    widget.onChanged();
  }

  Future<void> navigate(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('No maps app available');
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final v = o['vendors'] as Map?;
    if (!active) return const SizedBox();
    return Panel([
      Text('Your delivery', style: context.text.titleMedium),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (v?['latitude'] != null)
          OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
              onPressed: () => perform(context, () => navigate(decimal(v!['latitude']), decimal(v['longitude']))),
              icon: const Icon(Icons.storefront, size: 18),
              label: const Text('Navigate to pickup')),
        OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
            onPressed: () => perform(context, () => navigate(decimal(o['destination_lat']), decimal(o['destination_lng']))),
            icon: const Icon(Icons.home, size: 18),
            label: const Text('Navigate to customer')),
      ]),
      const SizedBox(height: 8),
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: sharing,
          onChanged: (v) => toggleSharing(v),
          title: const Text('Share live location with customer'),
          subtitle: Text(shareProblem ??
              (sharing
                  ? 'Sharing every 20 s while this screen is open${lastSent == null ? '' : ' • last sent ${clock(lastSent!)}'}. Stops automatically after delivery.'
                  : 'Only shared during this delivery, and only while you keep it on.'))),
      const SizedBox(height: 8),
      if (status == 'assigned')
        ActionButton('I have picked up the order', () => advance('picked_up'), icon: Icons.inventory_2_outlined),
      if (status == 'picked_up')
        ActionButton('Start delivery (out for delivery)', () => advance('out_for_delivery'), icon: Icons.delivery_dining),
      if (status == 'out_for_delivery')
        FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: success, minimumSize: const Size.fromHeight(56)),
            icon: const Icon(Icons.task_alt),
            label: const Text('Mark delivery as completed', style: TextStyle(fontSize: 16)),
            onPressed: () async {
              final ok = await confirm(
                  context,
                  'Confirm delivery of ${o['order_number']}',
                  'Deliver to: ${o['destination_address']}\nItems: ${widget.itemCount} line(s)\n\n'
                      'Only confirm after handing the order to the customer. Your earning is recorded once, when you confirm.',
                  yes: 'Yes, delivered');
              if (ok && context.mounted) {
                await perform(context, () => advance('delivered'), success: 'Delivery completed. Great job!');
              }
            }),
    ]);
  }
}

class _Tracking extends ConsumerStatefulWidget {
  final String orderId;
  final Json order;
  const _Tracking({required this.orderId, required this.order});
  @override
  ConsumerState<_Tracking> createState() => _TrackingState();
}

class _TrackingState extends ConsumerState<_Tracking> {
  Json? location;
  Object? error;
  Timer? timer;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    poll();
    timer = Timer.periodic(const Duration(seconds: 15), (_) => poll());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> poll() async {
    try {
      final data = await ref.read(repositoryProvider).rpc('order_live_location', {'p_order_id': widget.orderId});
      if (mounted) {
        setState(() {
          location = data == null ? null : Map<String, dynamic>.from(data as Map);
          error = null;
          loaded = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        error = e;
        loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final v = o['vendors'] as Map?;
    final dest = LatLng(decimal(o['destination_lat']), decimal(o['destination_lng']));
    final store = v?['latitude'] == null ? null : LatLng(decimal(v!['latitude']), decimal(v['longitude']));
    final rider = location == null ? null : LatLng(decimal(location!['latitude']), decimal(location!['longitude']));
    final points = [dest, if (store != null) store, if (rider != null) rider];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Live tracking',
          trailing: IconButton(tooltip: 'Refresh location', onPressed: poll, icon: const Icon(Icons.refresh))),
      ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
              height: 220,
              child: FlutterMap(
                  key: ValueKey(points.length),
                  options: MapOptions(
                      initialCameraFit: points.length > 1
                          ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(40), maxZoom: 16)
                          : null,
                      initialCenter: dest,
                      initialZoom: 14),
                  children: [
                    osmTiles(),
                    MarkerLayer(markers: [
                      if (store != null) pinMarker(store, Icons.storefront, warning, label: 'Restaurant'),
                      pinMarker(dest, Icons.home_rounded, brandBlue, label: 'Delivery address'),
                      if (rider != null) pinMarker(rider, Icons.delivery_dining, success, label: 'Delivery partner'),
                    ]),
                    osmAttribution()
                  ]))),
      const SizedBox(height: 6),
      Text(
          !loaded
              ? 'Checking rider location…'
              : error != null
                  ? 'Live location unavailable: ${errorText(error!)}'
                  : rider == null
                      ? 'The delivery partner has not shared a live location yet. Status updates still arrive here.'
                      : 'Rider location updated ${ago(location!['updated_at'])} • about ${straightKm(rider, dest).toStringAsFixed(1)} km away in a straight line',
          style: TextStyle(fontSize: 12, color: context.muted)),
    ]);
  }
}

class _Breakdown extends ConsumerWidget {
  final String orderId;
  const _Breakdown(this.orderId);
  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<Json>(
      future: ref.read(repositoryProvider).rpcJson('order_breakdown', {'p_order': orderId}),
      builder: (c, s) {
        if (!s.hasData) return const SizedBox();
        final b = s.data!;
        String m(String k) => b[k] == null ? '—' : money(integer(b[k]));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle('Settlement breakdown'),
          Panel([
            InfoRow('Customer total', m('total_paise')),
            InfoRow('Items subtotal', m('items_subtotal_paise')),
            InfoRow('Delivery fee', m('delivery_fee_paise')),
            InfoRow('Platform commission', '${m('platform_commission_paise')} (${b['commission_percent']}%)'),
            InfoRow('Restaurant payable', m('restaurant_payable_paise')),
            InfoRow('Partner earning', '${m('partner_earning_paise')}${b['partner_earning_final'] == true ? '' : ' (estimate until delivered)'}'),
            if (b['partner_earning_final'] == true) ...[
              InfoRow('Paid to partner', m('partner_paid_paise')),
              InfoRow('Remaining payable', m('partner_remaining_paise')),
              InfoRow('Payout status', b['payout_status'] == null ? 'Not in a payout yet' : statusLabel(b['payout_status'])),
            ]
          ])
        ]);
      });
}

class _RateOrder extends ConsumerStatefulWidget {
  final String orderId;
  const _RateOrder(this.orderId);
  @override
  ConsumerState<_RateOrder> createState() => _RateOrderState();
}

class _RateOrderState extends ConsumerState<_RateOrder> {
  int vendorRating = 0, partnerRating = 0;
  final vendorComment = TextEditingController(), partnerComment = TextEditingController();
  Json? existing;
  bool editing = false, loaded = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final j = await ref.read(repositoryProvider).rpcJson('my_order_reviews', {'p_order_id': widget.orderId});
      if (!mounted) return;
      setState(() {
        existing = j;
        vendorRating = integer(j['vendor']?['rating'] ?? 0);
        partnerRating = integer(j['partner']?['rating'] ?? 0);
        vendorComment.text = j['vendor']?['comment'] ?? '';
        partnerComment.text = j['partner']?['comment'] ?? '';
        editing = j['vendor'] == null && j['partner'] == null;
        loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => loaded = true);
    }
  }

  @override
  void dispose() {
    vendorComment.dispose();
    partnerComment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded || existing == null) return const SizedBox();
    final hasPartner = existing!['has_partner'] == true;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Rate this order'),
      Panel([
        if (!editing) ...[
          if (existing!['vendor'] != null) Text('Restaurant: ${'★' * vendorRating}  ${vendorComment.text}'),
          if (existing!['partner'] != null) Text('Delivery partner: ${'★' * partnerRating}  ${partnerComment.text}'),
          if ((existing!['vendor']?['vendor_reply'] ?? '').toString().isNotEmpty)
            Text('Restaurant replied: ${existing!['vendor']['vendor_reply']}',
                style: const TextStyle(fontStyle: FontStyle.italic)),
          TextButton(onPressed: () => setState(() => editing = true), child: const Text('Edit my review (within 7 days)')),
        ] else ...[
          const Text('Restaurant', style: TextStyle(fontWeight: FontWeight.w700)),
          StarInput(vendorRating, (v) => setState(() => vendorRating = v)),
          TextField(
              controller: vendorComment,
              maxLength: 500,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'How was the food? (optional)')),
          if (hasPartner) ...[
            const SizedBox(height: 8),
            const Text('Delivery partner', style: TextStyle(fontWeight: FontWeight.w700)),
            StarInput(partnerRating, (v) => setState(() => partnerRating = v)),
            TextField(
                controller: partnerComment,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(hintText: 'How was the delivery? (optional)')),
          ],
          Text('Your first name initial is shown with restaurant reviews. Links are not allowed.',
              style: TextStyle(fontSize: 12, color: context.muted)),
          const SizedBox(height: 8),
          ActionButton('Submit rating', () async {
            if (vendorRating == 0 && partnerRating == 0) throw StateError('Tap the stars to rate');
            await ref.read(repositoryProvider).rpc('submit_order_review', {
              'p_order_id': widget.orderId,
              'p_vendor_rating': vendorRating == 0 ? null : vendorRating,
              'p_vendor_comment': vendorComment.text.trim().isEmpty ? null : vendorComment.text.trim(),
              'p_partner_rating': partnerRating == 0 || !hasPartner ? null : partnerRating,
              'p_partner_comment': partnerComment.text.trim().isEmpty ? null : partnerComment.text.trim(),
            });
            if (context.mounted) toast(context, 'Thanks for your rating!');
            await load();
          }, icon: Icons.star),
        ]
      ])
    ]);
  }
}

/// Kept for screens that still prompt for a single line of text.
Future<String?> prompt(BuildContext context, String title) => askText(context, title);
