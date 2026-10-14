import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';
import 'location.dart';

/// Set at build time only when a Maps SDK key is configured; otherwise OpenStreetMap is used.
const useGoogleMaps = bool.fromEnvironment('GOOGLE_MAPS_ENABLED');

class MapPin {
  final LatLng point;
  final IconData icon;
  final Color color;
  final String label;
  const MapPin(this.point, this.icon, this.color, this.label);
}

class AppMap extends StatefulWidget {
  final LatLng center;
  final double zoom;
  final List<MapPin> pins;
  final ValueChanged<LatLng>? onTap;

  /// When two or more points are given, the camera frames all of them.
  final List<LatLng> fit;
  const AppMap(
      {required this.center, this.zoom = 14, this.pins = const [], this.onTap, this.fit = const [], super.key});
  @override
  State<AppMap> createState() => AppMapState();
}

class AppMapState extends State<AppMap> {
  final osm = MapController();
  gm.GoogleMapController? google;

  static gm.LatLng _g(LatLng p) => gm.LatLng(p.latitude, p.longitude);

  void moveTo(LatLng point, double zoom) {
    if (useGoogleMaps) {
      google?.animateCamera(gm.CameraUpdate.newLatLngZoom(_g(point), zoom));
    } else {
      try {
        osm.move(point, zoom);
      } catch (_) {
        // The map may not be laid out yet; the pin is still saved.
      }
    }
  }

  gm.LatLngBounds _bounds(List<LatLng> points) {
    final lats = points.map((p) => p.latitude), lngs = points.map((p) => p.longitude);
    return gm.LatLngBounds(
        southwest: gm.LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
        northeast: gm.LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)));
  }

  @override
  void dispose() {
    google?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (useGoogleMaps) {
      return gm.GoogleMap(
          initialCameraPosition: gm.CameraPosition(target: _g(widget.center), zoom: widget.zoom),
          markers: {
            for (final (i, p) in widget.pins.indexed)
              gm.Marker(
                  markerId: gm.MarkerId('$i'),
                  position: _g(p.point),
                  infoWindow: gm.InfoWindow(title: p.label),
                  icon: gm.BitmapDescriptor.defaultMarkerWithHue(HSVColor.fromColor(p.color).hue))
          },
          onTap: widget.onTap == null ? null : (x) => widget.onTap!(LatLng(x.latitude, x.longitude)),
          onMapCreated: (controller) {
            google = controller;
            if (widget.fit.length > 1) {
              Future<void>.delayed(const Duration(milliseconds: 300), () {
                if (mounted) controller.animateCamera(gm.CameraUpdate.newLatLngBounds(_bounds(widget.fit), 48));
              });
            }
          },
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
          // Inside scrolling pages the map keeps its own pan and pinch gestures.
          gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())});
    }
    return FlutterMap(
        mapController: osm,
        options: MapOptions(
            initialCenter: widget.center,
            initialZoom: widget.zoom,
            initialCameraFit: widget.fit.length > 1
                ? CameraFit.coordinates(coordinates: widget.fit, padding: const EdgeInsets.all(40), maxZoom: 16)
                : null,
            onTap: widget.onTap == null ? null : (_, point) => widget.onTap!(point)),
        children: [
          osmTiles(),
          MarkerLayer(markers: [for (final p in widget.pins) pinMarker(p.point, p.icon, p.color, label: p.label)]),
          osmAttribution()
        ]);
  }
}
