import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../core/editor.dart';

Widget _dStat(BuildContext context, String label, String value, IconData icon,
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
          // Personal stats
          final today = DateTime.now()
              .toUtc()
              .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0);
          final todayDeliveries = await repo.client
              .from('delivery_assignments')
              .select('id')
              .eq('partner_id', repo.uid)
              .eq('status', 'accepted')
              .gte('created_at', today.toIso8601String());
          final totalEarnings = await repo.client
              .from('delivery_earnings')
              .select('net_paise,created_at')
              .eq('partner_id', repo.uid);
          int todayEarn = 0, totalEarn = 0, totalDeliv = 0;
          for (final e in (totalEarnings as List)) {
            final paise = (e['net_paise'] ?? 0) as int;
            totalEarn += paise;
            totalDeliv++;
            final ts = DateTime.tryParse(e['created_at'] ?? '');
            if (ts != null && ts.isAfter(today)) todayEarn += paise;
          }
          return [
            {
              'kind': 'profile',
              ...profile,
              'stats': {
                'today_deliveries': (todayDeliveries as List).length,
                'total_deliveries': totalDeliv,
                'today_earn': todayEarn,
                'total_earn': totalEarn
              }
            },
            ...active.map((j) => {'kind': 'active', ...j}),
            ...offers.map((j) => {'kind': 'offer', ...j})
          ];
        },
        header: [
          Wrap(spacing: 8, children: [
            TextButton.icon(
                onPressed: () => context.push('/delivery/earnings'),
                icon: const Icon(Icons.account_balance_wallet_outlined,
                    size: 18),
                label: const Text('Earnings')),
            TextButton.icon(
                onPressed: () => context.push('/delivery/profile'),
                icon: const Icon(Icons.person_outline, size: 18),
                label: const Text('Profile')),
            TextButton.icon(
                onPressed: () => context.push('/orders'),
                icon: const Icon(Icons.history, size: 18),
                label: const Text('History'))
          ])
        ],
        item: (j, reload) {
          if (j['kind'] == 'profile') {
            final s = j['stats'] as Json;
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: j['approved_at'] == null
                              ? const Color(0xFFFEF3C7)
                              : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        Icon(
                            j['approved_at'] == null
                                ? Icons.pending_outlined
                                : Icons.verified_outlined,
                            color: j['approved_at'] == null
                                ? const Color(0xFFD97706)
                                : const Color(0xFF059669)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(
                                j['approved_at'] == null
                                    ? 'Awaiting admin approval'
                                    : 'Approved partner',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)))
                      ])),
                  const SizedBox(height: 14),
                  Row(children: const [
                    Icon(Icons.circle, size: 8, color: Color(0xFF059669)),
                    SizedBox(width: 6),
                    Text('LIVE',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF059669))),
                    SizedBox(width: 10),
                    Text('Your dashboard',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700))
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
                        _dStat(context, 'Deliveries today',
                            '${s['today_deliveries']}', Icons.pedal_bike_outlined,
                            color: const Color(0xFFEA580C)),
                        _dStat(context, 'Earnings today',
                            money(integer(s['today_earn'])),
                            Icons.payments_outlined,
                            color: const Color(0xFF059669)),
                        _dStat(context, 'Total deliveries',
                            '${s['total_deliveries']}',
                            Icons.check_circle_outlined,
                            color: const Color(0xFF2563EB)),
                        _dStat(
                            context,
                            'Total earnings',
                            money(integer(s['total_earn'])),
                            Icons.account_balance_wallet_outlined,
                            color: const Color(0xFF7C3AED))
                      ]),
                  const SizedBox(height: 14),
                  Card(
                      child: SwitchListTile(
                          title: const Text('Available for deliveries'),
                          subtitle: Text(online
                              ? 'You are receiving offers'
                              : 'Turn on to receive offers'),
                          value: online,
                          onChanged: (value) async {
                            if (await perform(
                                context,
                                () => repo.rpc('set_partner_online',
                                    {'p_online': value}))) {
                              if (mounted) setState(() => generation++);
                            }
                          })),
                  const SizedBox(height: 10)
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
