import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../notifications/notifications_provider.dart';
import 'more_models.dart';
import 'more_providers.dart';
import 'more_widgets.dart';

const _clockInColor = Color(0xFF2F6BFF);
const _clockOutColor = Color(0xFFF97316);

/// One timeline of recent punches and notifications, newest first.
class ActivityCenterScreen extends ConsumerWidget {
  const ActivityCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activityFeedProvider);

    return MorePage(
      title: 'Activity Center',
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(notificationsProvider);
          ref.invalidate(activityFeedProvider);
          try {
            await ref.read(activityFeedProvider.future);
          } catch (_) {}
        },
        child: AsyncView<List<ActivityEvent>>(
          value: async,
          onRetry: () => ref.invalidate(activityFeedProvider),
          builder: (events) {
            if (events.isEmpty) {
              return const CenteredScroll(
                child: EmptyPanel(
                  icon: HugeIcons.strokeRoundedAnalyticsUp,
                  title: 'No recent activity',
                  message: 'Your punches and updates from the last two weeks will show up here.',
                  color: AppColors.purple,
                ),
              );
            }
            final groups = _group(events);
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        4,
                        index == 0 ? 4 : 16,
                        4,
                        10,
                      ),
                      child: Text(
                        group.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    for (final event in group.events)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _EventTile(event: event),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Group {
  _Group(this.label);

  final String label;
  final List<ActivityEvent> events = [];
}

List<_Group> _group(List<ActivityEvent> events) {
  final today = DateTime.now();
  final todayKey = DateTime(today.year, today.month, today.day);
  final groups = <_Group>[];
  String? lastKey;
  for (final event in events) {
    final day = DateTime(event.at.year, event.at.month, event.at.day);
    final diff = todayKey.difference(day).inDays;
    final label = switch (diff) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => DateFormat('EEEE, d MMM').format(day),
    };
    if (label != lastKey) {
      groups.add(_Group(label));
      lastKey = label;
    }
    groups.last.events.add(event);
  }
  return groups;
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final ActivityEvent event;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (event.kind) {
      ActivityKind.clockIn => (_clockInColor, HugeIcons.strokeRoundedLogin01),
      ActivityKind.clockOut => (
        _clockOutColor,
        HugeIcons.strokeRoundedLogout01,
      ),
      ActivityKind.notification => (
        event.accent ?? AppColors.purple,
        HugeIcons.strokeRoundedNotification03,
      ),
    };
    final isNotification = event.kind == ActivityKind.notification;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GradientIconTile(icon: icon, color: color, size: 42),
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
                        event.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: event.unread
                              ? FontWeight.w800
                              : FontWeight.w700,
                          fontSize: 14,
                          height: 1.25,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (event.unread)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, top: 4),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                if (event.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    event.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  isNotification
                      ? DateFormat('h:mm a').format(event.at)
                      : DateFormat('EEE, d MMM').format(event.at),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
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
