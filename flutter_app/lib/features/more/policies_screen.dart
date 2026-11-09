import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme.dart';
import 'more_models.dart';
import 'more_providers.dart';
import 'more_widgets.dart';

const _tint = Color(0xFF8B5CF6);

class PoliciesScreen extends ConsumerStatefulWidget {
  const PoliciesScreen({super.key});

  @override
  ConsumerState<PoliciesScreen> createState() => _PoliciesScreenState();
}

class _PoliciesScreenState extends ConsumerState<PoliciesScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(policiesProvider);

    return MorePage(
      title: 'Company Policies',
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(policiesProvider);
          try {
            await ref.read(policiesProvider.future);
          } catch (_) {}
        },
        child: AsyncView<List<PolicyItem>>(
          value: async,
          onRetry: () => ref.invalidate(policiesProvider),
          builder: (items) {
            if (items.isEmpty) {
              return const CenteredScroll(
                child: EmptyPanel(
                  icon: HugeIcons.strokeRoundedShield01,
                  title: 'No policies published',
                  message: 'Company policies shared with you will appear here.',
                  color: _tint,
                ),
              );
            }
            final query = _query.trim().toLowerCase();
            final visible = query.isEmpty
                ? items
                : items
                      .where(
                        (p) =>
                            p.title.toLowerCase().contains(query) ||
                            p.body.toLowerCase().contains(query),
                      )
                      .toList();
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              itemCount: visible.length + 1 + (visible.isEmpty ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search policies',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                      ),
                    ),
                  );
                }
                if (visible.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: EmptyPanel(
                      icon: HugeIcons.strokeRoundedSearch01,
                      title: 'No matches',
                      message: 'Try a different search term.',
                      color: _tint,
                    ),
                  );
                }
                final item = visible[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PolicyTile(item: item),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _PolicyTile extends StatelessWidget {
  const _PolicyTile({required this.item});

  final PolicyItem item;

  @override
  Widget build(BuildContext context) {
    final preview = item.body.replaceAll(RegExp(r'\s+'), ' ');
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: cardDecoration(),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PolicyDetailScreen(item: item),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GradientIconTile(
                  icon: HugeIcons.strokeRoundedShield01,
                  color: _tint,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PolicyDetailScreen extends StatelessWidget {
  const PolicyDetailScreen({super.key, required this.item});

  final PolicyItem item;

  @override
  Widget build(BuildContext context) {
    return MorePage(
      title: 'Policy',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          SectionCard(
            children: [
              Row(
                children: [
                  GradientIconTile(
                    icon: HugeIcons.strokeRoundedShield01,
                    color: _tint,
                    size: 50,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                item.body.isEmpty
                    ? 'This policy has no description.'
                    : item.body,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
