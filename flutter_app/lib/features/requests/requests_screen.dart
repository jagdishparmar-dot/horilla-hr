import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../home/home_provider.dart';
import '../home/models.dart';
import 'models.dart';
import 'new_request_sheet.dart';
import 'request_details_sheet.dart';
import 'requests_provider.dart';

const _heroGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF2F6BFF), Color(0xFF6D5CFF), Color(0xFF9B5CFF)],
);

bool _isOpen(RequestStatus s) =>
    s == RequestStatus.pending || s == RequestStatus.cancelRequested;

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

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      floatingActionButton: DecoratedBox(
        decoration: BoxDecoration(
          gradient: _heroGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.navBlue.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _openNew(context, ref),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedFileAdd,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'New request',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: homeAsync.when(
          skipLoadingOnReload: true,
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
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: _RequestsHeader(
                      home: home,
                      openCount: items?.where((e) => _isOpen(e.status)).length,
                    ),
                  ),
                ),
                if (items != null && items.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: _StatusSummary(
                        items: items,
                        selected: statusFilter,
                        onSelected: (value) =>
                            ref
                                    .read(requestStatusFilterProvider.notifier)
                                    .state =
                                value,
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 22, 20, 12),
                    child: _SectionTitle(
                      title: 'Leave balance',
                      icon: HugeIcons.strokeRoundedSun03,
                      color: Color(0xFF22C55E),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 176,
                    child: balancesAsync.when(
                      skipLoadingOnReload: true,
                      loading: () => const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
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
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                              scrollDirection: Axis.horizontal,
                              itemCount: balances.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, index) =>
                                  _BalanceCard(balance: balances[index]),
                            ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 10, 20, 4),
                    child: _SectionTitle(
                      title: 'My requests',
                      icon: HugeIcons.strokeRoundedFile02,
                      color: Color(0xFF8B5CF6),
                    ),
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
                            ref.read(requestListFilterProvider.notifier).state =
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
                            Text(e.toString(), textAlign: TextAlign.center),
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
                                      .state =
                                  RequestListFilter.all;
                              ref
                                      .read(
                                        requestStatusFilterProvider.notifier,
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
            padding: EdgeInsets.fromLTRB(4, i == 0 ? 6 : 16, 4, 8),
            child: Row(
              children: [
                Text(
                  heading,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(height: 1, color: const Color(0xFFE5E7EB)),
                ),
                const SizedBox(width: 8),
                Text(
                  '${counts[heading]}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        rows.add(const SizedBox(height: 10));
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
  const _SectionTitle({
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
  final List<List<dynamic>> icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: HugeIcon(icon: icon, color: color, size: 16),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
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
              const Text(
                'Requests',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navBlue,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            gradient: _heroGradient,
            shape: BoxShape.circle,
          ),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.purpleSoft,
              backgroundImage: avatar != null
                  ? CachedNetworkImageProvider(avatar)
                  : null,
              child: avatar == null
                  ? Text(
                      home.firstName.isNotEmpty
                          ? home.firstName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: AppColors.purple,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
          ),
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
          if (i > 0) const SizedBox(width: 10),
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
    final color = status.color;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: active ? color : status.softBackground,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: active ? 0.30 : 0.10),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HugeIcon(
                icon: icon,
                color: active ? Colors.white : color,
                size: 20,
              ),
              const SizedBox(height: 8),
              Text(
                '$count',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  height: 1,
                  color: active ? Colors.white : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                status.label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                  color: active ? Colors.white.withValues(alpha: 0.92) : color,
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
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
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

    return Container(
      width: 152,
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.14),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color.lerp(accent, Colors.white, 0.3)!, accent],
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(
                  child: HugeIcon(
                    icon: balance.icon,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  balance.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    height: 1.15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                balance.availableFigure,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                  height: 1,
                  color: accent,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Text(
                  balance.availableCaption,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    height: 1.15,
                    color: accent.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 5,
              backgroundColor: accent.withValues(alpha: 0.14),
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: Text(
                  balance.usedLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                balance.totalLine,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterBarDelegate extends SliverPersistentHeaderDelegate {
  _FilterBarDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 54;

  @override
  double get maxExtent => 54;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: AppColors.scaffold,
      alignment: Alignment.center,
      child: child,
    );
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
      height: 38,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final count = items
              .where((item) => item.matchesFilter(filter))
              .length;
          final active = filter == selected;
          final (label, color) = switch (filter) {
            RequestListFilter.all => ('All', AppColors.navBlue),
            RequestListFilter.leave => ('Leave', const Color(0xFF22C55E)),
            RequestListFilter.permission => (
              'Permission',
              const Color(0xFFF59E0B),
            ),
            RequestListFilter.remote => ('Remote', const Color(0xFF22B8E8)),
            RequestListFilter.attendance => (
              'Attendance',
              const Color(0xFF8B5CF6),
            ),
            RequestListFilter.shift => ('Shift', const Color(0xFF6366F1)),
          };
          return GestureDetector(
            onTap: () => onSelected(filter),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? color : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? color : color.withValues(alpha: 0.28),
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.30),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: active ? Colors.white : color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white.withValues(alpha: 0.25)
                          : color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: active ? Colors.white : color,
                      ),
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
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.navBlue.withValues(alpha: 0.16),
                    const Color(0xFF9B5CFF).withValues(alpha: 0.16),
                  ],
                ),
              ),
              child: Center(
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedFile02,
                  color: AppColors.navBlue,
                  size: 44,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No requests yet',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Leave, permission, remote work, attendance fixes and shift changes you file will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onAdd,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Add new request',
                style: TextStyle(fontWeight: FontWeight.w700),
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
              color: const Color(0xFFCBD5E1),
              size: 48,
            ),
            const SizedBox(height: 12),
            const Text(
              'Nothing matches these filters',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onClear,
              child: const Text(
                'Clear filters',
                style: TextStyle(fontWeight: FontWeight.w800),
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

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [status.softBackground, Colors.white],
          ),
          boxShadow: [
            BoxShadow(
              color: status.color.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: item.accent.withValues(alpha: 0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: HugeIcon(
                      icon: item.icon,
                      color: item.accent,
                      size: 21,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: status.pillBackground,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              status.label,
                              style: TextStyle(
                                color: status.color,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.categoryLabel,
                        style: TextStyle(
                          color: item.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedClock01,
                            color: AppColors.textSecondary,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            item.durationLabel,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedCalendar03,
                            color: AppColors.textSecondary,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _dateLabel,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFB0B7C3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
