import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../attendance/attendance_provider.dart';
import '../attendance/models.dart';
import '../requests/models.dart';
import '../requests/request_details_sheet.dart';
import '../shell/main_shell.dart';
import 'announcements_screen.dart';
import 'home_typography.dart';
import 'models.dart';

const Color homeLine = Color(0x1A000000);

/// One accent for the whole screen: primary blue and a soft tint of it.
const Color homePrimary = AppColors.navBlue;
const Color homePrimarySoft = Color(0xFFEAF0FF);
const Color homeAmber = Color(0xFF854D0E);
const Color homeAmberSoft = Color(0xFFFEF9C3);
const Color homeGreenSoft = Color(0xFFDCFCE7);
const Color homeGreenDeep = Color(0xFF166534);

BoxDecoration homeSurface({double radius = 16}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: homeLine),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

/// Rounded tinted square that holds a primary-colored icon.
class HomeIconBadge extends StatelessWidget {
  const HomeIconBadge({
    super.key,
    required this.icon,
    this.size = 40,
    this.iconSize = 20,
  });

  final List<List<dynamic>> icon;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: homePrimarySoft,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Center(
        child: HugeIcon(icon: icon, color: homePrimary, size: iconSize),
      ),
    );
  }
}

/// Fades and slides a section in once, staggered by [index].
class HomeReveal extends StatelessWidget {
  const HomeReveal({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + index * 90),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 18),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Section heading with a colored accent chip and an optional trailing action.
class HomeSectionTitle extends StatelessWidget {
  const HomeSectionTitle({
    super.key,
    required this.title,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.showBar = false,
  });

  final String title;
  final List<List<dynamic>>? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showBar;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showBar) ...[
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: homePrimary,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (icon != null) ...[
          HugeIcon(icon: icon!, color: homePrimary, size: 18),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            title,
            style: HomeType.headline(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  color: homePrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class HomeAnnouncementSection extends StatelessWidget {
  const HomeAnnouncementSection({super.key, required this.announcement});

  final HomeAnnouncement announcement;

  Future<void> _openDetails(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bottom = MediaQuery.paddingOf(context).bottom;
        final created = announcement.createdAt == null
            ? null
            : DateFormat('MMM d, yyyy · h:mm a')
                  .format(announcement.createdAt!.toLocal());
        final expires = announcement.expireDate == null
            ? null
            : DateFormat('MMM d, yyyy').format(announcement.expireDate!);
        final body = (announcement.description ?? '').trim();

        return Theme(
          data: HomeType.of(context),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.78,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: homePrimarySoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedMegaphone01,
                            color: homePrimary,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Announcement',
                          style: HomeType.headline(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedCancel01,
                          color: AppColors.textSecondary,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottom),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          announcement.title,
                          style: HomeType.headline(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (created != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            created,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (expires != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Expires $expires',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          body.isEmpty ? 'No additional details.' : body,
                          style: TextStyle(
                            color: body.isEmpty
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                            fontSize: 15,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final created = announcement.createdAt == null
        ? null
        : DateFormat('MMM d').format(announcement.createdAt!.toLocal());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionTitle(
          title: 'Announcement',
          icon: HugeIcons.strokeRoundedMegaphone01,
          showBar: true,
          actionLabel: 'View all',
          onAction: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AnnouncementsScreen(),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () => _openDetails(context),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: homeSurface(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [homePrimary, Color(0xFF0052E1)],
                      ),
                    ),
                    child: const Center(
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedMegaphone01,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                announcement.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: HomeType.headline(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (created != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: homeAmberSoft,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  created,
                                  style: const TextStyle(
                                    color: homeAmber,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          announcement.previewText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  const HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowRight01,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class HomeWorkScheduleSection extends ConsumerStatefulWidget {
  const HomeWorkScheduleSection({super.key, required this.schedule});

  final HomeWorkSchedule? schedule;

  @override
  ConsumerState<HomeWorkScheduleSection> createState() =>
      _HomeWorkScheduleSectionState();
}

class _HomeWorkScheduleSectionState
    extends ConsumerState<HomeWorkScheduleSection> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final schedule = widget.schedule;
    final allDays = schedule?.days ?? const <HomeScheduleDay>[];
    final days = allDays.length <= 7
        ? allDays
        : () {
            final today = allDays.indexWhere((d) => d.isToday);
            final start = (today < 0 ? 0 : today - 3).clamp(
              0,
              allDays.length - 7,
            );
            return allDays.sublist(start, start + 7);
          }();
    final monthLabel = DateFormat('MMMM yyyy')
        .format(schedule?.companyToday ?? DateTime.now());
    final todayIndex = days.indexWhere((d) => d.isToday);
    final selectedIndex = days.isEmpty
        ? 0
        : (_selectedIndex ?? (todayIndex >= 0 ? todayIndex : 0)).clamp(
            0,
            days.length - 1,
          );
    final selected = days.isEmpty ? null : days[selectedIndex];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: homeSurface(),
      child: Column(
        children: [
          Row(
            children: [
              const HomeIconBadge(
                icon: HugeIcons.strokeRoundedCalendar03,
                size: 28,
                iconSize: 15,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Work Schedule',
                  style: HomeType.headline(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: homePrimarySoft,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  monthLabel,
                  style: const TextStyle(
                    color: homePrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (days.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No schedule assigned',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            )
          else ...[
            Row(
              children: [
                for (var i = 0; i < days.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: _WeekDayCell(
                      day: days[i],
                      selected: i == selectedIndex,
                      onTap: () => setState(() => _selectedIndex = i),
                    ),
                  ),
                ],
              ],
            ),
            if (selected != null) ...[
              const SizedBox(height: 12),
              _SelectedShiftCard(day: selected),
            ],
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                ref.read(attendanceSegmentProvider.notifier).state =
                    AttendanceSegment.shift;
                final companyStart = widget.schedule?.weekStart;
                ref
                    .read(attendanceWeekStartProvider.notifier)
                    .state = companyStart != null
                    ? DateTime(
                        companyStart.year,
                        companyStart.month,
                        companyStart.day,
                      )
                    : weekStartOf(
                        widget.schedule?.companyToday ?? DateTime.now(),
                      );
                ref.read(shellIndexProvider.notifier).state = 1;
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: homePrimary,
                backgroundColor: const Color(0xFFF0F5FF),
                side: BorderSide(color: homePrimary.withValues(alpha: 0.3)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'View Full Schedule',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  SizedBox(width: 4),
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowRight01,
                    color: homePrimary,
                    size: 18,
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

class _WeekDayCell extends StatelessWidget {
  const _WeekDayCell({
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final HomeScheduleDay day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final weekday = DateFormat('EEE').format(day.date).toUpperCase();
    final dayNum = DateFormat('dd').format(day.date);
    final muted = !day.hasSchedule && !selected;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: muted ? 0.6 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? homePrimary : const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(12),
            border: selected ? null : Border.all(color: homeLine),
          ),
          child: Column(
            children: [
              Text(
                weekday,
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.9)
                      : const Color(0xFF9CA3AF),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dayNum,
                style: HomeType.headline(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : const Color(0xFF4B5563),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? Colors.white
                      : (day.hasSchedule
                            ? homePrimary.withValues(alpha: 0.4)
                            : Colors.transparent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedShiftCard extends StatelessWidget {
  const _SelectedShiftCard({required this.day});

  final HomeScheduleDay day;

  @override
  Widget build(BuildContext context) {
    final title = day.hasSchedule
        ? (day.shiftName.trim().isEmpty ? 'Shift' : day.shiftName)
        : 'Day off';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F5FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: homePrimary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: day.hasSchedule
                      ? AppColors.green
                      : AppColors.textSecondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HomeType.headline(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              if (day.isToday)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: homePrimary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Text(
                    'Today',
                    style: TextStyle(
                      color: homePrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const HugeIcon(
                icon: HugeIcons.strokeRoundedClock01,
                color: homePrimary,
                size: 15,
              ),
              const SizedBox(width: 6),
              Text(
                day.hasSchedule ? day.timingLabel : 'No hours scheduled',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class HomeRecentRequestsSection extends ConsumerWidget {
  const HomeRecentRequestsSection({super.key, required this.requests});

  final List<HomeRecentRequest> requests;

  LeaveRequestItem _toLeaveItem(HomeRecentRequest item) {
    return LeaveRequestItem(
      id: item.id,
      title: item.title,
      status: RequestStatusX.fromApi(item.status),
      requestedDays: item.requestedDays,
      startDate: item.startDate,
      endDate: item.endDate,
      kind: switch (item.kind) {
        'remote' => RequestKind.remote,
        'annual' => RequestKind.annual,
        'early' => RequestKind.early,
        'casual' => RequestKind.casual,
        'permission' => RequestKind.permission,
        _ => RequestKind.other,
      },
      reason: item.reason,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = requests.take(2).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionTitle(
          title: 'Recent Requests',
          actionLabel: 'View all',
          onAction: () => ref.read(shellIndexProvider.notifier).state = 2,
        ),
        const SizedBox(height: 12),
        if (preview.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            decoration: homeSurface(),
            child: Column(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedFile02,
                  color: const Color(0xFFCBD5E1),
                  size: 34,
                ),
                const SizedBox(height: 8),
                const Text(
                  'No recent requests',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < preview.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _HomeRequestCard(
              item: _toLeaveItem(preview[i]),
              onTap: () => showRequestDetailsSheet(
                context,
                item: _toLeaveItem(preview[i]),
              ),
            ),
          ],
      ],
    );
  }
}

class _HomeRequestCard extends StatelessWidget {
  const _HomeRequestCard({required this.item, required this.onTap});

  final LeaveRequestItem item;
  final VoidCallback onTap;

  String get _dateLabel {
    final start = DateFormat('MMM d, yyyy').format(item.startDate);
    if (item.startDate.year == item.endDate.year &&
        item.startDate.month == item.endDate.month &&
        item.startDate.day == item.endDate.day) {
      return start;
    }
    final sameYear = item.startDate.year == item.endDate.year;
    final startFmt = DateFormat(sameYear ? 'MMM d' : 'MMM d, yyyy')
        .format(item.startDate);
    final endFmt = DateFormat('MMM d, yyyy').format(item.endDate);
    return '$startFmt to $endFmt';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: homeSurface(),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(
              children: [
                HomeIconBadge(icon: item.icon, size: 40, iconSize: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: HomeType.headline(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: item.status.pillBackground,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              item.status.label,
                              style: TextStyle(
                                color: item.status.color,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.durationLabel}  ·  $_dateLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowRight01,
                  color: Color(0xFFB0B7C3),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomePeopleMessageSection extends StatefulWidget {
  const HomePeopleMessageSection({
    super.key,
    required this.title,
    required this.colleagues,
    required this.placeholder,
    required this.avatarColor,
    this.icon = HugeIcons.strokeRoundedUserGroup,
  });

  final String title;
  final List<HomeColleague> colleagues;
  final String placeholder;
  final Color avatarColor;
  final List<List<dynamic>> icon;

  @override
  State<HomePeopleMessageSection> createState() =>
      _HomePeopleMessageSectionState();
}

class _HomePeopleMessageSectionState extends State<HomePeopleMessageSection> {
  late final TextEditingController _controller;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _resolveAvatar(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    return '${AppConfig.mediaOrigin}$url';
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.colleagues;
    if (people.isEmpty) return const SizedBox.shrink();
    final index = _selected.clamp(0, people.length - 1);
    final colleague = people[index];
    final avatar = _resolveAvatar(colleague.avatarUrl);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionTitle(title: widget.title, icon: widget.icon),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: homeSurface(),
          child: Column(
            children: [
              if (people.length > 1) ...[
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: people.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final person = people[i];
                      final photo = _resolveAvatar(person.avatarUrl);
                      final selected = i == index;
                      return GestureDetector(
                        onTap: () => setState(() => _selected = i),
                        child: SizedBox(
                          width: 64,
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selected
                                        ? widget.avatarColor
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: widget.avatarColor
                                      .withValues(alpha: 0.15),
                                  backgroundImage: photo != null
                                      ? CachedNetworkImageProvider(photo)
                                      : null,
                                  child: photo == null
                                      ? Text(
                                          person.name.isNotEmpty
                                              ? person.name[0].toUpperCase()
                                              : '?',
                                          style: HomeType.headline(
                                            color: widget.avatarColor,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                person.name.split(' ').first,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: HomeType.headline(
                                  fontSize: 11,
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: selected
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: widget.avatarColor.withValues(alpha: 0.15),
                    backgroundImage: avatar != null
                        ? CachedNetworkImageProvider(avatar)
                        : null,
                    child: avatar == null
                        ? Text(
                            colleague.name.isNotEmpty
                                ? colleague.name[0].toUpperCase()
                                : '?',
                            style: HomeType.headline(
                              color: widget.avatarColor,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          colleague.name,
                          style: HomeType.headline(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          colleague.roleLabel,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: widget.placeholder,
                        hintStyle: HomeType.body(
                          color: const Color(0xFF9CA3AF),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF3F4F6),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: homePrimary,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: () {
                        final text = _controller.text.trim();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              text.isEmpty
                                  ? 'Write a message first'
                                  : 'Message sent',
                            ),
                          ),
                        );
                        if (text.isNotEmpty) _controller.clear();
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: const SizedBox(
                        width: 46,
                        height: 46,
                        child: Center(
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedSent,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
