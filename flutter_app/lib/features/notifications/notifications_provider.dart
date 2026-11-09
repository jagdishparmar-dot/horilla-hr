import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/home_provider.dart';
import 'models.dart';
import 'notifications_repository.dart';

final notificationsProvider =
    FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  return ref.watch(notificationsRepositoryProvider).fetchAll();
});

final notificationSectionsProvider =
    Provider.autoDispose<AsyncValue<List<NotificationSection>>>((ref) {
  return ref.watch(notificationsProvider).whenData(_groupByDay);
});

final notificationsActionProvider = Provider<NotificationsActions>((ref) {
  return NotificationsActions(ref);
});

class NotificationsActions {
  NotificationsActions(this._ref);

  final Ref _ref;

  Future<String?> markRead(int id) async {
    try {
      await _ref.read(notificationsRepositoryProvider).markAsRead(id);
      _ref.invalidate(notificationsProvider);
      _ref.invalidate(mobileHomeProvider);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> markAllRead() async {
    try {
      await _ref.read(notificationsRepositoryProvider).markAllAsRead();
      _ref.invalidate(notificationsProvider);
      _ref.invalidate(mobileHomeProvider);
      return null;
    } catch (e) {
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
