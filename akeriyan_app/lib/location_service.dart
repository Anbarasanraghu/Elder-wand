import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Provides the phone's current location so the backend can give weather /
/// briefings for wherever you actually are (instead of the default city).
///
/// Fast + resilient: caches the last fix, prefers a quick "last known"
/// position, and never throws — returns null if location is unavailable so the
/// backend simply falls back to the default city.
class LocationService {
  static Position? _cached;

  static Future<Position?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return _cached;

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return _cached;
      }

      // A cached OS fix is instant; good enough for city-level weather.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) _cached = last;

      // Also try a fresh low-accuracy fix, but don't block the command for long.
      try {
        final fresh = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 6),
          ),
        );
        _cached = fresh;
      } catch (_) {
        // Timeout / transient error — keep whatever we already have.
      }

      return _cached;
    } catch (e) {
      debugPrint('[LOC] error: $e');
      return _cached;
    }
  }
}
