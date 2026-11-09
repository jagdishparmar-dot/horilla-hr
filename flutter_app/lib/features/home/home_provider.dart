import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../attendance/attendance_provider.dart';
import 'home_repository.dart';
import 'models.dart';

final mobileHomeProvider = FutureProvider.autoDispose<MobileHome>((ref) async {
  return ref.watch(homeRepositoryProvider).fetchHome();
});

final punchBusyProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Live distance from the fence returned by `GET /mobile/home/`.
/// Null when this employee is not geofenced.
final punchFenceProvider = FutureProvider.autoDispose<FenceFix?>((ref) async {
  final home = await ref.watch(mobileHomeProvider.future);
  if (!home.geofenceEnabled ||
      home.geofenceLatitude == null ||
      home.geofenceLongitude == null ||
      home.geofenceRadiusMeters == null) {
    return null;
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw Exception('Location permission is required to punch at this site.');
  }
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw Exception('Turn on GPS to punch at this site.');
  }

  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 12),
    ),
  );
  final meters = Geolocator.distanceBetween(
    position.latitude,
    position.longitude,
    home.geofenceLatitude!,
    home.geofenceLongitude!,
  );
  final allowed = home.geofenceRadiusMeters!;
  final name = (home.geofenceName ?? 'work site').trim();
  final inside = meters <= allowed;
  return FenceFix(
    inside: inside,
    distanceMeters: meters,
    label: inside
        ? 'Inside $name · ${formatMeters(meters)}'
        : 'Outside $name · ${formatMeters(meters)} (allowed ${formatMeters(allowed.toDouble())})',
  );
});

class FenceFix {
  const FenceFix({
    required this.inside,
    required this.distanceMeters,
    required this.label,
  });

  final bool inside;
  final double distanceMeters;
  final String label;
}

String formatMeters(double meters) {
  if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
  return '${meters.round()} m';
}

final punchActionProvider = Provider<PunchActions>((ref) {
  return PunchActions(ref);
});

class PunchActions {
  PunchActions(this._ref);

  final Ref _ref;

  Future<String?> togglePunch(MobileHome home) async {
    final busy = _ref.read(punchBusyProvider.notifier);
    busy.state = true;
    try {
      final repo = _ref.read(homeRepositoryProvider);
      if (home.isClockedIn) {
        await repo.clockOut(sendLocation: home.geofenceEnabled);
      } else {
        await repo.clockIn(sendLocation: home.geofenceEnabled);
      }
      _ref.invalidate(mobileHomeProvider);
      _ref.invalidate(punchFenceProvider);
      // Punch changes today's attendance row used by the Attendance tab.
      invalidateAttendance(_ref);
      return null;
    } catch (e) {
      final text = e.toString();
      return text.startsWith('Exception: ') ? text.substring(11) : text;
    } finally {
      busy.state = false;
    }
  }
}
