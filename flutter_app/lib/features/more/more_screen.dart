import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/config.dart';
import '../../core/server_url_provider.dart';
import '../../core/theme.dart';
import '../auth/app_lock.dart';
import '../auth/auth_provider.dart';
import '../auth/server_url_screen.dart';
import '../home/home_provider.dart';
import '../home/home_typography.dart';
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Sign out?',
          style: HomeType.headline(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: moreText,
          ),
        ),
        content: Text(
          'You will need to sign in again to use ClockMe.',
          style: HomeType.body(fontSize: 14, color: moreSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: HomeType.body(
                fontWeight: FontWeight.w600,
                color: moreBlue,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Sign out',
              style: HomeType.body(fontWeight: FontWeight.w600, color: moreRed),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).logout();
    }
  }

  Future<void> _setAppLock(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final ok = await promptAppLock(
      reason: enabled
          ? 'Confirm to turn on app lock'
          : 'Confirm to turn off app lock',
    );
    if (!ok) {
      if (context.mounted) {
        showSnack(
          context,
          enabled
              ? 'App lock needs a device PIN or biometric.'
              : 'App lock stays on.',
        );
      }
      return;
    }
    final saved = await ref
        .read(appLockEnabledProvider.notifier)
        .setEnabled(enabled);
    if (!saved) {
      if (context.mounted) showSnack(context, 'Could not update app lock.');
      return;
    }
    if (enabled) {
      ref.read(appLockSessionProvider.notifier).state = true;
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
    final appLock = ref.watch(appLockEnabledProvider);
    final serverDisplay = ServerUrl.display(
      ref.watch(serverUrlProvider).apiBaseUrl,
    );
    return Theme(
      data: HomeType.of(context),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: moreCanvas,
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                        child: Text(
                          'More',
                          style: HomeType.headline(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: moreText,
                            letterSpacing: -0.4,
                            height: 1.1,
                          ),
                        ),
                      ),
                      _ProfileCard(
                        home: home,
                        onViewProfile: () =>
                            _open(context, const ProfileScreen()),
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
                            onTap: () =>
                                _open(context, const DocumentsScreen()),
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
                            onTap: () =>
                                _open(context, const DirectoryScreen()),
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
                          _AppLockTile(
                            enabled: appLock.enabled,
                            loaded: appLock.loaded,
                            onChanged: (value) =>
                                _setAppLock(context, ref, value),
                          ),
                          _MenuTile(
                            icon: HugeIcons.strokeRoundedLink01,
                            color: moreBlue,
                            title: 'Server address',
                            subtitle: serverDisplay.isEmpty
                                ? 'ClockMe URL used by this device'
                                : serverDisplay,
                            onTap: () => _open(
                              context,
                              const ServerUrlScreen(editing: true),
                            ),
                          ),
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
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: HomeType.headline(
          fontWeight: FontWeight.w600,
          fontSize: 11,
          color: moreMuted,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _OnlineAvatar extends StatelessWidget {
  const _OnlineAvatar({
    required this.name,
    required this.url,
    required this.radius,
  });

  final String name;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: EmployeeAvatar(name: name, url: url, radius: radius),
        ),
        Positioned(
          right: 1,
          bottom: 1,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: moreGreen,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _OnlineAvatar(
                name: home.employeeName,
                url: home.avatarUrl,
                radius: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      home.employeeName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: HomeType.headline(
                        color: moreText,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    if (role.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        role,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: HomeType.body(
                          color: moreMuted,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: moreCanvas,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        home.displayBadgeId,
                        style: HomeType.body(
                          color: moreSecondary,
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onViewProfile,
              style: FilledButton.styleFrom(
                backgroundColor: moreBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              child: Text(
                'View profile',
                style: HomeType.headline(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.white,
                ),
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
      decoration: cardDecoration(),
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

class _AppLockTile extends StatelessWidget {
  const _AppLockTile({
    required this.enabled,
    required this.loaded,
    required this.onChanged,
  });

  final bool enabled;
  final bool loaded;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
          secondary: const _TintIcon(
            icon: HugeIcons.strokeRoundedFingerPrint,
            color: moreBlue,
          ),
          title: Text(
            'App lock',
            style: HomeType.headline(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: moreText,
            ),
          ),
          subtitle: Text(
            'Ask for fingerprint, face, or PIN',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HomeType.body(
              color: moreMuted,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
          value: enabled,
          onChanged: loaded ? onChanged : null,
          activeThumbColor: Colors.white,
          activeTrackColor: moreGreen,
        ),
        const Divider(height: 1, indent: 62, color: moreHairline),
      ],
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
          leading: _TintIcon(icon: icon, color: color),
          title: Text(
            title,
            style: HomeType.headline(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: destructive ? moreRed : moreText,
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HomeType.body(
                    color: moreMuted,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge > 0)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: moreBlue,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$badge',
                    style: HomeType.headline(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              if (!destructive)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFC7C7CC),
                ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, indent: 62, color: moreHairline),
      ],
    );
  }
}

class _TintIcon extends StatelessWidget {
  const _TintIcon({required this.icon, required this.color});

  final List<List<dynamic>> icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Center(
        child: HugeIcon(icon: icon, color: color, size: 18),
      ),
    );
  }
}
