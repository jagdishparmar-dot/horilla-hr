import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme.dart';

/// Mirrors `/leave/available-leave/` (`GetAvailableLeaveTypeSerializer`).
class LeaveBalance {
  const LeaveBalance({
    required this.id,
    required this.leaveTypeId,
    required this.name,
    required this.available,
    required this.used,
    required this.total,
    required this.unit,
    required this.kind,
  });

  final int id;
  final int leaveTypeId;
  final String name;
  final num available;
  final num used;
  final num total;
  final BalanceUnit unit;
  final BalanceKind kind;

  String get availableLabel {
    final value = _fmt(available);
    return unit == BalanceUnit.hours ? '$value Hours' : '$value Days';
  }

  String get usedLabel => _fmt(used);
  String get totalLabel => _fmt(total);

  static String _fmt(num value) {
    if (value % 1 == 0) return value.toInt().toString().padLeft(2, '0');
    return value.toString();
  }

  List<List<dynamic>> get icon => switch (kind) {
        BalanceKind.annual => HugeIcons.strokeRoundedSun03,
        BalanceKind.permission => HugeIcons.strokeRoundedClock01,
        BalanceKind.remote => HugeIcons.strokeRoundedHome01,
        BalanceKind.casual => HugeIcons.strokeRoundedBriefcase01,
        BalanceKind.other => HugeIcons.strokeRoundedCalendar03,
      };

  Color get accent => switch (kind) {
        BalanceKind.annual => AppColors.orange,
        BalanceKind.permission => AppColors.navBlue,
        BalanceKind.remote => AppColors.green,
        BalanceKind.casual => AppColors.purple,
        BalanceKind.other => AppColors.textSecondary,
      };
}

enum BalanceUnit { days, hours }

enum BalanceKind { annual, permission, remote, casual, other }

/// API leave status → UI label (`LEAVE_STATUS` on LeaveRequest).
enum RequestStatus { pending, approved, rejected, cancelled }

extension RequestStatusX on RequestStatus {
  String get label => switch (this) {
        RequestStatus.pending => 'Pending',
        RequestStatus.approved => 'Approved',
        RequestStatus.rejected => 'Rejected',
        RequestStatus.cancelled => 'Cancelled',
      };

  /// Maps API `status` values from `/leave/user-request/`.
  static RequestStatus fromApi(String? raw) {
    switch (raw) {
      case 'approved':
        return RequestStatus.approved;
      case 'rejected':
        return RequestStatus.rejected;
      case 'cancelled':
      case 'cancel_requested':
        return RequestStatus.cancelled;
      case 'requested':
      default:
        return RequestStatus.pending;
    }
  }

  Color get color => switch (this) {
        RequestStatus.pending => const Color(0xFFF59E0B),
        RequestStatus.approved => AppColors.green,
        RequestStatus.rejected => AppColors.red,
        RequestStatus.cancelled => AppColors.textSecondary,
      };

  Color get softBackground => switch (this) {
        RequestStatus.pending => const Color(0xFFFFF8E8),
        RequestStatus.approved => const Color(0xFFEAF8EF),
        RequestStatus.rejected => const Color(0xFFFFEBEE),
        RequestStatus.cancelled => const Color(0xFFF3F4F6),
      };
}

enum RequestKind { remote, annual, early, casual, permission, other }

enum ApprovalStepState { done, pending, waiting, rejected }

class ApprovalStep {
  const ApprovalStep({
    required this.title,
    required this.state,
    required this.subtitle,
  });

  final String title;
  final ApprovalStepState state;
  final String subtitle;
}

/// Mirrors `/leave/user-request/` list item fields (+ detail extras).
class LeaveRequestItem {
  const LeaveRequestItem({
    required this.id,
    required this.title,
    required this.status,
    required this.requestedDays,
    required this.startDate,
    required this.endDate,
    required this.kind,
    this.reason,
    this.rejectionReason,
    this.returnDate,
    this.timeline,
  });

  final int id;
  final String title;
  final RequestStatus status;
  final num requestedDays;
  final DateTime startDate;
  final DateTime endDate;
  final RequestKind kind;
  final String? reason;
  final String? rejectionReason;
  final DateTime? returnDate;

  /// Nullable so hot-reload of older mock instances does not crash.
  final List<ApprovalStep>? timeline;

  List<ApprovalStep> get approvalSteps => timeline ?? const [];

  String get durationLabel {
    final days = requestedDays % 1 == 0
        ? requestedDays.toInt()
        : requestedDays;
    if (days == 1 || days == 1.0) return '1 Day';
    return '$days Days';
  }

  DateTime get effectiveReturnDate =>
      returnDate ?? endDate.add(const Duration(days: 1));

  List<List<dynamic>> get icon => switch (kind) {
        RequestKind.remote => HugeIcons.strokeRoundedHome01,
        RequestKind.annual => HugeIcons.strokeRoundedSun03,
        RequestKind.early => HugeIcons.strokeRoundedClock01,
        RequestKind.casual => HugeIcons.strokeRoundedBriefcase01,
        RequestKind.permission => HugeIcons.strokeRoundedClock01,
        RequestKind.other => HugeIcons.strokeRoundedFile02,
      };

  Color get accent => switch (kind) {
        RequestKind.remote => AppColors.navBlue,
        RequestKind.annual => AppColors.orange,
        RequestKind.early => AppColors.purple,
        RequestKind.casual => AppColors.green,
        RequestKind.permission => AppColors.navBlue,
        RequestKind.other => AppColors.textSecondary,
      };
}
