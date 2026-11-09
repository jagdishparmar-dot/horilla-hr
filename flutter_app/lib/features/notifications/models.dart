import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

enum NotificationLevel { success, info, warning, error }

/// Where a notification comes from. Drives the icon, color and filter chips.
enum NotificationCategory { requests, attendance, updates, general }

extension NotificationCategoryX on NotificationCategory {
  String get label => switch (this) {
    NotificationCategory.requests => 'Requests',
    NotificationCategory.attendance => 'Attendance',
    NotificationCategory.updates => 'Updates',
    NotificationCategory.general => 'General',
  };

  Color get color => switch (this) {
    NotificationCategory.requests => const Color(0xFF8B5CF6),
    NotificationCategory.attendance => const Color(0xFF22B8E8),
    NotificationCategory.updates => const Color(0xFFF59E0B),
    NotificationCategory.general => const Color(0xFF2F6BFF),
  };

  List<List<dynamic>> get icon => switch (this) {
    NotificationCategory.requests => HugeIcons.strokeRoundedFile02,
    NotificationCategory.attendance => HugeIcons.strokeRoundedCalendarCheckIn01,
    NotificationCategory.updates => HugeIcons.strokeRoundedMegaphone01,
    NotificationCategory.general => HugeIcons.strokeRoundedNotification03,
  };
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.verb,
    required this.unread,
    required this.timestamp,
    required this.level,
    this.description,
    this.data,
    this.deleted = false,
  });

  final int id;
  final String verb;
  final String? description;
  final bool unread;
  final bool deleted;
  final DateTime timestamp;
  final NotificationLevel level;
  final Map<String, dynamic>? data;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final levelRaw = (json['level'] as String? ?? 'info').toLowerCase();
    final level = switch (levelRaw) {
      'success' => NotificationLevel.success,
      'warning' => NotificationLevel.warning,
      'error' => NotificationLevel.error,
      _ => NotificationLevel.info,
    };

    DateTime ts;
    final rawTs = json['timestamp'];
    if (rawTs is String) {
      ts = DateTime.tryParse(rawTs)?.toLocal() ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }

    Map<String, dynamic>? data;
    final rawData = json['data'];
    if (rawData is Map<String, dynamic>) {
      data = rawData;
    } else if (rawData is Map) {
      data = Map<String, dynamic>.from(rawData);
    }

    return AppNotification(
      id: json['id'] as int,
      verb: json['verb'] as String? ?? '',
      description: json['description'] as String?,
      unread: json['unread'] as bool? ?? false,
      deleted: json['deleted'] as bool? ?? false,
      timestamp: ts,
      level: level,
      data: data,
    );
  }

  AppNotification copyWith({bool? unread}) => AppNotification(
    id: id,
    verb: verb,
    description: description,
    unread: unread ?? this.unread,
    deleted: deleted,
    timestamp: timestamp,
    level: level,
    data: data,
  );

  String get title {
    final fromData = data?['title'] ?? data?['subject'];
    if (fromData is String && fromData.trim().isNotEmpty) {
      return fromData.trim();
    }
    final text = verb.trim();
    if (text.isEmpty) return 'Notification';
    return text;
  }

  String get body {
    final desc = description?.trim();
    if (desc == null || desc.isEmpty) return '';
    // Avoid repeating the same text under title when description equals verb.
    if (desc == verb.trim()) return '';
    return desc;
  }

  String get _haystack {
    final redirect = data?['redirect'];
    return '${verb.toLowerCase()} ${(description ?? '').toLowerCase()} '
        '${redirect is String ? redirect.toLowerCase() : ''}';
  }

  NotificationCategory get category {
    final text = _haystack;
    if (text.contains('attendance') ||
        text.contains('check-in') ||
        text.contains('check-out') ||
        text.contains('clock') ||
        text.contains('overtime') ||
        text.contains('late come') ||
        text.contains('early out')) {
      return NotificationCategory.attendance;
    }
    if (text.contains('leave') ||
        text.contains('request') ||
        text.contains('shift') ||
        text.contains('work type') ||
        text.contains('reimburse') ||
        text.contains('asset') ||
        text.contains('approv') ||
        text.contains('reject')) {
      return NotificationCategory.requests;
    }
    if (text.contains('announce') ||
        text.contains('policy') ||
        text.contains('document') ||
        text.contains('holiday') ||
        text.contains('birthday')) {
      return NotificationCategory.updates;
    }
    return NotificationCategory.general;
  }

  bool get _rejected {
    final text = _haystack;
    return text.contains('reject') || text.contains('declin');
  }

  bool get _approved {
    final text = _haystack;
    return text.contains('approv') || text.contains('success');
  }

  /// Outcome colors win (rejected red, approved green). Otherwise the
  /// category color applies, with warning/error levels overriding general.
  Color get accent {
    if (_rejected || level == NotificationLevel.error) {
      return const Color(0xFFEF4444);
    }
    if (_approved || level == NotificationLevel.success) {
      return const Color(0xFF16A34A);
    }
    if (level == NotificationLevel.warning) return const Color(0xFFF59E0B);
    return category.color;
  }

  List<List<dynamic>> get icon {
    if (_rejected) return HugeIcons.strokeRoundedCancelCircle;
    if (_approved) return HugeIcons.strokeRoundedCheckmarkCircle02;
    if (level == NotificationLevel.warning ||
        level == NotificationLevel.error) {
      return HugeIcons.strokeRoundedAlert02;
    }
    return category.icon;
  }
}

class NotificationSection {
  const NotificationSection({required this.label, required this.items});

  final String label;
  final List<AppNotification> items;
}
