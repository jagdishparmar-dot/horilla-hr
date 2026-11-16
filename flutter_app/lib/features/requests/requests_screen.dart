import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/api/dio_client.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../home/home_provider.dart';
import '../home/home_typography.dart';
import '../home/models.dart';
import 'models.dart';
import 'new_request_sheet.dart';
import 'request_details_sheet.dart';
import 'requests_provider.dart';

const _iosBg = Color(0xFFF2F2F7);
const _iosText = Color(0xFF1C1C1E);
const _iosMuted = Color(0xFF8E8E93);
const _iosSecondary = Color(0xFF636366);
const _iosBlue = AppColors.navBlue;
const _iosGreen = Color(0xFF34C759);
const _iosGreenText = Color(0xFF248A3D);
const _iosAmberText = Color(0xFFC97000);
const _iosRed = Color(0xFFFF3B30);
const _iosHairline = Color(0x0A000000);

BoxDecoration _iosCard({double radius = 13}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: _iosHairline),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  );
}

(Color, Color) _statusTone(RequestStatus status) => switch (status) {
  RequestStatus.pending ||
  RequestStatus.cancelRequested => (_iosAmberText, const Color(0x26FF9500)),
  RequestStatus.approved => (_iosGreenText, const Color(0x2634C759)),
  RequestStatus.rejected => (_iosRed, const Color(0x26FF3B30)),
  RequestStatus.cancelled => (_iosSecondary, const Color(0x1F767680)),
};

Color _statusAccent(RequestStatus status) => switch (status) {
  RequestStatus.pending ||
  RequestStatus.cancelRequested => const Color(0xFFFF9500),
  RequestStatus.approved => _iosGreen,
  RequestStatus.rejected => _iosRed,
  RequestStatus.cancelled => _iosSecondary,
};

bool _isOpen(RequestStatus s) =>
    s == RequestStatus.pending || s == RequestStatus.cancelRequested;

const _balanceCardHeight = 164.0;

class RequestsScreen extends ConsumerWidget {
  const RequestsScreen({super.key});

  Future<void> _openNew(BuildContext context, WidgetRef ref) async {
    final created = await showNewRequestSheet(context);
    if (created == true) invalidateRequests(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeAsync = ref.watch(mobileHomeProvider);
    final balancesAsync = ref.watch(leaveBalancesProvider);
    final requestsAsync = ref.watch(leaveRequestsProvider);
    final typeFilter = ref.watch(requestListFilterProvider);
    final statusFilter = ref.watch(requestStatusFilterProvider);
    final items = requestsAsync.asData?.value;

    return Theme(
      data: HomeType.of(context),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: _iosBg,
          floatingActionButton: Material(
            color: _iosBlue,
            elevation: 4,
            shadowColor: _iosBlue.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(99),
            child: InkWell(
              borderRadius: BorderRadius.circular(99),
              onTap: () => _openNew(context, ref),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 18, 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const HugeIcon(
                      icon: HugeIcons.strokeRoundedFileAdd,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'New request',
                      style: HomeType.headline(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: SafeArea(
            bottom: false,
            child: homeAsync.when(
              skipLoadingOnReload: true,
              loading: () => const Center(
                child: CircularProgressIndicator(color: _iosBlue),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(userFacingError(e), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => ref.invalidate(mobileHomeProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (home) => RefreshIndicator(
                onRefresh: () async {
                  invalidateRequests(ref);
                  ref.invalidate(mobileHomeProvider);
                  await ref.read(leaveRequestsProvider.future);
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: _RequestsHeader(
                          home: home,
                          openCount: items
                              ?.where((e) => _isOpen(e.status))
                              .length,
                        ),
                      ),
                    ),
                    if (items != null && items.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: _StatusSummary(
                            items: items,
                            selected: statusFilter,
                            onSelected: (value) =>
                                ref
                                        .read(
                                          requestStatusFilterProvider.notifier,
                                        )
                                        .state =
                                    value,
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: _SectionTitle(
                          title: 'Leave balance',
                          icon: HugeIcons.strokeRoundedSun03,
                          color: _iosGreen,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: _balanceCardHeight,
                        child: balancesAsync.when(
                          skipLoadingOnReload: true,
                          loading: () => const Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            ),
                          ),
                          error: (e, _) => Center(
                            child: TextButton(
                              onPressed: () =>
                                  ref.invalidate(leaveBalancesProvider),
                              child: const Text('Retry balances'),
                            ),
                          ),
                          data: (balances) => balances.isEmpty
                              ? const _InlineEmpty(
                                  label: 'No leave balances assigned yet',
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  scrollDirection: Axis.horizontal,
                                  itemCount: balances.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (context, index) =>
                                      _BalanceCard(balance: balances[index]),
                                ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: _SectionTitle(title: 'My requests'),
                      ),
                    ),
                    if (items != null && items.isNotEmpty)
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _FilterBarDelegate(
                          child: _FilterBar(
                            items: items,
                            selected: typeFilter,
                            onSelected: (value) =>
                                ref
                                        .read(
                                          requestListFilterProvider.notifier,
                                        )
                                        .state =
                                    value,
                          ),
                        ),
                      ),
                    ...requestsAsync.when(
                      skipLoadingOnReload: true,
                      loading: () => [
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 48),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                      ],
                      error: (e, _) => [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Text(
                                  userFacingError(e),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: () =>
                                      ref.invalidate(leaveRequestsProvider),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      data: (all) {
                        final visible = [
                          for (final item in all)
                            if (item.matchesFilter(typeFilter) &&
                                (statusFilter == null ||
                                    (statusFilter == RequestStatus.pending
                                        ? _isOpen(item.status)
                                        : item.status == statusFilter)))
                              item,
                        ];
                        if (all.isEmpty) {
                          return [
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _EmptyRequests(
                                onAdd: () => _openNew(context, ref),
                              ),
                            ),
                          ];
                        }
                        if (visible.isEmpty) {
                          return [
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _NoMatches(
                                onClear: () {
                                  ref
                                      .read(requestListFilterProvider.notifier)
                                      .state = RequestListFilter
                                      .all;
                                  ref
                                          .read(
                                            requestStatusFilterProvider
                                                .notifier,
                                          )
                                          .state =
                                      null;
                                },
                              ),
                            ),
                          ];
                        }
                        return [_groupedList(context, visible)];
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Requests grouped under month headings, newest first.
  Widget _groupedList(BuildContext context, List<LeaveRequestItem> items) {
    final rows = <Widget>[];
    String? currentGroup;
    final groupStarts = <int, String>{};
    final counts = <String, int>{};
    for (var i = 0; i < items.length; i++) {
      final key = DateFormat('MMMM yyyy').format(items[i].startDate);
      counts[key] = (counts[key] ?? 0) + 1;
      if (key != currentGroup) {
        currentGroup = key;
        groupStarts[i] = key;
      }
    }
    for (var i = 0; i < items.length; i++) {
      final heading = groupStarts[i];
      if (heading != null) {
        rows.add(
          Padding(
            padding: EdgeInsets.fromLTRB(2, i == 0 ? 8 : 16, 2, 8),
            child: Row(
              children: [
                Text(
                  heading.toUpperCase(),
                  style: HomeType.body(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: _iosMuted,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x0A000000),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${counts[heading]}',
                    style: HomeType.body(
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                      color: _iosMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        rows.add(const SizedBox(height: 8));
      }
      rows.add(
        _RequestCard(
          item: items[i],
          onTap: () => showRequestDetailsSheet(context, item: items[i]),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      sliver: SliverList(delegate: SliverChildListDelegate(rows)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.icon, this.color});

  final String title;
  final List<List<dynamic>>? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: HomeType.body(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _iosText,
          ),
        ),
        if (icon != null && color != null) ...[
          const Spacer(),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color!.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Center(
              child: HugeIcon(icon: icon!, color: color!, size: 16),
            ),
          ),
        ],
      ],
    );
  }
}

class _RequestsHeader extends StatelessWidget {
  const _RequestsHeader({required this.home, required this.openCount});

  final MobileHome home;
  final int? openCount;

  String? _resolveAvatar(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    return '${AppConfig.mediaOrigin}$url';
  }

  @override
  Widget build(BuildContext context) {
    final avatar = _resolveAvatar(home.avatarUrl);
    final subtitle = switch (openCount) {
      null => 'Leave, attendance, and work changes',
      0 => 'Nothing waiting for approval',
      1 => '1 request waiting for approval',
      final n => '$n requests waiting for approval',
    };

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Requests',
                style: HomeType.headline(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _iosText,
                  letterSpacing: -0.4,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: HomeType.body(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _iosMuted,
                ),
              ),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: CircleAvatar(
                backgroundColor: const Color(0xFFEAF0FF),
                backgroundImage: avatar != null
                    ? CachedNetworkImageProvider(avatar)
                    : null,
                child: avatar == null
                    ? Text(
                        home.firstName.isNotEmpty
                            ? home.firstName[0].toUpperCase()
                            : '?',
                        style: HomeType.headline(
                          color: _iosBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: _iosGreen,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Pending / Approved / Rejected counts. Tapping one narrows the list.
class _StatusSummary extends StatelessWidget {
  const _StatusSummary({
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<LeaveRequestItem> items;
  final RequestStatus? selected;
  final ValueChanged<RequestStatus?> onSelected;

  @override
  Widget build(BuildContext context) {
    int count(bool Function(RequestStatus) test) =>
        items.where((e) => test(e.status)).length;

    final entries = <(RequestStatus, int, List<List<dynamic>>)>[
      (RequestStatus.pending, count(_isOpen), HugeIcons.strokeRoundedTimer02),
      (
        RequestStatus.approved,
        count((s) => s == RequestStatus.approved),
        HugeIcons.strokeRoundedCheckmarkCircle02,
      ),
      (
        RequestStatus.rejected,
        count((s) => s == RequestStatus.rejected),
        HugeIcons.strokeRoundedCancelCircle,
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _StatusTile(
              status: entries[i].$1,
              count: entries[i].$2,
              icon: entries[i].$3,
              active: selected == entries[i].$1,
              onTap: () =>
                  onSelected(selected == entries[i].$1 ? null : entries[i].$1),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.status,
    required this.count,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final RequestStatus status;
  final int count;
  final List<List<dynamic>> icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _statusAccent(status);
    final tint = _statusTone(status).$2;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: _iosCard().copyWith(
            border: Border.all(
              color: active ? accent : _iosHairline,
              width: active ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      status.label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HomeType.body(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _iosMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Center(
                      child: HugeIcon(icon: icon, color: accent, size: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$count',
                style: HomeType.headline(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  height: 1,
                  color: _iosText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label,
        style: HomeType.body(color: _iosMuted, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

  final LeaveBalance balance;

  @override
  Widget build(BuildContext context) {
    final accent = balance.accent;
    final used = balance.used.toDouble();
    final total = balance.total.toDouble();
    final fraction = total <= 0 ? 0.0 : (used / total).clamp(0.0, 1.0);

    return SizedBox(
      width: 148,
      height: _balanceCardHeight,
      child: DecoratedBox(
        decoration: _iosCard(),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Center(
                    child: HugeIcon(
                      icon: balance.icon,
                      color: accent,
                      size: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  balance.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HomeType.body(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    height: 1.2,
                    color: _iosText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  balance.availableFigure,
                  style: HomeType.headline(
                    fontWeight: FontWeight.w700,
                    fontSize: 28,
                    height: 1,
                    color: _iosText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  balance.availableCaption.replaceAll('\n', ' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HomeType.body(
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                    height: 1.2,
                    color: _iosMuted,
                  ),
                ),
                const Spacer(),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 4,
                    backgroundColor: const Color(0x0F000000),
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${balance.usedLine}  ${balance.totalLine}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HomeType.body(
                    fontSize: 10,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    color: _iosMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterBarDelegate extends SliverPersistentHeaderDelegate {
  _FilterBarDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 44;

  @override
  double get maxExtent => 44;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: _iosBg, alignment: Alignment.center, child: child);
  }

  @override
  bool shouldRebuild(covariant _FilterBarDelegate oldDelegate) => true;
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<LeaveRequestItem> items;
  final RequestListFilter selected;
  final ValueChanged<RequestListFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    const filters = RequestListFilter.values;
    return SizedBox(
      height: 32,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final count = items
              .where((item) => item.matchesFilter(filter))
              .length;
          final active = filter == selected;
          final label = switch (filter) {
            RequestListFilter.all => 'All',
            RequestListFilter.leave => 'Leave',
            RequestListFilter.permission => 'Permission',
            RequestListFilter.remote => 'Remote',
            RequestListFilter.attendance => 'Attendance',
            RequestListFilter.shift => 'Shift',
          };
          return GestureDetector(
            onTap: () => onSelected(filter),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? _iosBlue : const Color(0x1F767680),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: HomeType.body(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      color: active ? Colors.white : _iosSecondary,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$count',
                    style: HomeType.body(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: active
                          ? Colors.white.withValues(alpha: 0.9)
                          : _iosMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyRequests extends StatelessWidget {
  const _EmptyRequests({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _iosBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedFile02,
                  color: _iosBlue,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No requests yet',
              style: HomeType.headline(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: _iosText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Leave, permission, remote work, attendance fixes and shift changes you file will show up here.',
              textAlign: TextAlign.center,
              style: HomeType.body(
                color: _iosMuted,
                fontWeight: FontWeight.w500,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onAdd,
              style: FilledButton.styleFrom(
                backgroundColor: _iosBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              child: Text(
                'Add new request',
                style: HomeType.headline(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedSearch01,
              color: _iosMuted,
              size: 36,
            ),
            const SizedBox(height: 12),
            Text(
              'Nothing matches these filters',
              textAlign: TextAlign.center,
              style: HomeType.headline(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: _iosText,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onClear,
              child: Text(
                'Clear filters',
                style: HomeType.body(
                  fontWeight: FontWeight.w600,
                  color: _iosBlue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.item, required this.onTap});

  final LeaveRequestItem item;
  final VoidCallback onTap;

  String get _dateLabel {
    final start = DateFormat('MMM d, yyyy').format(item.startDate);
    if (item.startDate.year == item.endDate.year &&
        item.startDate.month == item.endDate.month &&
        item.startDate.day == item.endDate.day) {
      return start;
    }
    final sameYear = item.startDate.year == item.endDate.year;
    final startFmt = DateFormat(sameYear ? 'MMM d' : 'MMM d, yyyy')
        .format(item.startDate);
    final endFmt = DateFormat('MMM d, yyyy').format(item.endDate);
    return '$startFmt to $endFmt';
  }

  @override
  Widget build(BuildContext context) {
    final status = item.status;

    final (fg, tint) = _statusTone(status);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Ink(
          decoration: _iosCard(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: item.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Center(
                    child: HugeIcon(
                      icon: item.icon,
                      color: item.accent,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HomeType.headline(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: _iosText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.categoryLabel} · ${item.durationLabel} · $_dateLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HomeType.body(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _iosMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    status.label,
                    style: HomeType.body(
                      color: fg,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
