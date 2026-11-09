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

class ShiftRequestScreen extends ConsumerStatefulWidget {
  const ShiftRequestScreen({super.key});

  @override
  ConsumerState<ShiftRequestScreen> createState() => _ShiftRequestScreenState();
}

class _ShiftRequestScreenState extends ConsumerState<ShiftRequestScreen> {
  static const _maxReason = 150;

  DateTime? _from;
  DateTime? _to;
  LookupItem? _shift;
  List<LookupItem> _shifts = const [];
  bool _loading = true;
  bool _submitting = false;
  String? _loadError;
  final _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reasonController.addListener(() => setState(() {}));
    _loadShifts();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting &&
      !_loading &&
      _shift != null &&
      _from != null &&
      _to != null;

  Future<void> _loadShifts() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final shifts = await ref.read(requestsRepositoryProvider).fetchShifts();
      if (!mounted) return;
      setState(() {
        _shifts = shifts;
        _shift = shifts.isEmpty ? null : shifts.first;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = isFrom ? (_from ?? now) : (_to ?? _from ?? now);
    final picked = await showRequestCalendarPicker(
      context,
      initialDate: initial,
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to != null && _to!.isBefore(picked)) _to = picked;
      } else {
        _to = _from != null && picked.isBefore(_from!) ? _from : picked;
      }
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    final note = _reasonController.text.trim();
    try {
      await ref
          .read(requestsRepositoryProvider)
          .createShiftRequest(
            shiftId: _shift!.id,
            startDate: _from!,
            endDate: _to!,
            description: note.isEmpty ? 'Shift change request' : note,
          );
      invalidateRequests(ref);
      ref.invalidate(mobileHomeProvider);
      if (!mounted) return;
      await showRequestSuccessDialog(context);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _shift != null && _shifts.any((s) => s.id == _shift!.id)
        ? _shifts.firstWhere((s) => s.id == _shift!.id)
        : null;

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
          'Shift Change',
          style: TextStyle(
            color: AppColors.navBlue,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loadShifts,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    children: [
                      const Text(
                        'Shift',
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
                          child: DropdownButton<LookupItem>(
                            value: selected,
                            isExpanded: true,
                            hint: const Text('Select shift'),
                            items: [
                              for (final shift in _shifts)
                                DropdownMenuItem(
                                  value: shift,
                                  child: Text(
                                    shift.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _shift = value),
                          ),
                        ),
                      ),
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
                      TextField(
                        controller: _reasonController,
                        maxLength: _maxReason,
                        maxLines: 4,
                        minLines: 3,
                        decoration: InputDecoration(
                          hintText: 'e.g. Covering the evening shift.',
                          filled: true,
                          fillColor: Colors.white,
                          counterText:
                              '${_reasonController.text.length}/$_maxReason',
                        ),
                      ),
                    ],
                  ),
                ),
                RequestFormFooter(
                  canSubmit: _canSubmit,
                  onCancel: () => Navigator.of(context).pop(),
                  onSubmit: _submit,
                ),
              ],
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
                      value == null
                          ? 'DD-Mon-YY'
                          : DateFormat('dd-MMM-yy').format(value!),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: value == null
                            ? const Color(0xFF9CA3AF)
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
