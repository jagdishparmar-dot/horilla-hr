import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final attendanceRecordsProvider =
    FutureProvider.autoDispose.family<List<AttendanceRecord>, _DateRange>((
  ref,
  range,
) async {
  return ref.watch(attendanceRepositoryProvider).fetchMyAttendance(
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
  return ref.watch(attendanceRecordsProvider(range)).whenData(
        (records) => buildDaysForRange(
          from: range.from,
          to: range.to,
          records: records,
        ),
      );
});

final attendanceMonthDaysProvider =
    Provider.autoDispose<AsyncValue<List<AttendanceDay>>>((ref) {
  final month = ref.watch(attendanceMonthProvider);
  final range = _monthRange(month);
  return ref.watch(attendanceRecordsProvider(range)).whenData(
        (records) => buildDaysForRange(
          from: range.from,
          to: range.to,
          records: records,
        ),
      );
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
  ref.invalidate(attendanceRecordsProvider);
}
