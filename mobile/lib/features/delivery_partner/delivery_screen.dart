import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../core/editor.dart';

class DeliveryScreen extends ConsumerStatefulWidget {
  const DeliveryScreen({super.key});
  @override
  ConsumerState<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends ConsumerState<DeliveryScreen> {
  int generation = 0;
  bool online = false;
  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    return RemoteList(
        key: ValueKey(generation),
        title: 'Delivery workspace',
        watch: 'delivery_assignments',
        load: (p) async {
          if (p > 0) return [];
          final profile = await repo.one('delivery_partner_profiles', repo.uid,
              key: 'user_id');
          online = profile['is_online'];
          final active = List<Json>.from(await repo.rpc('my_active_delivery'));
          final offers = online && profile['approved_at'] != null
              ? List<Json>.from(await repo.rpc('list_available_orders'))
              : <Json>[];
          return [
            {'kind': 'profile', ...profile},
            ...active.map((j) => {'kind': 'active', ...j}),
            ...offers.map((j) => {'kind': 'offer', ...j})
          ];
        },
        header: [
          Wrap(spacing: 8, children: [
            TextButton(
                onPressed: () => context.push('/delivery/earnings'),
                child: const Text('Earnings')),
            TextButton(
                onPressed: () => context.push('/delivery/profile'),
                child: const Text('Profile & documents')),
            TextButton(
                onPressed: () => context.push('/orders'),
                child: const Text('Delivery history'))
          ])
        ],
        item: (j, reload) {
          if (j['kind'] == 'profile') {
            return Column(children: [
              Text(
                  'Approval: ${j['approved_at'] == null ? 'Awaiting admin approval' : 'Approved'}'),
              SwitchListTile(
                  title: const Text('Available for deliveries'),
                  value: online,
                  onChanged: (value) async {
                    if (await perform(
                        context,
                        () => repo
                            .rpc('set_partner_online', {'p_online': value}))) {
                      if (mounted) setState(() => generation++);
                    }
                  })
            ]);
          }
          final active = j['kind'] == 'active';
          return Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${active ? 'ACTIVE' : 'AVAILABLE'} • ${j['order_number']}',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                            'Pickup: ${j['vendor_name']}\n${j['pickup_address']}'),
                        const SizedBox(height: 12),
                        Text('Deliver: ${j['destination_address']}'),
                        Text(
                            'Delivery earning: ${money(integer(j['delivery_fee_paise']))}'),
                        const SizedBox(height: 12),
                        if (active)
                          FilledButton(
                              onPressed: () =>
                                  context.push('/orders/${j['order_id']}'),
                              child: Text('Continue • ${human(j['status'])}'))
                        else
                          ActionButton('Accept delivery', () async {
                            await repo.rpc(
                                'accept_delivery', {'p_order_id': j['id']});
                            if (mounted) setState(() => generation++);
                          })
                      ])));
        });
  }
}

class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    return RemoteList(
        title: 'Delivery earnings',
        load: (p) => repo.rows('delivery_earnings',
            filters: {'partner_id': repo.uid}, page: p),
        header: [
          FutureBuilder<dynamic>(
              future: repo.rpc('my_earnings_summary'),
              builder: (c, s) {
                if (s.hasError) return Text(errorText(s.error!));
                if (!s.hasData) return const LinearProgressIndicator();
                final j = (s.data as List).first as Json;
                return Card(
                    child: Column(children: [
                  for (final pair in [
                    ('Today', 'today_paise'),
                    ('This week', 'week_paise'),
                    ('This month', 'month_paise'),
                    ('Pending settlement', 'pending_paise'),
                    ('Settled', 'settled_paise')
                  ])
                    ListTile(
                        title: Text(pair.$1),
                        trailing: Text(money(integer(j[pair.$2]))))
                ]));
              })
        ],
        item: (j, reload) => ListTile(
            title: Text(money(integer(j['net_paise']))),
            subtitle: Text(
                '${j['settled'] ? 'Settled' : 'Pending settlement'} • ${DateTime.parse(j['created_at']).toLocal()}'),
            onTap: () => context.push('/orders/${j['order_id']}')));
  }
}

class DeliveryProfileScreen extends ConsumerStatefulWidget {
  const DeliveryProfileScreen({super.key});
  @override
  ConsumerState<DeliveryProfileScreen> createState() =>
      _DeliveryProfileScreenState();
}

class _DeliveryProfileScreenState extends ConsumerState<DeliveryProfileScreen> {
  int generation = 0;
  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    return RemoteList(
        key: ValueKey(generation),
        title: 'Partner profile & documents',
        load: (p) => repo.rows('partner_documents',
            filters: {'partner_id': repo.uid}, page: p),
        header: [
          ActionButton('Edit vehicle details', () async {
            final j = await repo.one('delivery_partner_profiles', repo.uid,
                key: 'user_id');
            if (!context.mounted) return;
            await editRecord(context,
                title: 'Vehicle details',
                initial: j,
                fields: const [
                  EditField('vehicle_type', 'Vehicle type'),
                  EditField('vehicle_number', 'Registration number')
                ],
                save: (d) => repo.save('delivery_partner_profiles', d,
                    id: repo.uid, key: 'user_id'));
          }),
          ActionButton('Submit verification document', () async {
            await editRecord(context, title: 'Document details', fields: const [
              EditField('doc_type', 'Document type',
                  choices: ['driving_license', 'id_proof', 'vehicle_rc']),
              EditField('masked_reference', 'Last 4 characters only')
            ], save: (d) async {
              if ((d['masked_reference'] as String).length != 4) {
                throw StateError('Enter only the last four characters');
              }
              final file = await ImagePicker().pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 1600,
                  imageQuality: 85);
              if (file == null) {
                throw StateError('Choose a document photo to submit');
              }
              final path = await repo.upload(
                  'partner-docs', repo.uid, await file.readAsBytes());
              await repo.save('partner_documents', {
                ...d,
                'partner_id': repo.uid,
                'file_path': path,
                'status': 'pending'
              });
            });
            if (mounted) setState(() => generation++);
          }),
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'Documents are stored privately and reviewed by an administrator. Do not type your full identity number.')),
        ],
        item: (j, reload) => ListTile(
            title: Text(human(j['doc_type'])),
            subtitle:
                Text('•••• ${j['masked_reference'] ?? ''} · ${j['status']}')));
  }
}
