import 'package:flutter/material.dart';

/// ClockMe visual identity shared by the launcher, splash, and login.
class Brand {
  Brand._();

  static const hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2F6BFF), Color(0xFF6D5CFF), Color(0xFF9B5CFF)],
  );

  /// Native splash and Android 12 background. Matches the hero's first stop
  /// so the OS launch screen does not flash a different color.
  static const splash = Color(0xFF2F6BFF);

  static const assetIcon = 'assets/branding/app_icon.png';
  static const assetSplash = 'assets/branding/splash_logo.png';
}

class ClockMeLogo extends StatelessWidget {
  const ClockMeLogo({
    super.key,
    this.size = 88,
    this.elevated = true,
  });

  final double size;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        Brand.assetIcon,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
