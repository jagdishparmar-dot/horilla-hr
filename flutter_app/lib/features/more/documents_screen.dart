import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/theme.dart';
import 'documents_models.dart';
import 'documents_repository.dart';
import 'more_widgets.dart';

const _tint = Color(0xFF0EA5E9);

/// The employee's own documents: what HR requested, what is under review,
/// and a way to upload or replace a file.
class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(documentsProvider);

    return MorePage(
      title: 'Documents',
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(documentsProvider);
          try {
            await ref.read(documentsProvider.future);
          } catch (_) {}
        },
        child: AsyncView<List<DocumentEntry>>(
          value: async,
          onRetry: () => ref.invalidate(documentsProvider),
          builder: (entries) {
            if (entries.isEmpty) {
              return const CenteredScroll(
                child: EmptyPanel(
                  icon: HugeIcons.strokeRoundedFolder01,
                  title: 'No documents yet',
                  message: 'When HR asks you for a document, or adds one to your record, it will appear here.',
                  color: _tint,
                ),
              );
            }
            final waiting = entries.where((e) => e.document.canUpload).length;
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              itemCount: entries.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _Summary(total: entries.length, waiting: waiting);
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DocumentCard(entry: entries[index - 1]),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.total, required this.waiting});

  final int total;
  final int waiting;

  @override
  Widget build(BuildContext context) {
    final text = waiting == 0
        ? 'Everything is up to date.'
        : waiting == 1
        ? '1 document needs your attention.'
        : '$waiting documents need your attention.';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: heroGradient,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedFolder01,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    total == 1 ? '1 document' : '$total documents',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    text,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentCard extends ConsumerStatefulWidget {
  const _DocumentCard({required this.entry});

  final DocumentEntry entry;

  @override
  ConsumerState<_DocumentCard> createState() => _DocumentCardState();
}

class _DocumentCardState extends ConsumerState<_DocumentCard> {
  bool _uploading = false;
  bool _opening = false;

  DocumentItem get _doc => widget.entry.document;
  DocumentRequirement? get _rule => widget.entry.requirement;

  Future<void> _upload() async {
    final rule = _rule;
    final XFile? file;
    final int size;
    try {
      final extensions = rule?.allowedExtensions;
      file = await openFile(
        acceptedTypeGroups: [
          if (extensions != null)
            XTypeGroup(
              label: rule!.format.toUpperCase(),
              extensions: extensions,
            ),
        ],
      );
      size = file == null ? 0 : await file.length();
    } catch (_) {
      if (mounted) showSnack(context, "Couldn't open the file picker.");
      return;
    }
    if (file == null || !mounted) return;

    final problem = validateUpload(
      fileName: file.name,
      sizeBytes: size,
      requirement: rule,
    );
    if (problem != null) {
      showSnack(context, problem);
      return;
    }

    setState(() => _uploading = true);
    try {
      await ref.read(documentsRepositoryProvider).upload(_doc, file);
      ref.invalidate(documentsProvider);
      if (mounted) showSnack(context, 'Uploaded. HR will review it shortly.');
    } catch (e) {
      if (mounted) showSnack(context, cleanError(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _view() async {
    setState(() => _opening = true);
    try {
      final path = await ref.read(documentsRepositoryProvider).download(_doc);
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done && mounted) {
        showSnack(
          context,
          result.type == ResultType.noAppToOpen
              ? 'No app on this device can open this file.'
              : "Couldn't open the file.",
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, cleanError(e));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final rule = _rule;
    final color = doc.stateColor;
    final description = rule?.description;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GradientIconTile(
                icon: doc.hasFile
                    ? HugeIcons.strokeRoundedFile01
                    : HugeIcons.strokeRoundedFileUpload,
                color: color,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Pill(text: doc.stateLabel, color: color),
                        if (doc.isExpired)
                          const Pill(text: 'Expired', color: Color(0xFFEF4444)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 10),
            Text(
              description,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          if (doc.state == DocumentState.rejected &&
              doc.rejectReason != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Reason: ${doc.rejectReason}',
                style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
          if (rule != null && doc.canUpload) ...[
            const SizedBox(height: 8),
            Text(
              'Accepted: ${rule.ruleLabel}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
          if (doc.issueDate != null || doc.expiryDate != null) ...[
            const SizedBox(height: 8),
            Text(
              [
                if (doc.issueDate != null) 'Issued ${shortDate(doc.issueDate)}',
                if (doc.expiryDate != null)
                  'Expires ${shortDate(doc.expiryDate)}',
              ].join('  ·  '),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
          if (doc.hasFile || doc.canUpload) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (doc.hasFile)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _opening || _uploading ? null : _view,
                      icon: _opening
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('View'),
                    ),
                  ),
                if (doc.hasFile && doc.canUpload) const SizedBox(width: 10),
                if (doc.canUpload)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _uploading || _opening ? null : _upload,
                      icon: _uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.upload_file_rounded, size: 18),
                      label: Text(doc.hasFile ? 'Upload again' : 'Upload'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
