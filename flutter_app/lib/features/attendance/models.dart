import 'package:flutter/material.dart';

import '../../core/theme.dart';

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

  String get shiftTimingLabel {
    final start = shiftStart ?? '09:00';
    final end = shiftEnd ?? '05:00';
    return '$start - $end';
  }

  String get displayShiftName => shiftName ?? 'General';

  String get statusLine {
    if (status == AttendanceStatus.none) return '';
    if (statusDetail != null && workedLabel != null) {
      return '$workedLabel / $statusDetail';
    }
    if (statusDetail != null) return statusDetail!;
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
    required this.lateMinutes,
    required this.overtimeHours,
  });

  final int presentDays;
  final int absentDays;
  final int lateMinutes;
  final int overtimeHours;

  String get lateLabel {
    if (lateMinutes >= 60) {
      final h = lateMinutes ~/ 60;
      final m = lateMinutes % 60;
      return m == 0 ? '${h.toString().padLeft(2, '0')} hrs' : '${h}h ${m}m';
    }
    return '$lateMinutes mins';
  }

  String get overtimeLabel =>
      '${overtimeHours.toString().padLeft(2, '0')} hrs';
}
