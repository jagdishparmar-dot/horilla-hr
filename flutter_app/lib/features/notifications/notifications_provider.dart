import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/home_provider.dart';
import 'models.dart';
import 'notifications_repository.dart';

enum NotificationFilter { all, unread, requests, attendance, updates }

final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>(
  (ref) async {
    return ref.watch(notificationsRepositoryProvider).fetchAll();
  },
);

final notificationFilterProvider =
    StateProvider.autoDispose<NotificationFilter>((ref) {
      return NotificationFilter.all;
    });

/// Ids removed or read locally before the server round trip finishes.
final notificationHiddenIdsProvider = StateProvider<Set<int>>((ref) => {});
final notificationReadIdsProvider = StateProvider<Set<int>>((ref) => {});

/// Server list with local deletes and reads applied.
final notificationItemsProvider =
    Provider.autoDispose<AsyncValue<List<AppNotification>>>((ref) {
      final hidden = ref.watch(notificationHiddenIdsProvider);
      final read = ref.watch(notificationReadIdsProvider);
      return ref
          .watch(notificationsProvider)
          .whenData(
            (items) => [
              for (final item in items)
                if (!hidden.contains(item.id))
                  read.contains(item.id) ? item.copyWith(unread: false) : item,
            ],
          );
    });

bool _matches(
  AppNotification item,
  NotificationFilter filter,
) => switch (filter) {
  NotificationFilter.all => true,
  NotificationFilter.unread => item.unread,
  NotificationFilter.requests => item.category == NotificationCategory.requests,
  NotificationFilter.attendance =>
    item.category == NotificationCategory.attendance,
  NotificationFilter.updates => item.category == NotificationCategory.updates,
};

int notificationCount(List<AppNotification> items, NotificationFilter f) =>
    items.where((e) => _matches(e, f)).length;

final notificationSectionsProvider =
    Provider.autoDispose<AsyncValue<List<NotificationSection>>>((ref) {
      final filter = ref.watch(notificationFilterProvider);
      return ref
          .watch(notificationItemsProvider)
          .whenData(
            (items) => _groupByDay([
              for (final item in items)
                if (_matches(item, filter)) item,
            ]),
          );
    });

final notificationsActionProvider = Provider<NotificationsActions>((ref) {
  return NotificationsActions(ref);
});

class NotificationsActions {
  NotificationsActions(this._ref);

  final Ref _ref;

  Future<String?> markRead(int id) async {
    final reads = _ref.read(notificationReadIdsProvider.notifier);
    reads.state = {...reads.state, id};
    try {
      await _ref.read(notificationsRepositoryProvider).markAsRead(id);
      _ref.invalidate(mobileHomeProvider);
      return null;
    } catch (e) {
      reads.state = {...reads.state}..remove(id);
      return e.toString();
    }
  }

  Future<String?> markAllRead(List<AppNotification> items) async {
    final reads = _ref.read(notificationReadIdsProvider.notifier);
    final before = reads.state;
    reads.state = {...before, for (final i in items) i.id};
    try {
      await _ref.read(notificationsRepositoryProvider).markAllAsRead();
      _ref.invalidate(notificationsProvider);
      _ref.invalidate(mobileHomeProvider);
      return null;
    } catch (e) {
      reads.state = before;
      return e.toString();
    }
  }

  Future<String?> delete(int id) async {
    final hidden = _ref.read(notificationHiddenIdsProvider.notifier);
    hidden.state = {...hidden.state, id};
    try {
      await _ref.read(notificationsRepositoryProvider).delete(id);
      _ref.invalidate(mobileHomeProvider);
      return null;
    } catch (e) {
      hidden.state = {...hidden.state}..remove(id);
      return e.toString();
    }
  }

  Future<String?> clearAll(List<AppNotification> items) async {
    final hidden = _ref.read(notificationHiddenIdsProvider.notifier);
    final before = hidden.state;
    hidden.state = {...before, for (final i in items) i.id};
    try {
      await _ref.read(notificationsRepositoryProvider).deleteAll();
      _ref.invalidate(notificationsProvider);
      _ref.invalidate(mobileHomeProvider);
      return null;
    } catch (e) {
      hidden.state = before;
      return e.toString();
    }
  }
}

List<NotificationSection> _groupByDay(List<AppNotification> items) {
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final yesterdayStart = todayStart.subtract(const Duration(days: 1));

  final today = <AppNotification>[];
  final yesterday = <AppNotification>[];
  final earlier = <AppNotification>[];

  for (final item in items) {
    final day = DateTime(
      item.timestamp.year,
      item.timestamp.month,
      item.timestamp.day,
    );
    if (!day.isBefore(todayStart)) {
      today.add(item);
    } else if (!day.isBefore(yesterdayStart)) {
      yesterday.add(item);
    } else {
      earlier.add(item);
    }
  }

  return [
    if (today.isNotEmpty) NotificationSection(label: 'Today', items: today),
    if (yesterday.isNotEmpty)
      NotificationSection(label: 'Yesterday', items: yesterday),
    if (earlier.isNotEmpty)
      NotificationSection(label: 'Earlier', items: earlier),
  ];
}
