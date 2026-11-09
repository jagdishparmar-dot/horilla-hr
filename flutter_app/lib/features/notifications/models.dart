import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme.dart';

enum NotificationLevel { success, info, warning, error }

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

  Color get accent {
    final lower = verb.toLowerCase();
    if (lower.contains('reject') || lower.contains('declin')) {
      return AppColors.red;
    }
    if (lower.contains('approv') ||
        lower.contains('success') ||
        lower.contains('updated')) {
      return AppColors.green;
    }
    if (lower.contains('remind') || lower.contains('check-out')) {
      return AppColors.red;
    }
    if (lower.contains('shift') || lower.contains('check-in')) {
      return AppColors.green;
    }
    if (lower.contains('announce')) {
      return AppColors.navBlue;
    }
    return switch (level) {
      NotificationLevel.success => AppColors.green,
      NotificationLevel.warning => AppColors.orange,
      NotificationLevel.error => AppColors.red,
      NotificationLevel.info => AppColors.navBlue,
    };
  }

  List<List<dynamic>> get icon {
    final lower = verb.toLowerCase();
    if (lower.contains('reject') || lower.contains('declin')) {
      return HugeIcons.strokeRoundedCancel01;
    }
    if (lower.contains('announce')) {
      return HugeIcons.strokeRoundedMegaphone01;
    }
    if (lower.contains('profile') || lower.contains('phone')) {
      return HugeIcons.strokeRoundedUserCircle;
    }
    if (lower.contains('shift') ||
        lower.contains('check') ||
        lower.contains('remind')) {
      return HugeIcons.strokeRoundedAlarmClock;
    }
    if (lower.contains('leave') || lower.contains('request')) {
      return HugeIcons.strokeRoundedFile02;
    }
    return switch (level) {
      NotificationLevel.success => HugeIcons.strokeRoundedCheckmarkCircle02,
      NotificationLevel.warning => HugeIcons.strokeRoundedAlert02,
      NotificationLevel.error => HugeIcons.strokeRoundedCancel01,
      NotificationLevel.info => HugeIcons.strokeRoundedNotification03,
    };
  }
}

class NotificationSection {
  const NotificationSection({
    required this.label,
    required this.items,
  });

  final String label;
  final List<AppNotification> items;
}
