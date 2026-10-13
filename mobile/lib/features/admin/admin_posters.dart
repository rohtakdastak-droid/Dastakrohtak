import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class AdminPostersScreen extends ConsumerStatefulWidget {
  const AdminPostersScreen({super.key});
  @override
  ConsumerState<AdminPostersScreen> createState() => _AdminPostersScreenState();
}

class _AdminPostersScreenState extends ConsumerState<AdminPostersScreen> {
  int generation = 0;

  Future<void> open([Json? poster]) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PosterEditor(poster: poster)));
    if (mounted) setState(() => generation++);
  }

  Future<void> swap(Json a, Json b) async {
    final repo = ref.read(repositoryProvider);
    final sa = integer(a['sort_order']), sb = integer(b['sort_order']);
    await repo.save('promo_posters', {'sort_order': sa == sb ? sb + 1 : sb}, id: a['id']);
    await repo.save('promo_posters', {'sort_order': sa}, id: b['id']);
    if (mounted) setState(() => generation++);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    return FutureBuilder<List<Json>>(
        key: ValueKey(generation),
        future: repo.rows('promo_posters', sort: 'sort_order', ascending: true),
        builder: (c, s) => PageFrame('Promo posters',
            customerNav: false,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              ActionButton('Add poster', () => open(), icon: Icons.add_photo_alternate_outlined),
              const SizedBox(height: 8),
              Text('Customers see only active posters inside their schedule (and area, if set). If none are live, a clean welcome card is shown instead.',
                  style: TextStyle(fontSize: 12, color: context.muted)),
              const SizedBox(height: 12),
              if (s.hasError) Failure(s.error!, () => setState(() => generation++)),
              if (!s.hasData && !s.hasError) const LinearProgressIndicator(),
              if (s.hasData && s.data!.isEmpty) const Empty('No posters yet.', icon: Icons.view_carousel_outlined),
              if (s.hasData)
                for (final (i, p) in s.data!.indexed)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            AspectRatio(
                                aspectRatio: 2.2,
                                child: Photo(repo.imageUrl(p['image_path'], bucket: 'promo-posters'), height: 200, placeholder: Icons.image)),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(child: Text(p['title'], style: context.text.titleMedium)),
                              StatusChip(_live(p) ? 'active' : 'inactive', label: _live(p) ? 'Live' : (p['is_active'] == true ? 'Scheduled / ended' : 'Inactive')),
                            ]),
                            if (p['subtitle'] != null) Text(p['subtitle']),
                            Text(
                                [
                                  'Order ${p['sort_order']}',
                                  if (p['starts_at'] != null) 'from ${stamp(p['starts_at'])}',
                                  if (p['ends_at'] != null) 'until ${stamp(p['ends_at'])}',
                                  if (p['area_radius_km'] != null) 'within ${p['area_radius_km']} km of ${p['area_lat']}, ${p['area_lng']}',
                                  if (p['target_url'] != null) '→ ${p['target_url']}',
                                ].join(' • '),
                                style: TextStyle(fontSize: 12, color: context.muted)),
                            Row(children: [
                              IconButton(tooltip: 'Move up', onPressed: i == 0 ? null : () => perform(context, () => swap(p, s.data![i - 1])), icon: const Icon(Icons.arrow_upward)),
                              IconButton(
                                  tooltip: 'Move down',
                                  onPressed: i == s.data!.length - 1 ? null : () => perform(context, () => swap(p, s.data![i + 1])),
                                  icon: const Icon(Icons.arrow_downward)),
                              const Spacer(),
                              Switch(
                                  value: p['is_active'] == true,
                                  onChanged: (v) => perform(context, () async {
                                        await repo.save('promo_posters', {'is_active': v, 'updated_at': DateTime.now().toUtc().toIso8601String()}, id: p['id']);
                                        if (mounted) setState(() => generation++);
                                      })),
                              IconButton(tooltip: 'Edit', onPressed: () => open(p), icon: const Icon(Icons.edit_outlined)),
                              IconButton(
                                  tooltip: 'Delete',
                                  onPressed: () async {
                                    if (!await confirm(context, 'Delete poster?', '"${p['title']}" will be removed permanently.', yes: 'Delete', destructive: true)) {
                                      return;
                                    }
                                    if (!context.mounted) return;
                                    await perform(context, () async {
                                      await repo.remove('promo_posters', p['id']);
                                      try {
                                        await repo.client.storage.from('promo-posters').remove([p['image_path']]);
                                      } catch (_) {}
                                      if (mounted) setState(() => generation++);
                                    }, success: 'Poster deleted');
                                  },
                                  icon: const Icon(Icons.delete_outline, color: danger)),
                            ])
                          ]))),
            ])));
  }

  bool _live(Json p) {
    final now = DateTime.now().toUtc();
    final start = DateTime.tryParse('${p['starts_at']}');
    final end = DateTime.tryParse('${p['ends_at']}');
    return p['is_active'] == true && (start == null || !start.isAfter(now)) && (end == null || end.isAfter(now));
  }
}

class PosterEditor extends ConsumerStatefulWidget {
  final Json? poster;
  const PosterEditor({this.poster, super.key});
  @override
  ConsumerState<PosterEditor> createState() => _PosterEditorState();
}

class _PosterEditorState extends ConsumerState<PosterEditor> {
  final form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> c;
  String? image;
  DateTime? starts, ends;
  bool active = true;

  @override
  void initState() {
    super.initState();
    final p = widget.poster ?? {};
    c = {
      for (final k in ['title', 'subtitle', 'alt_text', 'cta_label', 'target_url', 'sort_order', 'area_lat', 'area_lng', 'area_radius_km'])
        k: TextEditingController(text: p[k] == null ? (k == 'sort_order' ? '100' : '') : '${p[k]}')
    };
    image = p['image_path'];
    starts = DateTime.tryParse('${p['starts_at']}')?.toLocal();
    ends = DateTime.tryParse('${p['ends_at']}')?.toLocal();
    active = p['is_active'] ?? true;
  }

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> pickDate(DateTime? current) async {
    final d = await showDatePicker(
        context: context, initialDate: current ?? DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime.now().add(const Duration(days: 730)));
    if (d == null || !mounted) return null;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current ?? DateTime(d.year, d.month, d.day, 0, 0)));
    return DateTime(d.year, d.month, d.day, t?.hour ?? 0, t?.minute ?? 0);
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) throw StateError('Please fix the highlighted fields');
    if (image == null) throw StateError('Upload a poster image');
    if (starts != null && ends != null && !ends!.isAfter(starts!)) throw StateError('End must be after start');
    String? t(String k) => c[k]!.text.trim().isEmpty ? null : c[k]!.text.trim();
    final area = [t('area_lat'), t('area_lng'), t('area_radius_km')];
    if (area.any((e) => e != null) && area.any((e) => e == null)) throw StateError('Fill all three area fields or leave all empty');
    final repo = ref.read(repositoryProvider);
    await repo.save(
        'promo_posters',
        {
          'title': t('title'),
          'subtitle': t('subtitle'),
          'alt_text': t('alt_text') ?? t('title'),
          'cta_label': t('cta_label'),
          'target_url': t('target_url'),
          'sort_order': int.tryParse(c['sort_order']!.text) ?? 100,
          'starts_at': starts?.toUtc().toIso8601String(),
          'ends_at': ends?.toUtc().toIso8601String(),
          'is_active': active,
          'image_path': image,
          'area_lat': area[0] == null ? null : double.parse(area[0]!),
          'area_lng': area[1] == null ? null : double.parse(area[1]!),
          'area_radius_km': area[2] == null ? null : double.parse(area[2]!),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          if (widget.poster == null) 'created_by': repo.uid,
        },
        id: widget.poster?['id']);
    if (mounted) {
      toast(context, 'Poster saved');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    String? number(String v) => double.tryParse(v) == null ? 'Enter a number' : null;
    return Scaffold(
        appBar: AppBar(title: Text(widget.poster == null ? 'New poster' : 'Edit poster')),
        body: SafeArea(
            child: Form(
                key: form,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  AspectRatio(
                      aspectRatio: 2.2,
                      child: Stack(fit: StackFit.expand, children: [
                        Photo(image == null ? null : repo.imageUrl(image, bucket: 'promo-posters'), height: 200, placeholder: Icons.image),
                        if (image != null)
                          Positioned(
                              left: 12,
                              bottom: 10,
                              right: 12,
                              child: Text(c['title']!.text,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, shadows: [Shadow(blurRadius: 6)]))),
                      ])),
                  const SizedBox(height: 8),
                  ActionButton(image == null ? 'Upload image (JPEG/PNG/WebP, max 5 MB)' : 'Replace image', () async {
                    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, imageQuality: 88);
                    if (file == null) return;
                    final path = await repo.upload('promo-posters', 'posters', await file.readAsBytes());
                    setState(() => image = path);
                  }, icon: Icons.upload, tonal: true),
                  Text('Recommended size 1100 × 500 px (wide banner).', style: TextStyle(fontSize: 12, color: context.muted)),
                  Field(c['title']!, 'Title', maxLength: 80),
                  Field(c['subtitle']!, 'Subtitle', requiredValue: false, maxLength: 160),
                  Field(c['alt_text']!, 'Image description for screen readers', requiredValue: false, maxLength: 160),
                  Row(children: [
                    Expanded(child: Field(c['cta_label']!, 'Button text', requiredValue: false, maxLength: 30, hint: 'e.g. Order now')),
                    const SizedBox(width: 10),
                    Expanded(child: Field(c['sort_order']!, 'Order', keyboard: TextInputType.number, validate: (v) => int.tryParse(v) == null ? 'Number' : null)),
                  ]),
                  Field(c['target_url']!, 'Link', requiredValue: false,
                      hint: 'https://… or /store/<restaurant id>',
                      validate: (v) => RegExp(r'^(https://\S+|/store/[0-9a-f-]{36})$').hasMatch(v) ? null : 'Use https://… or /store/<id>'),
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Active'), value: active, onChanged: (v) => setState(() => active = v)),
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Starts'),
                      subtitle: Text(starts == null ? 'Immediately' : stamp(starts!.toUtc().toIso8601String())),
                      trailing: Wrap(children: [
                        if (starts != null) IconButton(tooltip: 'Clear', onPressed: () => setState(() => starts = null), icon: const Icon(Icons.clear)),
                        IconButton(tooltip: 'Pick start', onPressed: () async {
                          final d = await pickDate(starts);
                          if (d != null) setState(() => starts = d);
                        }, icon: const Icon(Icons.event)),
                      ])),
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ends'),
                      subtitle: Text(ends == null ? 'No end date' : stamp(ends!.toUtc().toIso8601String())),
                      trailing: Wrap(children: [
                        if (ends != null) IconButton(tooltip: 'Clear', onPressed: () => setState(() => ends = null), icon: const Icon(Icons.clear)),
                        IconButton(tooltip: 'Pick end', onPressed: () async {
                          final d = await pickDate(ends);
                          if (d != null) setState(() => ends = d);
                        }, icon: const Icon(Icons.event)),
                      ])),
                  const SectionTitle('Service area (optional)'),
                  Text('Leave empty to show everywhere. Otherwise only customers within the radius of this point see it.',
                      style: TextStyle(fontSize: 12, color: context.muted)),
                  Row(children: [
                    Expanded(child: Field(c['area_lat']!, 'Latitude', requiredValue: false, keyboard: const TextInputType.numberWithOptions(decimal: true, signed: true), validate: number)),
                    const SizedBox(width: 8),
                    Expanded(child: Field(c['area_lng']!, 'Longitude', requiredValue: false, keyboard: const TextInputType.numberWithOptions(decimal: true, signed: true), validate: number)),
                    const SizedBox(width: 8),
                    Expanded(child: Field(c['area_radius_km']!, 'Radius km', requiredValue: false, keyboard: const TextInputType.numberWithOptions(decimal: true), validate: number)),
                  ]),
                  const SizedBox(height: 16),
                  ActionButton('Save poster', save, icon: Icons.check),
                  const SizedBox(height: 24),
                ]))));
  }
}
