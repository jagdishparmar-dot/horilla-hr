import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import 'models.dart';
import 'requests_repository.dart';

Future<void> showRequestDetailsSheet(
  BuildContext context, {
  required LeaveRequestItem item,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _RequestDetailsSheet(item: item),
  );
}

class _RequestDetailsSheet extends ConsumerStatefulWidget {
  const _RequestDetailsSheet({required this.item});

  final LeaveRequestItem item;

  @override
  ConsumerState<_RequestDetailsSheet> createState() =>
      _RequestDetailsSheetState();
}

class _RequestDetailsSheetState extends ConsumerState<_RequestDetailsSheet> {
  late LeaveRequestItem item;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    item = widget.item;
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    try {
      final detailed =
          await ref.read(requestsRepositoryProvider).fetchRequestDetail(item.id);
      if (!mounted) return;
      setState(() {
        item = detailed;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  static List<ApprovalStep> _fallbackTimeline(RequestStatus status) {
    switch (status) {
      case RequestStatus.approved:
        return const [
          ApprovalStep(
            title: 'Request Submitted',
            state: ApprovalStepState.done,
            subtitle: 'Completed',
          ),
          ApprovalStep(
            title: 'Direct Manager Approval',
            state: ApprovalStepState.done,
            subtitle: 'Completed',
          ),
          ApprovalStep(
            title: 'HR Approval',
            state: ApprovalStepState.done,
            subtitle: 'Completed',
          ),
        ];
      case RequestStatus.rejected:
        return const [
          ApprovalStep(
            title: 'Request Submitted',
            state: ApprovalStepState.done,
            subtitle: 'Completed',
          ),
          ApprovalStep(
            title: 'Direct Manager Approval',
            state: ApprovalStepState.rejected,
            subtitle: 'Rejected',
          ),
          ApprovalStep(
            title: 'HR Approval',
            state: ApprovalStepState.rejected,
            subtitle: 'Skipped',
          ),
        ];
      case RequestStatus.pending:
      case RequestStatus.cancelled:
        return const [
          ApprovalStep(
            title: 'Request Submitted',
            state: ApprovalStepState.done,
            subtitle: 'Submitted',
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
        ];
    }
  }

  String get _dateRange {
    final start = DateFormat('MMM d').format(item.startDate);
    if (item.startDate.year == item.endDate.year &&
        item.startDate.month == item.endDate.month &&
        item.startDate.day == item.endDate.day) {
      return DateFormat('MMM d').format(item.startDate);
    }
    final end = DateFormat('MMM d').format(item.endDate);
    return '$start - $end';
  }

  String get _returnDate =>
      DateFormat('MMM d').format(item.effectiveReturnDate);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
            decoration: const BoxDecoration(
              color: AppColors.navBlue,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Request Details',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Request type',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: item.status.color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          item.status.label,
                          style: TextStyle(
                            color: item.status.color,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoCell(
                          label: 'Duration',
                          value: item.durationLabel,
                        ),
                      ),
                      Expanded(
                        child: _InfoCell(
                          label: 'Date',
                          value: _dateRange,
                        ),
                      ),
                      Expanded(
                        child: _InfoCell(
                          label: 'Return Date',
                          value: _returnDate,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Request Reason',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.reason?.isNotEmpty == true
                        ? item.reason!
                        : 'No reason provided.',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  const SizedBox(height: 16),
                  _ApprovalTimeline(
                    steps: item.approvalSteps.isEmpty
                        ? _fallbackTimeline(item.status)
                        : item.approvalSteps,
                  ),
                  if (item.status == RequestStatus.rejected &&
                      item.rejectionReason != null) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: Color(0xFFE5E7EB)),
                    const SizedBox(height: 16),
                    const Text(
                      'Rejection Reason',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.rejectionReason!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (item.status == RequestStatus.pending) ...[
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Cancel request coming soon'),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.red,
                          side: const BorderSide(color: AppColors.red),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Cancel Request',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCell extends StatelessWidget {
  const _InfoCell({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ApprovalTimeline extends StatelessWidget {
  const _ApprovalTimeline({required this.steps});

  final List<ApprovalStep> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineRow(
            step: steps[i],
            isLast: i == steps.length - 1,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.step,
    required this.isLast,
  });

  final ApprovalStep step;
  final bool isLast;

  Color get _color => switch (step.state) {
        ApprovalStepState.done => AppColors.green,
        ApprovalStepState.pending => const Color(0xFFF59E0B),
        ApprovalStepState.waiting => const Color(0xFFF59E0B),
        ApprovalStepState.rejected => AppColors.red,
      };

  IconData get _icon => switch (step.state) {
        ApprovalStepState.done => Icons.check_rounded,
        ApprovalStepState.pending => Icons.schedule_rounded,
        ApprovalStepState.waiting => Icons.schedule_rounded,
        ApprovalStepState.rejected => Icons.close_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: _color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icon, size: 15, color: Colors.white),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: const Color(0xFFE5E7EB),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    step.subtitle,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: step.state == ApprovalStepState.done
                          ? AppColors.textSecondary
                          : _color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
