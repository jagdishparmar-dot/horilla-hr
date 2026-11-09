import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../requests/models.dart';
import '../requests/request_details_sheet.dart';
import '../shell/main_shell.dart';
import 'models.dart';

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
    required this.color,
    required this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final Color color;
  final List<List<dynamic>> icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: HugeIcon(icon: icon, color: color, size: 16),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
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
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                actionLabel!,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
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

        return Container(
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
                        color: AppColors.orange.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: HugeIcon(
                          icon: HugeIcons.strokeRoundedMegaphone01,
                          color: AppColors.orange,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Announcement',
                        style: TextStyle(
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
                        style: const TextStyle(
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
                            color: AppColors.orange,
                            fontWeight: FontWeight.w700,
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final created = announcement.createdAt == null
        ? null
        : DateFormat('MMM d, yyyy').format(announcement.createdAt!.toLocal());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeSectionTitle(
          title: 'Announcement',
          color: Color(0xFFF59E0B),
          icon: HugeIcons.strokeRoundedMegaphone01,
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: () => _openDetails(context),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFF1D6), Color(0xFFFFE7F0)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFFB84D), Color(0xFFF97316)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedMegaphone01,
                        color: Colors.white,
                        size: 21,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          announcement.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          announcement.previewText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        if (created != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const HugeIcon(
                                icon: HugeIcons.strokeRoundedCalendar03,
                                color: AppColors.textSecondary,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                created,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
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

class HomeWorkScheduleSection extends ConsumerWidget {
  const HomeWorkScheduleSection({super.key, required this.schedule});

  final HomeWorkSchedule? schedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final weekStart =
        schedule?.weekStart ?? now.subtract(Duration(days: (now.weekday % 7)));
    final weekEnd = schedule?.weekEnd ?? weekStart.add(const Duration(days: 6));
    final range =
        '${DateFormat('dd-MMM-yyyy').format(weekStart)} / ${DateFormat('dd-MMM-yyyy').format(weekEnd)}';

    final preview = schedule?.previewDays;
    final days = (preview != null && preview.isNotEmpty)
        ? preview
        : [
            HomeScheduleDay(
              date: DateTime(now.year, now.month, now.day),
              dayKey: '',
              shiftName: schedule?.shiftName ?? 'General',
              startTime: '09:00',
              endTime: '17:00',
              isToday: true,
              hasSchedule: false,
            ),
            HomeScheduleDay(
              date: DateTime(
                now.year,
                now.month,
                now.day,
              ).add(const Duration(days: 1)),
              dayKey: '',
              shiftName: schedule?.shiftName ?? 'General',
              startTime: '09:00',
              endTime: '17:00',
              isToday: false,
              hasSchedule: false,
            ),
          ];

    return Container(
      padding: const EdgeInsets.all(16),
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
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF5B8CFF), Color(0xFF2F6BFF)],
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Center(
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedClock01,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Work Schedule',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      range,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < days.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _ScheduleDayRow(day: days[i]),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                ref.read(shellIndexProvider.notifier).state = 1;
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.navBlue,
                side: const BorderSide(color: Color(0xFFD1D5DB)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'View Full Schedule',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(width: 4),
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowRight01,
                    color: AppColors.navBlue,
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

class _ScheduleDayRow extends StatelessWidget {
  const _ScheduleDayRow({required this.day});

  final HomeScheduleDay day;

  @override
  Widget build(BuildContext context) {
    final dayNum = DateFormat('dd').format(day.date);
    final weekday = DateFormat('EEE').format(day.date).toUpperCase();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: day.isToday
            ? const LinearGradient(
                colors: [Color(0xFFE3ECFF), Color(0xFFF0E9FF)],
              )
            : null,
        color: day.isToday ? null : const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: day.isToday ? AppColors.navBlue : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$dayNum\n$weekday',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                height: 1.15,
                fontSize: 11,
                color: day.isToday ? Colors.white : AppColors.navBlue,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day.shiftName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                Text(
                  day.timingLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (day.isToday)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.navBlue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Today',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
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
          color: const Color(0xFF8B5CF6),
          icon: HugeIcons.strokeRoundedFile02,
          actionLabel: 'View all',
          onAction: () => ref.read(shellIndexProvider.notifier).state = 2,
        ),
        const SizedBox(height: 12),
        if (preview.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
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
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [item.status.softBackground, Colors.white],
          ),
          boxShadow: [
            BoxShadow(
              color: item.status.color.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: HugeIcon(
                      icon: item.icon,
                      color: item.accent,
                      size: 20,
                    ),
                  ),
                ),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
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
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
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
                            color: AppColors.textSecondary,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            item.durationLabel,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const HugeIcon(
                            icon: HugeIcons.strokeRoundedCalendar03,
                            color: AppColors.textSecondary,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _dateLabel,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
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
        HomeSectionTitle(
          title: widget.title,
          color: widget.avatarColor,
          icon: widget.icon,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.avatarColor.withValues(alpha: 0.12),
                Colors.white,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: widget.avatarColor.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
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
                                          style: TextStyle(
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
                                style: TextStyle(
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
                            style: TextStyle(
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
                          style: const TextStyle(
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
                        hintStyle: const TextStyle(
                          color: Color(0xFF9CA3AF),
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
                    color: AppColors.navBlue,
                    borderRadius: BorderRadius.circular(12),
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
