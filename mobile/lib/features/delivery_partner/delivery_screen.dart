import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../customer/profile_menu.dart';
import '../settings/profile_screen.dart' show openPolicy, privacyUrl;

const vehicleTypes = {
  'bicycle': 'Bicycle',
  'e_bike': 'E-bike',
  'scooter': 'Scooter',
  'motorcycle': 'Motorcycle',
  'car': 'Car'
};

class DeliveryScreen extends ConsumerStatefulWidget {
  const DeliveryScreen({super.key});
  @override
  ConsumerState<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends ConsumerState<DeliveryScreen> {
  int generation = 0;
  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    return RemoteList(
        key: ValueKey(generation),
        title: 'Partner dashboard',
        watch: 'delivery_assignments',
        customerNav: false,
        showUpdated: true,
        actions: [
          const ThemeToggle(),
          IconButton(
              tooltip: 'Notifications',
              onPressed: () => context.push('/notifications'),
              icon: const Icon(Icons.notifications_outlined)),
        ],
        load: (p) async {
          if (p > 0) return [];
          final dash = await repo.rpcJson('my_partner_dashboard');
          if (dash['verification_status'] == 'none') return [{'kind': 'none'}];
          final active = await repo.rpcList('my_active_delivery');
          final offers = dash['can_accept'] == true && dash['is_online'] == true && active.isEmpty
              ? await repo.rpcList('list_available_orders')
              : <Json>[];
          return [
            {'kind': 'dash', ...dash},
            ...active.map((j) => {'kind': 'active', ...j}),
            if (dash['can_accept'] == true && dash['is_online'] == true && active.isEmpty)
              {'kind': 'offers_title', 'count': offers.length},
            ...offers.map((j) => {'kind': 'offer', ...j}),
          ];
        },
        item: (j, reload) => switch (j['kind']) {
              'none' => Column(children: [
                  const Empty('You have not started a partner application yet.', icon: Icons.pedal_bike),
                  FilledButton(onPressed: () => context.push('/partner/apply'), child: const Text('Start application'))
                ]),
              'dash' => _Dashboard(j, () => setState(() => generation++)),
              'offers_title' => SectionTitle('Available orders (${j['count']})'),
              'active' => _ActiveCard(j),
              _ => _OfferCard(j, () => setState(() => generation++)),
            });
  }
}

class _Dashboard extends ConsumerWidget {
  final Json d;
  final VoidCallback refresh;
  const _Dashboard(this.d, this.refresh);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    final status = '${d['verification_status']}';
    final canAccept = d['can_accept'] == true;
    final online = d['is_online'] == true;
    String m(String k) => money(integer(d[k] ?? 0));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('Hi ${d['legal_name'] ?? 'partner'}', style: context.text.titleLarge)),
        StatusChip(status),
      ]),
      const SizedBox(height: 8),
      if (d['block_reason'] != null)
        Notice('${d['block_reason']}',
            icon: Icons.info_outline,
            color: statusColor(status),
            action: status == 'draft' || status == 'action_required' || status == 'rejected'
                ? TextButton(onPressed: () => context.push('/partner/apply'), child: const Text('Open'))
                : null),
      Card(
          child: SwitchListTile(
              secondary: Icon(online ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                  color: online ? success : context.muted),
              title: Text(online ? 'You are online' : 'You are offline',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(canAccept
                  ? (online ? 'You will see new delivery offers below.' : 'Go online to receive delivery offers.')
                  : 'Available after your account is approved.'),
              value: online,
              onChanged: canAccept || online
                  ? (v) async {
                      if (await perform(context, () => repo.rpc('set_partner_online', {'p_online': v}))) refresh();
                    }
                  : null)),
      const SectionTitle('Deliveries'),
      StatGrid([
        StatTile('Completed today', '${d['deliveries_today']}', Icons.today, color: brandBlue),
        StatTile('Last 7 days', '${d['deliveries_week']}', Icons.date_range, color: const Color(0xFF2563EB)),
        StatTile('This month', '${d['deliveries_month']}', Icons.calendar_month, color: const Color(0xFF7C3AED)),
        StatTile('All time', '${d['deliveries_total']}', Icons.check_circle_outline, color: success),
        StatTile('Active now', '${d['active_orders']}', Icons.delivery_dining, color: warning),
        StatTile('Accepted (all time)', '${d['accepted_total']}', Icons.assignment_turned_in_outlined),
        StatTile('Cancelled / failed', '${d['cancelled_or_failed']}', Icons.cancel_outlined, color: danger),
        StatTile('Rating', d['rating_avg'] == null ? 'No ratings' : '${d['rating_avg']} ★ (${d['rating_count']})',
            Icons.star_outline, color: const Color(0xFFF59E0B)),
      ]),
      const SectionTitle('Earnings'),
      StatGrid([
        StatTile('Earned today', m('earned_today_paise'), Icons.payments_outlined, color: success,
            onTap: () => context.push('/delivery/earnings')),
        StatTile('Total earned', m('earned_total_paise'), Icons.account_balance_wallet_outlined,
            color: const Color(0xFF7C3AED), onTap: () => context.push('/delivery/earnings')),
        StatTile('Paid to you', m('paid_paise'), Icons.verified_outlined, color: brandBlue,
            onTap: () => context.push('/delivery/earnings')),
        StatTile('Pending payout', m('pending_payout_paise'), Icons.hourglass_bottom, color: warning,
            hint: integer(d['in_payout_paise'] ?? 0) > 0 ? '${m('in_payout_paise')} being processed' : null,
            onTap: () => context.push('/delivery/earnings')),
      ]),
      Text('Earnings are your delivery share only — not the customer order value or restaurant sales.',
          style: TextStyle(fontSize: 11, color: context.muted)),
      const SectionTitle('Manage'),
      _Nav([
        (Icons.history, 'Delivery history', () => context.push('/orders')),
        (Icons.account_balance_wallet_outlined, 'Earnings & payments', () => context.push('/delivery/earnings')),
        (Icons.qr_code_2, 'Payout QR (${statusLabel('${d['qr_status']}')})', () => context.push('/delivery/qr')),
        (Icons.badge_outlined, 'Personal info, vehicle & documents', () => context.push('/partner/apply')),
        (Icons.notifications_outlined, 'Notifications', () => context.push('/notifications')),
        (Icons.support_agent, 'Support', () => context.push('/support')),
        (Icons.settings_outlined, 'Settings', () => context.push('/profile')),
        (Icons.logout, 'Log out', () async {
          if (await confirm(context, 'Log out?', 'You will go offline and need to sign in again.', yes: 'Log out')) {
            try {
              await repo.rpc('set_partner_online', {'p_online': false});
            } catch (_) {}
            if (context.mounted) await signOut(context, ref);
          }
        }),
      ]),
    ]);
  }
}

class _Nav extends StatelessWidget {
  final List<(IconData, String, VoidCallback)> items;
  const _Nav(this.items);
  @override
  Widget build(BuildContext context) => Card(
      child: Column(children: [
        for (final (i, e) in items.indexed) ...[
          if (i > 0) const Divider(height: 1),
          ListTile(
              leading: Icon(e.$1, color: e.$2 == 'Log out' ? danger : context.colors.primary),
              title: Text(e.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.chevron_right),
              onTap: e.$3)
        ]
      ]));
}

class _ActiveCard extends StatelessWidget {
  final Json j;
  const _ActiveCard(this.j);
  @override
  Widget build(BuildContext context) => Card(
      color: context.tint,
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('ACTIVE DELIVERY • ${j['order_number']}', style: context.text.titleMedium)),
              StatusChip('${j['status']}')
            ]),
            const SizedBox(height: 8),
            InfoRow('Pickup', '${j['vendor_name']}\n${j['pickup_address']}'),
            InfoRow('Drop', j['destination_address']),
            InfoRow('Items', '${j['item_count']}'),
            if ((j['customer_note'] ?? '').toString().isNotEmpty) InfoRow('Note', j['customer_note']),
            const SizedBox(height: 8),
            FilledButton.icon(
                onPressed: () => context.push('/orders/${j['order_id']}'),
                icon: const Icon(Icons.navigation_outlined),
                label: const Text('Open active delivery'))
          ])));
}

class _OfferCard extends ConsumerWidget {
  final Json j;
  final VoidCallback refresh;
  const _OfferCard(this.j, this.refresh);
  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(j['order_number'], style: context.text.titleMedium)),
              Text('${decimal(j['delivery_distance_km']).toStringAsFixed(1)} km',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            InfoRow('Pickup', '${j['vendor_name']}\n${j['pickup_address']}'),
            InfoRow('Drop', j['destination_address']),
            InfoRow('Delivery fee', money(integer(j['delivery_fee_paise']))),
            Text('Your final earning follows the current partner earning rule.',
                style: TextStyle(fontSize: 11, color: context.muted)),
            const SizedBox(height: 8),
            ActionButton('Accept delivery', () async {
              await ref.read(repositoryProvider).rpc('accept_delivery', {'p_order_id': j['id']});
              if (context.mounted) {
                toast(context, 'Order ${j['order_number']} is yours. Head to pickup.');
                context.push('/orders/${j['id']}');
              }
              refresh();
            }, icon: Icons.check),
          ])));
}

class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key});
  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  bool payouts = false;
  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    return RemoteList(
        key: ValueKey(payouts),
        title: 'Earnings & payments',
        customerNav: false,
        watch: payouts ? 'partner_payouts' : 'delivery_earnings',
        emptyText: payouts ? 'No payouts recorded yet.' : 'No completed deliveries yet.',
        load: (p) => repo.rows(payouts ? 'partner_payouts' : 'delivery_earnings',
            filters: {'partner_id': repo.uid}, page: p),
        header: [
          FutureBuilder<Json>(
              future: repo.rpcJson('my_partner_dashboard'),
              builder: (c, s) {
                if (s.hasError) return Text(errorText(s.error!));
                if (!s.hasData) return const LinearProgressIndicator();
                final d = s.data!;
                String m(String k) => money(integer(d[k] ?? 0));
                return StatGrid([
                  StatTile('Total earned', m('earned_total_paise'), Icons.account_balance_wallet_outlined),
                  StatTile('Paid to you', m('paid_paise'), Icons.verified_outlined, color: success),
                  StatTile('Being processed', m('in_payout_paise'), Icons.sync, color: brandBlue),
                  StatTile('Not yet paid', m('pending_payout_paise'), Icons.hourglass_bottom, color: warning),
                ]);
              }),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Deliveries'), icon: Icon(Icons.receipt_long)),
                ButtonSegment(value: true, label: Text('Payouts'), icon: Icon(Icons.payments)),
              ],
              selected: {payouts},
              onSelectionChanged: (v) => setState(() => payouts = v.first)),
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                  onPressed: () => perform(context, () async {
                        final rows = await repo.rows(payouts ? 'partner_payouts' : 'delivery_earnings',
                            filters: {'partner_id': repo.uid});
                        final text = payouts
                            ? csv([
                                ['created', 'amount_inr', 'status', 'method', 'reference', 'paid_at'],
                                for (final r in rows)
                                  [r['created_at'], integer(r['amount_paise']) / 100, r['status'], r['method'], r['reference'], r['paid_at']]
                              ])
                            : csv([
                                ['date', 'order_id', 'earning_inr', 'settled'],
                                for (final r in rows) [r['created_at'], r['order_id'], integer(r['net_paise']) / 100, r['settled']]
                              ]);
                        if (context.mounted) await copyText(context, text, 'Statement (CSV, latest 30 rows)');
                      }),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy statement'))),
        ],
        item: (j, reload) => payouts
            ? Card(
                child: ListTile(
                    title: Row(children: [
                      Expanded(child: Text(money(integer(j['amount_paise'])), style: const TextStyle(fontWeight: FontWeight.w800))),
                      StatusChip(j['status'])
                    ]),
                    subtitle: Text([
                      '${statusLabel(j['method'])} • created ${stamp(j['created_at'])}',
                      if (j['reference'] != null) 'Ref ${j['reference']}',
                      if (j['paid_at'] != null) 'Paid ${stamp(j['paid_at'])}',
                      if (j['failed_reason'] != null) 'Failed: ${j['failed_reason']}',
                    ].join('\n'))))
            : Card(
                child: ListTile(
                    title: Text(money(integer(j['net_paise'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                        '${j['settled'] == true ? 'Paid' : (j['payout_id'] != null ? 'In a payout' : 'Not yet paid')} • ${stamp(j['created_at'])}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/orders/${j['order_id']}'))));
  }
}

class PartnerQrScreen extends ConsumerStatefulWidget {
  const PartnerQrScreen({super.key});
  @override
  ConsumerState<PartnerQrScreen> createState() => _PartnerQrScreenState();
}

class _PartnerQrScreenState extends ConsumerState<PartnerQrScreen> {
  late Future<Json> future;
  @override
  void initState() {
    super.initState();
    future = ref.read(repositoryProvider).rpcJson('my_partner_application');
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    return PageFrame('Payout QR code',
        customerNav: false,
        child: FutureBuilder<Json>(
            future: future,
            builder: (c, s) {
              if (s.hasError) return Failure(s.error!, () => setState(() => future = repo.rpcJson('my_partner_application')));
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              final p = (s.data!['profile'] as Map?) ?? {};
              final status = '${p['qr_status'] ?? 'none'}';
              return ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  Expanded(child: Text('Status', style: context.text.titleMedium)),
                  StatusChip(status, label: status == 'none' ? 'Not submitted' : null)
                ]),
                if (p['qr_review_reason'] != null) Notice('${p['qr_review_reason']}', color: statusColor(status)),
                const SizedBox(height: 8),
                const Text(
                    'Upload the UPI QR code where you want to receive payouts. It is stored privately and only administrators can view it. '
                    'Uploading a QR does not send money — payouts are recorded separately with a transaction reference.'),
                const SizedBox(height: 16),
                if (p['qr_image_path'] != null)
                  FutureBuilder<String>(
                      future: repo.signedUrl('partner-docs', p['qr_image_path']),
                      builder: (c, u) => u.hasData
                          ? Center(child: SizedBox(width: 240, child: Photo(u.data, height: 240, placeholder: Icons.qr_code_2)))
                          : const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()))),
                const SizedBox(height: 16),
                ActionButton(p['qr_image_path'] == null ? 'Upload payout QR' : 'Replace payout QR', () async {
                  final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1400, imageQuality: 90);
                  if (file == null) return;
                  final path = await repo.upload('partner-docs', repo.uid, await file.readAsBytes());
                  await repo.rpc('partner_submit_qr', {'p_path': path});
                  if (context.mounted) {
                    toast(context, 'QR submitted for review');
                    setState(() => future = repo.rpcJson('my_partner_application'));
                  }
                }, icon: Icons.qr_code_2),
              ]);
            }));
  }
}

class PartnerApplicationScreen extends ConsumerStatefulWidget {
  const PartnerApplicationScreen({super.key});
  @override
  ConsumerState<PartnerApplicationScreen> createState() => _PartnerApplicationScreenState();
}

class _PartnerApplicationScreenState extends ConsumerState<PartnerApplicationScreen> {
  final form = GlobalKey<FormState>();
  final c = <String, TextEditingController>{
    for (final k in [
      'legal_name', 'phone', 'email', 'residential_address', 'city', 'service_area', //
      'emergency_contact_name', 'emergency_contact_phone', 'vehicle_number', 'licence_last4', //
      'aadhaar_last4', 'payout_upi_vpa', 'bank_account_last4', 'bank_ifsc'
    ])
      k: TextEditingController()
  };
  String? vehicleType;
  bool terms = false, loaded = false;
  Json profile = {};
  List<Json> documents = [], events = [];
  Object? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    try {
      final j = await ref.read(repositoryProvider).rpcJson('my_partner_application');
      if (!mounted) return;
      final p = Map<String, dynamic>.from((j['profile'] as Map?) ?? {});
      final account = Map<String, dynamic>.from((j['account'] as Map?) ?? {});
      setState(() {
        profile = p;
        documents = List<Json>.from(((j['documents'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)));
        events = List<Json>.from(((j['events'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)));
        for (final e in c.entries) {
          e.value.text = '${p[e.key] ?? ''}';
        }
        if (c['legal_name']!.text.isEmpty) c['legal_name']!.text = '${account['display_name'] ?? ''}';
        if (c['phone']!.text.isEmpty) c['phone']!.text = '${account['phone'] ?? ''}';
        if (c['email']!.text.isEmpty) c['email']!.text = ref.read(repositoryProvider).client.auth.currentUser?.email ?? '';
        vehicleType = p['vehicle_type'];
        loaded = true;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() {
        error = e;
        loaded = true;
      });
    }
  }

  String get status => '${profile['verification_status'] ?? 'draft'}';
  bool get editable => ['draft', 'action_required', 'rejected'].contains(status);

  Json payload() => {
        for (final e in c.entries) e.key: e.value.text.trim(),
        'vehicle_type': vehicleType,
        'accept_terms': terms
      };

  Json? latestDoc(String type) => documents.where((d) => d['doc_type'] == type).firstOrNull;

  Future<void> uploadDoc(String type) async {
    final repo = ref.read(repositoryProvider);
    String? masked;
    if (type == 'aadhaar') masked = c['aadhaar_last4']!.text.trim();
    if (type == 'driving_license') masked = c['licence_last4']!.text.trim().toUpperCase();
    if ((type == 'aadhaar' || type == 'driving_license') && !RegExp(r'^[A-Za-z0-9]{4}$').hasMatch(masked ?? '')) {
      throw StateError('First enter the last 4 characters of this document in the form above');
    }
    // Save the draft first so the profile row exists for document uploads.
    if (editable) await repo.rpc('partner_save_application', {'p': payload(), 'p_submit': false});
    if (!mounted) return;
    final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (sheet) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Take a photo'),
                  onTap: () => Navigator.pop(sheet, ImageSource.camera)),
              ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choose from gallery'),
                  onTap: () => Navigator.pop(sheet, ImageSource.gallery)),
            ])));
    if (source == null) return;
    final file = await ImagePicker().pickImage(
        source: source,
        preferredCameraDevice: type == 'profile_photo' ? CameraDevice.front : CameraDevice.rear,
        maxWidth: 1800,
        imageQuality: 85);
    if (file == null) return;
    final path = await repo.upload('partner-docs', repo.uid, await file.readAsBytes());
    await repo.rpc('partner_submit_document',
        {'p_doc_type': type, 'p_path': path, 'p_masked': type == 'profile_photo' || type == 'vehicle_rc' ? null : masked});
    if (mounted) toast(context, 'Uploaded. It will be reviewed by an administrator.');
    await load();
  }

  Future<void> save(bool submit) async {
    if (submit) {
      if (!form.currentState!.validate()) throw StateError('Please fix the highlighted fields');
      if (vehicleType == null) throw StateError('Choose your vehicle type');
      if (!terms) throw StateError('Please accept the partner terms and privacy policy');
    }
    final result = await ref.read(repositoryProvider).rpc('partner_save_application', {'p': payload(), 'p_submit': submit});
    ref.invalidate(accountProvider);
    if (!mounted) return;
    toast(context, submit ? 'Application submitted. We will notify you after review.' : 'Draft saved');
    if (submit && result == 'pending_verification') {
      context.go('/delivery');
    } else {
      await load();
    }
  }

  String? phone(String v) => RegExp(r'^[6-9]\d{9}$').hasMatch(v.replaceAll(RegExp(r'\D'), '')) ? null : 'Enter a 10-digit mobile number';

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (error != null) return Scaffold(appBar: AppBar(), body: Failure(error!, load));
    final vehicleNeedsLicence = vehicleType != null && vehicleType != 'bicycle' && vehicleType != 'e_bike';
    return Scaffold(
        appBar: AppBar(title: const Text('Delivery partner application')),
        body: SafeArea(
            child: Form(
                key: form,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  Row(children: [
                    Expanded(child: Text('Application status', style: context.text.titleMedium)),
                    StatusChip(status)
                  ]),
                  if (profile['review_reason'] != null)
                    Notice('Admin note: ${profile['review_reason']}', icon: Icons.feedback_outlined, color: statusColor(status)),
                  if (!editable)
                    Notice(
                        status == 'pending_verification'
                            ? 'Your application is under review. You can still upload replacement documents below.'
                            : 'Your details are locked after approval. Contact support to change them.',
                        icon: Icons.lock_outline),
                  const SectionTitle('Personal information'),
                  Field(c['legal_name']!, 'Full name (as on ID)', enabled: editable, capitalization: TextCapitalization.words),
                  Field(c['phone']!, 'Mobile number', enabled: editable, keyboard: TextInputType.phone, maxLength: 10,
                      hint: 'OTP verification is not available yet; an admin confirms your number.', validate: phone),
                  Field(c['email']!, 'Email', requiredValue: false, enabled: editable, keyboard: TextInputType.emailAddress,
                      validate: (v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v) ? null : 'Enter a valid email'),
                  Field(c['residential_address']!, 'Residential address', enabled: editable, lines: 2,
                      validate: (v) => v.length < 10 ? 'Enter your full address' : null),
                  Row(children: [
                    Expanded(child: Field(c['city']!, 'City', enabled: editable, capitalization: TextCapitalization.words)),
                    const SizedBox(width: 10),
                    Expanded(child: Field(c['service_area']!, 'Preferred area', enabled: editable, hint: 'e.g. Sector 1–14')),
                  ]),
                  const SectionTitle('Emergency contact'),
                  Field(c['emergency_contact_name']!, 'Contact name', enabled: editable, capitalization: TextCapitalization.words),
                  Field(c['emergency_contact_phone']!, 'Contact mobile', enabled: editable, keyboard: TextInputType.phone,
                      maxLength: 10, validate: phone),
                  const SectionTitle('Vehicle'),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final v in vehicleTypes.entries)
                      ChoiceChip(
                          label: Text(v.value),
                          selected: vehicleType == v.key,
                          onSelected: editable ? (_) => setState(() => vehicleType = v.key) : null)
                  ]),
                  if (vehicleType != 'bicycle')
                    Field(c['vehicle_number']!, 'Vehicle registration number', enabled: editable,
                        requiredValue: vehicleType != null, capitalization: TextCapitalization.characters,
                        hint: 'e.g. HR12AB1234',
                        validate: (v) => RegExp(r'^[A-Z]{2}[0-9]{1,2}[A-Z]{0,3}[0-9]{1,4}$')
                                .hasMatch(v.toUpperCase().replaceAll(RegExp(r'[\s-]'), ''))
                            ? null
                            : 'Enter a valid registration number'),
                  const SectionTitle('Identity (last 4 characters only)'),
                  Text('Never type your full Aadhaar or licence number. Upload clear photos below; they are stored privately for verification by authorised staff only.',
                      style: TextStyle(fontSize: 12, color: context.muted)),
                  Row(children: [
                    Expanded(
                        child: Field(c['aadhaar_last4']!, 'Aadhaar last 4', enabled: editable, keyboard: TextInputType.number,
                            maxLength: 4, validate: (v) => RegExp(r'^\d{4}$').hasMatch(v) ? null : '4 digits')),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Field(c['licence_last4']!, 'Licence last 4', enabled: editable, requiredValue: vehicleNeedsLicence,
                            maxLength: 4, capitalization: TextCapitalization.characters,
                            validate: (v) => RegExp(r'^[A-Za-z0-9]{4}$').hasMatch(v) ? null : '4 characters')),
                  ]),
                  const SectionTitle('Payout details'),
                  Field(c['payout_upi_vpa']!, 'UPI ID for payouts', requiredValue: false, enabled: editable,
                      hint: 'e.g. name@okaxis. Add this or a bank account.',
                      validate: (v) => RegExp(r'^[A-Za-z0-9._-]{2,64}@[A-Za-z]{2,32}$').hasMatch(v) ? null : 'Enter a valid UPI ID'),
                  Row(children: [
                    Expanded(
                        child: Field(c['bank_account_last4']!, 'Bank a/c last 4', requiredValue: false, enabled: editable,
                            keyboard: TextInputType.number, maxLength: 4,
                            validate: (v) => RegExp(r'^\d{4}$').hasMatch(v) ? null : '4 digits')),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Field(c['bank_ifsc']!, 'IFSC', requiredValue: false, enabled: editable, maxLength: 11,
                            capitalization: TextCapitalization.characters,
                            validate: (v) => RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(v.toUpperCase()) ? null : 'Invalid IFSC')),
                  ]),
                  const SectionTitle('Documents'),
                  for (final (type, label, needed) in [
                    ('profile_photo', 'Profile photo (selfie)', true),
                    ('aadhaar', 'Aadhaar card photo', true),
                    ('driving_license', 'Driving licence photo', vehicleNeedsLicence),
                    ('vehicle_rc', 'Vehicle RC photo', false),
                  ])
                    _DocTile(
                        label: label + (needed ? ' *' : ''),
                        doc: latestDoc(type),
                        canUpload: status != 'suspended',
                        onUpload: () => uploadDoc(type)),
                  if (editable) ...[
                    const SizedBox(height: 8),
                    CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: terms,
                        onChanged: (v) => setState(() => terms = v == true),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('I accept the partner terms and privacy policy'),
                        subtitle: InkWell(
                            onTap: () => showDialog<void>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                        title: const Text('Partner terms & privacy'),
                                        content: const SingleChildScrollView(
                                            child: Text(
                                                '• You deliver orders as an independent partner and must follow traffic laws.\n'
                                                '• You will receive orders only after an administrator approves your documents.\n'
                                                '• Earnings are calculated per completed delivery using the published earning rule and paid out separately; a QR upload is not a payment.\n'
                                                '• Your identity documents are stored privately, visible only to authorised staff, and used only for verification.\n'
                                                '• Your live location is shared with the customer only during an active delivery when you turn sharing on.\n'
                                                '• False documents lead to rejection or suspension.')),
                                        actions: [
                                          TextButton(
                                              onPressed: () => openPolicy(ctx, privacyUrl),
                                              child: const Text('Privacy policy')),
                                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))
                                        ])),
                            child: Text('Read terms', style: TextStyle(color: context.colors.primary)))),
                    ActionButton('Save draft', () => save(false), icon: Icons.save_outlined, tonal: true),
                    const SizedBox(height: 8),
                    ActionButton(status == 'draft' ? 'Submit for verification' : 'Resubmit for verification', () => save(true),
                        icon: Icons.send),
                  ],
                  if (events.isNotEmpty) ...[
                    const SectionTitle('Verification history'),
                    for (final e in events)
                      ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.history, size: 18),
                          title: Text(statusLabel('${e['event']}')),
                          subtitle: Text([if (e['reason'] != null) '${e['reason']}', stamp(e['created_at'])].join(' • '))),
                  ],
                  const SizedBox(height: 24),
                ]))));
  }
}

class _DocTile extends StatelessWidget {
  final String label;
  final Json? doc;
  final bool canUpload;
  final Future<void> Function() onUpload;
  const _DocTile({required this.label, required this.doc, required this.canUpload, required this.onUpload});
  @override
  Widget build(BuildContext context) {
    final st = doc == null ? 'none' : '${doc!['status']}';
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
                StatusChip(st, label: doc == null ? 'Not uploaded' : (st == 'active' ? 'Accepted' : null)),
              ]),
              if (doc?['review_reason'] != null)
                Text('Reason: ${doc!['review_reason']}', style: const TextStyle(color: danger, fontSize: 12)),
              if (doc?['masked_reference'] != null)
                Text('Ending •••• ${doc!['masked_reference']}', style: TextStyle(color: context.muted, fontSize: 12)),
              if (canUpload) ...[
                const SizedBox(height: 6),
                ActionButton(doc == null ? 'Upload' : 'Upload a new photo', onUpload, icon: Icons.upload_file, tonal: true),
              ]
            ])));
  }
}
