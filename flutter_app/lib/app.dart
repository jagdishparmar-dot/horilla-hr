import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/server_url_provider.dart';
import 'core/theme.dart';
import 'features/auth/app_lock.dart';
import 'features/auth/auth_provider.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/server_url_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/shell/main_shell.dart';

class HorillaApp extends ConsumerWidget {
  const HorillaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(serverUrlProvider);

    Widget home;
    if (!server.loaded) {
      home = const SplashScreen();
    } else if (!server.isReady) {
      home = const ServerUrlScreen();
    } else {
      final auth = ref.watch(authProvider);
      // Load the lock flag during splash so sign-in is not held for it.
      ref.watch(appLockEnabledProvider);
      switch (auth.status) {
        case AuthStatus.unknown:
          home = const SplashScreen();
        case AuthStatus.unauthenticated:
          home = const LoginScreen();
        case AuthStatus.authenticated:
          home = const AppLockGate(child: MainShell());
      }
    }

    return MaterialApp(
      title: 'ClockMe',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: home,
    );
  }
}
