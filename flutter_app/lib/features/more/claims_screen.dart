import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/theme.dart';
import '../requests/request_form_widgets.dart';
import 'file_claim_screen.dart';
import 'more_models.dart';
import 'more_providers.dart';
import 'more_repository.dart';
import 'more_widgets.dart';

const _tint = Color(0xFFD97706);

class ExpenseClaimsScreen extends ConsumerStatefulWidget {
  const ExpenseClaimsScreen({super.key});

  @override
  ConsumerState<ExpenseClaimsScreen> createState() =>
      _ExpenseClaimsScreenState();
}

class _ExpenseClaimsScreenState extends ConsumerState<ExpenseClaimsScreen> {
  DateTime? _month;
  DateTime? _day;

  Future<void> _fileClaim() async {
    final filed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const FileClaimScreen()),
    );
    if (filed == true) ref.invalidate(expenseClaimsProvider);
  }

  Future<void> _pickDay() async {
    final picked = await showRequestCalendarPicker(
      context,
      initialDate: _day ?? _month ?? DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _day = DateTime(picked.year, picked.month, picked.day));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(expenseClaimsProvider);

    return MorePage(
      title: 'Expense claims',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _fileClaim,
        backgroundColor: _tint,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('File a claim'),
      ),
      body: AsyncView<List<ExpenseClaim>>(
        value: async,
        onRetry: () => ref.invalidate(expenseClaimsProvider),
        builder: (items) {
          final visible = filterClaims(items, month: _month, day: _day);
          final groups = groupClaimsByMonth(visible);
          return Column(
            children: [
              if (items.isNotEmpty)
                _ClaimFilters(
                  months: claimMonths(items),
                  month: _month,
                  day: _day,
                  onMonth: (month) => setState(() {
                    _month = month;
                    if (_day != null &&
                        month != null &&
                        (_day!.year != month.year ||
                            _day!.month != month.month)) {
                      _day = null;
                    }
                  }),
                  onPickDay: _pickDay,
                  onClearDay: () => setState(() => _day = null),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(expenseClaimsProvider);
                    try {
                      await ref.read(expenseClaimsProvider.future);
                    } catch (_) {}
                  },
                  child: _ClaimsBody(items: items, groups: groups),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ClaimsBody extends StatelessWidget {
  const _ClaimsBody({required this.items, required this.groups});

  final List<ExpenseClaim> items;
  final List<ClaimMonthGroup> groups;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const CenteredScroll(
        child: EmptyPanel(
          icon: HugeIcons.strokeRoundedReceipt,
          title: 'No expense claims yet',
          message:
              'Tap File a claim and attach the receipt for a reimbursement.',
          color: _tint,
        ),
      );
    }
    if (groups.isEmpty) {
      return const CenteredScroll(
        child: EmptyPanel(
          icon: HugeIcons.strokeRoundedCalendar03,
          title: 'Nothing in this period',
          message: 'Try another month or clear the date.',
          color: _tint,
        ),
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        for (final group in groups) ...[
          _MonthHeader(group: group),
          for (final claim in group.claims)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ClaimTile(claim: claim),
            ),
        ],
      ],
    );
  }
}

class _ClaimFilters extends StatelessWidget {
  const _ClaimFilters({
    required this.months,
    required this.month,
    required this.day,
    required this.onMonth,
    required this.onPickDay,
    required this.onClearDay,
  });

  final List<DateTime> months;
  final DateTime? month;
  final DateTime? day;
  final ValueChanged<DateTime?> onMonth;
  final VoidCallback onPickDay;
  final VoidCallback onClearDay;

  @override
  Widget build(BuildContext context) {
    final monthFormat = DateFormat('MMM yyyy');
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        children: [
          _FilterChip(
            label: 'All',
            selected: month == null,
            onTap: () => onMonth(null),
          ),
          for (final item in months)
            _FilterChip(
              label: monthFormat.format(item),
              selected:
                  month != null &&
                  month!.year == item.year &&
                  month!.month == item.month,
              onTap: () => onMonth(item),
            ),
          _FilterChip(
            label: day == null ? 'Date' : DateFormat('d MMM yyyy').format(day!),
            selected: day != null,
            icon: Icons.calendar_today_rounded,
            onTap: onPickDay,
            onClear: day == null ? null : onClearDay,
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.onClear,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? _tint : Colors.white,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: selected ? _tint : const Color(0xFFE5E7EB),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                if (onClear != null) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onClear,
                    child: Icon(Icons.close_rounded, size: 16, color: color),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.group});

  final ClaimMonthGroup group;

  @override
  Widget build(BuildContext context) {
    final count = group.claims.length;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  group.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                count == 1 ? '1 claim' : '$count claims',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MonthTotal(
                  label: 'Filed',
                  value: group.filedLabel,
                  color: _tint,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MonthTotal(
                  label: 'Approved',
                  value: group.approvedLabel,
                  color: const Color(0xFF16A34A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthTotal extends StatelessWidget {
  const _MonthTotal({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: cardDecoration(radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClaimTile extends StatelessWidget {
  const _ClaimTile({required this.claim});

  final ExpenseClaim claim;

  @override
  Widget build(BuildContext context) {
    final figure =
        claim.amountLabel ??
        claim.daysLabel ??
        claim.bonusLabel ??
        claim.typeLabel;
    final color = _statusColor(claim);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: cardDecoration(radius: 16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ClaimDetailScreen(claim: claim),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            child: Row(
              children: [
                _DayBadge(date: claim.date, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        claim.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        claim.typeLabel,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      figure,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Pill(text: claim.statusLabel, color: color),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayBadge extends StatelessWidget {
  const _DayBadge({required this.date, required this.color});

  final DateTime? date;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 52,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            date == null ? '—' : DateFormat('d').format(date!),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              height: 1,
            ),
          ),
          if (date != null)
            Text(
              DateFormat('MMM').format(date!).toUpperCase(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 9,
              ),
            ),
        ],
      ),
    );
  }
}

class ClaimDetailScreen extends ConsumerStatefulWidget {
  const ClaimDetailScreen({super.key, required this.claim});

  final ExpenseClaim claim;

  @override
  ConsumerState<ClaimDetailScreen> createState() => _ClaimDetailScreenState();
}

class _ClaimDetailScreenState extends ConsumerState<ClaimDetailScreen> {
  String? _opening;

  Future<void> _openFile(String url) async {
    setState(() => _opening = url);
    try {
      final path = await ref
          .read(moreRepositoryProvider)
          .downloadClaimFile(url);
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done && mounted) {
        showSnack(
          context,
          result.type == ResultType.noAppToOpen
              ? 'No app on this device can open this file.'
              : "Couldn't open the file.",
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, cleanError(e));
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final claim = widget.claim;
    return MorePage(
      title: 'Claim',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          _ClaimHero(claim: claim),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Details',
            children: [
              InfoRow(
                icon: HugeIcons.strokeRoundedReceipt,
                label: 'Type',
                value: claim.typeLabel,
                color: _tint,
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedCalendar03,
                label: 'Leave type',
                value: claim.leaveType,
                color: _tint,
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedSun03,
                label: 'Days',
                value: claim.daysLabel,
                color: _tint,
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedMoneyReceive01,
                label: 'Bonus points',
                value: claim.bonusLabel,
                color: _tint,
                last: claim.description == null,
              ),
            ],
          ),
          if (claim.description != null) ...[
            const SizedBox(height: 14),
            SectionCard(
              title: 'Note',
              children: [
                Text(
                  claim.description!,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ],
          if (claim.files.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Receipts',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            for (final url in claim.files)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  child: Ink(
                    decoration: cardDecoration(radius: 14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _opening == null ? () => _openFile(url) : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.attach_file_rounded,
                              color: _tint,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                claimFileName(url),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (_opening == url)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ClaimHero extends StatelessWidget {
  const _ClaimHero({required this.claim});

  final ExpenseClaim claim;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(claim);
    final figure =
        claim.amountLabel ??
        claim.daysLabel ??
        claim.bonusLabel ??
        claim.typeLabel;
    return Container(
      decoration: cardDecoration(radius: 20),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pill(text: claim.statusLabel, color: color),
              const Spacer(),
              Text(
                claim.typeLabel,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            figure,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 30,
              height: 1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            claim.title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
          if (claim.dateLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              claim.dateLabel!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Color _statusColor(ExpenseClaim claim) => switch (claim.status) {
  'approved' => const Color(0xFF16A34A),
  'rejected' => const Color(0xFFEF4444),
  _ => _tint,
};
