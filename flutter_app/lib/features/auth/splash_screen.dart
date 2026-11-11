import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/branding.dart';

/// In-app hold while the stored session is read. Same blue as the native
/// launch screen so the hand-off does not flash white.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Brand.splash,
      ),
      child: Scaffold(
        backgroundColor: Brand.splash,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ClockMeLogo(size: 96),
              const SizedBox(height: 22),
              const Text(
                'ClockMe',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Employee attendance',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
