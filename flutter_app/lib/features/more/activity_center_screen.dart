import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme.dart';

class ActivityCenterScreen extends StatelessWidget {
  const ActivityCenterScreen({super.key});

  static final _items = <_ActivityItem>[
    _ActivityItem(
      title: 'Checked in: 09:00 AM',
      subtitle: 'Today',
      color: AppColors.navBlue,
      icon: HugeIcons.strokeRoundedLogin01,
    ),
    _ActivityItem(
      title: 'Checked out: 05:30 PM',
      subtitle: 'Yesterday',
      color: AppColors.red,
      icon: HugeIcons.strokeRoundedLogout01,
    ),
    _ActivityItem(
      title: 'Annual leave approved',
      subtitle: 'Jan 26',
      color: AppColors.green,
      icon: HugeIcons.strokeRoundedCheckmarkCircle02,
    ),
    _ActivityItem(
      title: 'Leave request submitted',
      subtitle: 'Jan 25',
      color: AppColors.orange,
      icon: HugeIcons.strokeRoundedFile02,
    ),
    _ActivityItem(
      title: 'Checked in: 08:55 AM',
      subtitle: 'Jan 24',
      color: AppColors.navBlue,
      icon: HugeIcons.strokeRoundedLogin01,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.scaffold,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        ),
        title: const Text(
          'Activity Center',
          style: TextStyle(
            color: AppColors.navBlue,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = _items[index];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: HugeIcon(
                      icon: item.icon,
                      color: item.color,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
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
          );
        },
      ),
    );
  }
}

class _ActivityItem {
  const _ActivityItem({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final Color color;
  final List<List<dynamic>> icon;
}
