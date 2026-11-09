import '../home/models.dart';
import 'attendance_repository.dart';
import 'models.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _isWeekend(DateTime d) =>
    d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;

bool _isZeroDuration(String? value) {
  if (value == null || value.trim().isEmpty) return true;
  final parts = value.split(':');
  if (parts.isEmpty) return true;
  final h = int.tryParse(parts[0]) ?? 0;
  final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  final s = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;
  return h == 0 && m == 0 && s == 0;
}

int? parseHhMmToMinutes(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final match = RegExp(r'(\d+):(\d+)').firstMatch(value);
  if (match == null) return null;
  final h = int.tryParse(match.group(1)!) ?? 0;
  final m = int.tryParse(match.group(2)!) ?? 0;
  return h * 60 + m;
}

int secondsFromHhMm(String? value) {
  final mins = parseHhMmToMinutes(value);
  return mins == null ? 0 : mins * 60;
}

String formatHhMmFromSeconds(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

String formatSeconds(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  if (h == 0 && m == 0) return '0h 00m';
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

String formatWorkedLabel(String? workedHour, {int? seconds}) {
  if (seconds != null && seconds > 0) {
    return '${formatHhMmFromSeconds(seconds)} hrs';
  }
  if (workedHour == null || workedHour.trim().isEmpty) return '00:00 hrs';
  final parts = workedHour.split(':');
  if (parts.length >= 2) {
    return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')} hrs';
  }
  return '$workedHour hrs';
}

String formatTotalWorked(Iterable<AttendanceDay> days) {
  var total = 0;
  for (final day in days) {
    total += day.workedSeconds;
    if (day.workedSeconds == 0) {
      total += secondsFromHhMm(day.workedLabel);
    }
  }
  return formatSeconds(total);
}

/// Clock label, with the calendar date when it falls on another day (night shift).
String formatPunchClock(
  String? time,
  String? dateIso,
  DateTime attendanceDate,
) {
  if (time == null || time.isEmpty) return '--:--';
  final punchDate = DateTime.tryParse(dateIso ?? '');
  if (punchDate == null) return time;
  if (punchDate.year == attendanceDate.year &&
      punchDate.month == attendanceDate.month &&
      punchDate.day == attendanceDate.day) {
    return time;
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${punchDate.day} ${months[punchDate.month - 1]} $time';
}

String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

AttendanceDay mapRecordToDay(
  AttendanceRecord record, {
  AttendanceDayContext? context,
  DateTime? today,
}) {
  final date = _dateOnly(record.date);
  final now = _dateOnly(today ?? DateTime.now());
  final otSeconds = record.overtimeSeconds > 0
      ? record.overtimeSeconds
      : secondsFromHhMm(record.overtime);
  final hasOt = otSeconds > 0 || !_isZeroDuration(record.overtime);
  final approvedOt = hasOt && record.overtimeApproved;
  final pendingOt = hasOt && !record.overtimeApproved;
  final workedSeconds = record.atWorkSeconds > 0
      ? record.atWorkSeconds
      : secondsFromHhMm(record.workedHour);
  final short = !_isZeroDuration(record.hoursPending);
  final missingOut =
      record.clockIn != null && record.clockOut == null && date.isBefore(now);

  final AttendanceStatus status;
  final String? detail;
  String? workedLabel = workedSeconds > 0 || record.clockIn != null
      ? formatWorkedLabel(record.workedHour, seconds: workedSeconds)
      : null;

  if (missingOut) {
    status = AttendanceStatus.missingOut;
    detail = 'No clock-out';
  } else if (short && record.clockOut != null) {
    status = AttendanceStatus.shortHours;
    detail = 'Short hours';
  } else if (record.isLate) {
    status = AttendanceStatus.late;
    detail = 'Late';
  } else if (approvedOt) {
    status = AttendanceStatus.overtime;
    detail = 'Overtime';
  } else if (record.clockIn != null) {
    status = AttendanceStatus.present;
    detail = 'Present';
  } else if (context?.hasLeave == true) {
    status = AttendanceStatus.leave;
    detail = context!.leavePaid == false
        ? '${context.leaveName} (unpaid)'
        : context.leaveName;
    workedLabel = null;
  } else if (record.isHoliday || context?.isHoliday == true) {
    status = AttendanceStatus.holiday;
    detail = 'Holiday';
    workedLabel = null;
  } else if (context?.isCompanyLeave == true || _isWeekend(date)) {
    status = AttendanceStatus.weekend;
    detail = context?.isCompanyLeave == true ? 'Week off' : 'Weekend';
    workedLabel = null;
  } else {
    status = AttendanceStatus.absent;
    detail = 'Absent';
    workedLabel = null;
  }

  return AttendanceDay(
    date: date,
    status: status,
    clockIn: record.clockIn,
    clockOut: record.clockOut,
    clockInDate: record.clockInDate,
    clockOutDate: record.clockOutDate,
    workedLabel: workedLabel,
    workedSeconds: workedSeconds,
    statusDetail: detail,
    shiftName: record.shiftName,
    shiftStart: record.shiftStart,
    shiftEnd: record.shiftEnd,
    overtimeLabel: approvedOt
        ? formatWorkedLabel(record.overtime, seconds: otSeconds)
        : null,
    overtimeSeconds: approvedOt ? otSeconds : 0,
    overtimeApproved: approvedOt,
    overtimePending: pendingOt,
    isEarlyOut: record.isEarlyOut,
    isRequestPending: record.isRequestPending,
    hoursPending: short ? record.hoursPending : null,
    leaveName: context?.leaveName,
    markedToday: date == now,
    punches: record.punches,
  );
}

AttendanceDay placeholderDay(
  DateTime date, {
  DateTime? today,
  bool calendarWeekendIsOff = true,
  AttendanceDayContext? context,
}) {
  final d = _dateOnly(date);
  final now = today ?? _dateOnly(DateTime.now());

  final todayFlag = d == now;

  if (context?.hasLeave == true) {
    return AttendanceDay(
      date: d,
      status: AttendanceStatus.leave,
      statusDetail: context!.leavePaid == false
          ? '${context.leaveName} (unpaid)'
          : context.leaveName,
      leaveName: context.leaveName,
      markedToday: todayFlag,
    );
  }

  if (context?.isHoliday == true) {
    return AttendanceDay(
      date: d,
      status: AttendanceStatus.holiday,
      statusDetail: 'Holiday',
      markedToday: todayFlag,
    );
  }

  if (context?.isCompanyLeave == true) {
    return AttendanceDay(
      date: d,
      status: AttendanceStatus.weekend,
      statusDetail: 'Week off',
      markedToday: todayFlag,
    );
  }

  if (calendarWeekendIsOff && _isWeekend(d)) {
    return AttendanceDay(
      date: d,
      status: AttendanceStatus.weekend,
      statusDetail: 'Weekend',
      markedToday: todayFlag,
    );
  }

  if (d.isAfter(now)) {
    return AttendanceDay(
      date: d,
      status: AttendanceStatus.none,
      statusDetail: 'Upcoming',
      markedToday: todayFlag,
    );
  }

  if (d == now) {
    return AttendanceDay(
      date: d,
      status: AttendanceStatus.none,
      statusDetail: 'Not clocked in',
      markedToday: true,
    );
  }

  return AttendanceDay(
    date: d,
    status: AttendanceStatus.absent,
    statusDetail: 'Absent',
    markedToday: todayFlag,
  );
}

List<AttendanceDay> buildDaysForRange({
  required DateTime from,
  required DateTime to,
  required List<AttendanceRecord> records,
  HomeWorkSchedule? schedule,
  Map<String, AttendanceDayContext>? context,
  DateTime? today,
}) {
  final byDate = <String, AttendanceRecord>{};
  for (final record in records) {
    byDate[_dateKey(record.date)] = record;
  }
  final scheduleByDate = <String, HomeScheduleDay>{
    if (schedule != null)
      for (final day in schedule.days) _dateKey(day.date): day,
  };

  final start = _dateOnly(from);
  final end = _dateOnly(to);
  final now = _dateOnly(
    today ?? schedule?.companyToday ?? DateTime.now(),
  );
  final hasRoster = schedule != null;
  final days = <AttendanceDay>[];
  for (
    var cursor = start;
    !cursor.isAfter(end);
    cursor = cursor.add(const Duration(days: 1))
  ) {
    final key = _dateKey(cursor);
    final sched = scheduleByDate[key];
    final hasSchedule = sched?.hasSchedule ?? false;
    final flags = context?[key];
    final record = byDate[key];
    final todayFlag = cursor == now;

    if (record != null) {
      // Punched days keep the shift that was on the attendance row. Filling
      // blanks from the roster is fine; overwriting with today's assignment
      // is not — that is how a historical night shift became 09:30–18:30.
      var mapped = mapRecordToDay(record, context: flags, today: now);
      mapped = mapped.copyWith(
        shiftName:
            (mapped.shiftName != null && mapped.shiftName!.trim().isNotEmpty)
            ? mapped.shiftName
            : sched?.shiftName,
        shiftStart: mapped.shiftStart ?? sched?.startTime,
        shiftEnd: mapped.shiftEnd ?? sched?.endTime,
        hasSchedule: hasRoster ? hasSchedule : mapped.hasSchedule,
        markedToday: todayFlag,
      );
      days.add(mapped);
      continue;
    }

    if (hasRoster && !hasSchedule && flags?.hasLeave != true) {
      days.add(
        AttendanceDay(
          date: cursor,
          status: flags?.isHoliday == true
              ? AttendanceStatus.holiday
              : AttendanceStatus.weekend,
          statusDetail: flags?.isHoliday == true ? 'Holiday' : 'Day off',
          shiftName: sched?.shiftName,
          hasSchedule: false,
          leaveName: flags?.leaveName,
          markedToday: todayFlag,
        ),
      );
      continue;
    }

    final placeholder = placeholderDay(
      cursor,
      today: now,
      calendarWeekendIsOff: !hasRoster,
      context: flags,
    );
    days.add(
      placeholder.copyWith(
        shiftName: sched?.shiftName ?? placeholder.shiftName,
        shiftStart: hasSchedule ? sched?.startTime : placeholder.shiftStart,
        shiftEnd: hasSchedule ? sched?.endTime : placeholder.shiftEnd,
        hasSchedule: hasSchedule,
      ),
    );
  }
  return days;
}

/// Shift tab: roster is the skeleton, punches overlay hours / status.
List<AttendanceDay> buildShiftDaysForRange({
  required DateTime from,
  required DateTime to,
  required List<AttendanceRecord> records,
  required HomeWorkSchedule schedule,
  Map<String, AttendanceDayContext>? context,
  DateTime? today,
}) {
  return buildDaysForRange(
    from: from,
    to: to,
    records: records,
    schedule: schedule,
    context: context,
    today: today,
  );
}

AttendanceMonthStats buildMonthStats(List<AttendanceDay> days) {
  var present = 0;
  var absent = 0;
  var lateDays = 0;
  var otSeconds = 0;

  for (final day in days) {
    switch (day.status) {
      case AttendanceStatus.present:
      case AttendanceStatus.shortHours:
      case AttendanceStatus.missingOut:
        present++;
      case AttendanceStatus.late:
        present++;
        lateDays++;
      case AttendanceStatus.overtime:
        present++;
      case AttendanceStatus.absent:
        absent++;
      case AttendanceStatus.leave:
      case AttendanceStatus.holiday:
      case AttendanceStatus.weekend:
      case AttendanceStatus.none:
        break;
    }
    otSeconds += day.overtimeSeconds;
  }

  return AttendanceMonthStats(
    presentDays: present,
    absentDays: absent,
    lateDays: lateDays,
    overtimeSeconds: otSeconds,
  );
}
