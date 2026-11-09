import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../home/models.dart';

enum AttendanceStatus { present, late, overtime, absent, weekend, none }

enum AttendanceViewMode { list, calendar }

enum AttendanceSegment { summary, shift }

class AttendanceDay {
  const AttendanceDay({
    required this.date,
    required this.status,
    this.clockIn,
    this.clockOut,
    this.workedLabel,
    this.statusDetail,
    this.shiftName,
    this.shiftStart,
    this.shiftEnd,
    this.overtimeLabel,
    this.punches = const [],
  });

  final DateTime date;
  final AttendanceStatus status;
  final String? clockIn;
  final String? clockOut;
  final String? workedLabel;
  final String? statusDetail;

  /// Mirrors API `shift_name` from `/attendance/my-attendance/`.
  final String? shiftName;

  /// Mirrors schedule `start_time` / `end_time` from `/base/employee-shift-schedules/`.
  final String? shiftStart;
  final String? shiftEnd;

  /// Mirrors API `attendance_overtime`.
  final String? overtimeLabel;

  /// Each check-in / check-out pair for the day.
  final List<HomePunch> punches;

  bool get hasPunch => clockIn != null;

  Color get accentColor {
    switch (status) {
      case AttendanceStatus.present:
        return AppColors.green;
      case AttendanceStatus.late:
        return AppColors.late;
      case AttendanceStatus.overtime:
        return AppColors.purple;
      case AttendanceStatus.absent:
        return AppColors.red;
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
      case AttendanceStatus.absent:
        return const Color(0xFFFFEBEE);
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

  bool get isToday {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// Short status word shown on the day pill.
  String get statusLine {
    if (statusDetail != null && statusDetail!.isNotEmpty) return statusDetail!;
    return switch (status) {
      AttendanceStatus.present => 'Present',
      AttendanceStatus.late => 'Late',
      AttendanceStatus.overtime => 'Overtime',
      AttendanceStatus.absent => 'Absent',
      AttendanceStatus.weekend => 'Weekend',
      AttendanceStatus.none => '',
    };
  }
}

class AttendanceMonthStats {
  const AttendanceMonthStats({
    required this.presentDays,
    required this.absentDays,
    required this.lateDays,
    required this.overtimeHours,
  });

  final int presentDays;
  final int absentDays;

  /// Days flagged late. The API reports late as a flag, not minutes.
  final int lateDays;
  final int overtimeHours;

  String get overtimeLabel => '${overtimeHours.toString().padLeft(2, '0')} hrs';
}
