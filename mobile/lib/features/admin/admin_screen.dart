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
        Wrap(spacing: 8, children: [
          for (final e in [
            ('Stores', 'vendors'),
            ('Payments', 'payments'),
            ('Partners', 'partners'),
            ('Settings', 'settings'),
            ('Audit log', 'audit')
          ])
            OutlinedButton(
                onPressed: () => context.push('/admin/${e.$2}'),
                child: Text(e.$1)),
          OutlinedButton(
              onPressed: () => context.push('/orders'),
              child: const Text('Orders'))
        ])
      ],
      item: (j, reload) => Column(children: [
            for (final entry in j.entries)
              Card(
                  child: ListTile(
                      title: Text(human(entry.key)),
                      trailing: Text(
                          entry.key.endsWith('paise')
                              ? money(integer(entry.value))
                              : '${entry.value}',
                          style: Theme.of(context).textTheme.titleLarge)))
          ]));
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
        item: (j, reload) => Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(j['display_name'] ?? 'Partner',
                          style: Theme.of(context).textTheme.titleLarge),
                      Text(j['status']),
                      Wrap(spacing: 8, children: [
                        for (final status in [
                          'active',
                          'suspended',
                          'rejected'
                        ])
                          ActionButton(
                              status == 'active'
                                  ? 'Approve / reactivate'
                                  : human(status), () async {
                            await repo.rpc('admin_set_partner_status',
                                {'p_user_id': j['id'], 'p_status': status});
                            reload();
                          }),
                        TextButton(
                            onPressed: () =>
                                context.push('/admin/documents/${j['id']}'),
                            child: const Text('Review documents'))
                      ])
                    ]))));
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
