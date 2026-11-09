import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import 'models.dart';
import 'request_form_widgets.dart';
import 'requests_provider.dart';

class PermissionRequestScreen extends ConsumerStatefulWidget {
  const PermissionRequestScreen({super.key});

  @override
  ConsumerState<PermissionRequestScreen> createState() =>
      _PermissionRequestScreenState();
}

class _PermissionRequestScreenState
    extends ConsumerState<PermissionRequestScreen> {
  static const _maxReason = 150;

  DateTime? _date;
  int _fromMinutes = 9 * 60;
  int _toMinutes = 10 * 60;
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

  LeaveBalance? get _permissionBalance {
    final balances = ref.watch(leaveBalancesProvider).maybeWhen(
          data: (v) => v,
          orElse: () => const <LeaveBalance>[],
        );
    for (final b in balances) {
      if (b.kind == BalanceKind.permission) return b;
    }
    return balances.isNotEmpty ? balances.first : null;
  }

  bool get _canSubmit => _date != null && _durationMinutes > 0;

  int get _durationMinutes {
    final diff = _toMinutes - _fromMinutes;
    return diff > 0 ? diff : 0;
  }

  String get _remainingBalanceLabel {
    final balance = _permissionBalance;
    final availableHours = (balance?.available ?? 2).toDouble();
    final availableMins = (availableHours * 60).round();
    final remaining = (availableMins - _durationMinutes).clamp(0, availableMins);
    final h = remaining ~/ 60;
    final m = remaining % 60;
    return 'Remaining Balance: ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} hrs';
  }

  Future<void> _pickDate() async {
    final picked = await showRequestCalendarPicker(
      context,
      initialDate: _date ?? DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool isFrom}) async {
    final picked = await showRequestTimePicker(
      context,
      initialMinutes: isFrom ? _fromMinutes : _toMinutes,
      title: isFrom ? 'From time' : 'To time',
      use24Hour: false,
      minuteInterval: 5,
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromMinutes = picked;
        if (_toMinutes <= _fromMinutes) {
          _toMinutes = (_fromMinutes + 60).clamp(0, 24 * 60 - 1);
        }
      } else {
        _toMinutes = picked;
        if (_toMinutes <= _fromMinutes) {
          _fromMinutes = (_toMinutes - 60).clamp(0, 24 * 60 - 1);
        }
      }
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    await showRequestSuccessDialog(context);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
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
          'Permission',
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
                  'Date',
                  style: TextStyle(
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
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _date == null
                                  ? 'DD-Mon-YY'
                                  : DateFormat('dd-MMM-yy').format(_date!),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _date == null
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
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: RequestTimeField(
                        label: 'From',
                        minutes: _fromMinutes,
                        onTap: () => _pickTime(isFrom: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RequestTimeField(
                        label: 'To',
                        minutes: _toMinutes,
                        onTap: () => _pickTime(isFrom: false),
                      ),
                    ),
                  ],
                ),
                if (_date != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _remainingBalanceLabel,
                    style: const TextStyle(
                      color: AppColors.green,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
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
                          hintText: 'e.g. Family emergency, Traveling.',
                          hintStyle: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontWeight: FontWeight.w500,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.fromLTRB(14, 12, 14, 4),
                          counterText: '',
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 12, bottom: 10),
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
            canSubmit: _canSubmit,
            onCancel: () => Navigator.of(context).pop(),
            onSubmit: _submit,
          ),
        ],
      ),
    );
  }
}
