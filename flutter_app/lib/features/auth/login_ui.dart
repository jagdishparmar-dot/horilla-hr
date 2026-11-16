import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme.dart';
import '../home/home_typography.dart';

/// Stitch “ClockMe - Sign In” tokens for the login and forgot-password screens.
abstract final class LoginUi {
  static const canvas = Color(0xFFF9F9FF);
  static const onSurface = Color(0xFF24334A);
  static const onVariant = Color(0xFF506079);
  static const outline = Color(0xFF6C7B96);
  static const field = Color(0xFFF0F3FF);
  static const card = Color(0xFFFFFFFF);
  static const live = Color(0xFF1C6D25);
}

class LoginFieldLabel extends StatelessWidget {
  const LoginFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: HomeType.body(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.8,
        color: LoginUi.onVariant,
      ),
    );
  }
}

InputDecoration loginFieldDecoration({
  required String hint,
  required List<List<dynamic>> prefix,
  Widget? suffix,
}) {
  final radius = BorderRadius.circular(12);
  return InputDecoration(
    hintText: hint,
    hintStyle: HomeType.body(fontSize: 14, color: LoginUi.outline),
    filled: true,
    fillColor: LoginUi.field,
    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
    prefixIcon: Padding(
      padding: const EdgeInsets.all(12),
      child: HugeIcon(icon: prefix, color: LoginUi.outline, size: 20),
    ),
    suffixIcon: suffix,
    border: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: AppColors.navBlue.withValues(alpha: 0.28)),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: Color(0xFFFECACA)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AppColors.red),
    ),
  );
}

class LoginErrorBanner extends StatelessWidget {
  const LoginErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HugeIcon(
            icon: HugeIcons.strokeRoundedAlert02,
            size: 18,
            color: AppColors.red,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: HomeType.body(
                color: const Color(0xFFB91C1C),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
