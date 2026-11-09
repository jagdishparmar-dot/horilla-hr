import 'models.dart';

/// Mock balances / requests shaped like:
/// - `GET /leave/available-leave/`
/// - `GET /leave/user-request/`
class RequestsMockData {
  RequestsMockData._();

  static const balances = <LeaveBalance>[
    LeaveBalance(
      id: 1,
      leaveTypeId: 1,
      name: 'Annual Leave',
      available: 14,
      used: 1,
      total: 15,
      unit: BalanceUnit.days,
      kind: BalanceKind.annual,
    ),
    LeaveBalance(
      id: 2,
      leaveTypeId: 2,
      name: 'Permissions',
      available: 3,
      used: 5,
      total: 8,
      unit: BalanceUnit.hours,
      kind: BalanceKind.permission,
    ),
    LeaveBalance(
      id: 3,
      leaveTypeId: 3,
      name: 'Remote Work',
      available: 2,
      used: 1,
      total: 3,
      unit: BalanceUnit.days,
      kind: BalanceKind.remote,
    ),
    LeaveBalance(
      id: 4,
      leaveTypeId: 4,
      name: 'Casual Leave',
      available: 3,
      used: 2,
      total: 5,
      unit: BalanceUnit.days,
      kind: BalanceKind.casual,
    ),
  ];

  static final requests = <LeaveRequestItem>[
    LeaveRequestItem(
      id: 101,
      title: 'Remote Work',
      status: RequestStatus.pending,
      requestedDays: 1,
      startDate: DateTime(2026, 2, 9),
      endDate: DateTime(2026, 2, 9),
      kind: RequestKind.remote,
      reason: 'Working from home due to personal appointment.',
      timeline: const [
        ApprovalStep(
          title: 'Request Submitted',
          state: ApprovalStepState.done,
          subtitle: 'Feb 05 - 10:15 AM',
        ),
        ApprovalStep(
          title: 'Direct Manager Approval',
          state: ApprovalStepState.pending,
          subtitle: 'Pending',
        ),
        ApprovalStep(
          title: 'HR Approval',
          state: ApprovalStepState.waiting,
          subtitle: 'Waiting',
        ),
      ],
    ),
    LeaveRequestItem(
      id: 102,
      title: 'Annual Leave',
      status: RequestStatus.approved,
      requestedDays: 3,
      startDate: DateTime(2026, 1, 15),
      endDate: DateTime(2026, 1, 17),
      returnDate: DateTime(2026, 1, 18),
      kind: RequestKind.annual,
      reason: 'Traveling for family wedding.',
      timeline: const [
        ApprovalStep(
          title: 'Request Submitted',
          state: ApprovalStepState.done,
          subtitle: 'Jan 10 - 02:00 PM',
        ),
        ApprovalStep(
          title: 'Direct Manager Approval',
          state: ApprovalStepState.done,
          subtitle: 'Jan 10 - 04:20 PM',
        ),
        ApprovalStep(
          title: 'HR Approval',
          state: ApprovalStepState.done,
          subtitle: 'Jan 11 - 09:45 AM',
        ),
      ],
    ),
    LeaveRequestItem(
      id: 103,
      title: 'Early Leave',
      status: RequestStatus.rejected,
      requestedDays: 1,
      startDate: DateTime(2026, 1, 10),
      endDate: DateTime(2026, 1, 10),
      kind: RequestKind.early,
      reason: 'Need to leave early for medical checkup.',
      rejectionReason: 'Insufficient balance regarding current workload.',
      timeline: const [
        ApprovalStep(
          title: 'Request Submitted',
          state: ApprovalStepState.done,
          subtitle: 'Jan 08 - 11:30 AM',
        ),
        ApprovalStep(
          title: 'Direct Manager Approval',
          state: ApprovalStepState.rejected,
          subtitle: 'Jan 08 - 03:10 PM',
        ),
        ApprovalStep(
          title: 'HR Approval',
          state: ApprovalStepState.rejected,
          subtitle: 'Skipped',
        ),
      ],
    ),
    LeaveRequestItem(
      id: 104,
      title: 'Casual Leave',
      status: RequestStatus.approved,
      requestedDays: 2,
      startDate: DateTime(2025, 12, 22),
      endDate: DateTime(2025, 12, 23),
      returnDate: DateTime(2025, 12, 24),
      kind: RequestKind.casual,
      reason: 'Personal errands.',
      timeline: const [
        ApprovalStep(
          title: 'Request Submitted',
          state: ApprovalStepState.done,
          subtitle: 'Dec 18 - 01:00 PM',
        ),
        ApprovalStep(
          title: 'Direct Manager Approval',
          state: ApprovalStepState.done,
          subtitle: 'Dec 18 - 05:30 PM',
        ),
        ApprovalStep(
          title: 'HR Approval',
          state: ApprovalStepState.done,
          subtitle: 'Dec 19 - 10:00 AM',
        ),
      ],
    ),
  ];
}
