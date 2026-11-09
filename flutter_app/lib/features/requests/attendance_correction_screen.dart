import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../attendance/attendance_provider.dart';
import '../attendance/attendance_repository.dart';
import '../home/home_provider.dart';
import 'request_form_widgets.dart';
import 'requests_provider.dart';

class AttendanceCorrectionScreen extends ConsumerStatefulWidget {
  const AttendanceCorrectionScreen({super.key});

  @override
  ConsumerState<AttendanceCorrectionScreen> createState() =>
      _AttendanceCorrectionScreenState();
}

class _AttendanceCorrectionScreenState
    extends ConsumerState<AttendanceCorrectionScreen> {
  static const _maxReason = 150;
  static const _dayMinutes = 24 * 60;

  DateTime? _date;
  int _fromMinutes = 9 * 60;
  int _toMinutes = 17 * 60;
  bool _submitting = false;
  bool _loadingDay = false;
  AttendanceRecord? _existing;
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

  bool get _canSubmit =>
      !_submitting &&
      !_loadingDay &&
      _date != null &&
      _toMinutes != _fromMinutes;

  String get _workedHourLabel {
    final mins = _workedMinutes;
    final h = (mins ~/ 60).toString().padLeft(2, '0');
    final m = (mins % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  int get _workedMinutes {
    var diff = _toMinutes - _fromMinutes;
    if (diff <= 0) diff += _dayMinutes;
    return diff;
  }

  bool get _isOvernight => _toMinutes <= _fromMinutes;

  String _format24(int totalMinutes) {
    final h24 = (totalMinutes ~/ 60) % 24;
    final m = totalMinutes % 60;
    return '${h24.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  int? _parseTimeToMinutes(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return (h * 60 + m).clamp(0, _dayMinutes - 1);
  }

  Future<void> _pickDate() async {
    final picked = await showRequestCalendarPicker(
      context,
      initialDate: _date ?? DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _date = DateTime(picked.year, picked.month, picked.day);
      _existing = null;
    });
    await _loadExistingForDate(_date!);
  }

  Future<void> _pickTime({required bool isCheckIn}) async {
    final picked = await showRequestTimePicker(
      context,
      initialMinutes: isCheckIn ? _fromMinutes : _toMinutes,
      title: isCheckIn ? 'Check-in time' : 'Check-out time',
      use24Hour: true,
      minuteInterval: 5,
    );
    if (picked == null) return;
    setState(() {
      if (isCheckIn) {
        _fromMinutes = picked;
      } else {
        _toMinutes = picked;
      }
    });
  }

  Future<void> _loadExistingForDate(DateTime date) async {
    setState(() => _loadingDay = true);
    try {
      final rows = await ref.read(attendanceRepositoryProvider).fetchMyAttendance(
            from: date,
            to: date,
          );
      AttendanceRecord? match;
      for (final row in rows.records) {
        if (row.date.year == date.year &&
            row.date.month == date.month &&
            row.date.day == date.day) {
          match = row;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _existing = match;
        if (match?.clockIn != null) {
          _fromMinutes = _parseTimeToMinutes(match!.clockIn) ?? _fromMinutes;
        }
        if (match?.clockOut != null) {
          _toMinutes = _parseTimeToMinutes(match!.clockOut) ?? _toMinutes;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _existing = null);
    } finally {
      if (mounted) setState(() => _loadingDay = false);
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit || _date == null) return;
    final home = ref.read(mobileHomeProvider).asData?.value;
    final employeeId = home?.employeeId;
    if (employeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Employee profile not loaded yet')),
      );
      return;
    }

    final shiftId = _existing?.shiftId ?? home?.shiftId;
    final workTypeId = _existing?.workTypeId ?? home?.workTypeId;
    if (shiftId == null || workTypeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Shift / work type is not assigned on your profile. Ask HR to set it.',
          ),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);

    final clockIn = _format24(_fromMinutes);
    final clockOut = _format24(_toMinutes);
    final outDate =
        _isOvernight ? _date!.add(const Duration(days: 1)) : _date!;
    final minimumHour = (_existing?.minimumHour?.trim().isNotEmpty == true)
        ? _existing!.minimumHour!
        : '08:00';
    final description = _reasonController.text.trim().isEmpty
        ? 'Attendance correction request'
        : _reasonController.text.trim();

    try {
      await ref.read(attendanceRepositoryProvider).submitAttendanceCorrection(
            employeeId: employeeId,
            attendanceDate: _date!,
            clockInDate: _date!,
            clockIn: clockIn,
            clockOutDate: outDate,
            clockOut: clockOut,
            workedHour: _workedHourLabel,
            minimumHour: minimumHour.length >= 5
                ? minimumHour.substring(0, 5)
                : minimumHour,
            description: description,
            shiftId: shiftId,
            workTypeId: workTypeId,
            existingAttendanceId: _existing?.id,
          );
      invalidateAttendance(ref);
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
          'Attendance Correction',
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
                  'Attendance Date',
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
                    onTap: _loadingDay ? null : _pickDate,
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
                                  ? 'Select date'
                                  : DateFormat('dd-MMM-yyyy').format(_date!),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _date == null
                                    ? const Color(0xFF9CA3AF)
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (_loadingDay)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
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
                if (_existing != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Updating existing attendance (#${_existing!.id})',
                    style: const TextStyle(
                      color: AppColors.navBlue,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: RequestTimeField(
                        label: 'Check-in',
                        minutes: _fromMinutes,
                        use24Hour: true,
                        onTap: () => _pickTime(isCheckIn: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RequestTimeField(
                        label: 'Check-out',
                        minutes: _toMinutes,
                        use24Hour: true,
                        onTap: () => _pickTime(isCheckIn: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _isOvernight
                      ? 'Worked $_workedHourLabel hrs (overnight)'
                      : 'Worked $_workedHourLabel hrs',
                  style: const TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
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
                          hintText:
                              'e.g. Forgot to punch, Device error, Battery dead...',
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
