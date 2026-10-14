import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_map.dart';
import 'providers.dart';
import 'theme.dart';
import 'widgets.dart';

const rohtakCenter = LatLng(28.8955, 76.6066);

class DeliveryPoint {
  final double lat, lng;
  final String label;
  const DeliveryPoint(this.lat, this.lng, this.label);
  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'label': label};
}

class DeliveryPointController extends StateNotifier<DeliveryPoint?> {
  final void Function(String?) persist;
  DeliveryPointController(super.initial, this.persist);
  void set(DeliveryPoint point) {
    state = point;
    persist(jsonEncode(point.toJson()));
  }

  void clear() {
    state = null;
    persist(null);
  }
}

final deliveryPointProvider =
    StateNotifierProvider<DeliveryPointController, DeliveryPoint?>((ref) {
  final prefs = ref.watch(preferencesProvider);
  DeliveryPoint? initial;
  try {
    final raw = prefs.getString('delivery_point');
    if (raw != null) {
      final j = jsonDecode(raw) as Map;
      initial = DeliveryPoint((j['lat'] as num).toDouble(),
          (j['lng'] as num).toDouble(), '${j['label']}');
    }
  } catch (_) {}
  return DeliveryPointController(initial, (value) {
    if (value == null) {
      prefs.remove('delivery_point');
    } else {
      prefs.setString('delivery_point', value);
    }
  });
});

/// Asks for permission only when the user taps a location action.
Future<LatLng> currentPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw StateError(
        'Location is turned off. Turn on GPS, or pick the point on the map.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever) {
    throw StateError(
        'Location permission is blocked. Allow it in phone settings, or pick the point on the map.');
  }
  if (permission == LocationPermission.denied) {
    throw StateError(
        'Location permission was not given. You can pick the point on the map instead.');
  }
  final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 20));
  return LatLng(pos.latitude, pos.longitude);
}

double straightKm(LatLng a, LatLng b) =>
    const Distance().as(LengthUnit.Meter, a, b) / 1000;

TileLayer osmTiles() => TileLayer(
    urlTemplate: const String.fromEnvironment('MAP_TILE_URL',
        defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
    userAgentPackageName: 'com.dastak.app');

Widget osmAttribution() => RichAttributionWidget(
        alignment: AttributionAlignment.bottomRight,
        showFlutterMapAttribution: false,
        popupInitialDisplayDuration: Duration.zero,
        attributions: [
          TextSourceAttribution('OpenStreetMap',
              onTap: () => launchUrl(
                  Uri.parse('https://www.openstreetmap.org/copyright')))
        ]);

Marker pinMarker(LatLng point, IconData icon, Color color, {String? label}) =>
    Marker(
        point: point,
        width: 44,
        height: 44,
        alignment: Alignment.topCenter,
        child: Tooltip(
            message: label ?? '',
            child: Icon(icon, size: 40, color: color, semanticLabel: label)));

/// Type-ahead address search. Hides itself when the server search is not available.
class AddressSearch extends ConsumerStatefulWidget {
  final LatLng? near;
  final void Function(LatLng point, String title, String description) onSelected;
  const AddressSearch({required this.onSelected, this.near, super.key});
  @override
  ConsumerState<AddressSearch> createState() => _AddressSearchState();
}

class _AddressSearchState extends ConsumerState<AddressSearch> {
  final text = TextEditingController();
  Timer? debounce;
  List<Map<String, dynamic>> results = [];
  bool busy = false, available = true;
  int ticket = 0;

  @override
  void dispose() {
    debounce?.cancel();
    text.dispose();
    super.dispose();
  }

  void changed(String value) {
    debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => results = []);
      return;
    }
    debounce = Timer(const Duration(milliseconds: 400), () => search(value.trim()));
  }

  Future<void> search(String value) async {
    final my = ++ticket;
    setState(() => busy = true);
    try {
      final near = widget.near ?? rohtakCenter;
      final found = await ref.read(repositoryProvider).searchPlaces(value, lat: near.latitude, lng: near.longitude);
      if (mounted && my == ticket) setState(() => results = found);
    } catch (_) {
      if (mounted) setState(() => available = false);
    } finally {
      if (mounted && my == ticket) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!available) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
          controller: text,
          onChanged: changed,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
              hintText: 'Search area, street or landmark',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: busy
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                  : (text.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () => setState(() {
                                text.clear();
                                results = [];
                              }),
                          icon: const Icon(Icons.close))))),
      for (final r in results)
        ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const Icon(Icons.place_outlined),
            title: Text('${r['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${r['subtitle']}', maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () {
              FocusScope.of(context).unfocus();
              widget.onSelected(LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble()), '${r['title']}',
                  '${r['description']}');
              setState(() {
                text.text = '${r['title']}';
                results = [];
              });
            }),
      const SizedBox(height: 8),
    ]);
  }
}

/// Map pin picker with "use current location". Manual tapping always works when GPS is denied.
class LocationPicker extends StatefulWidget {
  final LatLng? initial;
  final ValueChanged<LatLng> onChanged;
  final double height;
  final String hint;
  final void Function(String title, String description)? onAddressChosen;
  const LocationPicker(
      {required this.onChanged,
      this.onAddressChosen,
      this.initial,
      this.height = 260,
      this.hint = 'Tap the map to drop the pin exactly at the delivery point.',
      super.key});
  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  final map = GlobalKey<AppMapState>();
  LatLng? pin;
  bool locating = false;
  String? problem;

  @override
  void initState() {
    super.initState();
    pin = widget.initial;
  }

  void place(LatLng point, {bool move = false}) {
    setState(() {
      pin = point;
      problem = null;
    });
    widget.onChanged(point);
    if (move) map.currentState?.moveTo(point, 17);
  }

  Future<void> locate() async {
    setState(() {
      locating = true;
      problem = null;
    });
    try {
      place(await currentPosition(), move: true);
    } catch (e) {
      if (mounted) setState(() => problem = errorText(e));
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AddressSearch(
                near: pin,
                onSelected: (point, title, description) {
                  place(point, move: true);
                  widget.onAddressChosen?.call(title, description);
                }),
            OutlinedButton.icon(
                onPressed: locating ? null : locate,
                icon: locating
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location),
                label: Text(
                    locating ? 'Finding your location…' : 'Use my current location')),
            if (problem != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(problem!,
                      style: TextStyle(color: context.colors.error, fontSize: 13))),
            const SizedBox(height: 8),
            Text(widget.hint, style: TextStyle(color: context.muted, fontSize: 12)),
            const SizedBox(height: 8),
            ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                    height: widget.height,
                    child: AppMap(
                        key: map,
                        center: pin ?? rohtakCenter,
                        zoom: pin == null ? 13 : 16,
                        pins: [if (pin != null) MapPin(pin!, Icons.location_pin, brandBlue, 'Selected point')],
                        onTap: place))),
            const SizedBox(height: 6),
            Row(children: [
              Icon(pin == null ? Icons.error_outline : Icons.check_circle,
                  size: 16,
                  color: pin == null ? context.colors.error : success),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(
                      pin == null
                          ? 'No point selected yet'
                          : 'Pin set at ${pin!.latitude.toStringAsFixed(5)}, ${pin!.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(fontSize: 12)))
            ])
          ]);
}
