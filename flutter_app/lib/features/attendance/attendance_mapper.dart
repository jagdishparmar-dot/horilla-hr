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

String formatWorkedLabel(String? workedHour) {
  if (workedHour == null || workedHour.trim().isEmpty) return '00:00 hrs';
  final parts = workedHour.split(':');
  if (parts.length >= 2) {
    return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')} hrs';
  }
  return '$workedHour hrs';
}

String formatTotalWorked(Iterable<AttendanceDay> days) {
  var totalMins = 0;
  for (final day in days) {
    totalMins += parseHhMmToMinutes(day.workedLabel) ?? 0;
  }
  final h = totalMins ~/ 60;
  final m = totalMins % 60;
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

AttendanceDay mapRecordToDay(AttendanceRecord record) {
  final date = _dateOnly(record.date);
  final hasOt = record.overtimeSeconds > 0 || !_isZeroDuration(record.overtime);
  final AttendanceStatus status;
  final String? detail;
  String? workedLabel = formatWorkedLabel(record.workedHour);

  if (record.isLate) {
    status = AttendanceStatus.late;
    detail = 'Late';
  } else if (hasOt) {
    status = AttendanceStatus.overtime;
    detail = 'Overtime';
  } else if (record.clockIn != null) {
    status = AttendanceStatus.present;
    detail = 'Present';
  } else if (record.isHoliday || _isWeekend(date)) {
    status = AttendanceStatus.weekend;
    detail = record.isHoliday ? 'Holiday' : 'Weekend';
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
    workedLabel: workedLabel,
    statusDetail: detail,
    shiftName: record.shiftName,
    shiftStart: record.shiftStart,
    shiftEnd: record.shiftEnd,
    overtimeLabel: hasOt ? formatWorkedLabel(record.overtime) : null,
    punches: record.punches,
  );
}

AttendanceDay placeholderDay(DateTime date, {DateTime? today}) {
  final d = _dateOnly(date);
  final now = today ?? _dateOnly(DateTime.now());

  if (_isWeekend(d)) {
    return AttendanceDay(
      date: d,
      status: AttendanceStatus.weekend,
      statusDetail: 'Weekend',
    );
  }

  if (d.isAfter(now)) {
    return AttendanceDay(
      date: d,
      status: AttendanceStatus.none,
      statusDetail: 'Upcoming',
    );
  }

  if (d == now) {
    // Today with no punch yet is not an absence.
    return AttendanceDay(
      date: d,
      status: AttendanceStatus.none,
      statusDetail: 'Not clocked in',
    );
  }

  return AttendanceDay(
    date: d,
    status: AttendanceStatus.absent,
    statusDetail: 'Absent',
  );
}

List<AttendanceDay> buildDaysForRange({
  required DateTime from,
  required DateTime to,
  required List<AttendanceRecord> records,
}) {
  final byDate = <String, AttendanceRecord>{};
  for (final record in records) {
    final key = '${record.date.year}-${record.date.month}-${record.date.day}';
    byDate[key] = record;
  }

  final start = _dateOnly(from);
  final end = _dateOnly(to);
  final today = _dateOnly(DateTime.now());
  final days = <AttendanceDay>[];
  for (
    var cursor = start;
    !cursor.isAfter(end);
    cursor = cursor.add(const Duration(days: 1))
  ) {
    final key = '${cursor.year}-${cursor.month}-${cursor.day}';
    final record = byDate[key];
    days.add(
      record != null
          ? mapRecordToDay(record)
          : placeholderDay(cursor, today: today),
    );
  }
  return days;
}

AttendanceMonthStats buildMonthStats(List<AttendanceDay> days) {
  var present = 0;
  var absent = 0;
  var lateDays = 0;
  var otMins = 0;

  for (final day in days) {
    switch (day.status) {
      case AttendanceStatus.present:
        present++;
      case AttendanceStatus.late:
        present++;
        lateDays++;
      case AttendanceStatus.overtime:
        present++;
      case AttendanceStatus.absent:
        absent++;
      case AttendanceStatus.weekend:
      case AttendanceStatus.none:
        break;
    }
    // A late day can carry overtime too.
    otMins += parseHhMmToMinutes(day.overtimeLabel) ?? 0;
  }

  return AttendanceMonthStats(
    presentDays: present,
    absentDays: absent,
    lateDays: lateDays,
    overtimeHours: (otMins / 60).ceil(),
  );
}
