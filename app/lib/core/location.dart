import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';

/// Why the phone's place couldn't be read.
enum LocateFailure { off, denied, timeout }

class LocateException implements Exception {
  const LocateException(this.failure);

  final LocateFailure failure;

  @override
  String toString() => 'Location failed: ${failure.name}';
}

/// Reads where the phone is, asking for the location permission first if need
/// be; throws a [LocateException] when it can't.
typedef Locate = Future<GeoPoint> Function();

Future<GeoPoint> locatePhone() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocateException(LocateFailure.off);
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw const LocateException(LocateFailure.denied);
  }
  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        timeLimit: Duration(seconds: 30),
      ),
    );
    return (lat: position.latitude, lon: position.longitude);
  } on TimeoutException {
    throw const LocateException(LocateFailure.timeout);
  }
}
