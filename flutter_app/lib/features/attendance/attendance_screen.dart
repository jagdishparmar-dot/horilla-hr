import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../home/home_provider.dart';
import '../home/models.dart';
import 'attendance_provider.dart';
import 'models.dart';

class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeAsync = ref.watch(mobileHomeProvider);
    final segment = ref.watch(attendanceSegmentProvider);
    final viewMode = ref.watch(attendanceViewModeProvider);
    final totalWorkedAsync = ref.watch(attendanceTotalWorkedProvider);
    final totalWorked = totalWorkedAsync.maybeWhen(
      data: (v) => v,
      orElse: () => '--',
    );

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: homeAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(e.toString(), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => ref.invalidate(mobileHomeProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (home) => Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: _AttendanceHeader(home: home),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _SummaryShiftToggle(
                        segment: segment,
                        onChanged: (s) =>
                            ref.read(attendanceSegmentProvider.notifier).state =
                                s,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async {
                          invalidateAttendance(ref);
                          ref.invalidate(mobileHomeProvider);
                        },
                        child: segment == AttendanceSegment.shift
                            ? const _ShiftPane()
                            : viewMode == AttendanceViewMode.list
                                ? const _ListPane()
                                : const _CalendarPane(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (segment != AttendanceSegment.shift)
              _AttendanceFooter(
                totalWorked: totalWorked,
                home: homeAsync.asData?.value,
              ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceHeader extends StatelessWidget {
  const _AttendanceHeader({required this.home});

  final MobileHome home;

  String? _resolveAvatar(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    return '${AppConfig.mediaOrigin}$url';
  }

  @override
  Widget build(BuildContext context) {
    final avatar = _resolveAvatar(home.avatarUrl);

    return Row(
      children: [
        const Expanded(
          child: Text(
            'Attendance',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.navBlue,
            ),
          ),
        ),
        CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.purpleSoft,
          backgroundImage:
              avatar != null ? CachedNetworkImageProvider(avatar) : null,
          child: avatar == null
              ? Text(
                  home.firstName.isNotEmpty
                      ? home.firstName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: AppColors.purple,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
        ),
      ],
    );
  }
}

class _SummaryShiftToggle extends StatelessWidget {
  const _SummaryShiftToggle({
    required this.segment,
    required this.onChanged,
  });

  final AttendanceSegment segment;
  final ValueChanged<AttendanceSegment> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF1F6),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentChip(
              label: 'Summary',
              selected: segment == AttendanceSegment.summary,
              onTap: () => onChanged(AttendanceSegment.summary),
            ),
          ),
          Expanded(
            child: _SegmentChip(
              label: 'Shift',
              selected: segment == AttendanceSegment.shift,
              onTap: () => onChanged(AttendanceSegment.shift),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.navBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.navBlue.withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ShiftPane extends ConsumerWidget {
  const _ShiftPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(attendanceWeekStartProvider);
    final daysAsync = ref.watch(attendanceWeekDaysProvider);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final rangeLabel =
        '${DateFormat('dd-MMM-yyyy').format(weekStart)} to ${DateFormat('dd-MMM-yyyy').format(weekEnd)}';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _PeriodNav(
            label: rangeLabel,
            onPrev: () {
              ref.read(attendanceWeekStartProvider.notifier).state =
                  weekStart.subtract(const Duration(days: 7));
            },
            onNext: () {
              ref.read(attendanceWeekStartProvider.notifier).state =
                  weekStart.add(const Duration(days: 7));
            },
            trailing: const SizedBox(width: 48),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: daysAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _AttendanceError(
              message: e.toString(),
              onRetry: () => invalidateAttendance(ref),
            ),
            data: (days) => ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              itemCount: days.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _ShiftDayCard(day: days[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShiftDayCard extends StatelessWidget {
  const _ShiftDayCard({required this.day});

  final AttendanceDay day;

  @override
  Widget build(BuildContext context) {
    final dayNum = DateFormat('dd').format(day.date);
    final weekday = DateFormat('EEE').format(day.date).toUpperCase();
    final tint = switch (day.status) {
      AttendanceStatus.present => const Color(0xFFEAF8EF),
      AttendanceStatus.overtime => const Color(0xFFF3EEFF),
      AttendanceStatus.late => const Color(0xFFFFF0E8),
      _ => Colors.white,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 14, 12),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  dayNum,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: AppColors.navBlue,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  weekday,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    color: AppColors.navBlue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day.displayShiftName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  day.shiftTimingLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _ShiftStatusColumn(day: day),
        ],
      ),
    );
  }
}

class _ShiftStatusColumn extends StatelessWidget {
  const _ShiftStatusColumn({required this.day});

  final AttendanceDay day;

  @override
  Widget build(BuildContext context) {
    switch (day.status) {
      case AttendanceStatus.none:
        return const SizedBox(width: 64, height: 36);
      case AttendanceStatus.weekend:
        return const Text(
          'Weekend',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        );
      case AttendanceStatus.overtime:
        return _StatusStack(
          hours: day.overtimeLabel ?? day.workedLabel ?? '00:00 hrs',
          label: 'Overtime',
          color: AppColors.purple,
        );
      case AttendanceStatus.present:
        return _StatusStack(
          hours: day.workedLabel ?? '08:00 hrs',
          label: 'Present',
          color: AppColors.green,
        );
      case AttendanceStatus.late:
        return _StatusStack(
          hours: day.workedLabel ?? '00:00 hrs',
          label: 'Late',
          color: AppColors.late,
        );
      case AttendanceStatus.absent:
        return const Text(
          'Absent',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: AppColors.red,
          ),
        );
    }
  }
}

class _StatusStack extends StatelessWidget {
  const _StatusStack({
    required this.hours,
    required this.label,
    required this.color,
  });

  final String hours;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          hours,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ListPane extends ConsumerWidget {
  const _ListPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(attendanceWeekStartProvider);
    final daysAsync = ref.watch(attendanceWeekDaysProvider);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final rangeLabel =
        '${DateFormat('dd-MMM-yyyy').format(weekStart)} to ${DateFormat('dd-MMM-yyyy').format(weekEnd)}';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _PeriodNav(
            label: rangeLabel,
            onPrev: () {
              ref.read(attendanceWeekStartProvider.notifier).state =
                  weekStart.subtract(const Duration(days: 7));
            },
            onNext: () {
              ref.read(attendanceWeekStartProvider.notifier).state =
                  weekStart.add(const Duration(days: 7));
            },
            trailing: IconButton(
              onPressed: () {
                ref.read(attendanceViewModeProvider.notifier).state =
                    AttendanceViewMode.calendar;
                ref.read(attendanceMonthProvider.notifier).state =
                    DateTime(weekStart.year, weekStart.month);
              },
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedCalendar03,
                color: AppColors.navBlue,
                size: 22,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: daysAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _AttendanceError(
              message: e.toString(),
              onRetry: () => invalidateAttendance(ref),
            ),
            data: (days) => ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: days.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _AttendanceDayCard(day: days[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _CalendarPane extends ConsumerWidget {
  const _CalendarPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(attendanceMonthProvider);
    final statsAsync = ref.watch(attendanceMonthStatsProvider);
    final daysAsync = ref.watch(attendanceMonthDaysProvider);
    final selected = ref.watch(attendanceSelectedDayProvider);
    final monthLabel = DateFormat('MMMM yyyy').format(month);

    return daysAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _AttendanceError(
        message: e.toString(),
        onRetry: () => invalidateAttendance(ref),
      ),
      data: (days) {
        final stats = statsAsync.maybeWhen(
          data: (s) => s,
          orElse: () => const AttendanceMonthStats(
            presentDays: 0,
            absentDays: 0,
            lateMinutes: 0,
            overtimeHours: 0,
          ),
        );
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            _PeriodNav(
              label: monthLabel,
              onPrev: () {
                ref.read(attendanceMonthProvider.notifier).state =
                    DateTime(month.year, month.month - 1);
              },
              onNext: () {
                ref.read(attendanceMonthProvider.notifier).state =
                    DateTime(month.year, month.month + 1);
              },
              trailing: IconButton(
                onPressed: () {
                  final selectedWeek = weekStartOf(selected);
                  ref.read(attendanceWeekStartProvider.notifier).state =
                      selectedWeek;
                  ref.read(attendanceViewModeProvider.notifier).state =
                      AttendanceViewMode.list;
                },
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedLeftToRightListBullet,
                  color: AppColors.navBlue,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _MonthStatsRow(stats: stats),
            const SizedBox(height: 14),
            _MonthCalendarGrid(
              month: month,
              days: days,
              selected: selected,
              onSelect: (d) =>
                  ref.read(attendanceSelectedDayProvider.notifier).state = d,
            ),
          ],
        );
      },
    );
  }
}

class _AttendanceError extends StatelessWidget {
  const _AttendanceError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 48),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Center(
          child: FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      ],
    );
  }
}

class _PeriodNav extends StatelessWidget {
  const _PeriodNav({
    required this.label,
    required this.onPrev,
    required this.onNext,
    required this.trailing,
  });

  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
        ),
        trailing,
      ],
    );
  }
}

class _AttendanceDayCard extends StatelessWidget {
  const _AttendanceDayCard({required this.day});

  final AttendanceDay day;

  @override
  Widget build(BuildContext context) {
    final dayNum = DateFormat('dd').format(day.date);
    final weekday = DateFormat('EEE').format(day.date).toUpperCase();
    final timeRange = day.hasPunch && day.clockOut != null
        ? '${day.clockIn} to ${day.clockOut}'
        : day.status == AttendanceStatus.absent
            ? '— — —'
            : '${day.clockIn ?? '00:00'} to ${day.clockOut ?? '00:00'}';

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: day.accentColor.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  dayNum,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: AppColors.navBlue,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  weekday,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    color: AppColors.navBlue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TimelineDots(status: day.status),
                const SizedBox(height: 6),
                Text(
                  timeRange,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              day.statusLine,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: day.accentColor,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineDots extends StatelessWidget {
  const _TimelineDots({required this.status});

  final AttendanceStatus status;

  @override
  Widget build(BuildContext context) {
    final endColor = status == AttendanceStatus.weekend ||
            status == AttendanceStatus.absent
        ? AppColors.textSecondary.withValues(alpha: 0.4)
        : AppColors.red;

    return SizedBox(
      height: 10,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: const Color(0xFFE5E7EB),
          ),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: status == AttendanceStatus.absent
                      ? AppColors.textSecondary.withValues(alpha: 0.35)
                      : AppColors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: endColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthStatsRow extends StatelessWidget {
  const _MonthStatsRow({required this.stats});

  final AttendanceMonthStats stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatChip(
            icon: HugeIcons.strokeRoundedCheckmarkCircle02,
            color: AppColors.green,
            value: '${stats.presentDays} days',
            label: 'Present',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            icon: HugeIcons.strokeRoundedCancel01,
            color: AppColors.red,
            value: '${stats.absentDays} days',
            label: 'Absent',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            icon: HugeIcons.strokeRoundedClock01,
            color: AppColors.late,
            value: stats.lateLabel,
            label: 'Late',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            icon: HugeIcons.strokeRoundedCalendarAdd01,
            color: AppColors.purple,
            value: stats.overtimeLabel,
            label: 'Overtime',
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final List<List<dynamic>> icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          HugeIcon(icon: icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 10,
              color: color.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthCalendarGrid extends StatelessWidget {
  const _MonthCalendarGrid({
    required this.month,
    required this.days,
    required this.selected,
    required this.onSelect,
  });

  final DateTime month;
  final List<AttendanceDay> days;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final leading = first.weekday % 7; // Sunday-start
    final byDay = {for (final d in days) d.date.day: d};
    final totalCells = leading + days.length;
    final rows = (totalCells / 7).ceil();
    final cellCount = rows * 7;

    const headers = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final h in headers)
                Expanded(
                  child: Text(
                    h,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var row = 0; row < rows; row++) ...[
            if (row > 0) const SizedBox(height: 6),
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _buildCell(
                      index: row * 7 + col,
                      leading: leading,
                      cellCount: cellCount,
                      daysInMonth: days.length,
                      byDay: byDay,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCell({
    required int index,
    required int leading,
    required int cellCount,
    required int daysInMonth,
    required Map<int, AttendanceDay> byDay,
  }) {
    final dayNum = index - leading + 1;
    if (dayNum < 1 || dayNum > daysInMonth) {
      return const SizedBox(height: 54);
    }

    final date = DateTime(month.year, month.month, dayNum);
    final day = byDay[dayNum]!;
    final isSelected = selected.year == date.year &&
        selected.month == date.month &&
        selected.day == date.day;

    Color bg;
    Color fg;
    if (isSelected) {
      bg = AppColors.navBlue;
      fg = Colors.white;
    } else if (day.status == AttendanceStatus.weekend) {
      bg = const Color(0xFFF3F4F6);
      fg = AppColors.textSecondary;
    } else if (day.status == AttendanceStatus.late) {
      bg = const Color(0xFFFFE8E4);
      fg = AppColors.textPrimary;
    } else if (day.status == AttendanceStatus.present ||
        day.status == AttendanceStatus.overtime) {
      bg = const Color(0xFFEAF8EF);
      fg = AppColors.textPrimary;
    } else if (day.status == AttendanceStatus.absent) {
      bg = const Color(0xFFFFEBEE);
      fg = AppColors.textPrimary;
    } else {
      bg = Colors.transparent;
      fg = AppColors.textPrimary;
    }

    final timeText = day.clockIn ??
        (day.status == AttendanceStatus.absent ? '--:--' : '00:00');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => onSelect(date),
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 54,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$dayNum',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  timeText,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.9)
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttendanceFooter extends ConsumerWidget {
  const _AttendanceFooter({
    required this.totalWorked,
    required this.home,
  });

  final String totalWorked;
  final MobileHome? home;

  Future<void> _onPunch(BuildContext context, WidgetRef ref) async {
    final current = home;
    if (current == null) return;
    final err = await ref.read(punchActionProvider).togglePunch(current);
    if (!context.mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      final msg = current.isClockedIn ? 'Checked out' : 'Checked in';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(punchBusyProvider);
    final isClockedIn = home?.isClockedIn ?? false;
    final buttonColor = isClockedIn ? AppColors.red : AppColors.green;
    final buttonLabel = isClockedIn ? 'Check-out' : 'Check-in';

    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Total worked hours',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedClock01,
                        color: AppColors.navBlue,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        totalWorked,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed:
                  home == null || busy ? null : () => _onPunch(context, ref),
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: buttonColor.withValues(alpha: 0.5),
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedFingerPrint,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          buttonLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
