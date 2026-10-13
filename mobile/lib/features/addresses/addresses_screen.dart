import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../core/location.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class AddressesScreen extends ConsumerStatefulWidget {
  const AddressesScreen({super.key});
  @override
  ConsumerState<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends ConsumerState<AddressesScreen> {
  int generation = 0;
  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final current = ref.watch(deliveryPointProvider);
    return RemoteList(
        key: ValueKey(generation),
        title: 'Saved addresses',
        emptyText: 'No saved addresses yet. Add one to start ordering.',
        load: (p) => repo.rows('user_addresses',
            filters: {'user_id': repo.uid}, page: p),
        header: [
          ActionButton('Add a new address', () async {
            await showAddressEditor(context, ref);
            if (mounted) setState(() => generation++);
          }, icon: Icons.add_location_alt_outlined),
          const SizedBox(height: 12),
        ],
        item: (j, reload) {
          final a = Address(j);
          final selected = current != null &&
              (current.lat - a.lat).abs() < 1e-6 &&
              (current.lng - a.lng).abs() < 1e-6;
          return Card(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(
                              a.label.toLowerCase() == 'work'
                                  ? Icons.work_outline
                                  : Icons.home_outlined,
                              color: context.colors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(a.label,
                                  style: context.text.titleMedium)),
                          if (selected)
                            const StatusChip('active', label: 'Delivering here'),
                          IconButton(
                              tooltip: 'Edit address',
                              onPressed: () async {
                                await showAddressEditor(context, ref,
                                    initial: j);
                                reload();
                              },
                              icon: const Icon(Icons.edit_outlined)),
                          IconButton(
                              tooltip: 'Delete address',
                              onPressed: () async {
                                if (!await confirm(context, 'Delete address?',
                                    'This removes "${a.label}" from your saved addresses. Past orders are not affected.',
                                    yes: 'Delete', destructive: true)) {
                                  return;
                                }
                                if (context.mounted &&
                                    await perform(context,
                                        () => repo.remove('user_addresses', a.id),
                                        success: 'Address deleted')) {
                                  reload();
                                }
                              },
                              icon: const Icon(Icons.delete_outline))
                        ]),
                        Text(a.text),
                        if ((j['instructions'] ?? '').toString().isNotEmpty)
                          Text('Note: ${j['instructions']}',
                              style: TextStyle(color: context.muted, fontSize: 12)),
                        if (!selected)
                          TextButton.icon(
                              onPressed: () {
                                ref.read(deliveryPointProvider.notifier).set(
                                    DeliveryPoint(a.lat, a.lng, a.label));
                                toast(context,
                                    'Showing restaurants that deliver to ${a.label}');
                              },
                              icon: const Icon(Icons.near_me_outlined, size: 18),
                              label: const Text('Deliver here'))
                      ])));
        });
  }
}

Future<void> showAddressEditor(BuildContext context, WidgetRef ref,
        {Json? initial}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AddressEditor(initial: initial)));

/// Parses addresses saved by this editor: "house, street[, landmark], city - 123456".
Map<String, String>? parseAddress(String text) {
  final m = RegExp(r'^(.+?), (.+?), (?:(.+), )?([^,]+) - (\d{6})$').firstMatch(text);
  if (m == null) return null;
  return {
    'house': m.group(1)!,
    'street': m.group(2)!,
    'landmark': m.group(3) ?? '',
    'city': m.group(4)!,
    'pincode': m.group(5)!
  };
}

String composeAddress(
        String house, String street, String landmark, String city, String pin) =>
    [house.trim(), street.trim(), if (landmark.trim().isNotEmpty) landmark.trim(), '${city.trim()} - ${pin.trim()}']
        .join(', ');

class AddressEditor extends ConsumerStatefulWidget {
  final Json? initial;
  const AddressEditor({this.initial, super.key});
  @override
  ConsumerState<AddressEditor> createState() => _AddressEditorState();
}

class _AddressEditorState extends ConsumerState<AddressEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController house, street, landmark, city, pincode,
      legacy, instructions;
  String label = 'Home';
  LatLng? pin;
  bool legacyMode = false;
  String? problem;

  @override
  void initState() {
    super.initState();
    final j = widget.initial;
    final parsed = j == null ? null : parseAddress('${j['formatted_address']}');
    legacyMode = j != null && parsed == null;
    house = TextEditingController(text: parsed?['house']);
    street = TextEditingController(text: parsed?['street']);
    landmark = TextEditingController(text: parsed?['landmark']);
    city = TextEditingController(text: parsed?['city'] ?? 'Rohtak');
    pincode = TextEditingController(text: parsed?['pincode']);
    legacy = TextEditingController(text: j?['formatted_address']);
    instructions = TextEditingController(text: j?['instructions']);
    label = (j?['label'] as String?)?.trim().isNotEmpty == true ? j!['label'] : 'Home';
    if (j != null) pin = LatLng(decimal(j['latitude']), decimal(j['longitude']));
  }

  @override
  void dispose() {
    for (final c in [house, street, landmark, city, pincode, legacy, instructions]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    setState(() => problem = null);
    if (!form.currentState!.validate()) {
      setState(() => problem = 'Please fix the highlighted fields above.');
      throw StateError('Please fix the highlighted fields');
    }
    if (pin == null || !validCoordinates(pin!.latitude, pin!.longitude)) {
      setState(() => problem =
          'Set the delivery point: tap "Use my current location" or tap the map.');
      throw StateError('Set the delivery point on the map');
    }
    final text = legacyMode
        ? legacy.text.trim()
        : composeAddress(house.text, street.text, landmark.text, city.text, pincode.text);
    final repo = ref.read(repositoryProvider);
    await repo.save(
        'user_addresses',
        {
          'user_id': repo.uid,
          'label': label,
          'formatted_address': text,
          'instructions': instructions.text.trim().isEmpty ? null : instructions.text.trim(),
          'latitude': double.parse(pin!.latitude.toStringAsFixed(6)),
          'longitude': double.parse(pin!.longitude.toStringAsFixed(6))
        },
        id: widget.initial?['id']);
    ref.read(deliveryPointProvider.notifier).set(DeliveryPoint(pin!.latitude, pin!.longitude, label));
    if (mounted) {
      toast(context, 'Address saved');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.initial == null ? 'Add delivery address' : 'Edit delivery address')),
      body: SafeArea(
          child: Form(
              key: form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Wrap(spacing: 8, children: [
                  for (final l in ['Home', 'Work', 'Other'])
                    ChoiceChip(
                        label: Text(l),
                        selected: label == l,
                        onSelected: (_) => setState(() => label = l))
                ]),
                const SizedBox(height: 8),
                if (legacyMode) ...[
                  Field(legacy, 'Full address', lines: 3,
                      hint: 'House number, street, locality, city and PIN code',
                      validate: (v) => v.length < 10 ? 'Enter the complete address (at least 10 characters)' : null),
                  TextButton(
                      onPressed: () => setState(() => legacyMode = false),
                      child: const Text('Re-enter as separate fields'))
                ] else ...[
                  Field(house, 'House / flat / floor no.',
                      hint: 'For example: H.No 214, 2nd floor',
                      capitalization: TextCapitalization.words,
                      maxLength: 80),
                  Field(street, 'Street, sector or area',
                      hint: 'For example: Sector 3, Delhi Road',
                      capitalization: TextCapitalization.words,
                      maxLength: 120,
                      validate: (v) => v.length < 3 ? 'Enter the street or area' : null),
                  Field(landmark, 'Landmark', requiredValue: false,
                      hint: 'Optional, e.g. near Tilak Nagar park',
                      capitalization: TextCapitalization.words,
                      maxLength: 80),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                        flex: 3,
                        child: Field(city, 'City',
                            capitalization: TextCapitalization.words,
                            maxLength: 40,
                            validate: (v) => v.length < 2 ? 'Enter the city' : null)),
                    const SizedBox(width: 10),
                    Expanded(
                        flex: 2,
                        child: Field(pincode, 'PIN code',
                            keyboard: TextInputType.number,
                            maxLength: 6,
                            validate: (v) => RegExp(r'^\d{6}$').hasMatch(v) ? null : '6 digits')),
                  ]),
                ],
                Field(instructions, 'Delivery instructions', requiredValue: false,
                    hint: 'Optional, e.g. ring the bell twice', maxLength: 200),
                const SizedBox(height: 8),
                Text('Delivery point on map *', style: context.text.titleMedium),
                const SizedBox(height: 8),
                LocationPicker(
                    initial: pin, onChanged: (p) => setState(() => pin = p)),
                const SizedBox(height: 16),
                if (problem != null)
                  Notice(problem!, icon: Icons.error_outline, color: danger),
                ActionButton('Save address', save, icon: Icons.check),
                const SizedBox(height: 24),
              ]))));
}
