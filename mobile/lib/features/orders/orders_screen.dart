import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    return RemoteList(
        title: 'Orders',
        watch: 'orders',
        load: (p) => repo.rows('orders', page: p),
        item: (j, reload) => Card(
            child: ListTile(
                title: Text(j['order_number']),
                subtitle: Text(
                    '${human(j['status'])} · Payment ${human(j['payment_status'])}'),
                trailing: Text(money(integer(j['total_payable_paise']))),
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
  final utr = TextEditingController();
  @override
  void initState() {
    super.initState();
    reload();
    channel = ref.read(repositoryProvider).watch('orders', () {
      if (mounted) setState(reload);
    }, column: 'id', value: widget.id);
  }

  void reload() {
    final repo = ref.read(repositoryProvider);
    future = Future.wait([
      repo.one('orders', widget.id, select: '*,vendors(name,dispatch_address)'),
      repo.orderRows('order_items', widget.id, sort: 'id'),
      repo.orderRows('order_status_history', widget.id),
      repo.client.from('payment_settings').select().eq('id', true).single()
    ]);
  }

  @override
  void dispose() {
    utr.dispose();
    if (channel != null) {
      ref.read(repositoryProvider).client.removeChannel(channel!);
    }
    super.dispose();
  }

  Future<void> transition(String rpc, String next) async {
    final repo = ref.read(repositoryProvider);
    final params = <String, dynamic>{'p_order_id': widget.id, 'p_new': next};
    if (next == 'rejected') {
      final reason = await prompt(context, 'Reason for rejection');
      if (reason == null) return;
      params['p_reason'] = reason;
    }
    await repo.rpc(rpc, params);
    if (mounted) setState(reload);
  }

  @override
  Widget build(BuildContext context) => PageFrame('Order details',
      child: FutureBuilder<List<dynamic>>(
          future: future,
          builder: (ctx, s) {
            if (s.hasError) return Failure(s.error!, () => setState(reload));
            if (!s.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = s.data!;
            final o = Order(data[0]);
            final settings = data[3] as Json;
            final repo = ref.read(repositoryProvider);
            final account = ref.watch(accountProvider).valueOrNull;
            final own = o.data['customer_id'] == repo.uid;
            return RefreshIndicator(
                onRefresh: () async {
                  setState(reload);
                  await future;
                },
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Text(o.number,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  Chip(label: Text(human(o.status))),
                  Text('Payment: ${human(o.payment)}'),
                  const Divider(),
                  Text('From ${o.data['vendors']?['name'] ?? 'Store'}'),
                  Text(o.data['vendors']?['dispatch_address'] ?? ''),
                  const SizedBox(height: 16),
                  const Text('DELIVER TO'),
                  Text(o.data['destination_address']),
                  const SizedBox(height: 20),
                  for (final item in data[1] as List)
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            '${item['quantity']} × ${item['product_name']}'),
                        subtitle: Text((item['options'] as List)
                            .map((o) => o['label'])
                            .join(', ')),
                        trailing:
                            Text(money(integer(item['line_total_paise'])))),
                  for (final pair in [
                    ('Items', 'items_subtotal_paise'),
                    ('Delivery', 'delivery_fee_paise'),
                    ('Tax', 'tax_paise'),
                    ('Discount', 'discount_paise'),
                    ('Total', 'total_payable_paise')
                  ])
                    ListTile(
                        title: Text(pair.$1),
                        trailing: Text(money(integer(o.data[pair.$2])))),
                  if (own &&
                      o.status == 'pending_payment' &&
                      ['unpaid', 'rejected'].contains(o.payment)) ...[
                    const Divider(),
                    Text('Pay with UPI',
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(settings['instructions'] ??
                        'Pay the exact total and submit your 12-digit UPI reference.'),
                    if (settings['qr_image_path'] != null)
                      Photo(
                          repo.imageUrl(settings['qr_image_path'],
                              bucket: 'payment-qr'),
                          height: 220),
                    if (settings['upi_vpa'] != null) ...[
                      SelectableText(settings['upi_vpa']),
                      ActionButton('Open UPI app', () async {
                        final uri =
                            Uri(scheme: 'upi', host: 'pay', queryParameters: {
                          'pa': settings['upi_vpa'],
                          'pn': settings['payee_name'] ?? 'Dastak',
                          'am': (o.total / 100).toStringAsFixed(2),
                          'cu': 'INR',
                          'tn': o.number
                        });
                        if (!await launchUrl(uri,
                            mode: LaunchMode.externalApplication)) {
                          throw StateError(
                              'No UPI app available. Pay manually using the displayed UPI ID.');
                        }
                      })
                    ] else
                      const Text(
                          'UPI payment details are not configured. Contact support.'),
                    Field(utr, '12-digit UPI reference',
                        keyboard: TextInputType.number),
                    ActionButton('Submit for review', () async {
                      if (!RegExp(r'^\d{12}$').hasMatch(utr.text.trim())) {
                        throw StateError(
                            'Enter a valid 12-digit UPI reference');
                      }
                      await repo.rpc('submit_payment_proof', {
                        'p_order_id': widget.id,
                        'p_upi_reference': utr.text.trim(),
                        'p_proof_image_path': null
                      });
                      if (mounted) setState(reload);
                    }),
                    const Text(
                        'Submitting a reference does not confirm payment. Verification is required.')
                  ],
                  if (account?.role == 'vendor' || account?.role == 'admin')
                    for (final next in vendorTransitions(o.status))
                      ActionButton(human(next),
                          () => transition('vendor_set_order_status', next)),
                  if (account?.role == 'delivery' &&
                      deliveryTransition(o.status) != null)
                    ActionButton(
                        human(deliveryTransition(o.status)!),
                        () => transition('partner_set_order_status',
                            deliveryTransition(o.status)!)),
                  if (account?.role == 'admin' &&
                      [
                        'pending_payment',
                        'payment_review',
                        'vendor_confirmation',
                        'preparing',
                        'ready_for_pickup',
                        'assigned'
                      ].contains(o.status))
                    ActionButton('Cancel order', () async {
                      final reason =
                          await prompt(context, 'Cancellation reason');
                      if (reason == null) return;
                      await repo.rpc('admin_cancel_order',
                          {'p_order_id': widget.id, 'p_reason': reason});
                      if (mounted) setState(reload);
                    }),
                  const SizedBox(height: 24),
                  Text('Status history',
                      style: Theme.of(context).textTheme.titleLarge),
                  for (final h in data[2] as List)
                    ListTile(
                        leading: const Icon(Icons.check_circle_outline),
                        title: Text(human(h['new_status'])),
                        subtitle: Text(
                            '${h['reason'] ?? ''}\n${DateTime.parse(h['created_at']).toLocal()}')),
                  const Text(
                      'Updates reflect actual order status. Live GPS tracking is not enabled.'),
                ]));
          }));
}

Future<String?> prompt(BuildContext context, String title) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
              title: Text(title),
              content: TextField(
                  controller: controller, autofocus: true, maxLines: 3),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () {
                      if (controller.text.trim().isNotEmpty) {
                        Navigator.pop(ctx, controller.text.trim());
                      }
                    },
                    child: const Text('Continue'))
              ]));
  // Dialog route may still animate; dispose after its transition.
  Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
  return result;
}
