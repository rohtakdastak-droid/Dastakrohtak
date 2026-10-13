import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../core/editor.dart';
import '../vendor/vendor_screen.dart';
import '../orders/orders_screen.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  static const _navItems = [
    (Icons.storefront_outlined, 'Restaurants', '/admin/vendors'),
    (Icons.receipt_long_outlined, 'Orders', '/orders'),
    (Icons.payments_outlined, 'Payments', '/admin/payments'),
    (Icons.pedal_bike_outlined, 'Partners', '/admin/partners'),
    (Icons.settings_outlined, 'Settings', '/admin/settings'),
    (Icons.history_outlined, 'Audit log', '/admin/audit'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) => RemoteList(
      title: 'Operations',
      load: (p) async => p == 0
          ? [
              Map<String, dynamic>.from(await ref
                  .read(repositoryProvider)
                  .rpc('mobile_admin_metrics'))
            ]
          : [],
      header: [
        GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1,
            children: [
              for (final e in _navItems)
                Material(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => context.push(e.$3),
                        child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(e.$1,
                                      size: 26, color: const Color(0xFFEA580C)),
                                  const SizedBox(height: 6),
                                  Text(e.$2,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600))
                                ]))))
            ]),
        const SizedBox(height: 20),
        const Text("Today's live metrics",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
      ],
      item: (j, reload) {
        final entries = j.entries.toList();
        return Column(children: [
          for (final entry in entries)
            Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                    leading: Icon(_iconFor(entry.key),
                        color: const Color(0xFFEA580C)),
                    title: Text(human(entry.key)),
                    trailing: Text(
                        entry.key.endsWith('paise')
                            ? money(integer(entry.value))
                            : '${entry.value}',
                        style: Theme.of(context).textTheme.titleLarge)))
        ]);
      });

  static IconData _iconFor(String key) {
    if (key.contains('paise') || key.contains('revenue')) {
      return Icons.payments_outlined;
    }
    if (key.contains('delivered')) return Icons.check_circle_outlined;
    if (key.contains('cancel')) return Icons.cancel_outlined;
    if (key.contains('deliver')) return Icons.pedal_bike_outlined;
    if (key.contains('vendor') || key.contains('store')) {
      return Icons.storefront_outlined;
    }
    if (key.contains('prepar')) return Icons.restaurant_outlined;
    return Icons.receipt_long_outlined;
  }
}

class AdminVendorsScreen extends ConsumerStatefulWidget {
  const AdminVendorsScreen({super.key});
  @override
  ConsumerState<AdminVendorsScreen> createState() => _AdminVendorsScreenState();
}

class _AdminVendorsScreenState extends ConsumerState<AdminVendorsScreen> {
  int generation = 0;
  Future<void> edit([Json? row]) async {
    await editRecord(context,
        title: 'Store management',
        initial: row ??
            {
              'is_active': true,
              'min_order_paise': 0,
              'prep_time_minutes': 20,
              'service_radius_km': 7,
              'sort_priority': 100
            },
        fields: const [
          EditField('name', 'Store name'),
          EditField('category', 'Category',
              choices: ['food', 'groceries', 'medicine', 'accessories']),
          ...storeFields,
          EditField('is_featured', 'Featured', type: 'bool'),
          EditField('sort_priority', 'Display priority (lower first)',
              type: 'int')
        ], save: (d) async {
      if (!validCoordinates(d['latitude'], d['longitude']) ||
          d['service_radius_km'] <= 0) {
        throw StateError('Enter valid location and radius');
      }
      await ref.read(repositoryProvider).save('vendors', d, id: row?['id']);
    });
    if (mounted) setState(() => generation++);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    return RemoteList(
        key: ValueKey(generation),
        title: 'Stores',
        load: (p) => repo.rows('vendors',
            sort: 'sort_priority', ascending: true, page: p),
        header: [ActionButton('Add store', () => edit())],
        item: (j, reload) => Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(j['name'],
                          style: Theme.of(context).textTheme.titleLarge),
                      Text(
                          '${j['category']} · ${j['is_active'] ? 'Active' : 'Disabled'}'),
                      Wrap(spacing: 8, children: [
                        TextButton(
                            onPressed: () => edit(j),
                            child: const Text('Edit')),
                        TextButton(
                            onPressed: () =>
                                context.push('/vendor/store/${j['id']}/menu'),
                            child: const Text('Products')),
                        ActionButton('Add existing member', () async {
                          final uid = await prompt(
                              context, 'User ID of the registered vendor');
                          if (uid == null) return;
                          await repo.rpc('admin_add_vendor_member', {
                            'p_user_id': uid,
                            'p_vendor_id': j['id'],
                            'p_role': 'manager'
                          });
                          if (context.mounted) {
                            toast(context, 'Vendor member assigned');
                          }
                        })
                      ])
                    ]))));
  }
}

class AdminPaymentsScreen extends ConsumerWidget {
  const AdminPaymentsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    return RemoteList(
        title: 'Payment review',
        watch: 'orders',
        load: (p) => repo.rows('payments', page: p),
        item: (j, reload) => Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${money(integer(j['amount_paise']))} • ${j['status']}',
                          style: Theme.of(context).textTheme.titleLarge),
                      SelectableText(
                          'UPI reference: ${j['upi_reference'] ?? '—'}'),
                      TextButton(
                          onPressed: () =>
                              context.push('/orders/${j['order_id']}'),
                          child: const Text('View order')),
                      if (j['status'] == 'submitted') ...[
                        const Text(
                            'Verify the credit in the merchant bank account before approving.'),
                        Wrap(spacing: 8, children: [
                          ActionButton('Approve', () async {
                            final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                        title: const Text('Payment received?'),
                                        content: Text(
                                            'Confirm ${money(integer(j['amount_paise']))} was received with reference ${j['upi_reference']}.'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('Back')),
                                          FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text(
                                                  'Verified in bank'))
                                        ]));
                            if (confirmed != true) return;
                            await repo.rpc('verify_payment', {
                              'p_payment_id': j['id'],
                              'p_approved': true,
                              'p_reason': null
                            });
                            reload();
                          }),
                          ActionButton('Reject', () async {
                            final reason =
                                await prompt(context, 'Reason for rejection');
                            if (reason == null) return;
                            await repo.rpc('verify_payment', {
                              'p_payment_id': j['id'],
                              'p_approved': false,
                              'p_reason': reason
                            });
                            reload();
                          })
                        ])
                      ]
                    ]))));
  }
}

class AdminPartnersScreen extends ConsumerStatefulWidget {
  const AdminPartnersScreen({super.key});
  @override
  ConsumerState<AdminPartnersScreen> createState() =>
      _AdminPartnersScreenState();
}

class _AdminPartnersScreenState extends ConsumerState<AdminPartnersScreen> {
  int generation = 0;
  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    return RemoteList(
        key: ValueKey(generation),
        title: 'Delivery partners',
        load: (p) =>
            repo.rows('profiles', filters: {'role': 'delivery'}, page: p),
        header: [
          ActionButton('Enroll existing user', () async {
            final uid = await prompt(context, 'Registered user ID');
            if (uid == null) return;
            await repo.rpc('admin_assign_delivery_role', {'p_user_id': uid});
            if (mounted) setState(() => generation++);
          })
        ],
        item: (j, reload) {
          final status = (j['status'] ?? '').toString();
          Color statusColor;
          switch (status) {
            case 'active':
              statusColor = const Color(0xFF059669);
              break;
            case 'suspended':
              statusColor = const Color(0xFFD97706);
              break;
            case 'rejected':
              statusColor = const Color(0xFFDC2626);
              break;
            default:
              statusColor = const Color(0xFF6B7280);
          }
          return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(j['display_name'] ?? 'Partner',
                                  style:
                                      Theme.of(context).textTheme.titleLarge)),
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(999)),
                              child: Text(human(status),
                                  style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12)))
                        ]),
                        const SizedBox(height: 14),
                        // Status actions as a clean vertical stack
                        if (status != 'active')
                          SizedBox(
                              width: double.infinity,
                              child: ActionButton(
                                  status == 'suspended' || status == 'rejected'
                                      ? 'Approve / reactivate'
                                      : 'Approve', () async {
                                await repo.rpc('admin_set_partner_status', {
                                  'p_user_id': j['id'],
                                  'p_status': 'active'
                                });
                                reload();
                              }, icon: Icons.check_circle_outline)),
                        const SizedBox(height: 8),
                        if (status != 'suspended' && status != 'rejected')
                          Row(children: [
                            Expanded(
                                child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFFD97706)),
                                    onPressed: () async {
                                      await repo.rpc(
                                          'admin_set_partner_status', {
                                        'p_user_id': j['id'],
                                        'p_status': 'suspended'
                                      });
                                      reload();
                                    },
                                    icon: const Icon(Icons.pause_circle_outline,
                                        size: 18),
                                    label: const Text('Suspend'))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFFDC2626)),
                                    onPressed: () async {
                                      await repo.rpc(
                                          'admin_set_partner_status', {
                                        'p_user_id': j['id'],
                                        'p_status': 'rejected'
                                      });
                                      reload();
                                    },
                                    icon: const Icon(Icons.block, size: 18),
                                    label: const Text('Reject')))
                          ]),
                        const SizedBox(height: 8),
                        Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                                onPressed: () => context
                                    .push('/admin/documents/${j['id']}'),
                                icon: const Icon(Icons.description_outlined,
                                    size: 16),
                                label: const Text('Review documents')))
                      ])));
        });
  }
}

class AdminDocumentsScreen extends ConsumerWidget {
  final String partner;
  const AdminDocumentsScreen(this.partner, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    return RemoteList(
        title: 'Document review',
        load: (p) => repo.rows('partner_documents',
            filters: {'partner_id': partner}, page: p),
        item: (j, reload) => Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(human(j['doc_type'])),
                      Text(
                          '•••• ${j['masked_reference'] ?? ''} • ${j['status']}'),
                      ActionButton('View private document', () async {
                        final url = await repo.client.storage
                            .from('partner-docs')
                            .createSignedUrl(j['file_path'], 60);
                        if (!await launchUrl(Uri.parse(url),
                            mode: LaunchMode.externalApplication)) {
                          throw StateError('Could not open document');
                        }
                      }),
                      if (j['status'] == 'pending')
                        Wrap(children: [
                          for (final approved in [true, false])
                            ActionButton(approved ? 'Approve' : 'Reject',
                                () async {
                              await repo.rpc('admin_review_document',
                                  {'p_id': j['id'], 'p_approved': approved});
                              reload();
                            })
                        ])
                    ]))));
  }
}

class AdminAuditScreen extends ConsumerWidget {
  const AdminAuditScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => RemoteList(
      title: 'Audit log',
      load: (p) =>
          ref.read(repositoryProvider).rows('admin_audit_logs', page: p),
      item: (j, reload) => ListTile(
          title: Text(human(j['action'])),
          subtitle: Text(
              '${j['entity']} · ${j['reason'] ?? ''}\n${DateTime.parse(j['created_at']).toLocal()}')));
}
