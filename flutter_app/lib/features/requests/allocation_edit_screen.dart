import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/dio_client.dart';
import '../../core/theme.dart';
import 'models.dart';
import 'request_form_widgets.dart';
import 'requests_provider.dart';

class AllocationEditScreen extends ConsumerStatefulWidget {
  const AllocationEditScreen({super.key, required this.item});

  final LeaveRequestItem item;

  @override
  ConsumerState<AllocationEditScreen> createState() =>
      _AllocationEditScreenState();
}

class _AllocationChoice {
  const _AllocationChoice({required this.id, required this.name});

  final int id;
  final String name;
}

class _AllocationEditScreenState extends ConsumerState<AllocationEditScreen> {
  late final TextEditingController _days;
  late final TextEditingController _description;
  late int? _leaveTypeId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final days = widget.item.requestedDays;
    _days = TextEditingController(
      text: days % 1 == 0 ? days.toInt().toString() : days.toString(),
    );
    _description = TextEditingController(text: widget.item.reason ?? '');
    _leaveTypeId = widget.item.leaveTypeId;
    _days.addListener(() => setState(() {}));
    _description.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _days.dispose();
    _description.dispose();
    super.dispose();
  }

  double? get _parsedDays => double.tryParse(_days.text.trim());

  bool get _canSave {
    final days = _parsedDays;
    return !_saving &&
        _leaveTypeId != null &&
        days != null &&
        days > 0 &&
        _description.text.trim().isNotEmpty;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await ref.read(allocationEditorProvider)(
        id: widget.item.id,
        leaveTypeId: _leaveTypeId!,
        days: _parsedDays!,
        description: _description.text.trim(),
      );
      invalidateRequests(ref);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(userFacingError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final balances = ref.watch(leaveBalancesProvider).asData?.value ?? const [];
    final choices = <_AllocationChoice>[
      if (widget.item.leaveTypeId != null)
        _AllocationChoice(
          id: widget.item.leaveTypeId!,
          name: widget.item.title,
        ),
      for (final balance in balances)
        if (balance.leaveTypeId != widget.item.leaveTypeId)
          _AllocationChoice(id: balance.leaveTypeId, name: balance.name),
    ];
    final selected = choices.where((choice) => choice.id == _leaveTypeId);
    final value = selected.isEmpty ? null : selected.first.id;

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
          'Edit extra leave',
          style: TextStyle(
            color: AppColors.navBlue,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
                const Text(
                  'Leave type',
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
                    child: DropdownButton<int>(
                      value: value,
                      isExpanded: true,
                      items: [
                        for (final choice in choices)
                          DropdownMenuItem(
                            value: choice.id,
                            child: Text(
                              choice.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (id) => setState(() => _leaveTypeId = id),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Days',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('allocation-days'),
                  controller: _days,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    hintText: '1',
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Reason',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('allocation-description'),
                  controller: _description,
                  maxLines: 4,
                  minLines: 3,
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    hintText: 'Why these days are needed',
                  ),
                ),
              ],
            ),
          ),
          RequestFormFooter(
            canSubmit: _canSave && choices.isNotEmpty,
            onCancel: () => Navigator.of(context).pop(),
            onSubmit: _save,
          ),
        ],
      ),
    );
  }
}
