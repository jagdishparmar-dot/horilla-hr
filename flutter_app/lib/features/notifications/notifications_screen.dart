import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import 'models.dart';
import 'notifications_provider.dart';

String _relativeTime(DateTime timestamp) {
  final now = DateTime.now();
  final diff = now.difference(timestamp);
  if (diff.inMinutes < 1) return 'Now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24 &&
      timestamp.day == now.day &&
      timestamp.month == now.month &&
      timestamp.year == now.year) {
    return '${diff.inHours}h ago';
  }
  if (diff.inHours < 48) return '1d ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('MMM d').format(timestamp);
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _markAll(
    BuildContext context,
    WidgetRef ref,
    List<AppNotification> items,
  ) async {
    final err = await ref.read(notificationsActionProvider).markAllRead(items);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? 'All notifications marked as read')),
    );
  }

  Future<void> _clearAll(
    BuildContext context,
    WidgetRef ref,
    List<AppNotification> items,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear all notifications?'),
        content: const Text('This removes every notification from your list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Clear all',
              style: TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final err = await ref.read(notificationsActionProvider).clearAll(items);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(err ?? 'Notifications cleared')));
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    AppNotification item,
  ) async {
    if (item.unread) {
      final err = await ref.read(notificationsActionProvider).markRead(item.id);
      if (err != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      }
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(notificationItemsProvider);
    final sectionsAsync = ref.watch(notificationSectionsProvider);
    final filter = ref.watch(notificationFilterProvider);
    final items = itemsAsync.asData?.value ?? const <AppNotification>[];
    final unread = notificationCount(items, NotificationFilter.unread);

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Notifications',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navBlue,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          unread == 0
                              ? "You're all caught up"
                              : unread == 1
                              ? '1 unread notification'
                              : '$unread unread notifications',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: unread == 0
                                ? AppColors.textSecondary
                                : AppColors.navBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (unread > 0)
                    _MarkAllButton(onTap: () => _markAll(context, ref, items)),
                  PopupMenuButton<String>(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    onSelected: (value) {
                      if (value == 'clear') _clearAll(context, ref, items);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'clear',
                        enabled: items.isNotEmpty,
                        child: const Text('Clear all'),
                      ),
                    ],
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedMoreVertical,
                      color: AppColors.textSecondary,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 10),
              _FilterBar(
                items: items,
                selected: filter,
                onSelected: (value) =>
                    ref.read(notificationFilterProvider.notifier).state = value,
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: sectionsAsync.when(
                skipLoadingOnReload: true,
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(e.toString(), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () =>
                              ref.invalidate(notificationsProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (sections) => RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(notificationsProvider);
                    await ref.read(notificationsProvider.future);
                  },
                  child: sections.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.5,
                              child: _EmptyState(
                                filter: filter,
                                hasAny: items.isNotEmpty,
                                onClear: () =>
                                    ref
                                        .read(
                                          notificationFilterProvider.notifier,
                                        )
                                        .state = NotificationFilter
                                        .all,
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: sections.length,
                          itemBuilder: (context, sectionIndex) {
                            final section = sections[sectionIndex];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _SectionHeader(
                                  label: section.label,
                                  count: section.items.length,
                                  first: sectionIndex == 0,
                                ),
                                for (
                                  var i = 0;
                                  i < section.items.length;
                                  i++
                                ) ...[
                                  if (i > 0) const SizedBox(height: 10),
                                  _SwipeToDelete(
                                    item: section.items[i],
                                    onDelete: () async {
                                      final err = await ref
                                          .read(notificationsActionProvider)
                                          .delete(section.items[i].id);
                                      if (err != null && context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              SnackBar(content: Text(err)),
                                            );
                                      }
                                    },
                                    child: _NotificationCard(
                                      item: section.items[i],
                                      onTap: () =>
                                          _open(context, ref, section.items[i]),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkAllButton extends StatelessWidget {
  const _MarkAllButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Material(
        color: AppColors.navBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedCheckmarkCircle02,
                  color: AppColors.navBlue,
                  size: 16,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Mark all read',
                  style: TextStyle(
                    color: AppColors.navBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
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

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<AppNotification> items;
  final NotificationFilter selected;
  final ValueChanged<NotificationFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    const filters = NotificationFilter.values;
    return SizedBox(
      height: 38,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final count = notificationCount(items, filter);
          final active = filter == selected;
          final (label, color) = switch (filter) {
            NotificationFilter.all => ('All', AppColors.navBlue),
            NotificationFilter.unread => ('Unread', const Color(0xFFEC4899)),
            NotificationFilter.requests => (
              'Requests',
              NotificationCategory.requests.color,
            ),
            NotificationFilter.attendance => (
              'Attendance',
              NotificationCategory.attendance.color,
            ),
            NotificationFilter.updates => (
              'Updates',
              NotificationCategory.updates.color,
            ),
          };
          return GestureDetector(
            onTap: () => onSelected(filter),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? color : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? color : color.withValues(alpha: 0.28),
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.30),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: active ? Colors.white : color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white.withValues(alpha: 0.25)
                          : color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: active ? Colors.white : color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.count,
    required this.first,
  });

  final String label;
  final int count;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, first ? 6 : 18, 4, 10),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: const Color(0xFFE5E7EB))),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeToDelete extends StatelessWidget {
  const _SwipeToDelete({
    required this.item,
    required this.onDelete,
    required this.child,
  });

  final AppNotification item;
  final VoidCallback onDelete;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('notification-${item.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          borderRadius: BorderRadius.circular(20),
        ),
        child: HugeIcon(
          icon: HugeIcons.strokeRoundedDelete02,
          color: Colors.white,
          size: 24,
        ),
      ),
      child: child,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.filter,
    required this.hasAny,
    required this.onClear,
  });

  final NotificationFilter filter;
  final bool hasAny;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final filtered = hasAny && filter != NotificationFilter.all;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.navBlue.withValues(alpha: 0.16),
                    const Color(0xFF9B5CFF).withValues(alpha: 0.16),
                  ],
                ),
              ),
              child: Center(
                child: HugeIcon(
                  icon: filtered
                      ? HugeIcons.strokeRoundedSearch01
                      : HugeIcons.strokeRoundedNotification03,
                  color: AppColors.navBlue,
                  size: 42,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              filtered ? 'Nothing here' : 'No notifications yet',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              filtered
                  ? 'No notifications match this filter.'
                  : 'Approvals, reminders and announcements will appear here.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            if (filtered) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onClear,
                child: const Text(
                  'Show all',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = item.unread;
    final accent = item.accent;

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: unread
              ? LinearGradient(
                  colors: [accent.withValues(alpha: 0.12), Colors.white],
                )
              : null,
          color: unread ? null : Colors.white,
          boxShadow: [
            BoxShadow(
              color: (unread ? accent : Colors.black).withValues(
                alpha: unread ? 0.10 : 0.04,
              ),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color.lerp(accent, Colors.white, 0.3)!, accent],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: HugeIcon(
                      icon: item.icon,
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: unread
                                    ? FontWeight.w800
                                    : FontWeight.w700,
                                fontSize: 14,
                                height: 1.25,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (unread)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, right: 6),
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (item.body.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.body,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: item.category.color.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              item.category.label,
                              style: TextStyle(
                                color: item.category.color,
                                fontWeight: FontWeight.w800,
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedClock01,
                            color: AppColors.textSecondary,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _relativeTime(item.timestamp),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 11.5,
                              color: unread ? accent : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
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

class _NotificationSheet extends StatelessWidget {
  const _NotificationSheet({required this.item});

  final AppNotification item;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final accent = item.accent;
    final when = DateFormat('EEEE, MMM d · h:mm a').format(item.timestamp);
    final body = item.body;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(accent, Colors.black, 0.08)!,
                  Color.lerp(accent, const Color(0xFF9B5CFF), 0.45)!,
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: HugeIcon(
                          icon: item.icon,
                          color: accent,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.category.label.toUpperCase(),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            when,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      height: 1.3,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F7FB),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        body,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          height: 1.45,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedClock01,
                        color: AppColors.textSecondary,
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _relativeTime(item.timestamp),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
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
