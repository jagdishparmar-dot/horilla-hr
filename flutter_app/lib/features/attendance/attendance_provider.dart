import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/models.dart';
import 'attendance_mapper.dart';
import 'attendance_repository.dart';
import 'models.dart';

/// Sunday-start week containing [date].
DateTime weekStartOf(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  return d.subtract(Duration(days: d.weekday % 7));
}

class _DateRange {
  const _DateRange(this.from, this.to);

  final DateTime from;
  final DateTime to;

  @override
  bool operator ==(Object other) =>
      other is _DateRange &&
      other.from.year == from.year &&
      other.from.month == from.month &&
      other.from.day == from.day &&
      other.to.year == to.year &&
      other.to.month == to.month &&
      other.to.day == to.day;

  @override
  int get hashCode => Object.hash(from.year, from.month, from.day, to.year, to.month, to.day);
}

final attendanceViewModeProvider =
    StateProvider<AttendanceViewMode>((ref) => AttendanceViewMode.list);

final attendanceSegmentProvider =
    StateProvider<AttendanceSegment>((ref) => AttendanceSegment.summary);

final attendanceWeekStartProvider = StateProvider<DateTime>((ref) {
  return weekStartOf(DateTime.now());
});

final attendanceMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

final attendanceSelectedDayProvider = StateProvider<DateTime>((ref) {
  return DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
});

final attendanceRangeProvider =
    FutureProvider.autoDispose.family<AttendanceRangePayload, _DateRange>((
  ref,
  range,
) async {
  return ref.watch(attendanceRepositoryProvider).fetchMyAttendance(
        from: range.from,
        to: range.to,
      );
});

final workScheduleProvider =
    FutureProvider.autoDispose.family<HomeWorkSchedule, _DateRange>((
  ref,
  range,
) async {
  return ref.watch(attendanceRepositoryProvider).fetchWorkSchedule(
        from: range.from,
        to: range.to,
      );
});

_DateRange _weekRange(DateTime weekStart) {
  final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
  return _DateRange(start, start.add(const Duration(days: 6)));
}

_DateRange _monthRange(DateTime month) {
  final start = DateTime(month.year, month.month, 1);
  final end = DateTime(month.year, month.month + 1, 0);
  return _DateRange(start, end);
}

final attendanceWeekDaysProvider =
    Provider.autoDispose<AsyncValue<List<AttendanceDay>>>((ref) {
  final start = ref.watch(attendanceWeekStartProvider);
  final range = _weekRange(start);
  final payload = ref.watch(attendanceRangeProvider(range));
  final schedule = ref.watch(workScheduleProvider(range));
  return _combineAsync(payload, schedule, (bundle, roster) {
    return buildDaysForRange(
      from: range.from,
      to: range.to,
      records: bundle.records,
      context: bundle.context,
      schedule: roster,
      today: _companyToday(roster),
    );
  });
});

/// Roster week with punches overlaid — the Shift tab, not Summary.
final attendanceShiftDaysProvider =
    Provider.autoDispose<AsyncValue<List<AttendanceDay>>>((ref) {
  final start = ref.watch(attendanceWeekStartProvider);
  final range = _weekRange(start);
  final payload = ref.watch(attendanceRangeProvider(range));
  final schedule = ref.watch(workScheduleProvider(range));
  return _combineAsync(payload, schedule, (bundle, roster) {
    return buildShiftDaysForRange(
      from: range.from,
      to: range.to,
      records: bundle.records,
      schedule: roster,
      context: bundle.context,
      today: _companyToday(roster),
    );
  });
});

DateTime _companyToday(HomeWorkSchedule roster) {
  final t = roster.companyToday;
  if (t != null) return DateTime(t.year, t.month, t.day);
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

AsyncValue<R> _combineAsync<A, B, R>(
  AsyncValue<A> a,
  AsyncValue<B> b,
  R Function(A a, B b) merge,
) {
  if (a.hasError) {
    return AsyncValue.error(a.error!, a.stackTrace ?? StackTrace.empty);
  }
  if (b.hasError) {
    return AsyncValue.error(b.error!, b.stackTrace ?? StackTrace.empty);
  }
  if (!a.hasValue || !b.hasValue) {
    return const AsyncValue.loading();
  }
  return AsyncValue.data(merge(a.requireValue, b.requireValue));
}

final attendanceMonthDaysProvider =
    Provider.autoDispose<AsyncValue<List<AttendanceDay>>>((ref) {
  final month = ref.watch(attendanceMonthProvider);
  final range = _monthRange(month);
  final payload = ref.watch(attendanceRangeProvider(range));
  final schedule = ref.watch(workScheduleProvider(range));
  return _combineAsync(payload, schedule, (bundle, roster) {
    return buildDaysForRange(
      from: range.from,
      to: range.to,
      records: bundle.records,
      context: bundle.context,
      schedule: roster,
      today: _companyToday(roster),
    );
  });
});

final attendanceMonthStatsProvider =
    Provider.autoDispose<AsyncValue<AttendanceMonthStats>>((ref) {
  return ref.watch(attendanceMonthDaysProvider).whenData(buildMonthStats);
});

final attendanceTotalWorkedProvider =
    Provider.autoDispose<AsyncValue<String>>((ref) {
  final mode = ref.watch(attendanceViewModeProvider);
  if (mode == AttendanceViewMode.list) {
    return ref.watch(attendanceWeekDaysProvider).whenData(formatTotalWorked);
  }
  return ref.watch(attendanceMonthDaysProvider).whenData(formatTotalWorked);
});

/// Invalidate cached attendance ranges after punch / refresh.
void invalidateAttendance(dynamic ref) {
  // Accepts both `Ref` (providers) and `WidgetRef` (widgets).
  // ignore: avoid_dynamic_calls
  ref.invalidate(attendanceRangeProvider);
  // ignore: avoid_dynamic_calls
  ref.invalidate(workScheduleProvider);
  try {
    // ignore: avoid_dynamic_calls
    ref.read(attendanceRepositoryProvider).clearScheduleCache();
  } catch (_) {}
}
