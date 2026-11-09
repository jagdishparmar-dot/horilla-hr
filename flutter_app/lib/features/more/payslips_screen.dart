import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import 'more_models.dart';
import 'more_providers.dart';
import 'more_widgets.dart';

const _green = Color(0xFF16A34A);
const _red = Color(0xFFEF4444);

class PayslipsScreen extends ConsumerWidget {
  const PayslipsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(payslipsProvider);

    return MorePage(
      title: 'Payslips',
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(payslipsProvider);
          try {
            await ref.read(payslipsProvider.future);
          } catch (_) {}
        },
        child: AsyncView<List<PayslipItem>>(
          value: async,
          onRetry: () => ref.invalidate(payslipsProvider),
          builder: (items) {
            if (items.isEmpty) {
              return const CenteredScroll(
                child: EmptyPanel(
                  icon: HugeIcons.strokeRoundedInvoice03,
                  title: 'No payslips yet',
                  message: 'Your payslips will appear here once payroll has been issued.',
                  color: _green,
                ),
              );
            }
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              itemCount: items.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return _LatestCard(item: items.first);
                final item = items[index - 1];
                final showYear =
                    index == 1 ||
                    items[index - 2].endDate.year != item.endDate.year;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showYear)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          4,
                          index == 1 ? 20 : 14,
                          4,
                          10,
                        ),
                        child: Text(
                          '${item.endDate.year}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PayslipTile(item: item),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

void _openPayslip(BuildContext context, PayslipItem item) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => PayslipDetailScreen(item: item)),
  );
}

class _LatestCard extends StatelessWidget {
  const _LatestCard({required this.item});

  final PayslipItem item;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openPayslip(context, item),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF16A34A), Color(0xFF22B8E8)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: _green.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'LATEST · ${item.periodLabel.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    item.statusLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Net pay',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatMoney(item.netPay),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 32,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _MiniStat(label: 'Gross', value: formatMoney(item.grossPay)),
                const SizedBox(width: 10),
                _MiniStat(
                  label: 'Deductions',
                  value: formatMoney(item.deduction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayslipTile extends StatelessWidget {
  const _PayslipTile({required this.item});

  final PayslipItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.isPaid ? _green : AppColors.navBlue;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: cardDecoration(radius: 18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openPayslip(context, item),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                GradientIconTile(
                  icon: HugeIcons.strokeRoundedInvoice03,
                  color: color,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.periodLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Pill(text: item.statusLabel, color: color),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatMoney(item.netPay),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Text(
                      'Net pay',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
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

class PayslipDetailScreen extends StatelessWidget {
  const PayslipDetailScreen({super.key, required this.item});

  final PayslipItem item;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    // Basic pay is its own line; the server lists the other earnings under
    // "allowances", so anything beyond them is reported as a remainder rather
    // than guessed at.
    final allowanceTotal = item.allowances.fold<double>(
      0,
      (sum, line) => sum + line.amount,
    );
    final otherEarnings = item.grossPay - item.basicPay - allowanceTotal;

    return MorePage(
      title: 'Payslip',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          SectionCard(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.periodLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${fmt.format(item.startDate)} – ${fmt.format(item.endDate)}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Pill(
                    text: item.statusLabel,
                    color: item.isPaid ? _green : AppColors.navBlue,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Net pay',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatMoney(item.netPay),
                        style: const TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w800,
                          fontSize: 30,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (item.hasAttendanceSummary) ...[
            const SizedBox(height: 14),
            SectionCard(
              title: 'Attendance this period',
              children: [
                Row(
                  children: [
                    _DayStat(
                      label: 'Working days',
                      value: item.workingDays,
                      color: AppColors.navBlue,
                    ),
                    _DayStat(
                      label: 'Paid days',
                      value: item.paidDays,
                      color: _green,
                    ),
                    _DayStat(
                      label: 'Unpaid days',
                      value: item.unpaidDays,
                      color: _red,
                    ),
                  ],
                ),
                if ((item.lossOfPay ?? 0) > 0.005) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Loss of pay for unpaid days: ${formatMoney(item.lossOfPay!)} '
                    '(already reflected in basic pay).',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 14),
          SectionCard(
            title: 'Earnings',
            children: [
              _AmountLine(label: 'Basic pay', amount: item.basicPay),
              for (final line in item.allowances)
                _AmountLine(label: line.title, amount: line.amount),
              if (otherEarnings > 0.005)
                _AmountLine(label: 'Other earnings', amount: otherEarnings),
              const Divider(height: 22),
              _AmountLine(
                label: 'Gross pay',
                amount: item.grossPay,
                bold: true,
              ),
            ],
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Deductions',
            children: [
              if (item.deductions.isEmpty && item.deduction <= 0)
                const Text(
                  'No deductions this period.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                )
              else ...[
                for (final line in item.deductions)
                  _AmountLine(
                    label: line.title,
                    amount: line.amount,
                    color: _red,
                    negative: true,
                  ),
                const Divider(height: 22),
                _AmountLine(
                  label: 'Total deductions',
                  amount: item.deduction,
                  bold: true,
                  color: _red,
                  negative: true,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DayStat extends StatelessWidget {
  const _DayStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value == null ? '—' : formatCount(value!),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({
    required this.label,
    required this.amount,
    this.bold = false,
    this.negative = false,
    this.color = AppColors.textPrimary,
  });

  final String label;
  final double amount;
  final bool bold;
  final bool negative;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final weight = bold ? FontWeight.w800 : FontWeight.w600;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: bold ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: weight,
                fontSize: 13.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${negative ? '− ' : ''}${formatMoney(amount)}',
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }
}
