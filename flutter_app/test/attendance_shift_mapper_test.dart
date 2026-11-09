import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/features/attendance/attendance_mapper.dart';
import 'package:horilla_employee/features/attendance/attendance_repository.dart';
import 'package:horilla_employee/features/attendance/models.dart';
import 'package:horilla_employee/features/home/models.dart';

// Tuesday in a Sunday–Saturday week. Passed into the mapper so these
// assertions do not depend on the machine clock.
final _today = DateTime(2026, 3, 10);
final _weekStart = DateTime(2026, 3, 8);
final _weekEnd = DateTime(2026, 3, 14);

HomeWorkSchedule _monFriMorning() {
  const keys = [
    'sunday',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
  ];
  return HomeWorkSchedule(
    shiftName: 'Morning',
    weekStart: _weekStart,
    weekEnd: _weekEnd,
    days: [
      for (var i = 0; i < 7; i++)
        HomeScheduleDay(
          date: _weekStart.add(Duration(days: i)),
          dayKey: keys[i],
          shiftName: 'Morning',
          startTime: i == 0 || i == 6 ? null : '09:30',
          endTime: i == 0 || i == 6 ? null : '18:30',
          isToday: i == 2,
          hasSchedule: i != 0 && i != 6,
        ),
    ],
  );
}

AttendanceRecord _punch({
  required DateTime date,
  String? shiftName,
  String? shiftStart,
  String? shiftEnd,
}) {
  return AttendanceRecord(
    id: 1,
    date: date,
    clockIn: '09:41',
    clockOut: '18:05',
    workedHour: '08:24',
    shiftName: shiftName,
    shiftStart: shiftStart,
    shiftEnd: shiftEnd,
  );
}

void main() {
  test('fromJson does not invent 09:00–17:00 on a day off', () {
    final day = HomeScheduleDay.fromJson({
      'date': '2026-03-08',
      'day_key': 'sunday',
      'shift_name': 'Morning',
      'start_time': null,
      'end_time': null,
      'is_today': false,
      'has_schedule': false,
    });
    expect(day.hasSchedule, isFalse);
    expect(day.startTime, isNull);
    expect(day.endTime, isNull);
    expect(day.timingLabel, 'Day off');
  });

  test('saturday without a schedule row is a day off, not because it is saturday', () {
    final days = buildShiftDaysForRange(
      from: _weekStart,
      to: _weekEnd,
      records: const [],
      schedule: _monFriMorning(),
      today: _today,
    );
    final saturday = days.last;
    expect(saturday.date.weekday, DateTime.saturday);
    expect(saturday.isDayOff, isTrue);
    expect(saturday.statusDetail, 'Day off');
    expect(saturday.shiftStart, isNull);
  });

  test('working saturday shows the roster, not weekend', () {
    final schedule = HomeWorkSchedule(
      shiftName: 'Weekend cover',
      weekStart: _weekStart,
      weekEnd: _weekEnd,
      days: [
        for (var i = 0; i < 7; i++)
          HomeScheduleDay(
            date: _weekStart.add(Duration(days: i)),
            dayKey: 'd$i',
            shiftName: 'Weekend cover',
            startTime: '10:00',
            endTime: '16:00',
            isToday: i == 2,
            hasSchedule: true,
          ),
      ],
    );
    final days = buildShiftDaysForRange(
      from: _weekStart,
      to: _weekEnd,
      records: const [],
      schedule: schedule,
      today: _today,
    );
    final saturday = days.last;
    expect(saturday.isDayOff, isFalse);
    expect(saturday.status, isNot(AttendanceStatus.weekend));
    expect(saturday.displayShiftName, 'Weekend cover');
    expect(saturday.shiftTimingLabel, '10:00 - 16:00');
  });

  test('unpunched scheduled weekday keeps current shift times', () {
    final tuesday = buildShiftDaysForRange(
      from: _weekStart,
      to: _weekEnd,
      records: const [],
      schedule: _monFriMorning(),
      today: _today,
    )[2];
    expect(tuesday.isDayOff, isFalse);
    expect(tuesday.statusDetail, 'Not clocked in');
    expect(tuesday.displayShiftName, 'Morning');
    expect(tuesday.shiftTimingLabel, '09:30 - 18:30');
  });

  test('punched day keeps the attendance-row shift, not the current roster', () {
    final tuesday = DateTime(2026, 3, 10);
    final days = buildShiftDaysForRange(
      from: _weekStart,
      to: _weekEnd,
      records: [
        _punch(
          date: tuesday,
          shiftName: 'Evening (old)',
          shiftStart: '22:00',
          shiftEnd: '06:00',
        ),
      ],
      schedule: _monFriMorning(),
      today: _today,
    );
    final day = days[2];
    expect(day.hasPunch, isTrue);
    expect(day.clockIn, '09:41');
    expect(day.displayShiftName, 'Evening (old)');
    expect(day.shiftTimingLabel, '22:00 - 06:00');
    expect(day.isDayOff, isFalse);
    expect(day.isToday, isTrue);
  });

  test('projectOntoRange stamps weekday hours onto another week', () {
    final nextWeek = _monFriMorning().projectOntoRange(
      from: DateTime(2026, 3, 15),
      to: DateTime(2026, 3, 21),
      today: _today,
    );
    expect(nextWeek.days, hasLength(7));
    expect(nextWeek.days.first.dayKey, 'sunday');
    expect(nextWeek.days.first.hasSchedule, isFalse);
    expect(nextWeek.days.first.startTime, isNull);
    final monday = nextWeek.days[1];
    expect(monday.dayKey, 'monday');
    expect(monday.hasSchedule, isTrue);
    expect(monday.timingLabel, '09:30 - 18:30');
    expect(monday.date, DateTime(2026, 3, 16));
  });

  test('projectOntoRange drops fake 09:00–17:00 on a day off', () {
    final template = HomeWorkSchedule(
      shiftName: 'Morning',
      weekStart: _weekStart,
      weekEnd: _weekEnd,
      days: [
        HomeScheduleDay(
          date: _weekStart,
          dayKey: 'sunday',
          shiftName: 'Morning',
          startTime: '09:00',
          endTime: '17:00',
          isToday: false,
          hasSchedule: false,
        ),
      ],
    );
    final sunday = template
        .projectOntoRange(from: _weekStart, to: _weekStart, today: _today)
        .days
        .single;
    expect(sunday.hasSchedule, isFalse);
    expect(sunday.startTime, isNull);
    expect(sunday.timingLabel, 'Day off');
  });

  test('a punch on an off day still shows, with the attendance shift', () {
    final sunday = DateTime(2026, 3, 8);
    final days = buildShiftDaysForRange(
      from: _weekStart,
      to: _weekEnd,
      records: [
        _punch(
          date: sunday,
          shiftName: 'Overtime cover',
          shiftStart: '10:00',
          shiftEnd: '14:00',
        ),
      ],
      schedule: _monFriMorning(),
      today: _today,
    );
    final day = days.first;
    expect(day.isDayOff, isFalse);
    expect(day.hasPunch, isTrue);
    expect(day.hasSchedule, isFalse);
    expect(day.displayShiftName, 'Overtime cover');
    expect(day.shiftTimingLabel, '10:00 - 14:00');
  });

  test('past open punch is missing clock-out, not present', () {
    final day = mapRecordToDay(
      AttendanceRecord(
        id: 1,
        date: DateTime(2026, 3, 9),
        clockIn: '09:00',
      ),
      today: _today,
    );
    expect(day.status, AttendanceStatus.missingOut);
  });

  test('unapproved overtime is pending, not an overtime day', () {
    final day = mapRecordToDay(
      AttendanceRecord(
        id: 1,
        date: _today,
        clockIn: '09:00',
        clockOut: '19:00',
        overtime: '01:00',
        overtimeSeconds: 3600,
        overtimeApproved: false,
        atWorkSeconds: 10 * 3600,
      ),
      today: _today,
    );
    expect(day.status, AttendanceStatus.present);
    expect(day.overtimePending, isTrue);
    expect(day.overtimeLabel, isNull);
    expect(day.overtimeSeconds, 0);
  });

  test('approved overtime uses exact seconds, not a rounded hour', () {
    final day = mapRecordToDay(
      AttendanceRecord(
        id: 1,
        date: _today,
        clockIn: '09:00',
        clockOut: '18:12',
        overtime: '00:12',
        overtimeSeconds: 12 * 60,
        overtimeApproved: true,
        atWorkSeconds: 8 * 3600 + 12 * 60,
      ),
      today: _today,
    );
    expect(day.status, AttendanceStatus.overtime);
    expect(day.overtimeSeconds, 12 * 60);
    final stats = buildMonthStats([day]);
    expect(stats.overtimeHours, 0);
    expect(stats.overtimeLabel, '12m');
  });

  test('leave overlay wins on a day with no punch', () {
    final days = buildDaysForRange(
      from: _today,
      to: _today,
      records: const [],
      schedule: _monFriMorning(),
      context: {
        '2026-3-10': const AttendanceDayContext(
          leaveName: 'Casual Leave',
          leavePaid: true,
        ),
      },
      today: _today,
    );
    expect(days.single.status, AttendanceStatus.leave);
    expect(days.single.statusDetail, 'Casual Leave');
  });

  test('totals use at_work_second rather than formatted labels', () {
    final day = mapRecordToDay(
      AttendanceRecord(
        id: 1,
        date: _today,
        clockIn: '09:00',
        clockOut: '17:30',
        workedHour: '08:30',
        atWorkSeconds: 8 * 3600 + 30 * 60,
      ),
      today: _today,
    );
    expect(formatTotalWorked([day]), '8h 30m');
  });

  test('night-shift clock-out shows the next calendar date', () {
    expect(
      formatPunchClock('06:00', '2026-03-11', DateTime(2026, 3, 10)),
      '11 Mar 06:00',
    );
    expect(
      formatPunchClock('22:00', '2026-03-10', DateTime(2026, 3, 10)),
      '22:00',
    );
  });

  test('unpunched days follow per-date roster after a rotation', () {
    final schedule = HomeWorkSchedule(
      shiftName: 'Evening',
      weekStart: _weekStart,
      weekEnd: _weekEnd,
      companyToday: _today,
      timezone: 'Asia/Kolkata',
      days: [
        for (var i = 0; i < 7; i++)
          HomeScheduleDay(
            date: _weekStart.add(Duration(days: i)),
            dayKey: ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'][i],
            shiftName: i <= 1 ? 'Morning' : 'Evening',
            startTime: (i == 0 || i == 6)
                ? null
                : (i <= 1 ? '09:30' : '14:00'),
            endTime: (i == 0 || i == 6)
                ? null
                : (i <= 1 ? '18:30' : '22:00'),
            isToday: i == 2,
            hasSchedule: i != 0 && i != 6,
          ),
      ],
    );
    final days = buildShiftDaysForRange(
      from: _weekStart,
      to: _weekEnd,
      records: [
        _punch(
          date: DateTime(2026, 3, 9),
          shiftName: 'Night (historical)',
          shiftStart: '22:00',
          shiftEnd: '06:00',
        ),
      ],
      schedule: schedule,
      today: _today,
    );
    final monday = days[1];
    expect(monday.hasPunch, isTrue);
    expect(monday.displayShiftName, 'Night (historical)');
    expect(monday.shiftTimingLabel, '22:00 - 06:00');

    final tuesday = days[2];
    expect(tuesday.hasPunch, isFalse);
    expect(tuesday.displayShiftName, 'Evening');
    expect(tuesday.shiftTimingLabel, '14:00 - 22:00');
    expect(tuesday.isToday, isTrue);
  });

  test('late wins over approved overtime and still keeps the OT label', () {
    final day = mapRecordToDay(
      AttendanceRecord(
        id: 1,
        date: _today,
        clockIn: '09:20',
        clockOut: '19:00',
        overtime: '01:00',
        overtimeSeconds: 3600,
        overtimeApproved: true,
        isLate: true,
        atWorkSeconds: 9 * 3600 + 40 * 60,
      ),
      today: _today,
    );
    expect(day.status, AttendanceStatus.late);
    expect(day.overtimeApproved, isTrue);
    expect(day.overtimeSeconds, 3600);
    expect(day.isToday, isTrue);
  });

  test('holiday overlay on an unpunched scheduled day', () {
    final days = buildDaysForRange(
      from: _today,
      to: _today,
      records: const [],
      schedule: _monFriMorning(),
      context: {
        '2026-3-10': const AttendanceDayContext(isHoliday: true),
      },
      today: _today,
    );
    expect(days.single.status, AttendanceStatus.holiday);
    expect(days.single.statusDetail, 'Holiday');
  });

  test('empty schedule is day off every day, with no invented hours', () {
    final schedule = HomeWorkSchedule(
      shiftName: 'General',
      weekStart: _weekStart,
      weekEnd: _weekEnd,
      companyToday: _today,
      days: [
        for (var i = 0; i < 7; i++)
          HomeScheduleDay(
            date: _weekStart.add(Duration(days: i)),
            dayKey: 'd$i',
            shiftName: 'General',
            isToday: i == 2,
            hasSchedule: false,
          ),
      ],
    );
    final days = buildShiftDaysForRange(
      from: _weekStart,
      to: _weekEnd,
      records: const [],
      schedule: schedule,
      today: _today,
    );
    expect(days, hasLength(7));
    for (final day in days) {
      expect(day.isDayOff, isTrue, reason: '${day.date}');
      expect(day.shiftStart, isNull);
      expect(day.statusDetail, 'Day off');
    }
  });

  test('fromJson reads company today and timezone', () {
    final schedule = HomeWorkSchedule.fromJson({
      'shift_name': 'Morning',
      'week_start': '2026-03-08',
      'week_end': '2026-03-14',
      'today': '2026-03-10',
      'timezone': 'Asia/Kolkata',
      'days': const [],
    });
    expect(schedule.companyToday, DateTime(2026, 3, 10));
    expect(schedule.timezone, 'Asia/Kolkata');
  });
}
