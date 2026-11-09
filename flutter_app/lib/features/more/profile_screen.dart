import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../home/models.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.home});

  final MobileHome home;

  String? _resolveAvatar(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    return '${AppConfig.mediaOrigin}$url';
  }

  @override
  Widget build(BuildContext context) {
    final avatar = _resolveAvatar(home.avatarUrl);

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.scaffold,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        ),
        title: const Text(
          'Profile',
          style: TextStyle(
            color: AppColors.navBlue,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: AppColors.purpleSoft,
                  backgroundImage:
                      avatar != null ? CachedNetworkImageProvider(avatar) : null,
                  child: avatar == null
                      ? Text(
                          home.firstName.isNotEmpty
                              ? home.firstName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: AppColors.purple,
                            fontWeight: FontWeight.w800,
                            fontSize: 32,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  home.employeeName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Edit profile coming soon')),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.navBlue,
                    side: const BorderSide(color: AppColors.navBlue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Edit Profile',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'About',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _AboutTile(
                  icon: HugeIcons.strokeRoundedBriefcase01,
                  label: 'Designation',
                  value: home.jobPosition?.isNotEmpty == true
                      ? home.jobPosition!
                      : '—',
                ),
                _AboutTile(
                  icon: HugeIcons.strokeRoundedId,
                  label: 'Employee ID',
                  value: home.badgeId?.isNotEmpty == true ? home.badgeId! : '—',
                ),
                _AboutTile(
                  icon: HugeIcons.strokeRoundedBuilding03,
                  label: 'Department',
                  value: home.department?.isNotEmpty == true
                      ? home.department!
                      : '—',
                ),
                _AboutTile(
                  icon: HugeIcons.strokeRoundedSmartPhone01,
                  label: 'Mobile Number',
                  value: home.phone?.isNotEmpty == true ? home.phone! : '—',
                ),
                _AboutTile(
                  icon: HugeIcons.strokeRoundedMail01,
                  label: 'Email ID',
                  value: home.email?.isNotEmpty == true ? home.email! : '—',
                  showDivider: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutTile extends StatelessWidget {
  const _AboutTile({
    required this.icon,
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final List<List<dynamic>> icon;
  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: HugeIcon(icon: icon, color: AppColors.navBlue, size: 20),
          title: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
        if (showDivider)
          const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}
