import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../more/more_models.dart';
import '../more/more_widgets.dart';
import 'announcement_models.dart';
import 'announcements_repository.dart';

const _tint = Color(0xFF2F6BFF);

class AnnouncementsScreen extends ConsumerWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(announcementsProvider);

    return MorePage(
      title: 'Announcements',
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(announcementsProvider);
          try {
            await ref.read(announcementsProvider.future);
          } catch (_) {}
        },
        child: AsyncView<List<AnnouncementItem>>(
          value: async,
          onRetry: () => ref.invalidate(announcementsProvider),
          builder: (items) {
            if (items.isEmpty) {
              return const CenteredScroll(
                child: EmptyPanel(
                  icon: HugeIcons.strokeRoundedMegaphone01,
                  title: 'No announcements',
                  message: 'Announcements shared with you will appear here.',
                  color: _tint,
                ),
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = items[index];
                return _AnnouncementTile(
                  item: item,
                  onTap: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => AnnouncementDetailScreen(item: item),
                      ),
                    );
                    ref.invalidate(announcementsProvider);
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _AnnouncementTile extends StatelessWidget {
  const _AnnouncementTile({required this.item, required this.onTap});

  final AnnouncementItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final created = item.createdAt == null
        ? null
        : DateFormat('MMM d, yyyy').format(item.createdAt!.toLocal());
    final preview = item.previewText.replaceAll('\n', ' ');

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: cardDecoration(radius: 16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const GradientIconTile(
                  icon: HugeIcons.strokeRoundedMegaphone01,
                  color: _tint,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (!item.hasViewed) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(top: 6),
                              decoration: const BoxDecoration(
                                color: _tint,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (created != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          created,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
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

class AnnouncementDetailScreen extends ConsumerWidget {
  const AnnouncementDetailScreen({super.key, required this.item});

  /// List row, shown immediately while the detail request loads.
  final AnnouncementItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(announcementDetailProvider(item.id));
    final detail = async.asData?.value ?? item;

    return MorePage(
      title: 'Announcement',
      body: async.hasError && async.asData == null
          ? AsyncView<AnnouncementItem>(
              value: async,
              onRetry: () =>
                  ref.invalidate(announcementDetailProvider(item.id)),
              builder: (_) => const SizedBox.shrink(),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                SectionCard(
                  children: [
                    Text(
                      detail.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: AppColors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                    if (detail.author != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        detail.author!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    if (detail.createdAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM d, yyyy · h:mm a')
                            .format(detail.createdAt!.toLocal()),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (detail.expireDate != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Expires ${DateFormat('MMM d, yyyy').format(detail.expireDate!)}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (detail.content.isEmpty)
                      const Text(
                        'No additional details.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                          height: 1.45,
                        ),
                      )
                    else
                      for (final block in detail.content) ...[
                        _BlockText(block: block),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
                if (detail.attachments.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Attachments',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final file in detail.attachments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.transparent,
                        child: Ink(
                          decoration: cardDecoration(radius: 14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              final url = resolveMediaUrl(file.url);
                              if (url == null) return;
                              openExternal(context, Uri.parse(url));
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Icon(
                                    file.isImage
                                        ? Icons.image_outlined
                                        : Icons.attach_file_rounded,
                                    color: _tint,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      file.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

class _BlockText extends StatelessWidget {
  const _BlockText({required this.block});

  final AnnouncementBlock block;

  @override
  Widget build(BuildContext context) {
    final heading = block.type == 'heading';
    final bullet = block.type == 'bullet';
    return Text(
      bullet ? '• ${block.text}' : block.text,
      style: TextStyle(
        color: AppColors.textPrimary,
        fontSize: heading ? 16 : 15,
        height: 1.45,
        fontWeight: heading ? FontWeight.w800 : FontWeight.w500,
      ),
    );
  }
}
