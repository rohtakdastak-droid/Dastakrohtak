import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../core/editor.dart';

class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});
  @override
  ConsumerState<AdminSettingsScreen> createState() =>
      _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends ConsumerState<AdminSettingsScreen> {
  late Future<List<dynamic>> future;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    final r = ref.read(repositoryProvider);
    future = Future.wait([
      r.client.from('payment_settings').select().eq('id', true).single(),
      r.rows('delivery_rate_rules', sort: 'min_km', ascending: true),
      r.client.from('delivery_overflow_rule').select().eq('id', true).single(),
      r.rows('app_settings', sort: 'key')
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    return PageFrame('Application settings',
        child: FutureBuilder<List<dynamic>>(
            future: future,
            builder: (c, s) {
              if (s.hasError) return Failure(s.error!, () => setState(load));
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final payment = s.data![0] as Json;
              final rates = List<Json>.from(s.data![1]);
              final overflow = s.data![2] as Json;
              final settings = List<Json>.from(s.data![3]);
              return ListView(padding: const EdgeInsets.all(20), children: [
                Text('Payment instructions',
                    style: Theme.of(context).textTheme.titleLarge),
                Text(payment['upi_vpa'] ?? 'UPI not configured'),
                const Text(
                    'Manual verification only. COD and gateway payments are unavailable.'),
                ActionButton('Edit UPI settings', () async {
                  await editRecord(context,
                      title: 'UPI settings',
                      initial: payment,
                      fields: const [
                        EditField('upi_vpa', 'UPI ID'),
                        EditField('payee_name', 'Payee name'),
                        EditField('instructions', 'Instructions',
                            type: 'multiline', optional: true)
                      ], save: (d) async {
                    if (!RegExp(r'^[^\s@]+@[^\s@]+$').hasMatch(d['upi_vpa'])) {
                      throw StateError('Enter a valid UPI ID');
                    }
                    await repo.client
                        .from('payment_settings')
                        .update(d)
                        .eq('id', true);
                  });
                  if (mounted) setState(load);
                }),
                ActionButton('Upload payment QR', () async {
                  final file = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 1200,
                      imageQuality: 90);
                  if (file == null) return;
                  final path = await repo.upload(
                      'payment-qr', 'qr', await file.readAsBytes());
                  await repo.client
                      .from('payment_settings')
                      .update({'qr_image_path': path}).eq('id', true);
                  if (mounted) setState(load);
                }),
                const SizedBox(height: 24),
                Text('Delivery rate bands',
                    style: Theme.of(context).textTheme.titleLarge),
                for (final rate in rates)
                  ListTile(
                      title: Text('${rate['min_km']}–${rate['max_km']} km'),
                      subtitle: Text(money(integer(rate['fee_paise']))),
                      trailing: IconButton(
                          tooltip: 'Edit rate',
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            await editRecord(context,
                                title: 'Delivery band',
                                initial: rate,
                                fields: const [
                                  EditField('min_km', 'Minimum km (exclusive)',
                                      type: 'decimal'),
                                  EditField('max_km', 'Maximum km (inclusive)',
                                      type: 'decimal'),
                                  EditField('fee_paise', 'Fee (paise)',
                                      type: 'int')
                                ], save: (d) async {
                              final next = [
                                for (final r in rates)
                                  if (r['id'] == rate['id']) d else r
                              ];
                              await repo.rpc(
                                  'admin_replace_rate_table', {'p_rows': next});
                            });
                            if (mounted) setState(load);
                          })),
                ActionButton('Edit overflow rate', () async {
                  await editRecord(context,
                      title: 'Beyond final rate band',
                      initial: overflow,
                      fields: const [
                        EditField('ceiling_km', 'Ceiling km', type: 'decimal'),
                        EditField('base_fee_paise', 'Base fee (paise)',
                            type: 'int'),
                        EditField(
                            'per_km_paise', 'Additional fee per km (paise)',
                            type: 'int')
                      ], save: (d) async {
                    if (decimal(d['ceiling_km']) !=
                        decimal(rates.last['max_km'])) {
                      throw StateError('Ceiling must match the final band');
                    }
                    await repo.client
                        .from('delivery_overflow_rule')
                        .update(d)
                        .eq('id', true);
                  });
                  if (mounted) setState(load);
                }),
                const SizedBox(height: 24),
                for (final setting in settings.where((j) => [
                      'tax_percent',
                      'cancellation_window_minutes'
                    ].contains(j['key'])))
                  ListTile(
                      title: Text(human(setting['key'])),
                      subtitle: Text('${setting['value']}'),
                      trailing: IconButton(
                          tooltip: 'Edit setting',
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            await editRecord(context,
                                title: human(setting['key']),
                                initial: {
                                  'value': setting['value']
                                },
                                fields: const [
                                  EditField('value', 'Value', type: 'int')
                                ], save: (d) async {
                              if (setting['key'] == 'tax_percent' &&
                                  d['value'] > 100) {
                                throw StateError(
                                    'Tax must be between 0 and 100');
                              }
                              await repo.save('app_settings',
                                  {'value': d['value'], 'updated_by': repo.uid},
                                  id: setting['key'], key: 'key');
                            });
                            if (mounted) setState(load);
                          })),
              ]);
            }));
  }
}
