import 'models.dart';

/// Deterministic mock attendance for UI development (Jan 2026 focus).
class AttendanceMockData {
  AttendanceMockData._();

  static final DateTime seedMonth = DateTime(2026, 1);

  static final Map<String, AttendanceDay> _overrides = {
    _key(DateTime(2026, 1, 1)): _day(
      DateTime(2026, 1, 1),
      AttendanceStatus.present,
      '09:00',
      '05:00',
      '08:00 hrs',
      'Present',
    ),
    _key(DateTime(2026, 1, 2)): _day(
      DateTime(2026, 1, 2),
      AttendanceStatus.present,
      '09:05',
      '05:00',
      '07:55 hrs',
      'Present',
    ),
    _key(DateTime(2026, 1, 5)): _day(
      DateTime(2026, 1, 5),
      AttendanceStatus.present,
      '08:55',
      '05:10',
      '08:15 hrs',
      'Present',
    ),
    _key(DateTime(2026, 1, 6)): _day(
      DateTime(2026, 1, 6),
      AttendanceStatus.present,
      '09:00',
      '05:00',
      '08:00 hrs',
      'Present',
    ),
    _key(DateTime(2026, 1, 7)): _day(
      DateTime(2026, 1, 7),
      AttendanceStatus.late,
      '09:20',
      '05:00',
      '00:20 hrs',
      'Late',
    ),
    _key(DateTime(2026, 1, 8)): _day(
      DateTime(2026, 1, 8),
      AttendanceStatus.present,
      '08:50',
      '05:00',
      '08:10 hrs',
      'Present',
    ),
    _key(DateTime(2026, 1, 9)): _day(
      DateTime(2026, 1, 9),
      AttendanceStatus.overtime,
      '09:00',
      '06:00',
      '01:00 hrs',
      'Overtime',
    ),
    _key(DateTime(2026, 1, 12)): _day(
      DateTime(2026, 1, 12),
      AttendanceStatus.present,
      '09:00',
      '05:00',
      '08:00 hrs',
      'Present',
    ),
    _key(DateTime(2026, 1, 13)): _day(
      DateTime(2026, 1, 13),
      AttendanceStatus.present,
      '08:58',
      '05:02',
      '08:04 hrs',
      'Present',
    ),
    _key(DateTime(2026, 1, 14)): _day(
      DateTime(2026, 1, 14),
      AttendanceStatus.absent,
    ),
    _key(DateTime(2026, 1, 15)): _day(
      DateTime(2026, 1, 15),
      AttendanceStatus.present,
      '09:00',
      '05:00',
      '08:00 hrs',
      'Present',
    ),
    _key(DateTime(2026, 1, 16)): _day(
      DateTime(2026, 1, 16),
      AttendanceStatus.present,
      '09:00',
      '05:00',
      '08:00 hrs',
      'Present',
    ),
    // Week shown in mock: 18–24 Jan 2026
    _key(DateTime(2026, 1, 18)): _day(
      DateTime(2026, 1, 18),
      AttendanceStatus.present,
      '09:00',
      '05:00',
      '08:00 hrs',
      'Present',
    ),
    _key(DateTime(2026, 1, 19)): _day(
      DateTime(2026, 1, 19),
      AttendanceStatus.late,
      '09:15',
      '05:00',
      '00:15 hrs',
      'Late',
    ),
    _key(DateTime(2026, 1, 20)): _day(
      DateTime(2026, 1, 20),
      AttendanceStatus.late,
      '09:30',
      '05:00',
      '00:30 hrs',
      'Late',
    ),
    _key(DateTime(2026, 1, 21)): _day(
      DateTime(2026, 1, 21),
      AttendanceStatus.overtime,
      '09:00',
      '05:30',
      '00:30 hrs',
      'Overtime',
    ),
    _key(DateTime(2026, 1, 22)): _day(
      DateTime(2026, 1, 22),
      AttendanceStatus.present,
      '08:45',
      '05:00',
      '08:15 hrs',
      'Present',
    ),
    _key(DateTime(2026, 1, 23)): _weekend(DateTime(2026, 1, 23)),
    _key(DateTime(2026, 1, 24)): _weekend(DateTime(2026, 1, 24)),
    // Week shown in Shift mock: 25–31 Jan 2026
    _key(DateTime(2026, 1, 25)): _day(
      DateTime(2026, 1, 25),
      AttendanceStatus.present,
      '09:00',
      '05:00',
      '08:00 hrs',
      'Present',
    ),
    _key(DateTime(2026, 1, 26)): _day(
      DateTime(2026, 1, 26),
      AttendanceStatus.present,
      '09:00',
      '05:00',
      '08:00 hrs',
      'Present',
    ),
    _key(DateTime(2026, 1, 27)): _day(
      DateTime(2026, 1, 27),
      AttendanceStatus.overtime,
      '09:00',
      '06:30',
      '09:30 hrs',
      'Overtime',
      '01:30 hrs',
    ),
    _key(DateTime(2026, 1, 28)): _day(
      DateTime(2026, 1, 28),
      AttendanceStatus.none,
    ),
    _key(DateTime(2026, 1, 29)): _day(
      DateTime(2026, 1, 29),
      AttendanceStatus.none,
    ),
    _key(DateTime(2026, 1, 30)): _weekend(DateTime(2026, 1, 30)),
    _key(DateTime(2026, 1, 31)): _weekend(DateTime(2026, 1, 31)),
  };

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static AttendanceDay _day(
    DateTime date,
    AttendanceStatus status, [
    String? clockIn,
    String? clockOut,
    String? worked,
    String? detail,
    String? overtime,
  ]) {
    return AttendanceDay(
      date: DateTime(date.year, date.month, date.day),
      status: status,
      clockIn: clockIn,
      clockOut: clockOut,
      workedLabel: worked,
      statusDetail: detail,
      // API-shaped defaults: shift_name + employee-shift-schedules times.
      shiftName: 'General',
      shiftStart: '09:00',
      shiftEnd: '05:00',
      overtimeLabel: overtime,
    );
  }

  static AttendanceDay _weekend(DateTime date) {
    return AttendanceDay(
      date: DateTime(date.year, date.month, date.day),
      status: AttendanceStatus.weekend,
      clockIn: '00:00',
      clockOut: '00:00',
      workedLabel: '00:00 hrs',
      statusDetail: 'Weekend',
      shiftName: 'General',
      shiftStart: '09:00',
      shiftEnd: '05:00',
    );
  }

  static AttendanceDay forDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final override = _overrides[_key(d)];
    if (override != null) return override;

    // Fri/Sat as weekend to match mock calendar off-days.
    if (d.weekday == DateTime.friday || d.weekday == DateTime.saturday) {
      return _weekend(d);
    }

    // Deterministic filler for other weekdays.
    final seed = d.day % 5;
    if (seed == 0) {
      return _day(d, AttendanceStatus.absent);
    }
    if (seed == 1) {
      return _day(d, AttendanceStatus.late, '09:18', '05:00', '00:18 hrs', 'Late');
    }
    if (seed == 2) {
      return _day(d, AttendanceStatus.overtime, '09:00', '05:45', '00:45 hrs', 'Overtime');
    }
    return _day(d, AttendanceStatus.present, '09:00', '05:00', '08:00 hrs', 'Present');
  }

  static List<AttendanceDay> forWeek(DateTime weekStart) {
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    return List.generate(7, (i) => forDate(start.add(Duration(days: i))));
  }

  static List<AttendanceDay> forMonth(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    return List.generate(daysInMonth, (i) => forDate(first.add(Duration(days: i))));
  }

  static AttendanceMonthStats monthStats(DateTime month) {
    final days = forMonth(month);
    var present = 0;
    var absent = 0;
    var lateMins = 0;
    var otHours = 0;

    for (final day in days) {
      switch (day.status) {
        case AttendanceStatus.present:
          present++;
        case AttendanceStatus.late:
          present++;
          lateMins += _parseWorkedMinutes(day.workedLabel) ?? 15;
        case AttendanceStatus.overtime:
          present++;
          otHours += ((_parseWorkedMinutes(day.workedLabel) ?? 30) / 60).ceil();
        case AttendanceStatus.absent:
          absent++;
        case AttendanceStatus.weekend:
        case AttendanceStatus.none:
          break;
      }
    }

    // Align January 2026 with the mock stats strip.
    if (month.year == 2026 && month.month == 1) {
      return const AttendanceMonthStats(
        presentDays: 21,
        absentDays: 3,
        lateMinutes: 45,
        overtimeHours: 2,
      );
    }

    return AttendanceMonthStats(
      presentDays: present,
      absentDays: absent,
      lateMinutes: lateMins,
      overtimeHours: otHours,
    );
  }

  static String weekTotalWorked(DateTime weekStart) {
    if (weekStart.year == 2026 &&
        weekStart.month == 1 &&
        weekStart.day == 18) {
      return '32h 20m';
    }

    var totalMins = 0;
    for (final day in forWeek(weekStart)) {
      totalMins += _parseWorkedMinutes(day.workedLabel) ?? 0;
      if (day.status == AttendanceStatus.present && day.workedLabel == null) {
        totalMins += 8 * 60;
      }
    }
    final h = totalMins ~/ 60;
    final m = totalMins % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  static String monthTotalWorked(DateTime month) {
    if (month.year == 2026 && month.month == 1) {
      return '168h 40m';
    }
    var totalMins = 0;
    for (final day in forMonth(month)) {
      totalMins += _parseWorkedMinutes(day.workedLabel) ?? 0;
    }
    final h = totalMins ~/ 60;
    final m = totalMins % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  static int? _parseWorkedMinutes(String? label) {
    if (label == null) return null;
    final match = RegExp(r'(\d+):(\d+)').firstMatch(label);
    if (match == null) return null;
    final h = int.tryParse(match.group(1)!) ?? 0;
    final m = int.tryParse(match.group(2)!) ?? 0;
    return h * 60 + m;
  }
}
