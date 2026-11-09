import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../attendance/attendance_provider.dart';
import 'home_repository.dart';
import 'models.dart';

final mobileHomeProvider = FutureProvider.autoDispose<MobileHome>((ref) async {
  return ref.watch(homeRepositoryProvider).fetchHome();
});

final punchBusyProvider = StateProvider.autoDispose<bool>((ref) => false);

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
      // Punch changes today's attendance row used by the Attendance tab.
      invalidateAttendance(_ref);
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      busy.state = false;
    }
  }
}
