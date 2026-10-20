import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:lanka_radar/app/motion.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/location.dart';
import 'package:lanka_radar/features/power/widgets/osm.dart';
import 'package:latlong2/latlong.dart';

/// Puts a place on the map: move the map under the pin; gives the point
/// picked.
class MapPickerPage extends StatefulWidget {
  const MapPickerPage({
    required this.locate,
    required this.name,
    this.initial,
    super.key,
  });

  static Route<GeoPoint> route({
    required Locate locate,
    required String name,
    GeoPoint? initial,
  }) => MaterialPageRoute(
    builder: (context) =>
        MapPickerPage(locate: locate, name: name, initial: initial),
  );

  /// Closer than this, the pin can go on a building, as a cut's lines need.
  static const pickZoom = 15.0;

  /// Where the map goes to show a place.
  static const closeZoom = 17.0;

  final Locate locate;

  /// The place's name, for the panel's title.
  final String name;
  final GeoPoint? initial;

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage>
    with SingleTickerProviderStateMixin {
  final _map = MapController();
  late final AnimationController _glide;
  (LatLng, double) _glideFrom = (sriLanka, 7.4);
  (LatLng, double) _glideTarget = (sriLanka, 7.4);
  bool _moving = false;
  bool _locating = false;
  late double _zoom = widget.initial == null ? 7.4 : MapPickerPage.closeZoom;

  @override
  void initState() {
    super.initState();
    _glide = AnimationController(vsync: this)..addListener(_onGlideTick);
    // A new place starts from where the phone is, if it can tell.
    if (widget.initial == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_locate(quiet: true)),
      );
    }
  }

  @override
  void dispose() {
    _glide.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _locate({bool quiet = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _locating = true);
    try {
      final point = await widget.locate();
      if (mounted) {
        _glideTo(latLng(point), MapPickerPage.closeZoom);
      }
    } on LocateException catch (error) {
      if (!quiet) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(locateMessage(error.failure))));
      }
    } finally {
      if (mounted) {
        setState(() => _locating = false);
      }
    }
  }

  void _glideTo(LatLng target, double zoom) {
    final duration = Motion.of(context, Motion.glide);
    if (duration == Duration.zero) {
      _map.move(target, zoom);
      return;
    }
    final from = _map.camera;
    _glideFrom = (from.center, from.zoom);
    _glideTarget = (target, zoom);
    _glide
      ..duration = duration
      ..forward(from: 0);
  }

  void _onGlideTick() {
    final (fromCenter, fromZoom) = _glideFrom;
    final (toCenter, toZoom) = _glideTarget;
    final t = Curves.easeInOutCubic.transform(_glide.value);
    double between(double from, double to) => from + (to - from) * t;
    _map.move(
      LatLng(
        between(fromCenter.latitude, toCenter.latitude),
        between(fromCenter.longitude, toCenter.longitude),
      ),
      between(fromZoom, toZoom),
    );
  }

  void _onMapEvent(MapEvent event) {
    final moving = switch (event) {
      MapEventMoveStart(source: != MapEventSource.mapController) ||
      MapEventFlingAnimationStart() => true,
      MapEventMoveEnd() ||
      MapEventFlingAnimationEnd() ||
      MapEventFlingAnimationNotStarted() => false,
      _ => _moving,
    };
    final zoom = event.camera.zoom;
    if (moving != _moving ||
        (zoom >= MapPickerPage.pickZoom) != (_zoom >= MapPickerPage.pickZoom)) {
      setState(() {
        _moving = moving;
        _zoom = zoom;
      });
    } else {
      _zoom = zoom;
    }
  }

  @override
  Widget build(BuildContext context) {
    final close = _zoom >= MapPickerPage.pickZoom;
    final initial = widget.initial;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: initial == null ? sriLanka : latLng(initial),
                    initialZoom: _zoom,
                    minZoom: 6,
                    maxZoom: 18,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                    onMapEvent: _onMapEvent,
                  ),
                  children: [const OsmTileLayer(), const OsmAttribution()],
                ),
                IgnorePointer(
                  child: Center(child: _Pin(lifted: _moving)),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: IconButton.filledTonal(
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.small(
                    heroTag: null,
                    tooltip: 'My location',
                    onPressed: _locating ? null : () => unawaited(_locate()),
                    child: AnimatedSwitcher(
                      duration: Motion.of(context, Motion.short),
                      child: _locating
                          ? const SizedBox.square(
                              key: ValueKey('locating'),
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.my_location,
                              key: ValueKey('icon'),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _BottomPanel(
            name: widget.name,
            close: close,
            onDone: () =>
                Navigator.of(context).pop(geoPoint(_map.camera.center)),
          ),
        ],
      ),
    );
  }
}

/// The pin marks the map's center. It lifts while you drag the map and drops
/// back when you let go, with a shadow on the exact spot.
class _Pin extends StatelessWidget {
  const _Pin({required this.lifted});

  final bool lifted;

  static const _size = 48.0;
  static const _lift = 14.0;

  @override
  Widget build(BuildContext context) {
    final duration = Motion.of(context, Motion.short);
    // The pin's tip sits 22/24 down its icon box. Lift it onto the center.
    final tipOffset = -_size * (22 / 24 - 0.5);
    return SizedBox.square(
      dimension: _size * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: duration,
            width: lifted ? 14 : 8,
            height: lifted ? 5 : 3,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: lifted ? 0.18 : 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          AnimatedSlide(
            duration: duration,
            curve: Curves.easeOutCubic,
            offset: Offset(0, (tipOffset - (lifted ? _lift : 0)) / _size),
            child: Icon(
              Icons.location_on,
              size: _size,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.name,
    required this.close,
    required this.onDone,
  });

  final String name;

  /// Zoomed in enough to put the pin on a building.
  final bool close;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final medium = Motion.of(context, Motion.medium);
    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      elevation: 3,
      shadowColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Where is $name?', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              AnimatedSwitcher(
                duration: medium,
                transitionBuilder: fadeRise,
                child: Text(
                  close
                      ? 'Put the pin on the building.'
                      : 'Zoom in and move the map under the pin.',
                  key: ValueKey(close),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: close ? onDone : null,
                child: const Text('Use this spot'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What to tell the user when the phone's location couldn't be read.
String locateMessage(LocateFailure failure) => switch (failure) {
  LocateFailure.off => 'Location is off. Turn it on and try again.',
  LocateFailure.denied => 'Allow location for Lanka Radar to use it.',
  LocateFailure.timeout => "Couldn't find the phone. Try again outdoors.",
};
