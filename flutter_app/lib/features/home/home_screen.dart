import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../auth/auth_provider.dart';
import '../shell/main_shell.dart';
import 'fence_status_line.dart';
import 'home_extra_sections.dart';
import 'home_provider.dart';
import 'models.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeAsync = ref.watch(mobileHomeProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: homeAsync.when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorPane(
            message: e.toString(),
            onRetry: () => ref.invalidate(mobileHomeProvider),
            onLogout: () => ref.read(authProvider.notifier).logout(),
          ),
          data: (home) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(mobileHomeProvider);
              ref.invalidate(punchFenceProvider);
              await ref.read(mobileHomeProvider.future);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HomeReveal(index: 0, child: _Header(home: home)),
                  const SizedBox(height: 16),
                  HomeReveal(index: 1, child: _AttendanceCard(home: home)),
                  const SizedBox(height: 16),
                  HomeReveal(index: 2, child: _QuickActions(home: home)),
                  if (home.announcement != null) ...[
                    const SizedBox(height: 22),
                    HomeReveal(
                      index: 3,
                      child: HomeAnnouncementSection(
                        announcement: home.announcement!,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  HomeReveal(
                    index: 4,
                    child: HomeWorkScheduleSection(schedule: home.workSchedule),
                  ),
                  const SizedBox(height: 22),
                  HomeReveal(
                    index: 5,
                    child: HomeRecentRequestsSection(
                      requests: home.recentRequests,
                    ),
                  ),
                  if (home.birthdays.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    HomeReveal(
                      index: 6,
                      child: HomePeopleMessageSection(
                        title: 'Birthdays',
                        colleagues: home.birthdays,
                        placeholder: 'Write a birthday wish...',
                        avatarColor: const Color(0xFFEC4899),
                        icon: HugeIcons.strokeRoundedGift,
                      ),
                    ),
                  ],
                  if (home.newHires.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    HomeReveal(
                      index: 7,
                      child: HomePeopleMessageSection(
                        title: 'New Hires',
                        colleagues: home.newHires,
                        placeholder: 'Write a welcome message...',
                        avatarColor: const Color(0xFF22B8E8),
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

class _Header extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final avatar = _resolveAvatar(home.avatarUrl);
    final role = home.roleLine;
    final dateLabel = DateFormat('EEE, MMM d').format(DateTime.now());

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F6BFF), Color(0xFF6D5CFF), Color(0xFF9B5CFF)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2F6BFF).withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_greeting 👋',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  home.firstName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 28,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
                if (role.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    role,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeaderChip(
                      icon: HugeIcons.strokeRoundedLocation01,
                      label: home.placeLabel,
                    ),
                    _HeaderChip(
                      icon: HugeIcons.strokeRoundedCalendar03,
                      label: dateLabel,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              _NotifyButton(count: home.unreadNotifications),
              const SizedBox(height: 12),
              PopupMenuButton<String>(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                onSelected: (value) {
                  if (value == 'logout') {
                    ref.read(authProvider.notifier).logout();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'logout', child: Text('Sign out')),
                ],
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 22,
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
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
      color: Colors.white.withValues(alpha: 0.2),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => ref.read(shellIndexProvider.notifier).state = 3,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const HugeIcon(
                icon: HugeIcons.strokeRoundedNotification03,
                color: Colors.white,
                size: 21,
              ),
              if (count > 0)
                Positioned(
                  right: 4,
                  top: 4,
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

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label});

  final List<List<dynamic>> icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(icon: icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
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
            color: const Color(0xFF8B5CF6),
            onTap: () => go(1),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickAction(
            label: 'Requests',
            icon: HugeIcons.strokeRoundedFileAdd,
            color: const Color(0xFFF59E0B),
            onTap: () => go(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickAction(
            label: 'Alerts',
            icon: HugeIcons.strokeRoundedNotification03,
            color: const Color(0xFFEC4899),
            badge: unread > 0 ? (unread > 9 ? '9+' : '$unread') : null,
            onTap: () => go(3),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickAction(
            label: 'Profile',
            icon: HugeIcons.strokeRoundedUser,
            color: const Color(0xFF22B8E8),
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
    required this.color,
    required this.onTap,
    this.badge,
  });

  final String label;
  final List<List<dynamic>> icon;
  final Color color;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color.lerp(color, Colors.white, 0.28)!, color],
                      ),
                    ),
                    child: Center(
                      child: HugeIcon(
                        icon: icon,
                        color: Colors.white,
                        size: 20,
                      ),
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
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
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
    final dateLabel = DateFormat('EEEE, MMM d').format(DateTime.now());
    final checkOutLabel = home.clockOutTime ?? '—';
    final onSite = home.isClockedIn;

    final tint = onSite ? const Color(0xFFE7F8EE) : const Color(0xFFEEF2FF);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [tint, Colors.white],
        ),
        boxShadow: [
          BoxShadow(
            color: (onSite ? AppColors.green : AppColors.navBlue).withValues(
              alpha: 0.10,
            ),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: (onSite ? AppColors.green : AppColors.navBlue)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: onSite ? AppColors.green : AppColors.navBlue,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      onSite ? 'Clocked in' : 'Clocked out',
                      style: TextStyle(
                        color: onSite ? AppColors.green : AppColors.navBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                dateLabel,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _fmt(_live),
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Worked today',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _shiftLabel(home),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.navBlue,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          _CheckButton(
            isClockedIn: home.isClockedIn,
            busy: busy,
            onPressed: busy ? null : _onPunch,
          ),
          if (home.geofenceEnabled) ...[
            const SizedBox(height: 12),
            const FenceStatusLine(),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Check-in',
                  value: home.clockInTime ?? '--:--',
                  color: const Color(0xFF16A34A),
                  icon: HugeIcons.strokeRoundedLogin01,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  label: home.isClockedIn && home.clockOutTime != null
                      ? 'Last out'
                      : 'Check-out',
                  value: checkOutLabel,
                  color: const Color(0xFFE5484D),
                  icon: HugeIcons.strokeRoundedLogout01,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Break',
                  value: _shortClock(home.breakTime),
                  color: const Color(0xFFF59E0B),
                  icon: HugeIcons.strokeRoundedCoffee01,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  label: 'Overtime',
                  value: _shortClock(home.overtime),
                  color: const Color(0xFF8B5CF6),
                  icon: HugeIcons.strokeRoundedAnalyticsUp,
                ),
              ),
            ],
          ),
          if (home.punches.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F7FB),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Today's punches",
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                  for (final punch in home.punches) _PunchLine(punch: punch),
                ],
              ),
            ),
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
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: punch.open ? AppColors.green : AppColors.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              punch.rangeLabel,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            punch.open ? 'In' : 'Done',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: punch.open ? AppColors.green : AppColors.textSecondary,
            ),
          ),
        ],
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
  late final AnimationController _pulseController;
  late final AnimationController _spinController;
  late final AnimationController _pressController;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;
  late final Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();

    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );

    _pulseScale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseOpacity = Tween<double>(begin: 0.55, end: 0.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pressScale = Tween<double>(
      begin: 1.0,
      end: 0.94,
    ).animate(CurvedAnimation(parent: _pressController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _spinController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isClockedIn ? AppColors.red : AppColors.green;
    final highlight = Color.lerp(color, Colors.white, 0.28)!;
    final deep = Color.lerp(color, Colors.black, 0.14)!;

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
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _pulseController,
          _spinController,
          _pressController,
        ]),
        builder: (context, child) {
          return Transform.scale(
            scale: _pressScale.value,
            child: SizedBox(
              width: 176,
              height: 176,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Soft pulsing halo
                  Transform.scale(
                    scale: _pulseScale.value,
                    child: Container(
                      width: 168,
                      height: 168,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: _pulseOpacity.value),
                            blurRadius: 28,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Rotating soft arc ring
                  CustomPaint(
                    size: const Size(168, 168),
                    painter: _RingArcPainter(
                      color: Colors.white.withValues(alpha: 0.95),
                      progress: _spinController.value,
                      strokeWidth: 2.4,
                    ),
                  ),
                  // Static white outer ring
                  Container(
                    width: 158,
                    height: 158,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.22),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                  ),
                  // Main button
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.2, -0.35),
                        radius: 0.95,
                        colors: [highlight, color, deep],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: widget.busy
                        ? const Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            ),
                          )
                        : child,
                  ),
                ],
              ),
            ),
          );
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedTouch02,
              color: Colors.white.withValues(alpha: 0.95),
              size: 34,
            ),
            const SizedBox(height: 6),
            Text(
              widget.isClockedIn ? 'Check-out' : 'Check-in',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingArcPainter extends CustomPainter {
  _RingArcPainter({
    required this.color,
    required this.progress,
    required this.strokeWidth,
  });

  final Color color;
  final double progress;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Soft full ring base
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 0.7,
    );

    // Sweeping highlight arcs
    final start = progress * 2 * math.pi;
    canvas.drawArc(rect, start, 1.35, false, paint);
    canvas.drawArc(
      rect,
      start + math.pi,
      0.85,
      false,
      paint..color = color.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _RingArcPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final List<List<dynamic>> icon;

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
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: HugeIcon(icon: icon, color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
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
