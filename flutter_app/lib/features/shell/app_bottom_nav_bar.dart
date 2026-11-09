import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme.dart';

class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.unreadNotifications = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int unreadNotifications;

  static const _active = Color(0xFF2F6BFF);
  static const _inactive = Color(0xFF9CA3AF);
  static const _indicatorHeight = 3.0;
  static const _iconSize = 24.0;
  static const _barHeight = 64.0;

  static const _items = <_NavItem>[
    _NavItem(label: 'Home', icon: HugeIcons.strokeRoundedHome01),
    _NavItem(label: 'Attendance', icon: HugeIcons.strokeRoundedCalendar03),
    _NavItem(label: 'Requests', icon: HugeIcons.strokeRoundedFile02),
    _NavItem(label: 'Notifications', icon: HugeIcons.strokeRoundedNotification03),
    _NavItem(label: 'More', icon: HugeIcons.strokeRoundedMenu01),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: SizedBox(
        height: _barHeight + bottomInset,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tabWidth = constraints.maxWidth / _items.length;
              final indicatorWidth = tabWidth * 0.42;

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    left: currentIndex * tabWidth + (tabWidth - indicatorWidth) / 2,
                    top: 0,
                    width: indicatorWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: _indicatorHeight,
                          decoration: BoxDecoration(
                            color: _active,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: _active.withValues(alpha: 0.45),
                                blurRadius: 10,
                                spreadRadius: 0.5,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                        IgnorePointer(
                          child: Container(
                            height: 28,
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: const Alignment(0, -0.85),
                                radius: 0.95,
                                colors: [
                                  _active.withValues(alpha: 0.22),
                                  _active.withValues(alpha: 0.06),
                                  _active.withValues(alpha: 0),
                                ],
                                stops: const [0.0, 0.45, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < _items.length; i++)
                        Expanded(
                          child: _NavTab(
                            item: _items[i],
                            selected: currentIndex == i,
                            badgeCount: i == 3 ? unreadNotifications : 0,
                            onTap: () => onTap(i),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.label, required this.icon});

  final String label;
  final List<List<dynamic>> icon;
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.item,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? AppBottomNavBar._active : AppBottomNavBar._inactive;

    Widget icon = HugeIcon(
      icon: item.icon,
      color: color,
      size: AppBottomNavBar._iconSize,
      strokeWidth: selected ? 2.2 : 1.6,
    );

    if (badgeCount > 0) {
      icon = Badge(
        label: Text('$badgeCount'),
        backgroundColor: AppColors.red,
        child: icon,
      );
    }

    return InkWell(
      onTap: onTap,
      splashColor: AppBottomNavBar._active.withValues(alpha: 0.08),
      highlightColor: AppBottomNavBar._active.withValues(alpha: 0.04),
      child: SizedBox(
        height: AppBottomNavBar._barHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 6),
            icon,
            const SizedBox(height: 4),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.1,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
