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

  /// Unpadded figure for the balance card, e.g. `14`.
  String get availableFigure => _plain(available);

  String get availableCaption =>
      unit == BalanceUnit.hours ? 'Hrs\navailable' : 'Days\navailable';

  String get usedLine =>
      'Used: ${_plain(used)} ${unit == BalanceUnit.hours ? 'hrs' : 'days'}';

  String get totalLine =>
      'Total: ${_plain(total)} ${unit == BalanceUnit.hours ? 'hrs' : 'days'}';

  String get usedLabel => _fmt(used);
  String get totalLabel => _fmt(total);

  static String _plain(num value) {
    if (value % 1 == 0) return value.toInt().toString();
    return value.toString();
  }

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
    BalanceKind.annual => const Color(0xFF22C55E),
    BalanceKind.permission => const Color(0xFFF59E0B),
    BalanceKind.remote => const Color(0xFF22B8E8),
    BalanceKind.casual => const Color(0xFF8B5CF6),
    BalanceKind.other => AppColors.navBlue,
  };
}

enum BalanceUnit { days, hours }

enum BalanceKind { annual, permission, remote, casual, other }

/// API leave status → UI label (`LEAVE_STATUS` on LeaveRequest).
enum RequestStatus { pending, approved, rejected, cancelled, cancelRequested }

extension RequestStatusX on RequestStatus {
  String get label => switch (this) {
    RequestStatus.pending => 'Pending',
    RequestStatus.approved => 'Approved',
    RequestStatus.rejected => 'Rejected',
    RequestStatus.cancelled => 'Cancelled',
    RequestStatus.cancelRequested => 'Cancel requested',
  };

  /// Maps API `status` values from `/leave/user-request/`.
  static RequestStatus fromApi(String? raw) {
    switch (raw) {
      case 'approved':
        return RequestStatus.approved;
      case 'rejected':
        return RequestStatus.rejected;
      case 'cancelled':
        return RequestStatus.cancelled;
      case 'cancel_requested':
        return RequestStatus.cancelRequested;
      case 'requested':
      default:
        return RequestStatus.pending;
    }
  }

  Color get color => switch (this) {
    RequestStatus.pending => const Color(0xFFE8A317),
    RequestStatus.approved => const Color(0xFF1F9D55),
    RequestStatus.rejected => const Color(0xFFE35D6A),
    RequestStatus.cancelled => AppColors.textSecondary,
    RequestStatus.cancelRequested => const Color(0xFFE8A317),
  };

  Color get pillBackground => switch (this) {
    RequestStatus.pending => const Color(0xFFFFE8B0),
    RequestStatus.approved => const Color(0xFFD4F5E2),
    RequestStatus.rejected => const Color(0xFFFCD9DE),
    RequestStatus.cancelled => const Color(0xFFE5E7EB),
    RequestStatus.cancelRequested => const Color(0xFFFFE8B0),
  };

  Color get softBackground => switch (this) {
    RequestStatus.pending => const Color(0xFFFFF6DE),
    RequestStatus.approved => const Color(0xFFE7F8EE),
    RequestStatus.rejected => const Color(0xFFFDECEE),
    RequestStatus.cancelled => const Color(0xFFF3F4F6),
    RequestStatus.cancelRequested => const Color(0xFFFFF6DE),
  };
}

/// Which Horilla record a row came from. Cancel and detail calls follow this.
enum RequestSource { leave, attendance, workType, shift }

enum RequestListFilter { all, leave, permission, remote, attendance, shift }

class LookupItem {
  const LookupItem({required this.id, required this.name});

  final int id;
  final String name;
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
    this.source = RequestSource.leave,
    this.durationOverride,
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
  final RequestSource source;

  /// Clock window or other label that replaces the day count on the card.
  final String? durationOverride;

  /// Nullable so hot-reload of older mock instances does not crash.
  final List<ApprovalStep>? timeline;

  List<ApprovalStep> get approvalSteps => timeline ?? const [];

  String get durationLabel {
    final override = durationOverride;
    if (override != null && override.isNotEmpty) return override;
    final days = requestedDays % 1 == 0 ? requestedDays.toInt() : requestedDays;
    if (days == 1 || days == 1.0) return '1 Day';
    return '$days Days';
  }

  String get categoryLabel => switch (source) {
    RequestSource.attendance => 'Attendance',
    RequestSource.shift => 'Shift',
    RequestSource.workType =>
      kind == RequestKind.remote ? 'Remote work' : 'Work type',
    RequestSource.leave => switch (kind) {
      RequestKind.permission => 'Permission',
      RequestKind.remote => 'Remote work',
      _ => 'Leave',
    },
  };

  bool matchesFilter(RequestListFilter filter) => switch (filter) {
    RequestListFilter.all => true,
    RequestListFilter.leave =>
      source == RequestSource.leave &&
          kind != RequestKind.permission &&
          kind != RequestKind.remote,
    RequestListFilter.permission => kind == RequestKind.permission,
    RequestListFilter.remote => kind == RequestKind.remote,
    RequestListFilter.attendance => source == RequestSource.attendance,
    RequestListFilter.shift => source == RequestSource.shift,
  };

  /// Pending rows can be withdrawn. An approved leave can ask to be cancelled.
  bool get canCancel {
    if (status == RequestStatus.rejected ||
        status == RequestStatus.cancelled ||
        status == RequestStatus.cancelRequested) {
      return false;
    }
    if (source == RequestSource.leave) {
      return status == RequestStatus.pending ||
          status == RequestStatus.approved;
    }
    return status == RequestStatus.pending;
  }

  String get cancelActionLabel =>
      source == RequestSource.leave && status == RequestStatus.approved
      ? 'Request cancellation'
      : 'Cancel request';

  List<List<dynamic>> get icon {
    if (source == RequestSource.attendance) {
      return HugeIcons.strokeRoundedCalendarCheckIn01;
    }
    if (source == RequestSource.shift) {
      return HugeIcons.strokeRoundedClock01;
    }
    return switch (kind) {
      RequestKind.remote => HugeIcons.strokeRoundedHome01,
      RequestKind.annual => HugeIcons.strokeRoundedSun03,
      RequestKind.early => HugeIcons.strokeRoundedClock01,
      RequestKind.casual => HugeIcons.strokeRoundedBriefcase01,
      RequestKind.permission => HugeIcons.strokeRoundedClock01,
      RequestKind.other => HugeIcons.strokeRoundedFile02,
    };
  }

  Color get accent {
    if (source == RequestSource.attendance) return const Color(0xFF8B5CF6);
    if (source == RequestSource.shift) return AppColors.navBlue;
    return switch (kind) {
      RequestKind.remote => const Color(0xFF22B8E8),
      RequestKind.annual => const Color(0xFF22C55E),
      RequestKind.early => const Color(0xFFF59E0B),
      RequestKind.casual => const Color(0xFF8B5CF6),
      RequestKind.permission => const Color(0xFFF59E0B),
      RequestKind.other => AppColors.navBlue,
    };
  }
}
