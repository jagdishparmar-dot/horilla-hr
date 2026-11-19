import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/core/theme.dart';
import 'package:horilla_employee/features/attendance/attendance_palette.dart';
import 'package:horilla_employee/features/attendance/models.dart';

double _linear(int channel) {
  final v = channel / 255.0;
  if (v <= 0.04045) return v / 12.92;
  return math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(Color color) {
  final argb = color.toARGB32();
  final r = _linear((argb >> 16) & 0xFF);
  final g = _linear((argb >> 8) & 0xFF);
  final b = _linear(argb & 0xFF);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _contrast(Color foreground, Color background) {
  final lighter = math.max(_luminance(foreground), _luminance(background));
  final darker = math.min(_luminance(foreground), _luminance(background));
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('summary status text clears AA contrast on its fill', () {
    for (final status in AttendanceStatus.values) {
      final ratio = _contrast(
        AttendancePalette.accent(status),
        AttendancePalette.pill(status),
      );
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: '$status text/fill contrast is ${ratio.toStringAsFixed(2)}',
      );
      expect(
        _contrast(AppColors.textPrimary, AttendancePalette.pill(status)),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('small summary labels clear AA contrast on white and the page', () {
    expect(
      _contrast(AttendancePalette.textMuted, Colors.white),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(AttendancePalette.textMuted, AttendancePalette.page),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(Colors.white, AttendancePalette.textBlue),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('shift row fills stay soft and close to the same lightness', () {
    final luminances = [
      for (final status in AttendanceStatus.values)
        _luminance(AttendancePalette.shiftSurface(status)),
    ];
    final spread = luminances.reduce(math.max) - luminances.reduce(math.min);
    expect(spread, lessThanOrEqualTo(0.04));
    for (final status in AttendanceStatus.values) {
      final surface = AttendancePalette.shiftSurface(status);
      expect(
        _luminance(surface),
        greaterThanOrEqualTo(0.92),
        reason: '$status surface is too dark',
      );
      expect(
        _contrast(AppColors.textPrimary, surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(AttendancePalette.accent(status), surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(AttendancePalette.textMuted, surface),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}
