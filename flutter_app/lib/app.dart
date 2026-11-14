import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'features/auth/app_lock.dart';
import 'features/auth/auth_provider.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/shell/main_shell.dart';

class HorillaApp extends ConsumerWidget {
  const HorillaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    // Load the lock flag during splash so sign-in is not held for it.
    ref.watch(appLockEnabledProvider);

    Widget home;
    switch (auth.status) {
      case AuthStatus.unknown:
        home = const SplashScreen();
      case AuthStatus.unauthenticated:
        home = const LoginScreen();
      case AuthStatus.authenticated:
        home = const AppLockGate(child: MainShell());
    }

    return MaterialApp(
      title: 'ClockMe',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: home,
    );
  }
}
