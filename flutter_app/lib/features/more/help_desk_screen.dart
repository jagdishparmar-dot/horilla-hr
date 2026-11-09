import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../home/home_provider.dart';
import 'more_models.dart';
import 'more_providers.dart';
import 'more_repository.dart';
import 'more_widgets.dart';

const _tint = Color(0xFF16A34A);

class HelpDeskScreen extends ConsumerWidget {
  const HelpDeskScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: MorePage(
        title: 'Help Desk',
        bottom: const TabBar(
          labelColor: AppColors.navBlue,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.navBlue,
          dividerColor: Colors.transparent,
          labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          tabs: [
            Tab(text: 'My tickets'),
            Tab(text: 'FAQs'),
          ],
        ),
        floatingActionButton: _NewTicketFab(
          onPressed: () async {
            final created = await Navigator.of(context).push<bool>(
              MaterialPageRoute<bool>(builder: (_) => const NewTicketScreen()),
            );
            if (created == true && context.mounted) {
              showSnack(context, 'Ticket submitted');
            }
          },
        ),
        body: const TabBarView(children: [_TicketsTab(), _FaqTab()]),
      ),
    );
  }
}

class _NewTicketFab extends StatelessWidget {
  const _NewTicketFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: heroGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6D5CFF).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'New ticket',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
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

// ---------------------------------------------------------------------------
// Tickets
// ---------------------------------------------------------------------------

class _TicketsTab extends ConsumerWidget {
  const _TicketsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ticketsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(ticketsProvider);
        try {
          await ref.read(ticketsProvider.future);
        } catch (_) {}
      },
      child: AsyncView<List<TicketItem>>(
        value: async,
        onRetry: () => ref.invalidate(ticketsProvider),
        builder: (items) {
          if (items.isEmpty) {
            return const CenteredScroll(
              child: EmptyPanel(
                icon: HugeIcons.strokeRoundedCustomerService01,
                title: 'No tickets yet',
                message: 'Need help from HR or another team? Raise a ticket and track it here.',
                color: _tint,
              ),
            );
          }
          final open = items.where((t) => t.status.isOpen).length;
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: items.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    open == 0
                        ? 'All caught up — no open tickets'
                        : '$open open ticket${open == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TicketCard(item: items[index - 1]),
              );
            },
          );
        },
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.item});

  final TicketItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.status.color;
    final created = item.createdAt;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.10), Colors.white],
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TicketDetailScreen(item: item),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item.code,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Pill(text: item.status.label, color: color),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.description,
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
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Pill(text: item.typeTitle, color: AppColors.navBlue),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: item.priorityColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${item.priorityLabel} priority',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                    if (created != null)
                      Text(
                        DateFormat('d MMM').format(created),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ticket detail
// ---------------------------------------------------------------------------

class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({super.key, required this.item});

  final TicketItem item;

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(moreRepositoryProvider).addComment(widget.item.id, text);
      _controller.clear();
      ref.invalidate(ticketCommentsProvider(widget.item.id));
      FocusManager.instance.primaryFocus?.unfocus();
    } catch (e) {
      if (mounted) showSnack(context, cleanError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final color = item.status.color;
    final commentsAsync = ref.watch(ticketCommentsProvider(item.id));
    final fmt = DateFormat('d MMM yyyy');

    return MorePage(
      title: item.code,
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(ticketCommentsProvider(item.id));
                try {
                  await ref.read(ticketCommentsProvider(item.id).future);
                } catch (_) {}
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  SectionCard(
                    children: [
                      Row(
                        children: [
                          Pill(text: item.status.label, color: color),
                          const SizedBox(width: 8),
                          Pill(
                            text: '${item.priorityLabel} priority',
                            color: item.priorityColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (item.description.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          item.description,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      InfoRow(
                        icon: HugeIcons.strokeRoundedTag01,
                        label: 'Type',
                        value: item.typeTitle,
                      ),
                      InfoRow(
                        icon: HugeIcons.strokeRoundedSent,
                        label: 'Forwarded to',
                        value: item.forwardedTo,
                        color: const Color(0xFF8B5CF6),
                      ),
                      InfoRow(
                        icon: HugeIcons.strokeRoundedUserCheck01,
                        label: 'Assigned to',
                        value: item.assignees.isEmpty
                            ? null
                            : item.assignees.join(', '),
                        color: const Color(0xFF22B8E8),
                      ),
                      InfoRow(
                        icon: HugeIcons.strokeRoundedCalendar03,
                        label: 'Raised on',
                        value: item.createdAt == null
                            ? null
                            : fmt.format(item.createdAt!),
                        color: const Color(0xFFF59E0B),
                      ),
                      InfoRow(
                        icon: HugeIcons.strokeRoundedAlarmClock,
                        label: 'Deadline',
                        value: item.deadline == null
                            ? null
                            : fmt.format(item.deadline!),
                        color: const Color(0xFFEF4444),
                      ),
                      InfoRow(
                        icon: HugeIcons.strokeRoundedCheckmarkCircle02,
                        label: 'Resolved on',
                        value: item.resolvedAt == null
                            ? null
                            : fmt.format(item.resolvedAt!),
                        color: _tint,
                        last: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
                    child: Text(
                      'Conversation',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  commentsAsync.when(
                    skipLoadingOnReload: true,
                    loading: () => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => SectionCard(
                      children: [
                        ErrorPanel(
                          message: cleanError(e),
                          onRetry: () =>
                              ref.invalidate(ticketCommentsProvider(item.id)),
                        ),
                      ],
                    ),
                    data: (comments) => comments.isEmpty
                        ? const SectionCard(
                            children: [
                              Text(
                                'No replies yet. Add a comment below to follow up.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              for (final c in comments)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _CommentBubble(comment: c),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
          if (item.status.isOpen)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Write a reply…',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.navBlue,
                        foregroundColor: Colors.white,
                      ),
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 20),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CommentBubble extends ConsumerWidget {
  const _CommentBubble({required this.comment});

  final TicketComment comment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(mobileHomeProvider).asData?.value.employeeId;
    final mine = myId != null && myId == comment.authorId;
    final date = comment.date;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: mine
                ? AppColors.navBlue.withValues(alpha: 0.10)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mine ? 'You' : comment.author,
                style: TextStyle(
                  color: mine ? AppColors.navBlue : const Color(0xFF8B5CF6),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                comment.text,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              if (date != null) ...[
                const SizedBox(height: 4),
                Text(
                  DateFormat('d MMM · h:mm a').format(date),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// New ticket
// ---------------------------------------------------------------------------

class NewTicketScreen extends ConsumerStatefulWidget {
  const NewTicketScreen({super.key});

  @override
  ConsumerState<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends ConsumerState<NewTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  int? _typeId;
  int? _departmentId;
  String _priority = 'low';
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(moreRepositoryProvider)
          .createTicket(
            title: _title.text.trim(),
            description: _description.text.trim(),
            ticketTypeId: _typeId!,
            departmentId: _departmentId!,
            priority: _priority,
          );
      ref.invalidate(ticketsProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, cleanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final typesAsync = ref.watch(ticketTypesProvider);
    final departmentsAsync = ref.watch(ticketDepartmentsProvider);

    return MorePage(
      title: 'New Ticket',
      body: AsyncView<List<TicketTypeItem>>(
        value: typesAsync,
        onRetry: () => ref.invalidate(ticketTypesProvider),
        builder: (types) => AsyncView<List<TicketDepartment>>(
          value: departmentsAsync,
          onRetry: () => ref.invalidate(ticketDepartmentsProvider),
          builder: (departments) {
            if (types.isEmpty || departments.isEmpty) {
              return const CenteredScroll(
                child: EmptyPanel(
                  icon: HugeIcons.strokeRoundedCustomerService01,
                  title: 'Help desk not set up',
                  message: 'HR has not configured ticket types or teams yet, so tickets cannot be raised from the app.',
                  color: _tint,
                ),
              );
            }
            return _form(types, departments);
          },
        ),
      ),
    );
  }

  Widget _form(List<TicketTypeItem> types, List<TicketDepartment> departments) {
    return Column(
      children: [
        Expanded(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                const Text(
                  'Describe what you need and pick the team that should handle it.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  children: [
                    const _FieldLabel('Type'),
                    DropdownButtonFormField<int>(
                      initialValue: _typeId,
                      isExpanded: true,
                      hint: const Text('Select a type'),
                      validator: (v) =>
                          v == null ? 'Choose a ticket type' : null,
                      items: [
                        for (final t in types)
                          DropdownMenuItem(value: t.id, child: Text(t.title)),
                      ],
                      onChanged: (v) => setState(() => _typeId = v),
                    ),
                    const SizedBox(height: 14),
                    const _FieldLabel('Send to'),
                    DropdownButtonFormField<int>(
                      initialValue: _departmentId,
                      isExpanded: true,
                      hint: const Text('Select a team'),
                      validator: (v) =>
                          v == null ? 'Choose who should handle this' : null,
                      items: [
                        for (final d in departments)
                          DropdownMenuItem(
                            value: d.id,
                            child: Text(
                              d.managerName == null
                                  ? d.name
                                  : '${d.name} · ${d.managerName}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _departmentId = v),
                    ),
                    const SizedBox(height: 14),
                    const _FieldLabel('Priority'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final p in const ['low', 'medium', 'high'])
                          ChoiceChip(
                            label: Text(humanize(p)),
                            selected: _priority == p,
                            onSelected: (_) => setState(() => _priority = p),
                            selectedColor: switch (p) {
                              'high' => const Color(0xFFEF4444),
                              'medium' => const Color(0xFFF59E0B),
                              _ => const Color(0xFF22B8E8),
                            }.withValues(alpha: 0.2),
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _priority == p
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _FieldLabel('Title'),
                    TextFormField(
                      controller: _title,
                      maxLength: 50,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Short summary',
                      ),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Enter a title' : null,
                    ),
                    const SizedBox(height: 6),
                    const _FieldLabel('Description'),
                    TextFormField(
                      controller: _description,
                      maxLength: 255,
                      minLines: 4,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Tell us what is going on…',
                      ),
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Describe the issue'
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Submit ticket',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// FAQs
// ---------------------------------------------------------------------------

class _FaqTab extends ConsumerWidget {
  const _FaqTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(faqsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(faqsProvider);
        try {
          await ref.read(faqsProvider.future);
        } catch (_) {}
      },
      child: AsyncView<List<FaqItem>>(
        value: async,
        onRetry: () => ref.invalidate(faqsProvider),
        builder: (items) {
          if (items.isEmpty) {
            return const CenteredScroll(
              child: EmptyPanel(
                icon: HugeIcons.strokeRoundedHelpCircle,
                title: 'No FAQs yet',
                message: 'Answers to common questions will appear here.',
                color: Color(0xFFF59E0B),
              ),
            );
          }
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: items.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _FaqTile(item: items[index]),
            ),
          );
        },
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.item});

  final FaqItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Text(
            item.question,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: item.category == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    item.category!,
                    style: const TextStyle(
                      color: Color(0xFFF59E0B),
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ),
          children: [
            Text(
              item.answer,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
