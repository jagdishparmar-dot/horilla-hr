import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme.dart';
import 'attendance_correction_screen.dart';
import 'leave_request_screen.dart';
import 'permission_request_screen.dart';
import 'remote_work_request_screen.dart';

enum NewRequestType {
  leave,
  permission,
  remoteWork,
  attendanceCorrection,
}

Future<bool?> showNewRequestSheet(BuildContext context) async {
  final type = await showModalBottomSheet<NewRequestType>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) => const _NewRequestSheet(),
  );
  if (type == null || !context.mounted) return null;

  return switch (type) {
    NewRequestType.leave => Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const LeaveRequestScreen()),
      ),
    NewRequestType.permission => Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const PermissionRequestScreen()),
      ),
    NewRequestType.remoteWork => Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const RemoteWorkRequestScreen()),
      ),
    NewRequestType.attendanceCorrection => Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const AttendanceCorrectionScreen(),
        ),
      ),
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
        color: AppColors.orange,
      ),
      _Option(
        type: NewRequestType.permission,
        title: 'Permission',
        subtitle: 'Request short permission hours',
        icon: HugeIcons.strokeRoundedClock01,
        color: AppColors.navBlue,
      ),
      _Option(
        type: NewRequestType.remoteWork,
        title: 'Remote Work',
        subtitle: 'Request to work remotely',
        icon: HugeIcons.strokeRoundedHome01,
        color: AppColors.green,
      ),
      _Option(
        type: NewRequestType.attendanceCorrection,
        title: 'Attendance Correction',
        subtitle: 'Fix a missed or wrong punch',
        icon: HugeIcons.strokeRoundedCalendarCheckIn01,
        color: AppColors.purple,
      ),
    ];

    return SafeArea(
      child: Padding(
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
                'New Request',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final option in options) ...[
              _OptionTile(
                option: option,
                onTap: () => Navigator.of(context).pop(option.type),
              ),
              if (option != options.last) const SizedBox(height: 8),
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
  const _OptionTile({
    required this.option,
    required this.onTap,
  });

  final _Option option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7F8FA),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: option.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: HugeIcon(
                    icon: option.icon,
                    color: option.color,
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
