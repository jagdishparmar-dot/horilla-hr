import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/api/dio_client.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../home/fence_status_line.dart';
import '../home/home_provider.dart';
import '../home/home_typography.dart';
import '../home/models.dart';
import 'attendance_mapper.dart';
import 'attendance_provider.dart';
import 'models.dart';

const _iosBg = Color(0xFFF2F2F7);
const _iosText = Color(0xFF1C1C1E);
const _iosMuted = Color(0xFF8E8E93);
const _iosSecondary = Color(0xFF636366);
const _iosBlue = AppColors.navBlue;
const _iosGreen = Color(0xFF34C759);
const _iosGreenText = Color(0xFF248A3D);
const _iosAmber = Color(0xFFFF9500);
const _iosAmberText = Color(0xFFC97000);
const _iosRed = Color(0xFFFF3B30);
const _iosHairline = Color(0x0A000000);

BoxDecoration _iosCard({
  double radius = 13,
  Color? borderColor,
  double borderWidth = 1,
}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor ?? _iosHairline, width: borderWidth),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  );
}

Color _accentOf(AttendanceStatus status) => switch (status) {
  AttendanceStatus.present => _iosGreenText,
  AttendanceStatus.late => _iosAmberText,
  AttendanceStatus.overtime => _iosGreenText,
  AttendanceStatus.shortHours => _iosAmberText,
  AttendanceStatus.missingOut => _iosRed,
  AttendanceStatus.absent => _iosRed,
  AttendanceStatus.leave => _iosBlue,
  AttendanceStatus.holiday => const Color(0xFF30B0C7),
  AttendanceStatus.weekend => _iosSecondary,
  AttendanceStatus.none => _iosMuted,
};

Color _tintOf(AttendanceStatus status) => switch (status) {
  AttendanceStatus.present => const Color(0x2634C759),
  AttendanceStatus.late => const Color(0x26FF9500),
  AttendanceStatus.overtime => const Color(0x2634C759),
  AttendanceStatus.shortHours => const Color(0x26FF9500),
  AttendanceStatus.missingOut => const Color(0x26FF3B30),
  AttendanceStatus.absent => const Color(0x26FF3B30),
  AttendanceStatus.leave => const Color(0x262F6BFF),
  AttendanceStatus.holiday => const Color(0x2630B0C7),
  AttendanceStatus.weekend => const Color(0x1F767680),
  AttendanceStatus.none => _iosBg,
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

    return Theme(
      data: HomeType.of(context),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: _iosBg,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: homeAsync.when(
                    skipLoadingOnReload: true,
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: _iosBlue),
                    ),
                    error: (e, _) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              userFacingError(e),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () =>
                                  ref.invalidate(mobileHomeProvider),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    data: (home) => Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: _AttendanceHeader(home: home),
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _SummaryShiftToggle(
                            segment: segment,
                            onChanged: (s) =>
                                ref
                                        .read(
                                          attendanceSegmentProvider.notifier,
                                        )
                                        .state =
                                    s,
                          ),
                        ),
                        const SizedBox(height: 10),
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
                                  : const _CalendarPane(
                                      key: ValueKey('calendar'),
                                    ),
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
              Text(
                'Attendance',
                style: HomeType.headline(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _iosText,
                  letterSpacing: -0.4,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dateLabel,
                style: HomeType.body(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _iosMuted,
                ),
              ),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: CircleAvatar(
                backgroundColor: const Color(0xFFEAF0FF),
                backgroundImage: avatar != null
                    ? CachedNetworkImageProvider(avatar)
                    : null,
                child: avatar == null
                    ? Text(
                        home.firstName.isNotEmpty
                            ? home.firstName[0].toUpperCase()
                            : '?',
                        style: HomeType.headline(
                          color: _iosBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: _iosGreen,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
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
      height: 32,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0x1F767680),
        borderRadius: BorderRadius.circular(9),
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
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 1,
                    offset: const Offset(0, 1),
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
              color: selected ? _iosBlue : _iosSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: selected
                  ? HomeType.headline(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _iosText,
                    )
                  : HomeType.body(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: _iosSecondary,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Period totals as compact iOS metric tiles. Same stats as before.
class _SummaryHero extends StatelessWidget {
  const _SummaryHero({required this.label, required this.days});

  final String label;
  final List<AttendanceDay> days;

  @override
  Widget build(BuildContext context) {
    final stats = buildMonthStats(days);
    final total = formatTotalWorked(days);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: _iosCard(),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: HomeType.body(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _iosMuted,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Total worked',
                      style: HomeType.body(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _iosSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                total,
                style: HomeType.headline(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _iosText,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'Present',
                value: '${stats.presentDays}',
                icon: HugeIcons.strokeRoundedCheckmarkCircle02,
                accent: _iosGreen,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricTile(
                label: 'Late',
                value: '${stats.lateDays}',
                icon: HugeIcons.strokeRoundedTimer02,
                accent: _iosAmber,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'Overtime',
                value: stats.overtimeLabel,
                icon: HugeIcons.strokeRoundedAnalyticsUp,
                accent: _iosGreen,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricTile(
                label: 'Absent',
                value: '${stats.absentDays}',
                icon: HugeIcons.strokeRoundedCancelCircle,
                accent: _iosRed,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final List<List<dynamic>> icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: _iosCard(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: HomeType.body(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _iosMuted,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HomeType.headline(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _iosText,
                    letterSpacing: -0.4,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: HugeIcon(icon: icon, color: accent, size: 18),
            ),
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
              message: userFacingError(e),
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
    final dayNum = DateFormat('dd').format(day.date);
    final weekday = DateFormat('EEE').format(day.date).toUpperCase();

    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: today ? _iosBlue : _iosBg,
        borderRadius: BorderRadius.circular(9),
        border: today ? null : Border.all(color: const Color(0x08000000)),
        boxShadow: today
            ? [
                BoxShadow(
                  color: _iosBlue.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            weekday,
            style: HomeType.body(
              fontWeight: FontWeight.w600,
              fontSize: 9,
              letterSpacing: 0.4,
              color: today ? Colors.white.withValues(alpha: 0.9) : _iosMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            dayNum,
            style: HomeType.headline(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: today ? Colors.white : _iosText,
              height: 1.1,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _tintOf(day.status),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: HomeType.headline(
          color: accent,
          fontWeight: FontWeight.w600,
          fontSize: 10,
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
              message: userFacingError(e),
              onRetry: () => invalidateAttendance(ref),
            ),
            data: (days) => ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: days.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
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
        message: userFacingError(e),
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
      color: _iosBlue.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: HugeIcon(icon: icon, color: _iosBlue, size: 16),
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
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: _iosCard(),
            child: Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: onPrev,
                  icon: const Icon(
                    Icons.chevron_left_rounded,
                    color: _iosBlue,
                    size: 22,
                  ),
                ),
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: HomeType.headline(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _iosText,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: onNext,
                  icon: const Icon(
                    Icons.chevron_right_rounded,
                    color: _iosBlue,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: _iosCard(
        borderColor: day.isToday ? _iosBlue : _iosHairline,
        borderWidth: day.isToday ? 2 : 1,
      ).copyWith(color: day.isToday ? const Color(0x082F6BFF) : Colors.white),
      child: Row(
        children: [
          _DateTile(day: day),
          const SizedBox(width: 10),
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
      style: HomeType.body(
        fontWeight: FontWeight.w500,
        fontSize: 13,
        color: _iosMuted,
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
              style: HomeType.headline(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: _iosGreen,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '→',
                style: HomeType.body(fontSize: 11, color: _iosMuted),
              ),
            ),
            Text(
              day.clockOut == null ? '—' : outLabel,
              style: HomeType.headline(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: day.clockOut == null ? _iosMuted : _iosRed,
              ),
            ),
          ],
        ),
        if (extraPunches.isNotEmpty) ...[
          const SizedBox(height: 2),
          for (final punch in extraPunches)
            Text(
              '${formatPunchClock(punch.clockIn, punch.clockInDate, day.date)} → ${punch.open ? 'now' : formatPunchClock(punch.clockOut, punch.clockOutDate, day.date)}',
              style: HomeType.body(
                fontWeight: FontWeight.w500,
                fontSize: 10,
                color: _iosMuted,
              ),
            ),
        ],
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            if (day.clockOut == null && day.hasPunch)
              const _MiniChip(
                icon: HugeIcons.strokeRoundedClock01,
                label: 'In progress',
                color: _iosGreenText,
              ),
            if (day.workedLabel != null)
              _MiniChip(
                icon: HugeIcons.strokeRoundedClock01,
                label: day.workedLabel!,
                color: _iosBlue,
              ),
            if (day.overtimeLabel != null)
              _MiniChip(
                icon: HugeIcons.strokeRoundedAnalyticsUp,
                label: '+${day.overtimeLabel}',
                color: _iosGreenText,
              ),
            if (day.overtimePending)
              const _MiniChip(
                icon: HugeIcons.strokeRoundedAnalyticsUp,
                label: 'OT pending',
                color: _iosAmberText,
              ),
            if (day.hoursPending != null)
              _MiniChip(
                icon: HugeIcons.strokeRoundedClock01,
                label: 'Short ${day.hoursPending}',
                color: _iosAmberText,
              ),
            if (day.isEarlyOut)
              const _MiniChip(
                icon: HugeIcons.strokeRoundedLogout01,
                label: 'Early out',
                color: _iosAmberText,
              ),
            if (day.isRequestPending)
              const _MiniChip(
                icon: HugeIcons.strokeRoundedCalendar03,
                label: 'Pending',
                color: _iosAmberText,
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(icon: icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: HomeType.body(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w500,
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
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      decoration: _iosCard(radius: 16),
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
              color: isSelected ? _iosBlue : _tintOf(day.status),
              borderRadius: BorderRadius.circular(14),
              border: day.isToday && !isSelected
                  ? Border.all(color: _iosBlue, width: 1.4)
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
        _LegendDot(color: _iosGreen, label: 'Present'),
        _LegendDot(color: _iosAmber, label: 'Late'),
        _LegendDot(color: _iosGreen, label: 'Overtime'),
        _LegendDot(color: _iosAmber, label: 'Short'),
        _LegendDot(color: _iosRed, label: 'Absent'),
        _LegendDot(color: _iosBlue, label: 'Leave'),
        _LegendDot(color: Color(0xFF30B0C7), label: 'Holiday'),
        _LegendDot(color: _iosMuted, label: 'Off'),
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
                    value:
                        day.overtimeLabel ??
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
    final buttonColor = isClockedIn ? _iosRed : _iosGreen;
    final buttonLabel = isClockedIn ? 'Check-out' : 'Check-in';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0x0F000000))),
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
                          color: isClockedIn ? _iosGreen : _iosMuted,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isClockedIn ? 'Clocked in' : 'Clocked out',
                        style: HomeType.headline(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: _iosText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _statusLine(home),
                    style: HomeType.body(
                      color: _iosMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
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
                  borderRadius: BorderRadius.circular(12),
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
                          style: HomeType.headline(
                            fontWeight: FontWeight.w700,
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
