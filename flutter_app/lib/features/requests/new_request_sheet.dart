import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme.dart';
import 'attendance_correction_screen.dart';
import 'leave_request_screen.dart';
import 'permission_request_screen.dart';
import 'remote_work_request_screen.dart';
import 'shift_request_screen.dart';

enum NewRequestType {
  leave,
  permission,
  remoteWork,
  attendanceCorrection,
  shift,
}

Future<bool?> showNewRequestSheet(BuildContext context) async {
  final type = await showModalBottomSheet<NewRequestType>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => const _NewRequestSheet(),
  );
  if (type == null || !context.mounted) return null;

  return switch (type) {
    NewRequestType.leave => Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const LeaveRequestScreen())),
    NewRequestType.permission => Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PermissionRequestScreen()),
    ),
    NewRequestType.remoteWork => Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const RemoteWorkRequestScreen()),
    ),
    NewRequestType.attendanceCorrection => Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AttendanceCorrectionScreen()),
    ),
    NewRequestType.shift => Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const ShiftRequestScreen())),
  };
}

class _NewRequestSheet extends StatelessWidget {
  const _NewRequestSheet();

  @override
  Widget build(BuildContext context) {
    final options = <_Option>[
      _Option(
        type: NewRequestType.leave,
        title: 'Leave Request',
        subtitle: 'Apply for annual, casual, or other leave',
        icon: HugeIcons.strokeRoundedSun03,
        color: const Color(0xFF22C55E),
      ),
      _Option(
        type: NewRequestType.permission,
        title: 'Permission',
        subtitle: 'Request short permission hours',
        icon: HugeIcons.strokeRoundedClock01,
        color: const Color(0xFFF59E0B),
      ),
      _Option(
        type: NewRequestType.remoteWork,
        title: 'Remote Work',
        subtitle: 'Request to work remotely',
        icon: HugeIcons.strokeRoundedHome01,
        color: const Color(0xFF22B8E8),
      ),
      _Option(
        type: NewRequestType.attendanceCorrection,
        title: 'Attendance Correction',
        subtitle: 'Fix a missed or wrong punch',
        icon: HugeIcons.strokeRoundedCalendarCheckIn01,
        color: const Color(0xFF8B5CF6),
      ),
      _Option(
        type: NewRequestType.shift,
        title: 'Shift Change',
        subtitle: 'Ask to work a different shift',
        icon: HugeIcons.strokeRoundedTimer02,
        color: const Color(0xFF6366F1),
      ),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'New request',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: 2),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'What would you like to request?',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            for (final option in options) ...[
              _OptionTile(
                option: option,
                onTap: () => Navigator.of(context).pop(option.type),
              ),
              if (option != options.last) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _Option {
  const _Option({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final NewRequestType type;
  final String title;
  final String subtitle;
  final List<List<dynamic>> icon;
  final Color color;
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.option, required this.onTap});

  final _Option option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: option.color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(option.color, Colors.white, 0.3)!,
                      option.color,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: HugeIcon(
                    icon: option.icon,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
