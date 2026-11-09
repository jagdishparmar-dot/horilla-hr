import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../home/home_provider.dart';
import 'models.dart';
import 'requests_provider.dart';
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
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    item = widget.item;
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    if (item.source != RequestSource.leave) {
      setState(() => _loading = false);
      return;
    }
    try {
      final detailed = await ref
          .read(requestsRepositoryProvider)
          .fetchRequestDetail(item.id);
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

  String get _statusNote => switch (item.status) {
    RequestStatus.pending => 'Waiting for approval.',
    RequestStatus.approved => 'This request is approved.',
    RequestStatus.rejected => 'This request was rejected.',
    RequestStatus.cancelled => 'This request was cancelled.',
    RequestStatus.cancelRequested => 'Cancellation is waiting for a manager.',
  };

  List<List<dynamic>> get _statusIcon => switch (item.status) {
    RequestStatus.pending ||
    RequestStatus.cancelRequested => HugeIcons.strokeRoundedTimer02,
    RequestStatus.approved => HugeIcons.strokeRoundedCheckmarkCircle02,
    RequestStatus.rejected => HugeIcons.strokeRoundedCancelCircle,
    RequestStatus.cancelled => HugeIcons.strokeRoundedCancel01,
  };

  Future<void> _cancel() async {
    final approvedLeave =
        item.source == RequestSource.leave &&
        item.status == RequestStatus.approved;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(item.cancelActionLabel),
        content: Text(
          approvedLeave
              ? 'This asks your manager to cancel the approved leave.'
              : 'This withdraws the request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              item.cancelActionLabel,
              style: const TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cancelling = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(requestsRepositoryProvider).cancelRequest(item);
      invalidateRequests(ref);
      ref.invalidate(mobileHomeProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            approvedLeave ? 'Cancellation requested' : 'Request cancelled',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  bool get _singleDay =>
      item.startDate.year == item.endDate.year &&
      item.startDate.month == item.endDate.month &&
      item.startDate.day == item.endDate.day;

  String get _dateRange {
    final start = DateFormat('EEE, MMM d').format(item.startDate);
    if (_singleDay) return start;
    final end = DateFormat('EEE, MMM d').format(item.endDate);
    return '$start  →  $end';
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final status = item.status;
    final accent = item.accent;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(accent, Colors.black, 0.08)!,
                  Color.lerp(accent, const Color(0xFF9B5CFF), 0.45)!,
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: HugeIcon(
                          icon: item.icon,
                          color: accent,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.categoryLabel.toUpperCase(),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: status.pillBackground,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HugeIcon(
                        icon: _statusIcon,
                        color: status.color,
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        status.label,
                        style: TextStyle(
                          color: status.color,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _InfoTile(
                          icon: HugeIcons.strokeRoundedClock01,
                          label: 'Duration',
                          value: item.durationLabel,
                          color: const Color(0xFF2F6BFF),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: _InfoTile(
                          icon: HugeIcons.strokeRoundedCalendar03,
                          label: _singleDay ? 'Date' : 'Dates',
                          value: _dateRange,
                          color: const Color(0xFF8B5CF6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionLabel(
                    icon: HugeIcons.strokeRoundedNote01,
                    text: 'Request reason',
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F7FB),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      item.reason?.isNotEmpty == true
                          ? item.reason!
                          : 'No reason provided.',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: item.reason?.isNotEmpty == true
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: status.softBackground,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        HugeIcon(
                          icon: _statusIcon,
                          color: status.color,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _statusNote,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: status.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (status == RequestStatus.rejected &&
                      item.rejectionReason != null &&
                      item.rejectionReason!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _SectionLabel(
                      icon: HugeIcons.strokeRoundedAlert02,
                      text: 'Rejection reason',
                      color: AppColors.red,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDECEE),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        item.rejectionReason!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                  if (item.canCancel) ...[
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _cancelling ? null : _cancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.red,
                          side: const BorderSide(color: AppColors.red),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          _cancelling ? 'Working…' : item.cancelActionLabel,
                          style: const TextStyle(fontWeight: FontWeight.w800),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.text,
    this.color = AppColors.textSecondary,
  });

  final List<List<dynamic>> icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        HugeIcon(icon: icon, color: color, size: 15),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final List<List<dynamic>> icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(icon: icon, color: color, size: 15),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
