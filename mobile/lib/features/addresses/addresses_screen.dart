import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
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
    return RemoteList(
        key: ValueKey(generation),
        title: 'Saved addresses',
        load: (p) => repo.rows('user_addresses',
            filters: {'user_id': repo.uid}, page: p),
        header: [
          ActionButton('Add address', () async {
            await showAddressEditor(context, ref);
            if (mounted) setState(() => generation++);
          })
        ],
        item: (j, reload) => Card(
            child: ListTile(
                title: Text(j['label'] ?? 'Address'),
                subtitle: Text(j['formatted_address']),
                trailing: Wrap(children: [
                  IconButton(
                      tooltip: 'Edit address',
                      onPressed: () async {
                        await showAddressEditor(context, ref, initial: j);
                        reload();
                      },
                      icon: const Icon(Icons.edit_outlined)),
                  IconButton(
                      tooltip: 'Delete address',
                      onPressed: () async {
                        if (await perform(context,
                            () => repo.remove('user_addresses', j['id']))) {
                          reload();
                        }
                      },
                      icon: const Icon(Icons.delete_outline))
                ]))));
  }
}

Future<void> showAddressEditor(BuildContext context, WidgetRef ref,
        {Json? initial}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AddressEditor(initial: initial)));

class AddressEditor extends ConsumerStatefulWidget {
  final Json? initial;
  const AddressEditor({this.initial, super.key});
  @override
  ConsumerState<AddressEditor> createState() => _AddressEditorState();
}

class _AddressEditorState extends ConsumerState<AddressEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController label,
      address,
      instructions,
      latitude,
      longitude;
  LatLng? pin;
  @override
  void initState() {
    super.initState();
    final j = widget.initial;
    label = TextEditingController(text: j?['label'] ?? 'Home');
    address = TextEditingController(text: j?['formatted_address']);
    instructions = TextEditingController(text: j?['instructions']);
    latitude = TextEditingController(text: j?['latitude']?.toString());
    longitude = TextEditingController(text: j?['longitude']?.toString());
    if (j != null) {
      pin = LatLng(decimal(j['latitude']), decimal(j['longitude']));
    }
  }

  @override
  void dispose() {
    for (final c in [label, address, instructions, latitude, longitude]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Delivery address')),
      body: SafeArea(
          child: Form(
              key: form,
              child: ListView(padding: const EdgeInsets.all(20), children: [
                Field(label, 'Label'),
                Field(address, 'House, street, locality and postcode',
                    lines: 3),
                Field(instructions, 'Delivery instructions',
                    requiredValue: false),
                const SizedBox(height: 12),
                const Text(
                    'Tap your delivery point on the map, or enter coordinates from a known address. No device location is collected.'),
                const SizedBox(height: 12),
                SizedBox(
                    height: 300,
                    child: FlutterMap(
                        options: MapOptions(
                            initialCenter:
                                pin ?? const LatLng(28.8955, 76.6066),
                            initialZoom: 14,
                            onTap: (_, point) => setState(() {
                                  pin = point;
                                  latitude.text =
                                      point.latitude.toStringAsFixed(6);
                                  longitude.text =
                                      point.longitude.toStringAsFixed(6);
                                })),
                        children: [
                          TileLayer(
                              urlTemplate: const String.fromEnvironment(
                                  'MAP_TILE_URL',
                                  defaultValue:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                              userAgentPackageName: 'com.dastak.app'),
                          if (pin != null)
                            MarkerLayer(markers: [
                              Marker(
                                  point: pin!,
                                  child: const Icon(Icons.location_pin,
                                      size: 42, color: Color(0xFFEA580C)))
                            ]),
                          RichAttributionWidget(attributions: [
                            TextSourceAttribution('OpenStreetMap contributors',
                                onTap: () => launchUrl(Uri.parse(
                                    'https://www.openstreetmap.org/copyright')))
                          ])
                        ])),
                Field(latitude, 'Latitude',
                    keyboard: const TextInputType.numberWithOptions(
                        decimal: true, signed: true)),
                Field(longitude, 'Longitude',
                    keyboard: const TextInputType.numberWithOptions(
                        decimal: true, signed: true)),
                ActionButton('Save address', () async {
                  if (!form.currentState!.validate()) return;
                  final lat = double.tryParse(latitude.text),
                      lng = double.tryParse(longitude.text);
                  if (!validCoordinates(lat, lng) ||
                      address.text.trim().length < 8) {
                    throw StateError(
                        'Enter a complete address and select a valid delivery pin');
                  }
                  final repo = ref.read(repositoryProvider);
                  await repo.save(
                      'user_addresses',
                      {
                        'user_id': repo.uid,
                        'label': label.text.trim(),
                        'formatted_address': address.text.trim(),
                        'instructions': instructions.text.trim(),
                        'latitude': lat,
                        'longitude': lng
                      },
                      id: widget.initial?['id']);
                  if (context.mounted) Navigator.pop(context);
                }),
              ]))));
}
