import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../attendance/attendance_mapper.dart';
import '../attendance/attendance_repository.dart';
import '../home/home_provider.dart';
import '../notifications/notifications_provider.dart';
import 'more_models.dart';
import 'more_repository.dart';

/// Profile + work + bank details for the signed-in employee.
final profileBundleProvider = FutureProvider.autoDispose<ProfileBundle>((
  ref,
) async {
  final home = await ref.watch(mobileHomeProvider.future);
  final id = home.employeeId;
  if (id == null) {
    throw Exception('Your account is not linked to an employee record.');
  }
  return ref.watch(moreRepositoryProvider).fetchProfile(id);
});

final payslipsProvider = FutureProvider.autoDispose<List<PayslipItem>>((ref) {
  return ref.watch(moreRepositoryProvider).fetchPayslips();
});

final policiesProvider = FutureProvider.autoDispose<List<PolicyItem>>((ref) {
  return ref.watch(moreRepositoryProvider).fetchPolicies();
});

final ticketsProvider = FutureProvider.autoDispose<List<TicketItem>>((ref) {
  return ref.watch(moreRepositoryProvider).fetchTickets();
});

final ticketTypesProvider = FutureProvider.autoDispose<List<TicketTypeItem>>((
  ref,
) {
  return ref.watch(moreRepositoryProvider).fetchTicketTypes();
});

final ticketDepartmentsProvider =
    FutureProvider.autoDispose<List<TicketDepartment>>((ref) {
      return ref.watch(moreRepositoryProvider).fetchTicketDepartments();
    });

final ticketCommentsProvider = FutureProvider.autoDispose
    .family<List<TicketComment>, int>((ref, ticketId) {
      return ref.watch(moreRepositoryProvider).fetchComments(ticketId);
    });

final faqsProvider = FutureProvider.autoDispose<List<FaqItem>>((ref) {
  return ref.watch(moreRepositoryProvider).fetchFaqs();
});

void invalidateTickets(WidgetRef ref) {
  ref.invalidate(ticketsProvider);
}

/// Last two weeks of punches plus notifications, newest first.
///
/// Either source may fail on its own; the feed only errors when both do.
final activityFeedProvider = FutureProvider.autoDispose<List<ActivityEvent>>((
  ref,
) async {
  final today = DateTime.now();
  final to = DateTime(today.year, today.month, today.day);
  final from = to.subtract(const Duration(days: 14));

  Object? attendanceError;
  Object? notificationError;

  final attendanceFuture = ref
      .read(attendanceRepositoryProvider)
      .fetchMyAttendance(from: from, to: to)
      .then<List<ActivityEvent>>((payload) => _attendanceEvents(payload.records))
      .catchError((Object e) {
        attendanceError = e;
        return <ActivityEvent>[];
      });

  final notificationFuture = ref
      .watch(notificationsProvider.future)
      .then<List<ActivityEvent>>(
        (items) => [
          for (final n in items)
            ActivityEvent(
              kind: ActivityKind.notification,
              title: n.title,
              subtitle: n.body,
              at: n.timestamp,
              unread: n.unread,
              accent: n.accent,
            ),
        ],
      )
      .catchError((Object e) {
        notificationError = e;
        return <ActivityEvent>[];
      });

  final results = await Future.wait([attendanceFuture, notificationFuture]);
  if (attendanceError != null && notificationError != null) {
    throw attendanceError!;
  }

  final events = [...results[0], ...results[1]]
    ..sort((a, b) => b.at.compareTo(a.at));
  return events;
});

List<ActivityEvent> _attendanceEvents(List<AttendanceRecord> records) {
  // The mapper turns the records into per-day rows with every punch of the
  // day attached.
  final days = buildDaysForRange(
    from: DateTime.now().subtract(const Duration(days: 14)),
    to: DateTime.now(),
    records: records,
  );
  final events = <ActivityEvent>[];
  for (final day in days) {
    final punches = day.punches.isNotEmpty
        ? day.punches.map((p) => (p.clockIn, p.clockOut, p.open)).toList()
        : [
            (
              day.clockIn,
              day.clockOut,
              day.clockIn != null && day.clockOut == null,
            ),
          ];
    for (final (clockIn, clockOut, open) in punches) {
      if (clockIn != null && clockIn.isNotEmpty) {
        events.add(
          ActivityEvent(
            kind: ActivityKind.clockIn,
            title: 'Clocked in at ${formatClock(clockIn)}',
            subtitle: open ? 'Still clocked in' : 'Attendance',
            at: _at(day.date, clockIn),
          ),
        );
      }
      if (clockOut != null && clockOut.isNotEmpty && !open) {
        events.add(
          ActivityEvent(
            kind: ActivityKind.clockOut,
            title: 'Clocked out at ${formatClock(clockOut)}',
            subtitle: 'Attendance',
            at: _at(day.date, clockOut),
          ),
        );
      }
    }
  }
  return events;
}

DateTime _at(DateTime date, String clock) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(clock.trim());
  final hour = match == null ? 12 : int.parse(match.group(1)!);
  final minute = match == null ? 0 : int.parse(match.group(2)!);
  return DateTime(date.year, date.month, date.day, hour, minute);
}
