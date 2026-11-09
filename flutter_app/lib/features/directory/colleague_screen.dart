import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme.dart';
import '../more/more_widgets.dart';
import 'directory_models.dart';
import 'directory_repository.dart';

/// One colleague's basic profile: role, reporting line, work site and work
/// contact. Never shows pay, bank, birthday or home details - the server does
/// not send them.
class ColleagueScreen extends ConsumerWidget {
  const ColleagueScreen({super.key, required this.entry});

  /// What the list already knows, used for the header while the rest loads.
  final DirectoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(directoryDetailProvider(entry.id));

    return MorePage(
      title: 'Colleague',
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(directoryDetailProvider(entry.id));
          try {
            await ref.read(directoryDetailProvider(entry.id).future);
          } catch (_) {}
        },
        child: AsyncView<DirectoryDetail>(
          value: async,
          onRetry: () => ref.invalidate(directoryDetailProvider(entry.id)),
          builder: (detail) => _Body(detail: detail),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.detail});

  final DirectoryDetail detail;

  Future<void> _copy(BuildContext context, String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) showSnack(context, '$label copied');
  }

  @override
  Widget build(BuildContext context) {
    final e = detail.entry;
    final phone = detail.workPhone;
    final email = detail.workEmail;
    final role = e.roleLine;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
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
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: EmployeeAvatar(name: e.name, url: e.photo, radius: 42),
              ),
              const SizedBox(height: 12),
              Text(
                e.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
              if (role.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  role,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
              if (e.badgeId != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    e.badgeId!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              if (phone != null || email != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (phone != null)
                      Expanded(
                        child: _ActionButton(
                          icon: HugeIcons.strokeRoundedCall02,
                          label: 'Call',
                          onTap: () => openExternal(
                            context,
                            Uri(scheme: 'tel', path: phone),
                            failMessage: "Couldn't start a call.",
                          ),
                        ),
                      ),
                    if (phone != null && email != null)
                      const SizedBox(width: 10),
                    if (email != null)
                      Expanded(
                        child: _ActionButton(
                          icon: HugeIcons.strokeRoundedMail01,
                          label: 'Email',
                          onTap: () => openExternal(
                            context,
                            Uri(scheme: 'mailto', path: email),
                            failMessage: 'No email app is available.',
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Work',
          children: [
            InfoRow(
              icon: HugeIcons.strokeRoundedBriefcase01,
              label: 'Job position',
              value: e.jobPosition,
              color: AppColors.navBlue,
            ),
            InfoRow(
              icon: HugeIcons.strokeRoundedUserCircle,
              label: 'Job role',
              value: detail.jobRole,
              color: const Color(0xFF8B5CF6),
            ),
            InfoRow(
              icon: HugeIcons.strokeRoundedBuilding03,
              label: 'Department',
              value: e.department,
              color: const Color(0xFF22B8E8),
            ),
            InfoRow(
              icon: HugeIcons.strokeRoundedBuilding01,
              label: 'Company',
              value: detail.company,
              color: const Color(0xFFF97316),
            ),
            InfoRow(
              icon: HugeIcons.strokeRoundedUserStar01,
              label: 'Reports to',
              value: detail.managerName,
              color: const Color(0xFF16A34A),
            ),
            InfoRow(
              icon: HugeIcons.strokeRoundedLocation01,
              label: 'Work site',
              value: detail.workSite,
              color: const Color(0xFFEF4444),
            ),
            InfoRow(
              icon: HugeIcons.strokeRoundedMapPinpoint01,
              label: 'Work location',
              value: detail.workLocation,
              color: const Color(0xFFF59E0B),
              last: true,
            ),
            if ([
              e.jobPosition,
              detail.jobRole,
              e.department,
              detail.company,
              detail.managerName,
              detail.workSite,
              detail.workLocation,
            ].every((v) => v == null))
              const Text(
                'No work details have been added yet.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        if (phone != null || email != null) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: 'Contact',
            children: [
              if (email != null)
                _CopyRow(
                  icon: HugeIcons.strokeRoundedMail01,
                  label: 'Email',
                  value: email,
                  color: AppColors.navBlue,
                  last: phone == null,
                  onCopy: () => _copy(context, 'Email', email),
                ),
              if (phone != null)
                _CopyRow(
                  icon: HugeIcons.strokeRoundedCall02,
                  label: 'Work phone',
                  value: phone,
                  color: const Color(0xFF16A34A),
                  last: true,
                  onCopy: () => _copy(context, 'Phone number', phone),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final List<List<dynamic>> icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.navBlue,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: HugeIcon(icon: icon, color: AppColors.navBlue, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
      ),
    );
  }
}

/// An [InfoRow] that copies its value on long-press or via the trailing icon.
class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onCopy,
    this.last = false,
  });

  final List<List<dynamic>> icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback onCopy;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InfoRow(
            icon: icon,
            label: label,
            value: value,
            color: color,
            last: last,
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: last ? 0 : 14),
          child: IconButton(
            tooltip: 'Copy',
            onPressed: onCopy,
            icon: const Icon(
              Icons.copy_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
