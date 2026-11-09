import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../attendance/attendance_screen.dart';
import '../home/home_provider.dart';
import '../home/home_screen.dart';
import '../more/more_screen.dart';
import '../notifications/notifications_screen.dart';
import '../requests/requests_screen.dart';
import 'app_bottom_nav_bar.dart';

final shellIndexProvider = StateProvider<int>((ref) => 0);

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(shellIndexProvider);
    final homeAsync = ref.watch(mobileHomeProvider);
    final unread = homeAsync.maybeWhen(
      data: (h) => h.unreadNotifications,
      orElse: () => 0,
    );

    final pages = [
      const HomeScreen(),
      const AttendanceScreen(),
      const RequestsScreen(),
      const NotificationsScreen(),
      const MoreScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: index,
        unreadNotifications: unread,
        onTap: (i) => ref.read(shellIndexProvider.notifier).state = i,
      ),
    );
  }
}
