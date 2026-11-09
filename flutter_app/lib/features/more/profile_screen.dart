import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../directory/directory_models.dart';
import '../directory/directory_repository.dart';
import '../home/home_provider.dart';
import '../home/models.dart';
import 'edit_profile_screen.dart';
import 'more_models.dart';
import 'more_providers.dart';
import 'more_widgets.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(mobileHomeProvider);
    ref.invalidate(profileBundleProvider);
    ref.invalidate(myWorkSiteProvider);
    try {
      await ref.read(profileBundleProvider.future);
    } catch (_) {
      // The error state is rendered by the screen itself.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(mobileHomeProvider).asData?.value;
    final bundleAsync = ref.watch(profileBundleProvider);
    final bundle = bundleAsync.asData?.value;

    return MorePage(
      title: 'My Profile',
      actions: [
        if (bundle != null)
          IconButton(
            tooltip: 'Edit profile',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EditProfileScreen(profile: bundle.profile),
              ),
            ),
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedPencilEdit02,
              color: AppColors.navBlue,
              size: 22,
            ),
          ),
      ],
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            _Hero(home: home, bundle: bundle),
            const SizedBox(height: 16),
            bundleAsync.when(
              skipLoadingOnReload: true,
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SectionCard(
                children: [
                  ErrorPanel(
                    message: cleanError(e),
                    onRetry: () => ref.invalidate(profileBundleProvider),
                  ),
                ],
              ),
              data: (data) => _Sections(bundle: data),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.home, required this.bundle});

  final MobileHome? home;
  final ProfileBundle? bundle;

  @override
  Widget build(BuildContext context) {
    final name = bundle?.profile.fullName.isNotEmpty == true
        ? bundle!.profile.fullName
        : (home?.employeeName ?? 'Employee');
    final role = home?.roleLine ?? '';
    final badge = home?.displayBadgeId ?? '—';
    final work = bundle?.work;
    final joined = work?.dateJoining;
    final tenure = work?.tenureLabel;

    final stats = <(String, String)>[
      if (joined != null) ('Joined', DateFormat('d MMM yyyy').format(joined)),
      if (tenure != null) ('Tenure', tenure),
      if (work?.shift != null) ('Shift', work!.shift!),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      decoration: BoxDecoration(
        gradient: heroGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6D5CFF).withValues(alpha: 0.32),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: EmployeeAvatar(
              name: name,
              url: home?.avatarUrl ?? bundle?.profile.avatarUrl,
              radius: 44,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 21,
            ),
          ),
          if (role.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              role,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < stats.length; i++) ...[
                    if (i > 0)
                      Container(
                        width: 1,
                        height: 30,
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            stats[i].$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            stats[i].$1,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Sections extends StatelessWidget {
  const _Sections({required this.bundle});

  final ProfileBundle bundle;

  @override
  Widget build(BuildContext context) {
    final p = bundle.profile;
    final w = bundle.work;
    final bank = bundle.bank;
    final dateFmt = DateFormat('d MMMM yyyy');

    final contactEmail = p.email;
    final personalRows = <Widget>[
      InfoRow(
        icon: HugeIcons.strokeRoundedBirthdayCake,
        label: 'Date of birth',
        value: p.dob == null ? null : dateFmt.format(p.dob!),
        color: const Color(0xFFEC4899),
      ),
      InfoRow(
        icon: HugeIcons.strokeRoundedUser,
        label: 'Gender',
        value: humanize(p.gender),
        color: const Color(0xFF8B5CF6),
      ),
      InfoRow(
        icon: HugeIcons.strokeRoundedFavourite,
        label: 'Marital status',
        value: humanize(p.maritalStatus),
        color: const Color(0xFFEF4444),
      ),
      InfoRow(
        icon: HugeIcons.strokeRoundedBaby01,
        label: 'Children',
        value: p.children?.toString(),
        color: const Color(0xFF22B8E8),
      ),
      InfoRow(
        icon: HugeIcons.strokeRoundedMortarboard01,
        label: 'Qualification',
        value: p.qualification,
        color: const Color(0xFFF59E0B),
      ),
      InfoRow(
        icon: HugeIcons.strokeRoundedBriefcase01,
        label: 'Experience',
        value: p.experience == null ? null : '${p.experience} years',
        color: const Color(0xFF16A34A),
        last: true,
      ),
    ];

    return Column(
      children: [
        SectionCard(
          title: 'Contact',
          children: [
            InfoRow(
              icon: HugeIcons.strokeRoundedMail01,
              label: 'Email',
              value: contactEmail,
            ),
            InfoRow(
              icon: HugeIcons.strokeRoundedSmartPhone01,
              label: 'Mobile',
              value: p.phone,
              color: const Color(0xFF16A34A),
            ),
            InfoRow(
              icon: HugeIcons.strokeRoundedLocation01,
              label: 'Address',
              value: p.fullAddress,
              color: const Color(0xFFF59E0B),
              last: true,
            ),
            if (contactEmail == null &&
                p.phone == null &&
                p.fullAddress == null)
              const _NotProvided(),
          ],
        ),
        if (w != null) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: 'Work',
            children: [
              InfoRow(
                icon: HugeIcons.strokeRoundedBuilding03,
                label: 'Company',
                value: w.company,
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedBriefcase01,
                label: 'Position',
                value: w.jobPosition,
                color: const Color(0xFF8B5CF6),
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedUserGroup,
                label: 'Department',
                value: w.department,
                color: const Color(0xFF22B8E8),
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedUserStar01,
                label: 'Reports to',
                value: w.managerName,
                color: const Color(0xFFEC4899),
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedId,
                label: 'Employment type',
                value: w.employeeType,
                color: const Color(0xFFF59E0B),
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedHome01,
                label: 'Work type',
                value: w.workType,
                color: const Color(0xFF16A34A),
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedLocation01,
                label: 'Location',
                value: w.location,
                color: const Color(0xFFEF4444),
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedMail01,
                label: 'Work email',
                value: w.workEmail,
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedCall,
                label: 'Work phone',
                value: w.workPhone,
                color: const Color(0xFF16A34A),
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedCalendar03,
                label: 'Date joined',
                value: w.dateJoining == null
                    ? null
                    : dateFmt.format(w.dateJoining!),
                color: const Color(0xFF8B5CF6),
                last: true,
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        const _WorkSiteCard(),
        SectionCard(title: 'Personal', children: personalRows),
        if (p.hasEmergencyContact) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: 'Emergency contact',
            children: [
              InfoRow(
                icon: HugeIcons.strokeRoundedUser,
                label: 'Name',
                value: p.emergencyContactName,
                color: const Color(0xFFEF4444),
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedFavourite,
                label: 'Relation',
                value: p.emergencyContactRelation,
                color: const Color(0xFFEC4899),
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedCall,
                label: 'Phone',
                value: p.emergencyContact,
                color: const Color(0xFF16A34A),
                last: true,
              ),
            ],
          ),
        ],
        if (bank != null &&
            (bank.bankName != null || bank.accountNumber != null)) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: 'Bank account',
            children: [
              InfoRow(
                icon: HugeIcons.strokeRoundedBank,
                label: 'Bank',
                value: bank.bankName,
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedCreditCard,
                label: 'Account',
                value: bank.maskedAccount,
                color: const Color(0xFF8B5CF6),
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedLocation01,
                label: 'Branch',
                value: bank.branch,
                color: const Color(0xFFF59E0B),
                last: true,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _NotProvided extends StatelessWidget {
  const _NotProvided();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'No contact details on file.',
      style: TextStyle(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
    );
  }
}

/// Where the employee is assigned to work, from `GET /mobile/work-site/`.
/// Hidden while loading, on error, or when nothing is configured: it is
/// supporting information and must not push an error onto the profile.
class _WorkSiteCard extends ConsumerWidget {
  const _WorkSiteCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final site = ref.watch(myWorkSiteProvider).asData?.value;
    if (site == null || !site.isConfigured) return const SizedBox.shrink();

    final radius = site.radiusMeters;
    final fenceText = site.geofenceEnabled
        ? 'On${radius == null ? '' : ' · within $radius m'}'
        : 'Off · you can punch from anywhere';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SectionCard(
        title: site.kind == 'site' ? 'Work site' : 'Company location',
        children: [
          InfoRow(
            icon: HugeIcons.strokeRoundedLocation01,
            label: site.kind == 'site' ? 'Assigned site' : 'Location',
            value: site.name,
            color: const Color(0xFFEF4444),
          ),
          InfoRow(
            icon: HugeIcons.strokeRoundedBuilding01,
            label: 'Company',
            value: site.company,
            color: const Color(0xFFF97316),
          ),
          InfoRow(
            icon: HugeIcons.strokeRoundedMapPinpoint01,
            label: 'Work location',
            value: site.location,
            color: const Color(0xFFF59E0B),
          ),
          InfoRow(
            icon: HugeIcons.strokeRoundedGps01,
            label: 'Punch geofence',
            value: fenceText,
            color: site.geofenceEnabled
                ? const Color(0xFF16A34A)
                : AppColors.textSecondary,
            last: !site.hasCoordinates,
          ),
          if (site.hasCoordinates)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => openExternal(
                  context,
                  _mapsUri(site),
                  failMessage: 'No maps app is available.',
                ),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Open in maps'),
              ),
            ),
        ],
      ),
    );
  }

  Uri _mapsUri(WorkSiteInfo site) {
    final lat = site.latitude!;
    final lng = site.longitude!;
    return Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
  }
}
