import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:url_launcher/url_launcher.dart';
import '../../core/location.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../cart/cart_controller.dart';
import 'profile_menu.dart';

class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});
  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen>
    with WidgetsBindingObserver {
  final search = TextEditingController();
  List<Json> stores = [];
  Object? error;
  bool busy = true, more = false;
  int page = 0, ticket = 0;
  DateTime? updated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Opening hours change over time; refresh when the app returns to the foreground.
    if (state == AppLifecycleState.resumed) load(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    search.dispose();
    super.dispose();
  }

  Future<void> load(bool reset) async {
    final my = ++ticket;
    final point = ref.read(deliveryPointProvider);
    setState(() => busy = true);
    try {
      final repo = ref.read(repositoryProvider);
      List<Json> next;
      try {
        next = await repo.discover(
            lat: point?.lat, lng: point?.lng, search: search.text, page: reset ? 0 : page + 1);
      } on PostgrestException catch (e) {
        // Older backend without discover_stores: show the plain active list rather than an error.
        if (e.code != 'PGRST202' && e.code != '42883') rethrow;
        next = (await repo.rows('vendors',
                filters: {'is_active': true, 'category': 'food'}, sort: 'sort_priority', ascending: true, page: reset ? 0 : page + 1))
            .map((v) => {...v, 'is_open': true, 'preview': []})
            .toList();
      }
      if (!mounted || my != ticket) return;
      setState(() {
        stores = reset ? next : [...stores, ...next];
        page = reset ? 0 : page + 1;
        more = next.length == 30;
        error = null;
        updated = DateTime.now();
      });
    } catch (e) {
      if (mounted && my == ticket) setState(() => error = e);
    } finally {
      if (mounted && my == ticket) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(deliveryPointProvider, (_, __) => load(true));
    final point = ref.watch(deliveryPointProvider);
    final account = ref.watch(accountProvider).valueOrNull;
    return PageFrame('Dastak',
        actions: [
          const ThemeToggle(),
          IconButton(
              tooltip: 'Notifications',
              onPressed: () => context.push('/notifications'),
              icon: const Icon(Icons.notifications_outlined)),
          Padding(
              padding: const EdgeInsets.only(right: 10, left: 2),
              child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => showProfileMenu(context, ref),
                  child: Semantics(
                      button: true,
                      label: 'Open profile menu',
                      child: account == null
                          ? const CircleAvatar(
                              radius: 17, child: Icon(Icons.person_outline, size: 20))
                          : InitialAvatar(account.name.isEmpty ? 'U' : account.name,
                              radius: 17))))
        ],
        child: RefreshIndicator(
            onRefresh: () => load(true),
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  _LocationBar(point),
                  const SizedBox(height: 12),
                  PosterCarousel(lat: point?.lat, lng: point?.lng),
                  const SizedBox(height: 16),
                  Text('What are you craving today?',
                      style: context.text.headlineMedium),
                  const SizedBox(height: 12),
                  TextField(
                      controller: search,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => load(true),
                      decoration: InputDecoration(
                          hintText: 'Search restaurants, cafes or cuisines',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                search.clear();
                                load(true);
                              },
                              icon: const Icon(Icons.close)))),
                  const SizedBox(height: 16),
                  if (point == null)
                    Notice(
                        'Showing all restaurants. Set your delivery location to see only the ones that deliver to you.',
                        icon: Icons.location_searching,
                        color: warning,
                        action: TextButton(
                            onPressed: () => pickDeliveryPoint(context, ref),
                            child: const Text('Set'))),
                  if (busy) const LinearProgressIndicator(),
                  if (updated != null && !busy)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                            '${stores.length}${more ? '+' : ''} restaurant${stores.length == 1 ? '' : 's'} • updated ${clock(updated!)}',
                            style: TextStyle(fontSize: 12, color: context.muted))),
                  if (error != null) Failure(error!, () => load(true)),
                  if (!busy && error == null && stores.isEmpty)
                    Empty(
                        point == null
                            ? 'No restaurants are available right now.'
                            : 'No restaurants deliver to ${point.label} yet. Try another address.',
                        icon: Icons.storefront_outlined),
                  for (final s in stores) StoreCard(s),
                  if (more && !busy)
                    TextButton(
                        onPressed: () => load(false),
                        child: const Text('Show more restaurants'))
                ])));
  }
}

class _LocationBar extends ConsumerWidget {
  final DeliveryPoint? point;
  const _LocationBar(this.point);
  @override
  Widget build(BuildContext context, WidgetRef ref) => Material(
      color: context.tint,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => pickDeliveryPoint(context, ref),
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Icon(Icons.location_on, color: context.colors.primary),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('DELIVER TO',
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w800,
                              color: context.muted)),
                      Text(point?.label ?? 'Choose delivery location',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700))
                    ])),
                const Icon(Icons.expand_more)
              ]))));
}

Future<void> pickDeliveryPoint(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(repositoryProvider);
  List<Address> saved = [];
  if (repo.client.auth.currentUser != null) {
    try {
      saved = (await repo.rows('user_addresses', filters: {'user_id': repo.uid}))
          .map(Address.new)
          .toList();
    } catch (_) {}
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
          child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Where should we deliver?', style: sheet.text.titleLarge),
                const SizedBox(height: 12),
                ActionButton('Use my current location', () async {
                  final here = await currentPosition();
                  ref.read(deliveryPointProvider.notifier)
                      .set(DeliveryPoint(here.latitude, here.longitude, 'Current location'));
                  if (sheet.mounted) Navigator.pop(sheet);
                }, icon: Icons.my_location, tonal: true),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(sheet);
                      await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => const _MapPointScreen()));
                    },
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Pick a point on the map')),
                if (saved.isNotEmpty) ...[
                  const SectionTitle('Saved addresses'),
                  ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView(shrinkWrap: true, children: [
                        for (final a in saved)
                          ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.home_outlined),
                              title: Text(a.label),
                              subtitle: Text(a.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                              onTap: () {
                                ref.read(deliveryPointProvider.notifier)
                                    .set(DeliveryPoint(a.lat, a.lng, a.label));
                                Navigator.pop(sheet);
                              })
                      ]))
                ] else if (repo.client.auth.currentUser != null)
                  TextButton(
                      onPressed: () {
                        Navigator.pop(sheet);
                        context.push('/addresses');
                      },
                      child: const Text('Save a full delivery address')),
              ]))));
}

class _MapPointScreen extends ConsumerStatefulWidget {
  const _MapPointScreen();
  @override
  ConsumerState<_MapPointScreen> createState() => _MapPointScreenState();
}

class _MapPointScreenState extends ConsumerState<_MapPointScreen> {
  LatLng? pin;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Pick delivery area')),
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
        LocationPicker(
            height: 380,
            hint: 'Tap where you want the food delivered. You can save the full address at checkout.',
            onChanged: (p) => setState(() => pin = p)),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: pin == null
                ? null
                : () {
                    ref.read(deliveryPointProvider.notifier).set(
                        DeliveryPoint(pin!.latitude, pin!.longitude, 'Pinned location'));
                    Navigator.pop(context);
                  },
            child: const Text('Show restaurants here'))
      ])));
}

class PosterCarousel extends ConsumerStatefulWidget {
  final double? lat, lng;
  const PosterCarousel({this.lat, this.lng, super.key});
  @override
  ConsumerState<PosterCarousel> createState() => _PosterCarouselState();
}

class _PosterCarouselState extends ConsumerState<PosterCarousel> {
  final controller = PageController();
  List<Json> posters = [];
  int index = 0;
  bool loaded = false, holding = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(PosterCarousel old) {
    super.didUpdateWidget(old);
    if (old.lat != widget.lat || old.lng != widget.lng) load();
  }

  Future<void> load() async {
    try {
      final list = await ref
          .read(repositoryProvider)
          .rpcList('active_posters', {'p_lat': widget.lat, 'p_lng': widget.lng});
      if (mounted) setState(() => posters = list);
    } catch (_) {
      if (mounted) setState(() => posters = []);
    } finally {
      if (mounted) setState(() => loaded = true);
      restart();
    }
  }

  void restart() {
    timer?.cancel();
    if (posters.length < 2) return;
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || holding || !controller.hasClients) return;
      if (MediaQuery.of(context).disableAnimations) return;
      controller.animateToPage((index + 1) % posters.length,
          duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  Future<void> open(Json p) async {
    final target = p['target_url'] as String?;
    if (target == null || target.isEmpty) return;
    if (target.startsWith('/store/')) {
      context.push(target);
    } else if (!await launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication)) {
      if (mounted) toast(context, 'Could not open the offer link');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return AspectRatio(
          aspectRatio: 2.2,
          child: Container(
              decoration: BoxDecoration(
                  color: context.tint, borderRadius: BorderRadius.circular(18))));
    }
    if (posters.isEmpty) return const _WelcomeCard();
    final repo = ref.read(repositoryProvider);
    return Column(children: [
      AspectRatio(
          aspectRatio: 2.2,
          child: Listener(
              onPointerDown: (_) => holding = true,
              onPointerUp: (_) => holding = false,
              onPointerCancel: (_) => holding = false,
              child: PageView.builder(
                  controller: controller,
                  itemCount: posters.length,
                  onPageChanged: (i) => setState(() => index = i),
                  itemBuilder: (c, i) {
                    final p = posters[i];
                    return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Semantics(
                            image: true,
                            label: p['alt_text'] ?? p['title'],
                            child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => open(p),
                                child: ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: Stack(fit: StackFit.expand, children: [
                                      Image.network(
                                          repo.imageUrl(p['image_path'], bucket: 'promo-posters')!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (a, b, e) => Container(color: context.tint)),
                                      const DecoratedBox(
                                          decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [Colors.transparent, Color(0xAA000000)]))),
                                      Positioned(
                                          left: 14,
                                          right: 14,
                                          bottom: 12,
                                          child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(p['title'] ?? '',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.w800,
                                                        fontSize: 18)),
                                                if ((p['subtitle'] ?? '').toString().isNotEmpty)
                                                  Text(p['subtitle'],
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                                                if (p['ends_at'] != null)
                                                  Text('Valid till ${stamp(p['ends_at']).split(',').first}',
                                                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                                if ((p['cta_label'] ?? '').toString().isNotEmpty &&
                                                    p['target_url'] != null)
                                                  Padding(
                                                      padding: const EdgeInsets.only(top: 6),
                                                      child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                          decoration: BoxDecoration(
                                                              color: Colors.white,
                                                              borderRadius: BorderRadius.circular(999)),
                                                          child: Text(p['cta_label'],
                                                              style: const TextStyle(
                                                                  color: brandDeep,
                                                                  fontWeight: FontWeight.w800,
                                                                  fontSize: 12))))
                                              ]))
                                    ])))));
                  }))),
      if (posters.length > 1)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < posters.length; i++)
                AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == index ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: i == index ? context.colors.primary : context.muted.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(3)))
            ]))
    ]);
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: context.dark
                  ? [const Color(0xFF0C4A6E), const Color(0xFF082F49)]
                  : [const Color(0xFFE0F2FE), const Color(0xFFF0F9FF)]),
          borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        const BrandMark(size: 46),
        const SizedBox(width: 12),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Dastak',
              style: GoogleFonts.playfairDisplay(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: context.dark ? Colors.white : brandDeep,
                  height: 1)),
          const SizedBox(height: 2),
          Text('Dil Se Ghar Tak • Local Delivery',
              style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.dark ? const Color(0xFFBAE6FD) : const Color(0xFF075985)))
        ]))
      ]));
}

class StoreCard extends ConsumerWidget {
  final Json s;
  const StoreCard(this.s, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    final open = s['is_open'] == true;
    final preview = List<Json>.from(
        ((s['preview'] as List?) ?? []).map((j) => Map<String, dynamic>.from(j)));
    final closedText = s['temporarily_closed'] == true
        ? 'Temporarily closed${(s['closed_reason'] ?? '').toString().isEmpty ? '' : ' • ${s['closed_reason']}'}'
        : nextOpening(s['opening_hours']) ?? 'Closed now';
    final meta = [
      if ((s['cuisine'] ?? '').toString().isNotEmpty) s['cuisine'],
      if (s['distance_km'] != null) '${decimal(s['distance_km']).toStringAsFixed(1)} km',
      '${s['prep_time_minutes']} min prep',
      if (integer(s['min_order_paise']) > 0) 'Min ${money(integer(s['min_order_paise']))}'
    ].join(' • ');
    return Opacity(
        opacity: open ? 1 : 0.62,
        child: Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => context.push('/store/${s['id']}'),
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Stack(children: [
                        ColorFiltered(
                            colorFilter: open
                                ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                                : const ColorFilter.matrix([
                                    0.33, 0.59, 0.11, 0, 0, 0.33, 0.59, 0.11, 0, 0, //
                                    0.33, 0.59, 0.11, 0, 0, 0, 0, 0, 1, 0
                                  ]),
                            child: Photo(
                                repo.imageUrl(s['cover_image_path'], bucket: 'vendor-images'),
                                height: 130)),
                        Positioned(
                            top: 10,
                            left: 10,
                            child: StatusChip(open ? 'open' : 'closed',
                                label: open ? 'Open' : 'Closed'))
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: Text(s['name'] ?? '',
                                style: context.text.titleLarge,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)),
                        Stars(s['rating_avg'] == null ? null : decimal(s['rating_avg']),
                            integer(s['rating_count'] ?? 0))
                      ]),
                      Text(meta, style: TextStyle(color: context.muted, fontSize: 12)),
                      if (!open)
                        Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(closedText,
                                style: const TextStyle(
                                    color: danger, fontWeight: FontWeight.w700, fontSize: 12))),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                            height: 128,
                            child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: preview.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 10),
                                itemBuilder: (c, i) => _PreviewItem(preview[i], s['id']))),
                      ]
                    ])))));
  }
}

class _PreviewItem extends ConsumerWidget {
  final Json p;
  final String storeId;
  const _PreviewItem(this.p, this.storeId);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    final available = p['available'] != false;
    return SizedBox(
        width: 112,
        child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.push('/store/$storeId'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Stack(children: [
                Photo(repo.imageUrl(p['image_path']),
                    height: 72, radius: 12, placeholder: Icons.restaurant),
                if (p['diet'] == 'veg' || p['diet'] == 'non_veg' || p['diet'] == 'egg')
                  Positioned(top: 6, left: 6, child: DietMark(p['diet']))
              ]),
              const SizedBox(height: 4),
              Text(p['name'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              Text(available ? '${p['has_choices'] == true ? 'from ' : ''}${money(integer(p['price_paise']))}' : 'Sold out',
                  style: TextStyle(
                      fontSize: 12,
                      color: available ? context.colors.primary : danger,
                      fontWeight: FontWeight.w700))
            ])));
  }
}

class DietMark extends StatelessWidget {
  final String diet;
  const DietMark(this.diet, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = diet == 'veg' ? const Color(0xFF16A34A) : (diet == 'egg' ? warning : danger);
    return Tooltip(
        message: diet == 'veg' ? 'Vegetarian' : (diet == 'egg' ? 'Contains egg' : 'Non-vegetarian'),
        child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: c, width: 1.6),
                borderRadius: BorderRadius.circular(3)),
            child: Center(
                child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle)))));
  }
}

class StoreScreen extends ConsumerStatefulWidget {
  final String id;
  const StoreScreen(this.id, {super.key});
  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  String search = '';
  bool veg = false;
  late Future<List<dynamic>> info;

  @override
  void initState() {
    super.initState();
    loadInfo();
  }

  void loadInfo() {
    final repo = ref.read(repositoryProvider);
    info = Future.wait([
      repo.one('vendors', widget.id),
      repo.rpcJson('store_status', {'p_vendor': widget.id})
    ]);
  }

  Future<void> add(Product product) async {
    final selected = <String>{};
    if (product.options.isNotEmpty) {
      final groups = product.choiceGroups;
      final extras = product.options.where((o) => !o.required).toList();
      final result = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (sheet) => StatefulBuilder(builder: (sheet, set) {
                final unit = product.price +
                    product.options.where((o) => selected.contains(o.id)).fold<int>(0, (t, o) => t + o.delta);
                final ready = groups.values.every((g) => g.any((o) => selected.contains(o.id)));
                return SafeArea(
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: SingleChildScrollView(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(product.name, style: sheet.text.titleLarge),
                          for (final g in groups.entries) ...[
                            const SizedBox(height: 12),
                            Text('${g.key} (choose one) *', style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final o in g.value)
                                ChoiceChip(
                                    label: Text('${o.label} • ${money(product.price + o.delta)}'),
                                    selected: selected.contains(o.id),
                                    onSelected: (_) => set(() {
                                          selected.removeAll(g.value.map((x) => x.id));
                                          selected.add(o.id);
                                        }))
                            ]),
                          ],
                          if (extras.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Text('Add-ons (optional)', style: TextStyle(fontWeight: FontWeight.w700)),
                            for (final o in extras)
                              CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text('${o.group}: ${o.label}'),
                                  subtitle: Text('+ ${money(o.delta)}'),
                                  value: selected.contains(o.id),
                                  onChanged: (v) => set(() => v == true ? selected.add(o.id) : selected.remove(o.id))),
                          ],
                          const SizedBox(height: 16),
                          FilledButton(
                              onPressed: ready ? () => Navigator.pop(sheet, true) : null,
                              child: Text(ready ? 'Add to bag • ${money(unit)}' : 'Choose ${groups.keys.join(' & ').toLowerCase()}')),
                        ]))));
              }));
      if (result != true) return;
    }
    final cart = ref.read(cartProvider);
    bool replace = false;
    if (cart.isNotEmpty && cart.first.product.vendorId != product.vendorId) {
      if (!mounted) return;
      replace = await confirm(context, 'Start a new bag?',
          'Orders can contain items from one restaurant. Your current bag will be cleared.',
          yes: 'Switch restaurant');
      if (!replace) return;
    }
    await ref.read(cartProvider.notifier).add(
        product, product.options.where((o) => selected.contains(o.id)).toList(),
        replace: replace);
    if (mounted) toast(context, '${product.name} added to bag');
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final cart = ref.watch(cartProvider);
    final itemCount = cart.fold<int>(0, (s, l) => s + l.quantity);
    final cartTotal = cart.fold<int>(0, (s, l) => s + l.total);
    return FutureBuilder<List<dynamic>>(
        future: info,
        builder: (context, snap) {
          final vendor = snap.data?[0] as Json?;
          final status = snap.data?[1] as Json?;
          final open = status?['is_open'] == true;
          return RemoteList(
              title: vendor?['name'] ?? 'Menu',
              watch: 'products',
              emptyText: 'This restaurant has not added any items yet.',
              load: (p) async => (await repo.products(widget.id, page: p))
                  .map((p) => {'product': p})
                  .toList(),
              floatingBottom: itemCount == 0
                  ? null
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: FilledButton(
                          onPressed: () => context.push('/cart'),
                          child: Row(children: [
                            Text('$itemCount item${itemCount == 1 ? '' : 's'} • ${money(cartTotal)}'),
                            const Spacer(),
                            const Text('View bag'),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_forward_rounded, size: 18)
                          ]))),
              header: [
                if (snap.hasError)
                  Failure(snap.error!, () => setState(loadInfo))
                else if (vendor == null)
                  const LinearProgressIndicator()
                else ...[
                  Photo(repo.imageUrl(vendor['cover_image_path'], bucket: 'vendor-images'),
                      height: 140),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: Text(vendor['name'], style: context.text.headlineMedium)),
                    StatusChip(open ? 'open' : 'closed', label: open ? 'Open now' : 'Closed')
                  ]),
                  if ((vendor['description'] ?? '').toString().isNotEmpty)
                    Text(vendor['description']),
                  const SizedBox(height: 4),
                  Text(
                      '${vendor['dispatch_address']} • ${vendor['prep_time_minutes']} min prep'
                      '${integer(vendor['min_order_paise']) > 0 ? ' • Min ${money(integer(vendor['min_order_paise']))}' : ''}',
                      style: TextStyle(color: context.muted, fontSize: 12)),
                  Row(children: [
                    Stars(status?['rating_avg'] == null ? null : decimal(status!['rating_avg']),
                        integer(status?['rating_count'] ?? 0)),
                    TextButton(
                        onPressed: () => showStoreReviews(context, ref, widget.id),
                        child: const Text('Reviews')),
                    if (hoursSummary(vendor['opening_hours']).isNotEmpty)
                      TextButton(
                          onPressed: () => showDialog<void>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                      title: const Text('Opening hours'),
                                      content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            for (final line in hoursSummary(vendor['opening_hours'])) Text(line),
                                            const SizedBox(height: 8),
                                            Text('Times are in India Standard Time.',
                                                style: TextStyle(color: ctx.muted, fontSize: 12))
                                          ]),
                                      actions: [
                                        TextButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: const Text('Close'))
                                      ])),
                          child: const Text('Hours'))
                  ]),
                  if (!open)
                    Notice(
                        status?['temporarily_closed'] == true
                            ? 'Temporarily closed${(status?['closed_reason'] ?? '').toString().isEmpty ? '' : ': ${status!['closed_reason']}'}. You can browse the menu, but ordering is paused.'
                            : '${nextOpening(vendor['opening_hours']) ?? 'Closed right now'}. You can browse the menu, but ordering is paused.',
                        icon: Icons.schedule,
                        color: danger),
                ],
                const SizedBox(height: 8),
                TextField(
                    decoration: const InputDecoration(
                        hintText: 'Search this menu', prefixIcon: Icon(Icons.search)),
                    onChanged: (v) => setState(() => search = v.toLowerCase())),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Vegetarian only'),
                    value: veg,
                    onChanged: (v) => setState(() => veg = v)),
              ],
              item: (j, reload) {
                final p = j['product'] as Product;
                if (!p.name.toLowerCase().contains(search) || (veg && p.diet != 'veg')) {
                  return const SizedBox();
                }
                final soldOut = p.stock == 0;
                return Card(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (p.diet != 'unknown') DietMark(p.diet),
                            const SizedBox(height: 4),
                            Text(p.name, style: context.text.titleMedium),
                            Text(p.priceText, style: const TextStyle(fontWeight: FontWeight.w700)),
                            if (p.description.isNotEmpty)
                              Text(p.description,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: context.muted, fontSize: 12)),
                          ])),
                          const SizedBox(width: 10),
                          SizedBox(
                              width: 108,
                              child: Column(children: [
                                Photo(repo.imageUrl(p.image),
                                    height: 84, radius: 12, placeholder: Icons.restaurant),
                                const SizedBox(height: 6),
                                SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.tonal(
                                        style: FilledButton.styleFrom(
                                            minimumSize: const Size(0, 38),
                                            padding: EdgeInsets.zero),
                                        onPressed: soldOut || !open
                                            ? null
                                            : () => perform(context, () => add(p)),
                                        child: Text(soldOut ? 'Sold out' : (open ? 'ADD' : 'Closed'))))
                              ]))
                        ])));
              });
        });
  }
}

Future<void> showStoreReviews(BuildContext context, WidgetRef ref, String vendorId) async {
  final repo = ref.read(repositoryProvider);
  await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
          child: SizedBox(
              height: MediaQuery.of(sheet).size.height * 0.7,
              child: FutureBuilder<List<Json>>(
                  future: repo.rpcList('store_reviews', {'p_vendor': vendorId, 'p_page': 0}),
                  builder: (c, s) {
                    if (s.hasError) return Failure(s.error!, () => Navigator.pop(sheet));
                    if (!s.hasData) return const Center(child: CircularProgressIndicator());
                    if (s.data!.isEmpty) return const Empty('No reviews yet.', icon: Icons.star_outline);
                    return ListView(padding: const EdgeInsets.all(16), children: [
                      Text('Ratings & reviews', style: sheet.text.titleLarge),
                      for (final r in s.data!)
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Row(children: [
                              for (var i = 1; i <= 5; i++)
                                Icon(i <= integer(r['rating']) ? Icons.star_rounded : Icons.star_outline_rounded,
                                    size: 16, color: const Color(0xFFF59E0B)),
                              const SizedBox(width: 6),
                              Text('${r['author']} • ${ago(r['created_at'])}',
                                  style: TextStyle(fontSize: 12, color: sheet.muted))
                            ]),
                            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              if ((r['comment'] ?? '').toString().isNotEmpty) Text(r['comment']),
                              if ((r['vendor_reply'] ?? '').toString().isNotEmpty)
                                Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text('Restaurant: ${r['vendor_reply']}',
                                        style: const TextStyle(fontStyle: FontStyle.italic)))
                            ]))
                    ]);
                  }))));
}
