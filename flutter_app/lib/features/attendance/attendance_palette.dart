import 'package:flutter/material.dart';

import 'models.dart';

/// Text and surface colors for the attendance Summary and Shift tabs.
///
/// Text colors are dark enough for small labels on white and on the pale
/// status fills. Shift surfaces stay in a narrow light band so the list
/// does not jump between loud washes.
class AttendancePalette {
  AttendancePalette._();

  static const textMuted = Color(0xFF4B5160);
  static const textGreen = Color(0xFF166534);
  static const textAmber = Color(0xFF9A5700);
  static const textRed = Color(0xFFB42318);
  static const textTeal = Color(0xFF0E7490);
  static const textBlue = Color(0xFF1D4ED8);
  static const textPurple = Color(0xFF6D28D9);

  static const page = Color(0xFFF2F2F7);

  static Color accent(AttendanceStatus status) => switch (status) {
    AttendanceStatus.present || AttendanceStatus.overtime => textGreen,
    AttendanceStatus.late || AttendanceStatus.shortHours => textAmber,
    AttendanceStatus.missingOut || AttendanceStatus.absent => textRed,
    AttendanceStatus.leave => textBlue,
    AttendanceStatus.holiday => textTeal,
    AttendanceStatus.weekend || AttendanceStatus.none => textMuted,
  };

  /// Status chip and calendar-cell fill. Stronger than a shift card, still pale.
  static Color pill(AttendanceStatus status) => switch (status) {
    AttendanceStatus.present || AttendanceStatus.overtime => const Color(
      0xFFDDF3E6,
    ),
    AttendanceStatus.late || AttendanceStatus.shortHours => const Color(
      0xFFFFF1D6,
    ),
    AttendanceStatus.missingOut || AttendanceStatus.absent => const Color(
      0xFFFDE8E6,
    ),
    AttendanceStatus.leave => const Color(0xFFE6ECFF),
    AttendanceStatus.holiday => const Color(0xFFDDF3F6),
    AttendanceStatus.weekend || AttendanceStatus.none => const Color(
      0xFFE8E8ED,
    ),
  };

  /// Full-row fill on the Shift tab. Same lightness across statuses.
  static Color shiftSurface(AttendanceStatus status) => switch (status) {
    AttendanceStatus.present => const Color(0xFFF3FAF6),
    AttendanceStatus.overtime => const Color(0xFFF2F8F5),
    AttendanceStatus.late || AttendanceStatus.shortHours => const Color(
      0xFFFFF8EE,
    ),
    AttendanceStatus.missingOut || AttendanceStatus.absent => const Color(
      0xFFFDF6F5,
    ),
    AttendanceStatus.leave => const Color(0xFFF5F7FF),
    AttendanceStatus.holiday => const Color(0xFFF3FAFB),
    AttendanceStatus.weekend || AttendanceStatus.none => const Color(
      0xFFF7F7F9,
    ),
  };

  static Color shiftBorder(AttendanceStatus status) => switch (status) {
    AttendanceStatus.present || AttendanceStatus.overtime => const Color(
      0xFFD5EADF,
    ),
    AttendanceStatus.late || AttendanceStatus.shortHours => const Color(
      0xFFF0E2CC,
    ),
    AttendanceStatus.missingOut || AttendanceStatus.absent => const Color(
      0xFFF0DCD9,
    ),
    AttendanceStatus.leave => const Color(0xFFDCE3F7),
    AttendanceStatus.holiday => const Color(0xFFD4E8EC),
    AttendanceStatus.weekend || AttendanceStatus.none => const Color(
      0xFFE4E4EA,
    ),
  };
}
