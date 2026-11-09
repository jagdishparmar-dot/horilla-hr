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

  LeaveBalance? get _permissionBalance {
    final balances = ref
        .watch(leaveBalancesProvider)
        .maybeWhen(data: (v) => v, orElse: () => const <LeaveBalance>[]);
    for (final b in balances) {
      if (b.kind == BalanceKind.permission) return b;
    }
    return null;
  }

  bool get _canSubmit =>
      !_submitting &&
      _permissionBalance != null &&
      _date != null &&
      _durationMinutes > 0;

  int get _durationMinutes {
    final diff = _toMinutes - _fromMinutes;
    return diff > 0 ? diff : 0;
  }

  String? get _balanceLabel {
    final balance = _permissionBalance;
    if (balance == null) return null;
    return 'Available balance: ${balance.availableLabel}';
  }

  String get _dayUseLabel {
    if (_durationMinutes <= 4 * 60) {
      return 'Uses a half day of permission leave.';
    }
    return 'Uses a full day of permission leave.';
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

  String _clock(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _submit() async {
    final type = _permissionBalance;
    if (!_canSubmit || type == null || _date == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    final window = '${_clock(_fromMinutes)}–${_clock(_toMinutes)}';
    final note = _reasonController.text.trim();
    final description = note.isEmpty
        ? 'Permission $window'
        : 'Permission $window. $note';
    final halfDay = _durationMinutes <= 4 * 60;
    final breakdown = !halfDay
        ? 'full_day'
        : _fromMinutes < 12 * 60
        ? 'first_half'
        : 'second_half';
    try {
      await ref
          .read(requestsRepositoryProvider)
          .createLeaveRequest(
            leaveTypeId: type.leaveTypeId,
            startDate: _date!,
            endDate: _date!,
            description: description,
            startBreakdown: breakdown,
            endBreakdown: breakdown,
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
                const SizedBox(height: 8),
                if (ref.watch(leaveBalancesProvider).isLoading)
                  const Text(
                    'Loading leave balances…',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  )
                else if (_permissionBalance == null)
                  const Text(
                    'No Permission leave type is assigned. Ask HR to add one before filing this request.',
                    style: TextStyle(
                      color: AppColors.red,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  )
                else ...[
                  Text(
                    _balanceLabel!,
                    style: const TextStyle(
                      color: AppColors.green,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  if (_date != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _dayUseLabel,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
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
