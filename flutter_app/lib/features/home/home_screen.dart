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
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorPane(
            message: e.toString(),
            onRetry: () => ref.invalidate(mobileHomeProvider),
            onLogout: () => ref.read(authProvider.notifier).logout(),
          ),
          data: (home) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(mobileHomeProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                _Header(home: home),
                const SizedBox(height: 20),
                _AttendanceCard(home: home),
                if (home.announcement != null) ...[
                  const SizedBox(height: 16),
                  HomeAnnouncementSection(announcement: home.announcement!),
                ],
                const SizedBox(height: 16),
                HomeWorkScheduleSection(schedule: home.workSchedule),
                const SizedBox(height: 20),
                HomeRecentRequestsSection(requests: home.recentRequests),
                if (home.birthdays.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  HomePeopleMessageSection(
                    title: 'Birthdays',
                    colleague: home.birthdays.first,
                    placeholder: 'Write a birthday wish...',
                    avatarColor: AppColors.purple,
                  ),
                ],
                if (home.newHires.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  HomePeopleMessageSection(
                    title: 'New Hires',
                    colleague: home.newHires.first,
                    placeholder: 'Write a welcome message...',
                    avatarColor: AppColors.navBlue,
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

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                  children: [
                    TextSpan(text: '$_greeting, '),
                    TextSpan(
                      text: '${home.firstName} !',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedLocation01,
                    size: 16,
                    color: home.geofenceEnabled
                        ? AppColors.blue
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    home.geofenceEnabled ? 'OFFICE' : 'REMOTE',
                    style: TextStyle(
                      color: home.geofenceEnabled
                          ? AppColors.blue
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'logout') {
              ref.read(authProvider.notifier).logout();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'logout', child: Text('Sign out')),
          ],
          child: CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.purpleSoft,
            backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar) : null,
            child: avatar == null
                ? Text(
                    home.firstName.isNotEmpty ? home.firstName[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: AppColors.purple,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
        ),
      ],
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
        oldWidget.home.lastActivityAt != widget.home.lastActivityAt) {
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
    if (home.isClockedIn && home.lastActivityAt != null) {
      final started = DateTime.tryParse(home.lastActivityAt!);
      if (started != null) {
        // Prefer server worked + elapsed since last open punch when available.
        final open = DateTime.now().difference(started);
        if (open.inSeconds > base.inSeconds) {
          base = open;
        }
      }
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
    final dateLabel = DateFormat('MMM d, yyyy - EEEE').format(DateTime.now());
    final checkOutLabel = home.isClockedIn
        ? '—'
        : (home.clockOutTime ?? (home.clockInTime == null ? '--:--' : '—'));

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF3EEFF), Colors.white],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            '+ ${_fmt(_live)} hrs',
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: AppColors.purple,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '08 : 00 : 00 hrs',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            dateLabel,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 22),
          _CheckButton(
            isClockedIn: home.isClockedIn,
            busy: busy,
            onPressed: busy ? null : _onPunch,
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _TimeStat(
                  icon: HugeIcons.strokeRoundedLogin01,
                  iconColor: AppColors.green,
                  time: home.clockInTime ?? '--:--',
                  label: 'Check-in time',
                  labelColor: AppColors.green,
                ),
              ),
              Container(width: 1, height: 42, color: Colors.grey.shade300),
              Expanded(
                child: _TimeStat(
                  icon: HugeIcons.strokeRoundedLogout01,
                  iconColor: AppColors.red,
                  time: checkOutLabel,
                  label: 'Check-out time',
                  labelColor: AppColors.red,
                ),
              ),
            ],
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
    _pressScale = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOut),
    );
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

class _TimeStat extends StatelessWidget {
  const _TimeStat({
    required this.icon,
    required this.iconColor,
    required this.time,
    required this.label,
    required this.labelColor,
  });

  final List<List<dynamic>> icon;
  final Color iconColor;
  final String time;
  final String label;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HugeIcon(icon: icon, size: 18, color: iconColor),
            const SizedBox(width: 6),
            Text(
              time,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: labelColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
