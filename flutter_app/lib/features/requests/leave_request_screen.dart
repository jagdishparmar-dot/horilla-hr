import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../home/home_provider.dart';
import 'models.dart';
import 'request_form_widgets.dart';
import 'requests_provider.dart';
import 'requests_repository.dart';

class LeaveRequestScreen extends ConsumerStatefulWidget {
  const LeaveRequestScreen({super.key});

  @override
  ConsumerState<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends ConsumerState<LeaveRequestScreen> {
  static const _maxReason = 150;

  LeaveBalance? _selectedType;
  DateTime? _from;
  DateTime? _to;
  bool _submitting = false;
  final _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reasonController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  List<LeaveBalance> _leaveTypesFrom(List<LeaveBalance> balances) {
    final preferred = balances
        .where(
          (b) =>
              b.kind == BalanceKind.annual ||
              b.kind == BalanceKind.casual ||
              b.kind == BalanceKind.other,
        )
        .toList();
    return preferred.isNotEmpty ? preferred : balances;
  }

  bool get _canSubmit =>
      !_submitting &&
      _selectedType != null &&
      _from != null &&
      _to != null;

  String get _balanceLabel {
    final type = _selectedType;
    if (type == null) return '';
    return 'Available Balance: ${type.availableLabel}';
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = isFrom
        ? (_from ?? now)
        : (_to ?? _from ?? now);
    final picked = await showRequestCalendarPicker(
      context,
      initialDate: initial,
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to != null && _to!.isBefore(picked)) {
          _to = picked;
        }
      } else {
        if (_from != null && picked.isBefore(_from!)) {
          _to = _from;
        } else {
          _to = picked;
        }
      }
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      await ref.read(requestsRepositoryProvider).createLeaveRequest(
            leaveTypeId: _selectedType!.leaveTypeId,
            startDate: _from!,
            endDate: _to!,
            description: _reasonController.text.trim().isEmpty
                ? 'Leave request'
                : _reasonController.text.trim(),
          );
      invalidateRequests(ref);
      ref.invalidate(mobileHomeProvider);
      if (!mounted) return;
      await showRequestSuccessDialog(context);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final balancesAsync = ref.watch(leaveBalancesProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.scaffold,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        ),
        title: const Text(
          'Leave Request',
          style: TextStyle(
            color: AppColors.navBlue,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      body: balancesAsync.when(
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
                  onPressed: () => ref.invalidate(leaveBalancesProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (balances) {
          final types = _leaveTypesFrom(balances);
          if (_selectedType == null && types.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _selectedType == null) {
                setState(() => _selectedType = types.first);
              }
            });
          }
          final selected = _selectedType != null &&
                  types.any((t) => t.id == _selectedType!.id)
              ? types.firstWhere((t) => t.id == _selectedType!.id)
              : null;

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  children: [
                    const Text(
                      'Leave Type',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<LeaveBalance>(
                          value: selected,
                          isExpanded: true,
                          hint: const Text('Select leave type'),
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: AppColors.textSecondary,
                          ),
                          items: [
                            for (final type in types)
                              DropdownMenuItem(
                                value: type,
                                child: Text(
                                  type.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _selectedType = value),
                        ),
                      ),
                    ),
                    if (_selectedType != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _balanceLabel,
                        style: const TextStyle(
                          color: AppColors.green,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _DateField(
                            label: 'Date (from)',
                            value: _from,
                            onTap: () => _pickDate(isFrom: true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DateField(
                            label: 'Date (to)',
                            value: _to,
                            onTap: () => _pickDate(isFrom: false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Reason (Optional)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          TextField(
                            controller: _reasonController,
                            maxLength: _maxReason,
                            maxLines: 4,
                            minLines: 3,
                            decoration: const InputDecoration(
                              hintText: 'Traveling for family wedding.',
                              hintStyle: TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontWeight: FontWeight.w500,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding:
                                  EdgeInsets.fromLTRB(14, 12, 14, 4),
                              counterText: '',
                            ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.only(right: 12, bottom: 10),
                            child: Text(
                              '${_reasonController.text.length}/$_maxReason',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              RequestFormFooter(
                canSubmit: _canSubmit && types.isNotEmpty,
                onCancel: () => Navigator.of(context).pop(),
                onSubmit: _submit,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? 'Select'
        : DateFormat('dd-MMM-yy').format(value!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: value == null
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedCalendar03,
                    color: AppColors.navBlue,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
