import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../home/models.dart';

enum AttendanceStatus {
  present,
  late,
  overtime,
  shortHours,
  missingOut,
  absent,
  leave,
  holiday,
  weekend,
  none,
}

enum AttendanceViewMode { list, calendar }

enum AttendanceSegment { summary, shift }

class AttendanceDayContext {
  const AttendanceDayContext({
    this.isHoliday = false,
    this.isCompanyLeave = false,
    this.leaveName,
    this.leavePaid,
  });

  final bool isHoliday;
  final bool isCompanyLeave;
  final String? leaveName;
  final bool? leavePaid;

  bool get hasLeave => leaveName != null && leaveName!.trim().isNotEmpty;

  factory AttendanceDayContext.fromJson(Map<String, dynamic> json) {
    return AttendanceDayContext(
      isHoliday: json['is_holiday'] as bool? ?? false,
      isCompanyLeave: json['is_company_leave'] as bool? ?? false,
      leaveName: json['leave_name'] as String?,
      leavePaid: json['leave_paid'] as bool?,
    );
  }
}

class AttendanceDay {
  const AttendanceDay({
    required this.date,
    required this.status,
    this.clockIn,
    this.clockOut,
    this.clockInDate,
    this.clockOutDate,
    this.workedLabel,
    this.workedSeconds = 0,
    this.statusDetail,
    this.shiftName,
    this.shiftStart,
    this.shiftEnd,
    this.overtimeLabel,
    this.overtimeSeconds = 0,
    this.overtimeApproved = false,
    this.overtimePending = false,
    this.isEarlyOut = false,
    this.isRequestPending = false,
    this.hoursPending,
    this.leaveName,
    this.hasSchedule = false,
    this.markedToday = false,
    this.punches = const [],
  });

  final DateTime date;
  final AttendanceStatus status;
  final String? clockIn;
  final String? clockOut;
  final String? clockInDate;
  final String? clockOutDate;
  final String? workedLabel;
  final int workedSeconds;
  final String? statusDetail;
  final String? shiftName;
  final String? shiftStart;
  final String? shiftEnd;
  final String? overtimeLabel;
  final int overtimeSeconds;
  final bool overtimeApproved;
  final bool overtimePending;
  final bool isEarlyOut;
  final bool isRequestPending;
  final String? hoursPending;
  final String? leaveName;
  final bool hasSchedule;
  final bool markedToday;
  final List<HomePunch> punches;

  bool get hasPunch => clockIn != null;

  /// No roster hours and no punch — a week-off, not "Saturday".
  bool get isDayOff => !hasSchedule && !hasPunch;

  AttendanceDay copyWith({
    DateTime? date,
    AttendanceStatus? status,
    String? clockIn,
    String? clockOut,
    String? clockInDate,
    String? clockOutDate,
    String? workedLabel,
    int? workedSeconds,
    String? statusDetail,
    String? shiftName,
    String? shiftStart,
    String? shiftEnd,
    String? overtimeLabel,
    int? overtimeSeconds,
    bool? overtimeApproved,
    bool? overtimePending,
    bool? isEarlyOut,
    bool? isRequestPending,
    String? hoursPending,
    String? leaveName,
    bool? hasSchedule,
    bool? markedToday,
    List<HomePunch>? punches,
  }) {
    return AttendanceDay(
      date: date ?? this.date,
      status: status ?? this.status,
      clockIn: clockIn ?? this.clockIn,
      clockOut: clockOut ?? this.clockOut,
      clockInDate: clockInDate ?? this.clockInDate,
      clockOutDate: clockOutDate ?? this.clockOutDate,
      workedLabel: workedLabel ?? this.workedLabel,
      workedSeconds: workedSeconds ?? this.workedSeconds,
      statusDetail: statusDetail ?? this.statusDetail,
      shiftName: shiftName ?? this.shiftName,
      shiftStart: shiftStart ?? this.shiftStart,
      shiftEnd: shiftEnd ?? this.shiftEnd,
      overtimeLabel: overtimeLabel ?? this.overtimeLabel,
      overtimeSeconds: overtimeSeconds ?? this.overtimeSeconds,
      overtimeApproved: overtimeApproved ?? this.overtimeApproved,
      overtimePending: overtimePending ?? this.overtimePending,
      isEarlyOut: isEarlyOut ?? this.isEarlyOut,
      isRequestPending: isRequestPending ?? this.isRequestPending,
      hoursPending: hoursPending ?? this.hoursPending,
      leaveName: leaveName ?? this.leaveName,
      hasSchedule: hasSchedule ?? this.hasSchedule,
      markedToday: markedToday ?? this.markedToday,
      punches: punches ?? this.punches,
    );
  }

  Color get accentColor {
    switch (status) {
      case AttendanceStatus.present:
        return AppColors.green;
      case AttendanceStatus.late:
        return AppColors.late;
      case AttendanceStatus.overtime:
        return AppColors.purple;
      case AttendanceStatus.shortHours:
        return const Color(0xFFD97706);
      case AttendanceStatus.missingOut:
      case AttendanceStatus.absent:
        return AppColors.red;
      case AttendanceStatus.leave:
        return const Color(0xFF2563EB);
      case AttendanceStatus.holiday:
        return const Color(0xFF0F766E);
      case AttendanceStatus.weekend:
      case AttendanceStatus.none:
        return AppColors.textSecondary;
    }
  }

  Color get softBackground {
    switch (status) {
      case AttendanceStatus.present:
        return const Color(0xFFE8F7EE);
      case AttendanceStatus.late:
        return const Color(0xFFFFF0E8);
      case AttendanceStatus.overtime:
        return const Color(0xFFF3EEFF);
      case AttendanceStatus.shortHours:
        return const Color(0xFFFFF7ED);
      case AttendanceStatus.missingOut:
      case AttendanceStatus.absent:
        return const Color(0xFFFFEBEE);
      case AttendanceStatus.leave:
        return const Color(0xFFEFF6FF);
      case AttendanceStatus.holiday:
        return const Color(0xFFCCFBF1);
      case AttendanceStatus.weekend:
        return const Color(0xFFF3F4F6);
      case AttendanceStatus.none:
        return Colors.white;
    }
  }

  bool get hasShiftTiming => shiftStart != null && shiftEnd != null;

  String get shiftTimingLabel =>
      hasShiftTiming ? '$shiftStart - $shiftEnd' : 'Timing not set';

  String get displayShiftName =>
      (shiftName != null && shiftName!.trim().isNotEmpty)
      ? shiftName!
      : 'No shift assigned';

  bool get isToday => markedToday;

  /// Short status word shown on the day pill.
  String get statusLine {
    if (statusDetail != null && statusDetail!.isNotEmpty) return statusDetail!;
    return switch (status) {
      AttendanceStatus.present => 'Present',
      AttendanceStatus.late => 'Late',
      AttendanceStatus.overtime => 'Overtime',
      AttendanceStatus.shortHours => 'Short hours',
      AttendanceStatus.missingOut => 'No clock-out',
      AttendanceStatus.absent => 'Absent',
      AttendanceStatus.leave => leaveName ?? 'Leave',
      AttendanceStatus.holiday => 'Holiday',
      AttendanceStatus.weekend => 'Week off',
      AttendanceStatus.none => '',
    };
  }
}

class AttendanceMonthStats {
  const AttendanceMonthStats({
    required this.presentDays,
    required this.absentDays,
    required this.lateDays,
    required this.overtimeSeconds,
  });

  final int presentDays;
  final int absentDays;
  final int lateDays;

  /// Approved overtime only, in seconds.
  final int overtimeSeconds;

  int get overtimeHours => overtimeSeconds ~/ 3600;

  String get overtimeLabel {
    final h = overtimeSeconds ~/ 3600;
    final m = (overtimeSeconds % 3600) ~/ 60;
    if (h == 0 && m == 0) return '0h 00m';
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }
}
