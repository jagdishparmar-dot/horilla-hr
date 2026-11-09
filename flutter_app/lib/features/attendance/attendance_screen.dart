import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../home/fence_status_line.dart';
import '../home/home_provider.dart';
import '../home/models.dart';
import 'attendance_mapper.dart';
import 'attendance_provider.dart';
import 'models.dart';

const _heroGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF2F6BFF), Color(0xFF6D5CFF), Color(0xFF9B5CFF)],
);

Color _accentOf(AttendanceStatus status) => switch (status) {
  AttendanceStatus.present => const Color(0xFF16A34A),
  AttendanceStatus.late => const Color(0xFFF97316),
  AttendanceStatus.overtime => const Color(0xFF8B5CF6),
  AttendanceStatus.shortHours => const Color(0xFFD97706),
  AttendanceStatus.missingOut => const Color(0xFFEF4444),
  AttendanceStatus.absent => const Color(0xFFEF4444),
  AttendanceStatus.leave => const Color(0xFF2563EB),
  AttendanceStatus.holiday => const Color(0xFF0F766E),
  AttendanceStatus.weekend => const Color(0xFF94A3B8),
  AttendanceStatus.none => const Color(0xFF64748B),
};

Color _tintOf(AttendanceStatus status) => switch (status) {
  AttendanceStatus.present => const Color(0xFFE7F8EE),
  AttendanceStatus.late => const Color(0xFFFFF0E4),
  AttendanceStatus.overtime => const Color(0xFFF3EEFF),
  AttendanceStatus.shortHours => const Color(0xFFFFF7ED),
  AttendanceStatus.missingOut => const Color(0xFFFDECEE),
  AttendanceStatus.absent => const Color(0xFFFDECEE),
  AttendanceStatus.leave => const Color(0xFFEFF6FF),
  AttendanceStatus.holiday => const Color(0xFFCCFBF1),
  AttendanceStatus.weekend => const Color(0xFFF3F4F6),
  AttendanceStatus.none => Colors.white,
};

class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeAsync = ref.watch(mobileHomeProvider);
    final segment = ref.watch(attendanceSegmentProvider);
    final viewMode = ref.watch(attendanceViewModeProvider);

    ref.listen(mobileHomeProvider, (prev, next) {
      final today = next.asData?.value.workSchedule?.companyToday;
      if (today == null) return;
      final wantedWeek = weekStartOf(today);
      final currentWeek = ref.read(attendanceWeekStartProvider);
      final deviceWeek = weekStartOf(DateTime.now());
      if (currentWeek == deviceWeek && wantedWeek != currentWeek) {
        ref.read(attendanceWeekStartProvider.notifier).state = wantedWeek;
      }
      final wantedMonth = DateTime(today.year, today.month);
      final currentMonth = ref.read(attendanceMonthProvider);
      final now = DateTime.now();
      if (currentMonth.year == now.year &&
          currentMonth.month == now.month &&
          (wantedMonth.year != currentMonth.year ||
              wantedMonth.month != currentMonth.month)) {
        ref.read(attendanceMonthProvider.notifier).state = wantedMonth;
      }
      final selected = ref.read(attendanceSelectedDayProvider);
      if (selected.year == now.year &&
          selected.month == now.month &&
          selected.day == now.day &&
          (today.year != selected.year ||
              today.month != selected.month ||
              today.day != selected.day)) {
        ref.read(attendanceSelectedDayProvider.notifier).state = DateTime(
          today.year,
          today.month,
          today.day,
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: homeAsync.when(
                skipLoadingOnReload: true,
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
                    const SizedBox(height: 8),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async {
                          invalidateAttendance(ref);
                          ref.invalidate(mobileHomeProvider);
                        },
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          child: segment == AttendanceSegment.shift
                              ? const _ShiftPane(key: ValueKey('shift'))
                              : viewMode == AttendanceViewMode.list
                              ? const _ListPane(key: ValueKey('list'))
                              : const _CalendarPane(key: ValueKey('calendar')),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (segment != AttendanceSegment.shift)
              _AttendanceFooter(home: homeAsync.asData?.value),
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
    final dateLabel = DateFormat('EEEE, MMM d').format(DateTime.now());

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Attendance',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navBlue,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dateLabel,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            gradient: _heroGradient,
            shape: BoxShape.circle,
          ),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.purpleSoft,
              backgroundImage: avatar != null
                  ? CachedNetworkImageProvider(avatar)
                  : null,
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
          ),
        ),
      ],
    );
  }
}

class _SummaryShiftToggle extends StatelessWidget {
  const _SummaryShiftToggle({required this.segment, required this.onChanged});

  final AttendanceSegment segment;
  final ValueChanged<AttendanceSegment> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE9EDF7),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentChip(
              label: 'Summary',
              icon: HugeIcons.strokeRoundedAnalyticsUp,
              selected: segment == AttendanceSegment.summary,
              onTap: () => onChanged(AttendanceSegment.summary),
            ),
          ),
          Expanded(
            child: _SegmentChip(
              label: 'Shift',
              icon: HugeIcons.strokeRoundedClock01,
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
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final List<List<dynamic>> icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected ? _heroGradient : null,
          borderRadius: BorderRadius.circular(20),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.navBlue.withValues(alpha: 0.30),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: icon,
              size: 16,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Big gradient card with the period's total hours and day counts.
class _SummaryHero extends StatelessWidget {
  const _SummaryHero({required this.label, required this.days});

  final String label;
  final List<AttendanceDay> days;

  @override
  Widget build(BuildContext context) {
    final stats = buildMonthStats(days);
    final total = formatTotalWorked(days);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: _heroGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2F6BFF).withValues(alpha: 0.26),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      total,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Total worked',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedTimer02,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  value: '${stats.presentDays}',
                  label: 'Present',
                  dot: const Color(0xFF4ADE80),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroStat(
                  value: '${stats.lateDays}',
                  label: 'Late',
                  dot: const Color(0xFFFDBA74),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroStat(
                  value: stats.overtimeLabel,
                  label: 'Overtime',
                  dot: const Color(0xFFD8B4FE),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroStat(
                  value: '${stats.absentDays}',
                  label: 'Absent',
                  dot: const Color(0xFFFCA5A5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.value,
    required this.label,
    required this.dot,
  });

  final String value;
  final String label;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShiftPane extends ConsumerWidget {
  const _ShiftPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(attendanceWeekStartProvider);
    final daysAsync = ref.watch(attendanceShiftDaysProvider);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final rangeLabel =
        '${DateFormat('dd MMM').format(weekStart)} – ${DateFormat('dd MMM yyyy').format(weekEnd)}';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _PeriodNav(
            label: rangeLabel,
            onPrev: () {
              ref.read(attendanceWeekStartProvider.notifier).state = weekStart
                  .subtract(const Duration(days: 7));
            },
            onNext: () {
              ref.read(attendanceWeekStartProvider.notifier).state = weekStart
                  .add(const Duration(days: 7));
            },
            trailing: const SizedBox(width: 4),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: daysAsync.when(
            skipLoadingOnReload: true,
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

class _DateTile extends StatelessWidget {
  const _DateTile({required this.day});

  final AttendanceDay day;

  @override
  Widget build(BuildContext context) {
    final today = day.isToday;
    final accent = _accentOf(day.status);
    final dayNum = DateFormat('dd').format(day.date);
    final weekday = DateFormat('EEE').format(day.date).toUpperCase();
    final fg = today ? Colors.white : accent;

    return Container(
      width: 52,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: today ? _heroGradient : null,
        color: today ? null : accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            dayNum,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: fg,
              height: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            weekday,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
              color: today ? Colors.white.withValues(alpha: 0.9) : fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.day});

  final AttendanceDay day;

  @override
  Widget build(BuildContext context) {
    final label = day.statusLine;
    if (label.isEmpty) return const SizedBox.shrink();
    final accent = _accentOf(day.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _ShiftDayCard extends StatelessWidget {
  const _ShiftDayCard({required this.day});

  final AttendanceDay day;

  @override
  Widget build(BuildContext context) {
    final accent = _accentOf(day.status);
    final off = day.isDayOff;
    final worked = day.workedLabel;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_tintOf(day.status), Colors.white]),
        borderRadius: BorderRadius.circular(20),
        border: day.isToday
            ? Border.all(
                color: AppColors.navBlue.withValues(alpha: 0.35),
                width: 1.2,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          _DateTile(day: day),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  off ? day.statusLine : day.displayShiftName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedClock01,
                      size: 13,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        off ? 'Day off' : day.shiftTimingLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!off) _StatusPill(day: day),
              if (worked != null && day.hasPunch) ...[
                const SizedBox(height: 6),
                Text(
                  worked,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: accent,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ListPane extends ConsumerWidget {
  const _ListPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(attendanceWeekStartProvider);
    final daysAsync = ref.watch(attendanceWeekDaysProvider);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final rangeLabel =
        '${DateFormat('dd MMM').format(weekStart)} – ${DateFormat('dd MMM yyyy').format(weekEnd)}';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _PeriodNav(
            label: rangeLabel,
            onPrev: () {
              ref.read(attendanceWeekStartProvider.notifier).state = weekStart
                  .subtract(const Duration(days: 7));
            },
            onNext: () {
              ref.read(attendanceWeekStartProvider.notifier).state = weekStart
                  .add(const Duration(days: 7));
            },
            trailing: _RoundIconButton(
              icon: HugeIcons.strokeRoundedCalendar03,
              onTap: () {
                ref.read(attendanceViewModeProvider.notifier).state =
                    AttendanceViewMode.calendar;
                ref.read(attendanceMonthProvider.notifier).state = DateTime(
                  weekStart.year,
                  weekStart.month,
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: daysAsync.when(
            skipLoadingOnReload: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _AttendanceError(
              message: e.toString(),
              onRetry: () => invalidateAttendance(ref),
            ),
            data: (days) => ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: days.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  final isThisWeek = weekStart == weekStartOf(DateTime.now());
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _SummaryHero(
                      label: isThisWeek ? 'This week' : 'Selected week',
                      days: days,
                    ),
                  );
                }
                return _AttendanceDayCard(day: days[index - 1]);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _CalendarPane extends ConsumerWidget {
  const _CalendarPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(attendanceMonthProvider);
    final daysAsync = ref.watch(attendanceMonthDaysProvider);
    final selected = ref.watch(attendanceSelectedDayProvider);
    final monthLabel = DateFormat('MMMM yyyy').format(month);

    return daysAsync.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _AttendanceError(
        message: e.toString(),
        onRetry: () => invalidateAttendance(ref),
      ),
      data: (days) {
        AttendanceDay? selectedDay;
        for (final d in days) {
          if (d.date.year == selected.year &&
              d.date.month == selected.month &&
              d.date.day == selected.day) {
            selectedDay = d;
          }
        }
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            _PeriodNav(
              label: monthLabel,
              onPrev: () {
                ref.read(attendanceMonthProvider.notifier).state = DateTime(
                  month.year,
                  month.month - 1,
                );
              },
              onNext: () {
                ref.read(attendanceMonthProvider.notifier).state = DateTime(
                  month.year,
                  month.month + 1,
                );
              },
              trailing: _RoundIconButton(
                icon: HugeIcons.strokeRoundedLeftToRightListBullet,
                onTap: () {
                  final selectedWeek = weekStartOf(selected);
                  ref.read(attendanceWeekStartProvider.notifier).state =
                      selectedWeek;
                  ref.read(attendanceViewModeProvider.notifier).state =
                      AttendanceViewMode.list;
                },
              ),
            ),
            const SizedBox(height: 8),
            _SummaryHero(label: monthLabel, days: days),
            const SizedBox(height: 14),
            _MonthCalendarGrid(
              month: month,
              days: days,
              selected: selected,
              onSelect: (d) =>
                  ref.read(attendanceSelectedDayProvider.notifier).state = d,
            ),
            const SizedBox(height: 12),
            const _CalendarLegend(),
            if (selectedDay != null) ...[
              const SizedBox(height: 14),
              _SelectedDayCard(day: selectedDay),
            ],
          ],
        );
      },
    );
  }
}

class _AttendanceError extends StatelessWidget {
  const _AttendanceError({required this.message, required this.onRetry});

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

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final List<List<dynamic>> icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.navBlue.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Center(
            child: HugeIcon(icon: icon, color: AppColors.navBlue, size: 19),
          ),
        ),
      ),
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
        Expanded(
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onPrev,
                  icon: const Icon(
                    Icons.chevron_left_rounded,
                    color: AppColors.navBlue,
                  ),
                ),
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onNext,
                  icon: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.navBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        trailing,
      ],
    );
  }
}

class _AttendanceDayCard extends StatelessWidget {
  const _AttendanceDayCard({required this.day});

  final AttendanceDay day;

  String get _emptyLabel => switch (day.status) {
    AttendanceStatus.absent => 'No punches recorded',
    AttendanceStatus.weekend => 'Day off',
    AttendanceStatus.holiday => 'Holiday',
    AttendanceStatus.leave => day.leaveName ?? 'On leave',
    AttendanceStatus.missingOut => 'Missing clock-out',
    AttendanceStatus.shortHours => 'Short of minimum hours',
    _ => day.statusDetail ?? '',
  };

  @override
  Widget build(BuildContext context) {
    final accent = _accentOf(day.status);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_tintOf(day.status), Colors.white]),
        borderRadius: BorderRadius.circular(20),
        border: day.isToday
            ? Border.all(
                color: AppColors.navBlue.withValues(alpha: 0.35),
                width: 1.2,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          _DateTile(day: day),
          const SizedBox(width: 12),
          Expanded(child: day.hasPunch ? _punchBody() : _emptyBody()),
          const SizedBox(width: 8),
          _StatusPill(day: day),
        ],
      ),
    );
  }

  Widget _emptyBody() {
    return Text(
      _emptyLabel,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _punchBody() {
    final inLabel = formatPunchClock(day.clockIn, day.clockInDate, day.date);
    final outLabel = day.clockOut == null
        ? '—'
        : formatPunchClock(day.clockOut, day.clockOutDate, day.date);
    final extraPunches = day.punches.length > 1
        ? day.punches.skip(1).toList()
        : const <HomePunch>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              inLabel,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: Color(0xFF16A34A),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _TimelineDots(status: day.status)),
            const SizedBox(width: 8),
            Text(
              outLabel,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: day.clockOut == null
                    ? AppColors.textSecondary
                    : const Color(0xFFE5484D),
              ),
            ),
          ],
        ),
        if (extraPunches.isNotEmpty) ...[
          const SizedBox(height: 4),
          for (final punch in extraPunches)
            Text(
              '${formatPunchClock(punch.clockIn, punch.clockInDate, day.date)} → ${punch.open ? 'now' : formatPunchClock(punch.clockOut, punch.clockOutDate, day.date)}',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            if (day.workedLabel != null)
              _MiniChip(
                icon: HugeIcons.strokeRoundedClock01,
                label: day.workedLabel!,
                color: AppColors.navBlue,
              ),
            if (day.overtimeLabel != null)
              _MiniChip(
                icon: HugeIcons.strokeRoundedAnalyticsUp,
                label: '+${day.overtimeLabel}',
                color: const Color(0xFF8B5CF6),
              ),
            if (day.overtimePending)
              _MiniChip(
                icon: HugeIcons.strokeRoundedAnalyticsUp,
                label: 'OT pending',
                color: const Color(0xFFD97706),
              ),
            if (day.hoursPending != null)
              _MiniChip(
                icon: HugeIcons.strokeRoundedClock01,
                label: 'Short ${day.hoursPending}',
                color: const Color(0xFFD97706),
              ),
            if (day.isEarlyOut)
              _MiniChip(
                icon: HugeIcons.strokeRoundedLogout01,
                label: 'Early out',
                color: const Color(0xFFF97316),
              ),
            if (day.isRequestPending)
              _MiniChip(
                icon: HugeIcons.strokeRoundedCalendar03,
                label: 'Pending',
                color: const Color(0xFFF97316),
              ),
          ],
        ),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final List<List<dynamic>> icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(icon: icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
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
    return SizedBox(
      height: 10,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 3,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: const LinearGradient(
                colors: [Color(0xFF86EFAC), Color(0xFFFCA5A5)],
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
              const Spacer(),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5484D),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ],
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
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.navBlue.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
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
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: h == 'SUN' || h == 'SAT'
                          ? const Color(0xFFF59E0B)
                          : AppColors.textSecondary,
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
    final isSelected =
        selected.year == date.year &&
        selected.month == date.month &&
        selected.day == date.day;
    final accent = _accentOf(day.status);

    final fg = isSelected ? Colors.white : AppColors.textPrimary;
    final timeText = switch (day.status) {
      AttendanceStatus.weekend => 'off',
      AttendanceStatus.holiday => 'hol',
      AttendanceStatus.leave => 'leave',
      AttendanceStatus.missingOut => day.clockIn ?? 'out',
      _ => day.clockIn ?? '--:--',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelect(date),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            height: 54,
            decoration: BoxDecoration(
              gradient: isSelected ? _heroGradient : null,
              color: isSelected ? null : _tintOf(day.status),
              borderRadius: BorderRadius.circular(14),
              border: day.isToday && !isSelected
                  ? Border.all(color: AppColors.navBlue, width: 1.4)
                  : null,
            ),
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
                    fontWeight: FontWeight.w700,
                    fontSize: 9.5,
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.92)
                        : accent,
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

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 6,
      children: [
        _LegendDot(color: Color(0xFF16A34A), label: 'Present'),
        _LegendDot(color: Color(0xFFF97316), label: 'Late'),
        _LegendDot(color: Color(0xFF8B5CF6), label: 'Overtime'),
        _LegendDot(color: Color(0xFFD97706), label: 'Short'),
        _LegendDot(color: Color(0xFFEF4444), label: 'Absent'),
        _LegendDot(color: Color(0xFF2563EB), label: 'Leave'),
        _LegendDot(color: Color(0xFF0F766E), label: 'Holiday'),
        _LegendDot(color: Color(0xFF94A3B8), label: 'Off'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Details for the day tapped on the calendar.
class _SelectedDayCard extends StatelessWidget {
  const _SelectedDayCard({required this.day});

  final AttendanceDay day;

  @override
  Widget build(BuildContext context) {
    final accent = _accentOf(day.status);
    final title = DateFormat('EEEE, MMM d').format(day.date);
    final off = day.isDayOff;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Container(
        key: ValueKey(day.date),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.14),
              blurRadius: 20,
              offset: const Offset(0, 10),
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
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                _StatusPill(day: day),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _FactTile(
                    icon: HugeIcons.strokeRoundedLogin01,
                    label: 'Check-in',
                    value: formatPunchClock(
                      day.clockIn,
                      day.clockInDate,
                      day.date,
                    ),
                    color: const Color(0xFF16A34A),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FactTile(
                    icon: HugeIcons.strokeRoundedLogout01,
                    label: 'Check-out',
                    value: day.clockOut == null
                        ? '--:--'
                        : formatPunchClock(
                            day.clockOut,
                            day.clockOutDate,
                            day.date,
                          ),
                    color: const Color(0xFFE5484D),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _FactTile(
                    icon: HugeIcons.strokeRoundedClock01,
                    label: 'Worked',
                    value: day.hasPunch ? (day.workedLabel ?? '—') : '—',
                    color: AppColors.navBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FactTile(
                    icon: HugeIcons.strokeRoundedAnalyticsUp,
                    label: 'Overtime',
                    value: day.overtimeLabel ??
                        (day.overtimePending ? 'Pending' : 'None'),
                    color: day.overtimePending
                        ? const Color(0xFFD97706)
                        : const Color(0xFF8B5CF6),
                  ),
                ),
              ],
            ),
            if (day.punches.length > 1) ...[
              const SizedBox(height: 10),
              for (final punch in day.punches)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${formatPunchClock(punch.clockIn, punch.clockInDate, day.date)} → ${punch.open ? 'now' : formatPunchClock(punch.clockOut, punch.clockOutDate, day.date)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
            if (day.leaveName != null) ...[
              const SizedBox(height: 8),
              Text(
                day.leaveName!,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: Color(0xFF2563EB),
                ),
              ),
            ],
            if (!off) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedCalendar03,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${day.displayShiftName} · ${day.shiftTimingLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: HugeIcon(icon: icon, color: Colors.white, size: 15),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceFooter extends ConsumerWidget {
  const _AttendanceFooter({required this.home});

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

  String _statusLine(MobileHome? h) {
    if (h == null) return '';
    if (h.isClockedIn) {
      return h.clockInTime == null ? 'On the clock' : 'Since ${h.clockInTime}';
    }
    if (h.clockOutTime != null) return 'Last check-out ${h.clockOutTime}';
    return 'Not clocked in today';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(punchBusyProvider);
    final isClockedIn = home?.isClockedIn ?? false;
    final buttonColor = isClockedIn
        ? const Color(0xFFE5484D)
        : const Color(0xFF16A34A);
    final buttonLabel = isClockedIn ? 'Check-out' : 'Check-in';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: isClockedIn
                              ? const Color(0xFF16A34A)
                              : AppColors.textSecondary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isClockedIn ? 'Clocked in' : 'Clocked out',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _statusLine(home),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (home?.geofenceEnabled == true) ...[
                    const SizedBox(height: 4),
                    const FenceStatusLine(align: TextAlign.start),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: home == null || busy
                  ? null
                  : () => _onPunch(context, ref),
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: buttonColor.withValues(alpha: 0.5),
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
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
