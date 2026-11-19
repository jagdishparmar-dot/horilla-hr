import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/api/dio_client.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../auth/auth_provider.dart';
import '../more/profile_screen.dart';
import '../shell/main_shell.dart';
import 'fence_status_line.dart';
import 'home_extra_sections.dart';
import 'home_provider.dart';
import 'home_typography.dart';
import 'models.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeAsync = ref.watch(mobileHomeProvider);

    Future<void> refresh() async {
      ref.invalidate(mobileHomeProvider);
      ref.invalidate(punchFenceProvider);
      try {
        await ref.read(mobileHomeProvider.future);
      } catch (_) {
        // The provider keeps the error; the pane below shows it.
      }
    }

    return Theme(
      data: HomeType.of(context),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: AppColors.scaffold,
          body: homeAsync.when(
            skipLoadingOnReload: true,
            loading: () => const SafeArea(
              bottom: false,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.navBlue),
              ),
            ),
            error: (e, _) => _PinnedRefresh(
              onRefresh: refresh,
              header: const SizedBox(height: 4),
              child: _ErrorPane(
                message: userFacingError(e),
                onRetry: () {
                  refresh();
                },
                onLogout: () => ref.read(authProvider.notifier).logout(),
              ),
            ),
            data: (home) => _PinnedRefresh(
              onRefresh: refresh,
              header: HomeReveal(index: 0, child: _Header(home: home)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HomeReveal(index: 1, child: _AttendanceCard(home: home)),
                  const SizedBox(height: 16),
                  HomeReveal(index: 2, child: _QuickActions(home: home)),
                  if (home.announcement != null) ...[
                    const SizedBox(height: 24),
                    HomeReveal(
                      index: 3,
                      child: HomeAnnouncementSection(
                        announcement: home.announcement!,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  HomeReveal(
                    index: 4,
                    child: HomeWorkScheduleSection(schedule: home.workSchedule),
                  ),
                  const SizedBox(height: 24),
                  HomeReveal(
                    index: 5,
                    child: HomeRecentRequestsSection(
                      requests: home.recentRequests,
                    ),
                  ),
                  if (home.birthdays.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    HomeReveal(
                      index: 6,
                      child: HomePeopleMessageSection(
                        title: 'Birthdays Today',
                        colleagues: home.birthdays,
                        placeholder: 'Write a birthday wish...',
                        avatarColor: AppColors.navBlue,
                        icon: HugeIcons.strokeRoundedGift,
                      ),
                    ),
                  ],
                  if (home.newHires.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    HomeReveal(
                      index: 7,
                      child: HomePeopleMessageSection(
                        title: 'New Hires',
                        colleagues: home.newHires,
                        placeholder: 'Write a welcome message...',
                        avatarColor: AppColors.navBlue,
                        icon: HugeIcons.strokeRoundedUserAdd01,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps [header] fixed under the status bar while only [child] scrolls
/// and accepts the pull-to-refresh gesture.
class _PinnedRefresh extends StatelessWidget {
  const _PinnedRefresh({
    required this.header,
    required this.child,
    required this.onRefresh,
  });

  final Widget header;
  final Widget child;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF4F7FF), Colors.white],
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x1A1E3A8A),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, top + 10, 16, 14),
            child: header,
          ),
        ),
        Expanded(
          child: ClipRect(
            child: RefreshIndicator(
              color: AppColors.navBlue,
              backgroundColor: Colors.white,
              displacement: 28,
              onRefresh: onRefresh,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight > 32
                            ? constraints.maxHeight - 32
                            : 0,
                      ),
                      child: child,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.home});

  final MobileHome home;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String? _resolveAvatar(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    return '${AppConfig.mediaOrigin}$url';
  }

  @override
  Widget build(BuildContext context) {
    final avatar = _resolveAvatar(home.avatarUrl);
    final role = home.roleLine;
    final dateLabel = DateFormat('EEEE, MMM d').format(DateTime.now());
    final hour = DateTime.now().hour;
    final greetingIcon = hour < 17
        ? HugeIcons.strokeRoundedSun03
        : HugeIcons.strokeRoundedMoon02;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Semantics(
          button: true,
          label: 'Profile',
          child: GestureDetector(
            key: const Key('home-avatar'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ProfileScreen(backLabel: null),
                ),
              );
            },
            child: SizedBox(
              width: 52,
              height: 52,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                        colors: [
                          homePrimary,
                          Color(0xFF638AFF),
                          Color(0xFFA3F69C),
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.white,
                        backgroundImage: avatar != null
                            ? CachedNetworkImageProvider(avatar)
                            : null,
                        child: avatar == null
                            ? Text(
                                home.firstName.isNotEmpty
                                    ? home.firstName[0].toUpperCase()
                                    : '?',
                                style: HomeType.headline(
                                  color: homePrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: homeGreenDeep,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
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
                  HugeIcon(icon: greetingIcon, color: homeAmber, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '$_greeting, ',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      home.firstName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HomeType.headline(
                        color: AppColors.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (role.isNotEmpty)
                    Text(
                      role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF4B5563),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: homePrimarySoft,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: homePrimary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: homePrimary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          home.placeLabel,
                          style: const TextStyle(
                            color: homePrimary,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const HugeIcon(
                    icon: HugeIcons.strokeRoundedCalendar03,
                    color: Color(0xFF9CA3AF),
                    size: 13,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      dateLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _NotifyButton(count: home.unreadNotifications),
      ],
    );
  }
}

class _NotifyButton extends ConsumerWidget {
  const _NotifyButton({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = count > 9 ? '9+' : '$count';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => ref.read(shellIndexProvider.notifier).state = 3,
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: homeLine),
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              const HugeIcon(
                icon: HugeIcons.strokeRoundedNotification03,
                color: Color(0xFF24334A),
                size: 21,
              ),
              if (count > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.home});

  final MobileHome home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void go(int i) => ref.read(shellIndexProvider.notifier).state = i;
    final unread = home.unreadNotifications;
    return Row(
      children: [
        Expanded(
          child: _QuickAction(
            label: 'Attendance',
            icon: HugeIcons.strokeRoundedCalendarCheckIn01,
            wellColor: homePrimarySoft,
            iconColor: homePrimary,
            onTap: () => go(1),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickAction(
            label: 'Requests',
            icon: HugeIcons.strokeRoundedFileAdd,
            wellColor: homeGreenSoft,
            iconColor: homeGreenDeep,
            onTap: () => go(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickAction(
            label: 'Alerts',
            icon: HugeIcons.strokeRoundedNotification03,
            wellColor: homeAmberSoft,
            iconColor: homeAmber,
            badge: unread > 0 ? (unread > 9 ? '9+' : '$unread') : null,
            onTap: () => go(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickAction(
            label: 'Profile',
            icon: HugeIcons.strokeRoundedUser,
            wellColor: const Color(0xFFD5E3FF),
            iconColor: const Color(0xFF0052E1),
            onTap: () => go(4),
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.wellColor,
    required this.iconColor,
    required this.onTap,
    this.badge,
  });

  final String label;
  final List<List<dynamic>> icon;
  final Color wellColor;
  final Color iconColor;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: homeLine),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: wellColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: HugeIcon(icon: icon, color: iconColor, size: 20),
                    ),
                  ),
                  if (badge != null)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.red,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          badge!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttendanceCard extends ConsumerStatefulWidget {
  const _AttendanceCard({required this.home});

  final MobileHome home;

  @override
  ConsumerState<_AttendanceCard> createState() => _AttendanceCardState();
}

class _AttendanceCardState extends ConsumerState<_AttendanceCard> {
  Timer? _ticker;
  Duration _live = Duration.zero;

  @override
  void initState() {
    super.initState();
    _syncLive();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _syncLive());
  }

  @override
  void didUpdateWidget(covariant _AttendanceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.home.isClockedIn != widget.home.isClockedIn ||
        oldWidget.home.worked != widget.home.worked ||
        oldWidget.home.fetchedAt != widget.home.fetchedAt) {
      _syncLive();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration _parseHms(String value) {
    final parts = value.split(':');
    if (parts.length < 3) return Duration.zero;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final s = int.tryParse(parts[2]) ?? 0;
    return Duration(hours: h, minutes: m, seconds: s);
  }

  void _syncLive() {
    final home = widget.home;
    var base = _parseHms(home.worked);
    if (home.isClockedIn) {
      final extra = DateTime.now().difference(home.fetchedAt);
      if (!extra.isNegative) base += extra;
    }
    if (!mounted) return;
    setState(() => _live = base);
  }

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h : $m : $s';
  }

  String _shiftLabel(MobileHome home) {
    final days = home.workSchedule?.days ?? const <HomeScheduleDay>[];
    for (final day in days) {
      if (day.isToday) {
        if (!day.hasSchedule) return 'Day off';
        final name = day.shiftName.trim();
        return name.isEmpty ? day.timingLabel : '$name · ${day.timingLabel}';
      }
    }
    final name = home.workSchedule?.shiftName.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'No shift today';
  }

  String _shortClock(String raw) {
    final parts = raw.split(':');
    if (parts.length < 2) return raw;
    return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
  }

  String _compactDuration(Duration duration) {
    if (duration.isNegative) duration = Duration.zero;
    if (duration.inHours > 0) {
      final minutes = duration.inMinutes.remainder(60);
      if (minutes == 0) return '${duration.inHours}h';
      return '${duration.inHours}h ${minutes.toString().padLeft(2, '0')}m';
    }
    if (duration.inMinutes > 0) return '${duration.inMinutes}m';
    return '0m';
  }

  HomeScheduleDay? _todayShift(MobileHome home) {
    for (final day in home.workSchedule?.days ?? const <HomeScheduleDay>[]) {
      if (day.isToday) return day;
    }
    return null;
  }

  String _shiftTime(MobileHome home) {
    final today = _todayShift(home);
    if (today != null &&
        today.hasSchedule &&
        today.startTime != null &&
        today.endTime != null) {
      return '${today.startTime} – ${today.endTime}';
    }
    return _shiftLabel(home);
  }

  Duration? _shiftGoal(MobileHome home) {
    final today = _todayShift(home);
    if (today == null || !today.hasSchedule) return null;
    final start = _parseClock(today.startTime);
    final end = _parseClock(today.endTime);
    if (start == null || end == null) return null;
    var span = end.difference(start);
    if (span.inSeconds <= 0) span += const Duration(hours: 24);
    return span;
  }

  DateTime? _parseClock(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return DateTime(2000, 1, 1, hour, minute);
  }

  Future<void> _onPunch() async {
    final err = await ref.read(punchActionProvider).togglePunch(widget.home);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      final msg = widget.home.isClockedIn ? 'Checked out' : 'Checked in';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = widget.home;
    final busy = ref.watch(punchBusyProvider);
    final onSite = home.isClockedIn;
    final location = (home.geofenceName ?? '').trim();
    final goal = _shiftGoal(home);
    final progress = goal == null || goal.inSeconds <= 0
        ? null
        : (_live.inSeconds / goal.inSeconds).clamp(0.0, 1.0);
    final remaining = goal == null ? null : goal - _live;
    final overtime = _parseHms(home.overtime);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: homeSurface(radius: 22),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: onSite
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: onSite
                              ? const Color(0x1A2E7D32)
                              : const Color(0x0A000000),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: onSite
                                  ? const Color(0xFF2E7D32)
                                  : AppColors.textSecondary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            onSite ? 'Clocked in' : 'Clocked out',
                            style: HomeType.body(
                              color: onSite
                                  ? const Color(0xFF2E7D32)
                                  : AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (location.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: const Color(0x0A000000)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedLocation01,
                              size: 12,
                              color: onSite
                                  ? const Color(0xFF2E7D32)
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 120),
                              child: Text(
                                location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: HomeType.body(
                                  color: const Color(0xFF4B5563),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: homePrimarySoft,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: homePrimary.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const HugeIcon(
                      icon: HugeIcons.strokeRoundedClock01,
                      color: homePrimary,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        _shiftTime(home),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HomeType.body(
                          color: homePrimary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFF8F9FA),
                  homePrimary.withValues(alpha: 0.06),
                  const Color(0xFFEAF0FF).withValues(alpha: 0.85),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: homePrimary.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Worked Today',
                        style: HomeType.body(
                          color: const Color(0xFF6B7280),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _fmt(_live),
                          style: HomeType.headline(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.5,
                            height: 1.1,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      if (progress != null && goal != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Shift Goal: ${_compactDuration(goal)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: HomeType.body(
                                  color: const Color(0xFF4B5563),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${(progress * 100).round()}%',
                              style: HomeType.body(
                                color: homePrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            backgroundColor: Colors.white,
                            valueColor: const AlwaysStoppedAnimation(
                              homePrimary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    _CheckButton(
                      isClockedIn: home.isClockedIn,
                      busy: busy,
                      onPressed: busy ? null : _onPunch,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      onSite ? 'Tap to clock out' : 'Tap to clock in',
                      style: HomeType.body(
                        color: const Color(0xFF6B7280),
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricCell(
                  icon: HugeIcons.strokeRoundedLogin01,
                  label: 'In',
                  value: home.clockInTime ?? '--:--',
                  color: homePrimary,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MetricCell(
                  icon: HugeIcons.strokeRoundedCoffee01,
                  label: 'Break',
                  value: _compactDuration(_parseHms(home.breakTime)),
                  color: homeAmber,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: remaining != null
                    ? _MetricCell(
                        icon: HugeIcons.strokeRoundedTimer02,
                        label: 'Left',
                        value: _compactDuration(remaining),
                        color: const Color(0xFF0052E1),
                      )
                    : _MetricCell(
                        icon: HugeIcons.strokeRoundedLogout01,
                        label: home.isClockedIn && home.clockOutTime != null
                            ? 'Last out'
                            : 'Out',
                        value: home.clockOutTime ?? '--:--',
                        color: homePrimary,
                      ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MetricCell(
                  icon: HugeIcons.strokeRoundedAnalyticsUp,
                  label: 'OT',
                  value: overtime == Duration.zero
                      ? '0m'
                      : '+${_shortClock(home.overtime)}',
                  color: homeGreenDeep,
                ),
              ),
            ],
          ),
          if (home.punches.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  "Today's punches",
                  style: HomeType.headline(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: homePrimarySoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${home.punches.length} '
                    '${home.punches.length == 1 ? 'Punch' : 'Punches'}',
                    style: HomeType.body(
                      color: homePrimary,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final punch in home.punches) _PunchLine(punch: punch),
          ],
          if (home.geofenceEnabled) ...[
            const SizedBox(height: 10),
            const FenceStatusLine(align: TextAlign.left),
          ],
        ],
      ),
    );
  }
}

class _PunchLine extends StatelessWidget {
  const _PunchLine({required this.punch});

  final HomePunch punch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            punch.open
                ? Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.green,
                      shape: BoxShape.circle,
                    ),
                  )
                : const HugeIcon(
                    icon: HugeIcons.strokeRoundedCheckmarkCircle02,
                    color: AppColors.textSecondary,
                    size: 14,
                  ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                punch.rangeLabel,
                style: HomeType.headline(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: punch.open
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                punch.open ? 'In' : 'Done',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: punch.open ? AppColors.green : const Color(0xFF4B5563),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckButton extends StatefulWidget {
  const _CheckButton({
    required this.isClockedIn,
    required this.busy,
    required this.onPressed,
  });

  final bool isClockedIn;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  State<_CheckButton> createState() => _CheckButtonState();
}

class _CheckButtonState extends State<_CheckButton>
    with TickerProviderStateMixin {
  late final AnimationController _pressController;
  late final AnimationController _breathController;
  late final AnimationController _shimmerController;
  late final AnimationController _burstController;
  late final Animation<double> _pressScale;
  late final Animation<double> _breath;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _pressScale = Tween<double>(
      begin: 1,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _pressController, curve: Curves.easeOut));
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _breath = CurvedAnimation(
      parent: _breathController,
      curve: Curves.easeInOut,
    );
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
    _burstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLoops();
  }

  @override
  void didUpdateWidget(covariant _CheckButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncLoops();
    if (oldWidget.isClockedIn != widget.isClockedIn) {
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (!reduce) _burstController.forward(from: 0);
    }
  }

  /// Breathing and shimmer run while the button is idle. They stop during a
  /// punch and when the system asks for reduced motion.
  void _syncLoops() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final shouldRun = !widget.busy && !reduce;
    if (shouldRun) {
      if (!_breathController.isAnimating) {
        _breathController.repeat(reverse: true);
      }
      if (!_shimmerController.isAnimating) _shimmerController.repeat();
    } else {
      _breathController.stop();
      _shimmerController.stop();
    }
  }

  @override
  void dispose() {
    _pressController.dispose();
    _breathController.dispose();
    _shimmerController.dispose();
    _burstController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.isClockedIn ? AppColors.red : homePrimary;

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: const Duration(milliseconds: 450),
      builder: (context, animated, _) {
        final color = animated ?? target;
        return GestureDetector(
          onTapDown: widget.onPressed == null
              ? null
              : (_) => _pressController.forward(),
          onTapUp: widget.onPressed == null
              ? null
              : (_) {
                  _pressController.reverse();
                  widget.onPressed?.call();
                },
          onTapCancel: () => _pressController.reverse(),
          child: SizedBox(
            width: 118,
            height: 118,
            child: Stack(
              alignment: Alignment.center,
              children: [
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _burstController,
                    builder: (context, _) => CustomPaint(
                      size: const Size(118, 118),
                      painter: _BurstPainter(
                        color: color,
                        progress: _burstController.value,
                        running: _burstController.isAnimating,
                      ),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: Listenable.merge([_breath, _pressScale]),
                  builder: (context, child) {
                    final b = _breath.value;
                    return Transform.scale(
                      scale: _pressScale.value * (1 + 0.035 * b),
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color.lerp(color, Colors.white, 0.18)!,
                              color,
                            ],
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.55),
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.18 + 0.20 * b),
                              blurRadius: 16 + 14 * b,
                              spreadRadius: 2 * b,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: ClipOval(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _shimmerController,
                            builder: (context, _) {
                              // Sweep during the first part of each cycle,
                              // then rest.
                              final v = _shimmerController.value;
                              final t = (v / 0.4).clamp(0.0, 1.0);
                              if (v > 0.4) return const SizedBox.shrink();
                              return Transform.translate(
                                offset: Offset(-150 + 300 * t, 0),
                                child: Transform.rotate(
                                  angle: 0.45,
                                  child: Container(
                                    width: 38,
                                    height: 240,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.white.withValues(alpha: 0),
                                          Colors.white.withValues(alpha: 0.30),
                                          Colors.white.withValues(alpha: 0),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutBack,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: animation,
                                  child: child,
                                ),
                              ),
                          child: widget.busy
                              ? const SizedBox(
                                  key: ValueKey('busy'),
                                  width: 26,
                                  height: 26,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Column(
                                  key: ValueKey(widget.isClockedIn),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const HugeIcon(
                                      icon: HugeIcons.strokeRoundedFingerPrint,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.isClockedIn
                                          ? 'Check-out'
                                          : 'Check-in',
                                      style: HomeType.headline(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
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
}

/// One expanding ring that fades out after the state changes.
class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.color,
    required this.progress,
    required this.running,
  });

  final Color color;
  final double progress;
  final bool running;

  @override
  void paint(Canvas canvas, Size size) {
    if (!running) return;
    final center = size.center(Offset.zero);
    final t = Curves.easeOutCubic.transform(progress);
    canvas.drawCircle(
      center,
      50 + 22 * t,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5 * (1 - t) + 1
        ..color = color.withValues(alpha: 0.45 * (1 - t)),
    );
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) =>
      old.progress != progress || old.color != color || old.running != running;
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final List<List<dynamic>> icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x05000000)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HugeIcon(icon: icon, color: color, size: 13),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HomeType.headline(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({
    required this.message,
    required this.onRetry,
    required this.onLogout,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
          TextButton(onPressed: onLogout, child: const Text('Sign out')),
        ],
      ),
    );
  }
}
