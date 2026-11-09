import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme.dart';
import '../auth/auth_provider.dart';
import '../home/home_provider.dart';
import '../home/models.dart';
import 'activity_center_screen.dart';
import 'change_password_screen.dart';
import '../directory/directory_screen.dart';
import 'documents_repository.dart';
import 'documents_screen.dart';
import 'help_desk_screen.dart';
import 'more_models.dart';
import 'more_providers.dart';
import 'more_widgets.dart';
import 'payslips_screen.dart';
import 'policies_screen.dart';
import 'profile_screen.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(mobileHomeProvider);
    ref.invalidate(payslipsProvider);
    ref.invalidate(policiesProvider);
    ref.invalidate(documentsProvider);
    ref.invalidate(ticketsProvider);
    try {
      await ref.read(mobileHomeProvider.future);
    } catch (_) {
      // The error state is rendered by the screen itself.
    }
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to use ClockMe.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Sign out',
              style: TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeAsync = ref.watch(mobileHomeProvider);

    // Subtitles come from the same endpoints the detail screens use. A failed
    // or still-loading call just falls back to the static description.
    final payslips = ref.watch(payslipsProvider).asData?.value;
    final policies = ref.watch(policiesProvider).asData?.value;
    final documents = ref.watch(documentsProvider).asData?.value;
    final tickets = ref.watch(ticketsProvider).asData?.value;

    final docsWaiting =
        documents?.where((d) => d.document.canUpload).length ?? 0;
    final openTickets = tickets?.where((t) => t.status.isOpen).length ?? 0;
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        bottom: false,
        child: homeAsync.when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: ErrorPanel(
              message: cleanError(e),
              onRetry: () => ref.invalidate(mobileHomeProvider),
            ),
          ),
          data: (home) => ConstrainedContent(
            child: RefreshIndicator(
              onRefresh: () => _refresh(ref),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 14),
                    child: Text(
                      'More',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navBlue,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  _ProfileCard(
                    home: home,
                    onViewProfile: () => _open(context, const ProfileScreen()),
                  ),
                  const _SectionTitle('My work'),
                  _MenuGroup(
                    children: [
                      _MenuTile(
                        icon: HugeIcons.strokeRoundedInvoice03,
                        color: const Color(0xFF16A34A),
                        title: 'Payslips',
                        subtitle: payslips == null
                            ? 'Monthly salary breakdown'
                            : payslips.isEmpty
                            ? 'No payslips issued yet'
                            : 'Latest: ${payslips.first.periodLabel}',
                        onTap: () => _open(context, const PayslipsScreen()),
                      ),
                      _MenuTile(
                        icon: HugeIcons.strokeRoundedFolder01,
                        color: const Color(0xFF0EA5E9),
                        title: 'Documents',
                        subtitle: documents == null
                            ? 'Your files and requests from HR'
                            : documents.isEmpty
                            ? 'No documents yet'
                            : docsWaiting > 0
                            ? '$docsWaiting need${docsWaiting == 1 ? 's' : ''} your attention'
                            : '${documents.length} on file',
                        badge: docsWaiting,
                        onTap: () => _open(context, const DocumentsScreen()),
                      ),
                      _MenuTile(
                        icon: HugeIcons.strokeRoundedAnalyticsUp,
                        color: const Color(0xFFF97316),
                        title: 'Activity center',
                        subtitle: 'Recent punches and updates',
                        showDivider: false,
                        onTap: () =>
                            _open(context, const ActivityCenterScreen()),
                      ),
                    ],
                  ),
                  const _SectionTitle('Company'),
                  _MenuGroup(
                    children: [
                      _MenuTile(
                        icon: HugeIcons.strokeRoundedUserGroup,
                        color: const Color(0xFF22B8E8),
                        title: 'Directory',
                        subtitle: 'Find colleagues and contact details',
                        onTap: () => _open(context, const DirectoryScreen()),
                      ),
                      _MenuTile(
                        icon: HugeIcons.strokeRoundedShield01,
                        color: const Color(0xFF8B5CF6),
                        title: 'Company policies',
                        subtitle: policies == null
                            ? 'Guidelines shared with you'
                            : policies.isEmpty
                            ? 'No policies published'
                            : '${policies.length} polic${policies.length == 1 ? 'y' : 'ies'} published',
                        showDivider: false,
                        onTap: () => _open(context, const PoliciesScreen()),
                      ),
                    ],
                  ),
                  const _SectionTitle('Support'),
                  _MenuGroup(
                    children: [
                      _MenuTile(
                        icon: HugeIcons.strokeRoundedCustomerService01,
                        color: const Color(0xFF22B8E8),
                        title: 'Help desk',
                        subtitle: tickets == null
                            ? 'Raise tickets and read FAQs'
                            : openTickets == 0
                            ? 'No open tickets'
                            : '$openTickets open ticket${openTickets == 1 ? '' : 's'}',
                        badge: openTickets,
                        showDivider: false,
                        onTap: () => _open(context, const HelpDeskScreen()),
                      ),
                    ],
                  ),
                  const _SectionTitle('Account'),
                  _MenuGroup(
                    children: [
                      _MenuTile(
                        icon: HugeIcons.strokeRoundedSquareLockPassword,
                        color: AppColors.orange,
                        title: 'Change password',
                        subtitle: 'Keep your account secure',
                        onTap: () =>
                            _open(context, const ChangePasswordScreen()),
                      ),
                      _MenuTile(
                        icon: HugeIcons.strokeRoundedLogout01,
                        color: const Color(0xFFEF4444),
                        title: 'Sign out',
                        showDivider: false,
                        destructive: true,
                        onTap: () => _confirmSignOut(context, ref),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.home, required this.onViewProfile});

  final MobileHome home;
  final VoidCallback onViewProfile;

  @override
  Widget build(BuildContext context) {
    final role = home.roleLine;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6D5CFF).withValues(alpha: 0.30),
            blurRadius: 20,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: EmployeeAvatar(
                  name: home.employeeName,
                  url: home.avatarUrl,
                  radius: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      home.employeeName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    if (role.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        role,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        home.displayBadgeId,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onViewProfile,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.navBlue,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'View profile',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
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
      decoration: cardDecoration(radius: 20),
      clipBehavior: Clip.antiAlias,
      // The tiles' ink has to paint above the white card, so give them their
      // own (transparent) Material instead of the scaffold's behind it.
      child: Material(
        color: Colors.transparent,
        child: Column(children: children),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.badge = 0,
    this.showDivider = true,
    this.destructive = false,
  });

  final List<List<dynamic>> icon;
  final Color color;
  final String title;
  final String? subtitle;
  final int badge;
  final VoidCallback onTap;
  final bool showDivider;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 2,
          ),
          leading: GradientIconTile(icon: icon, color: color, size: 42),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14.5,
              color: destructive ? AppColors.red : AppColors.textPrimary,
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge > 0)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$badge',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              if (!destructive)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, indent: 70, color: Color(0xFFEEF0F3)),
      ],
    );
  }
}
