import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/links.dart';
import 'package:latlong2/latlong.dart';

/// Sri Lanka's middle, where a map starts when a place has no point yet.
const sriLanka = LatLng(7.87, 80.70);

LatLng latLng(GeoPoint point) => LatLng(point.lat, point.lon);

GeoPoint geoPoint(LatLng point) => (lat: point.latitude, lon: point.longitude);

/// Switches map tiles off below it. Tests use it so nothing is fetched over
/// the network.
class NoMapTiles extends InheritedWidget {
  const NoMapTiles({required super.child, super.key});

  static bool _isAbove(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NoMapTiles>() != null;

  @override
  bool updateShouldNotify(NoMapTiles oldWidget) => false;
}

/// OpenStreetMap's standard tiles. Its tile policy asks for an identifying
/// user agent and visible attribution, see [OsmAttribution].
class OsmTileLayer extends StatelessWidget {
  const OsmTileLayer({super.key});

  @override
  Widget build(BuildContext context) {
    if (NoMapTiles._isAbove(context)) {
      return const SizedBox.shrink();
    }
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'app.lankaradar',
    );
  }
}

/// The OpenStreetMap credit its license requires, linking to the license.
class OsmAttribution extends StatelessWidget {
  const OsmAttribution({
    this.alignment = Alignment.bottomLeft,
    this.compact = false,
    super.key,
  });

  final Alignment alignment;

  /// The short form, as small text on the map without a box, for small maps.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (compact) {
      return Align(
        alignment: alignment,
        child: GestureDetector(
          onTap: () => openExternally(
            Uri.parse('https://www.openstreetmap.org/copyright'),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Text(
              '\u00a9 OpenStreetMap',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: Colors.black87,
                shadows: const [Shadow(color: Colors.white, blurRadius: 4)],
              ),
            ),
          ),
        ),
      );
    }
    final shape = BorderRadius.circular(4);
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: theme.colorScheme.surface.withValues(alpha: 0.85),
          borderRadius: shape,
          child: InkWell(
            borderRadius: shape,
            onTap: () => openExternally(
              Uri.parse('https://www.openstreetmap.org/copyright'),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                '\u00a9 OpenStreetMap contributors',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
