import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/theme.dart';
import 'more_models.dart';
import 'more_providers.dart';
import 'more_repository.dart';
import 'more_widgets.dart';

const _tint = Color(0xFF0F766E);

class ContractScreen extends ConsumerWidget {
  const ContractScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(contractsProvider);

    return MorePage(
      title: 'Pay',
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(contractsProvider);
          try {
            await ref.read(contractsProvider.future);
          } catch (_) {}
        },
        child: AsyncView<List<ContractItem>>(
          value: async,
          onRetry: () => ref.invalidate(contractsProvider),
          builder: (items) {
            if (items.isEmpty) {
              return const CenteredScroll(
                child: EmptyPanel(
                  icon: HugeIcons.strokeRoundedContracts,
                  title: 'No pay details yet',
                  message: 'Your salary details will appear here once HR adds them.',
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
                return _ContractTile(
                  item: item,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ContractDetailScreen(item: item),
                      ),
                    );
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

class _ContractTile extends StatelessWidget {
  const _ContractTile({required this.item, required this.onTap});

  final ContractItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: cardDecoration(radius: 18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const GradientIconTile(
                  icon: HugeIcons.strokeRoundedContracts,
                  color: _tint,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.payLabel,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Pill(text: item.statusLabel, color: _tint),
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

class ContractDetailScreen extends ConsumerStatefulWidget {
  const ContractDetailScreen({super.key, required this.item});

  final ContractItem item;

  @override
  ConsumerState<ContractDetailScreen> createState() =>
      _ContractDetailScreenState();
}

class _ContractDetailScreenState extends ConsumerState<ContractDetailScreen> {
  bool _opening = false;

  Future<void> _openFile() async {
    setState(() => _opening = true);
    try {
      final path = await ref
          .read(moreRepositoryProvider)
          .downloadContractFile(widget.item);
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
    final item = widget.item;
    return MorePage(
      title: 'Pay',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          SectionCard(
            children: [
              Text(
                item.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: AppColors.textPrimary,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              Pill(text: item.statusLabel, color: _tint),
              const SizedBox(height: 14),
              Text(
                item.payLabel,
                style: const TextStyle(
                  color: _tint,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.dateLabel,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Role',
            children: [
              InfoRow(
                icon: HugeIcons.strokeRoundedBuilding03,
                label: 'Department',
                value: item.department,
                color: _tint,
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedBriefcase01,
                label: 'Position',
                value: item.jobPosition,
                color: _tint,
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedUser,
                label: 'Role',
                value: item.jobRole,
                color: _tint,
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedClock01,
                label: 'Shift',
                value: item.shift,
                color: _tint,
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedWork,
                label: 'Work type',
                value: item.workType,
                color: _tint,
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedCalendar03,
                label: 'Pay frequency',
                value: item.frequencyLabel,
                color: _tint,
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedMoney03,
                label: 'Monthly CTC',
                value: item.ctcLabel,
                color: _tint,
              ),
              InfoRow(
                icon: HugeIcons.strokeRoundedAlert02,
                label: 'Notice period',
                value: item.noticeLabel,
                color: _tint,
                last: true,
              ),
            ],
          ),
          if (item.note != null) ...[
            const SizedBox(height: 14),
            SectionCard(
              title: 'Note',
              children: [
                Text(
                  item.note!,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ],
          if (item.documentUrl != null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _opening ? null : _openFile,
              icon: _opening
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.attach_file_rounded),
              label: Text(_opening ? 'Opening file…' : 'Open pay file'),
            ),
          ],
        ],
      ),
    );
  }
}
