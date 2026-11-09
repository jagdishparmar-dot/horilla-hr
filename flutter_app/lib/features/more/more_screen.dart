import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../home/home_provider.dart';
import '../home/models.dart';
import 'activity_center_screen.dart';
import 'change_password_screen.dart';
import 'contracts_screen.dart';
import 'hr_support_screen.dart';
import 'profile_screen.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  String? _resolveAvatar(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    return '${AppConfig.mediaOrigin}$url';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeAsync = ref.watch(mobileHomeProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: homeAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(e.toString(), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => ref.invalidate(mobileHomeProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          data: (home) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              const Text(
                'More',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navBlue,
                ),
              ),
              const SizedBox(height: 16),
              _ProfileCard(
                home: home,
                avatarUrl: _resolveAvatar(home.avatarUrl),
                onViewProfile: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProfileScreen(home: home),
                    ),
                  );
                },
              ),
              const SizedBox(height: 22),
              const Text(
                'User Center',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              _MenuGroup(
                children: [
                  _MenuTile(
                    icon: HugeIcons.strokeRoundedFile02,
                    color: AppColors.navBlue,
                    title: 'Contracts',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ContractsScreen(),
                      ),
                    ),
                  ),
                  _MenuTile(
                    icon: HugeIcons.strokeRoundedAnalyticsUp,
                    color: AppColors.purple,
                    title: 'Activity Center',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ActivityCenterScreen(),
                      ),
                    ),
                  ),
                  _MenuTile(
                    icon: HugeIcons.strokeRoundedCustomerService01,
                    color: AppColors.green,
                    title: 'HR Support',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const HrSupportScreen(),
                      ),
                    ),
                  ),
                  _MenuTile(
                    icon: HugeIcons.strokeRoundedSquareLockPassword,
                    color: AppColors.orange,
                    title: 'Change Password',
                    showDivider: false,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ChangePasswordScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                'App Settings',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              _MenuGroup(
                children: [
                  _MenuTile(
                    icon: HugeIcons.strokeRoundedGlobe02,
                    color: AppColors.navBlue,
                    title: 'Language',
                    showDivider: false,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Language settings coming soon'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.home,
    required this.avatarUrl,
    required this.onViewProfile,
  });

  final MobileHome home;
  final String? avatarUrl;
  final VoidCallback onViewProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: AppColors.purpleSoft,
            backgroundImage:
                avatarUrl != null ? CachedNetworkImageProvider(avatarUrl!) : null,
            child: avatarUrl == null
                ? Text(
                    home.firstName.isNotEmpty
                        ? home.firstName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: AppColors.purple,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  home.employeeName,
                  style: const TextStyle(
                    color: AppColors.navBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  home.jobPosition?.isNotEmpty == true
                      ? home.jobPosition!
                      : 'Employee',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  home.displayBadgeId,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 34,
                  child: FilledButton(
                    onPressed: onViewProfile,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'View Profile',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
    this.showDivider = true,
  });

  final List<List<dynamic>> icon;
  final Color color;
  final String title;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: HugeIcon(icon: icon, color: color, size: 20),
            ),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondary,
          ),
        ),
        if (showDivider)
          const Divider(height: 1, indent: 68, color: Color(0xFFEEF0F3)),
      ],
    );
  }
}
