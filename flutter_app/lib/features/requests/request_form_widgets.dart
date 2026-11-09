import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';

Future<DateTime?> showRequestCalendarPicker(
  BuildContext context, {
  required DateTime initialDate,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (context) => _CalendarPickerDialog(initialDate: initialDate),
  );
}

/// Returns minutes from midnight (0–1439).
Future<int?> showRequestTimePicker(
  BuildContext context, {
  required int initialMinutes,
  String title = 'Select time',
  bool use24Hour = false,
  int minuteInterval = 5,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _TimePickerSheet(
      initialMinutes: initialMinutes.clamp(0, 24 * 60 - 1),
      title: title,
      use24Hour: use24Hour,
      minuteInterval: minuteInterval.clamp(1, 30),
    ),
  );
}

String formatRequestTime(int totalMinutes, {bool use24Hour = false}) {
  final mins = totalMinutes % (24 * 60);
  final h24 = mins ~/ 60;
  final m = mins % 60;
  if (use24Hour) {
    return '${h24.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
  final isAm = h24 < 12;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} ${isAm ? 'AM' : 'PM'}';
}

class RequestTimeField extends StatelessWidget {
  const RequestTimeField({
    super.key,
    required this.label,
    required this.minutes,
    required this.onTap,
    this.use24Hour = false,
  });

  final String label;
  final int minutes;
  final VoidCallback onTap;
  final bool use24Hour;

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
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      formatRequestTime(minutes, use24Hour: use24Hour),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedClock01,
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

Future<void> showRequestSuccessDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _SuccessDialog(),
  );
}

class RequestFormFooter extends StatelessWidget {
  const RequestFormFooter({
    super.key,
    required this.canSubmit,
    required this.onCancel,
    required this.onSubmit,
  });

  final bool canSubmit;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: canSubmit ? onSubmit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navBlue,
                  disabledBackgroundColor:
                      AppColors.navBlue.withValues(alpha: 0.35),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Submit',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarPickerDialog extends StatefulWidget {
  const _CalendarPickerDialog({required this.initialDate});

  final DateTime initialDate;

  @override
  State<_CalendarPickerDialog> createState() => _CalendarPickerDialogState();
}

class _CalendarPickerDialogState extends State<_CalendarPickerDialog> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    _month = DateTime(_selected.year, _selected.month);
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = first.weekday % 7;
    final totalCells = ((leading + daysInMonth) / 7).ceil() * 7;
    const headers = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(() {
                    _month = DateTime(_month.year, _month.month - 1);
                  }),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    DateFormat('MMMM yyyy').format(_month),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _month = DateTime(_month.year, _month.month + 1);
                  }),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (final h in headers)
                  Expanded(
                    child: Text(
                      h,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (var row = 0; row < totalCells / 7; row++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    for (var col = 0; col < 7; col++)
                      Expanded(
                        child: _dayCell(
                          index: row * 7 + col,
                          leading: leading,
                          daysInMonth: daysInMonth,
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_selected),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Confirm',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayCell({
    required int index,
    required int leading,
    required int daysInMonth,
  }) {
    final dayNum = index - leading + 1;
    if (dayNum < 1 || dayNum > daysInMonth) {
      return const SizedBox(height: 36);
    }
    final date = DateTime(_month.year, _month.month, dayNum);
    final selected = date.year == _selected.year &&
        date.month == _selected.month &&
        date.day == _selected.day;

    return InkWell(
      onTap: () => setState(() => _selected = date),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.navBlue : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Text(
          '$dayNum',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _SuccessDialog extends StatelessWidget {
  const _SuccessDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.navBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedCheckmarkCircle02,
                  color: AppColors.navBlue,
                  size: 36,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Request Submitted Successfully!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "We'll notify you once it's reviewed.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navBlue,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimePickerSheet extends StatefulWidget {
  const _TimePickerSheet({
    required this.initialMinutes,
    required this.title,
    required this.use24Hour,
    required this.minuteInterval,
  });

  final int initialMinutes;
  final String title;
  final bool use24Hour;
  final int minuteInterval;

  @override
  State<_TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<_TimePickerSheet> {
  static const _itemExtent = 44.0;

  late int _hour24;
  late int _minute;
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  late FixedExtentScrollController _periodController;

  List<int> get _minuteOptions {
    final options = <int>[];
    for (var m = 0; m < 60; m += widget.minuteInterval) {
      options.add(m);
    }
    return options;
  }

  @override
  void initState() {
    super.initState();
    _hour24 = widget.initialMinutes ~/ 60;
    final rawMinute = widget.initialMinutes % 60;
    final options = _minuteOptions;
    _minute = options.reduce(
      (a, b) => (rawMinute - a).abs() <= (rawMinute - b).abs() ? a : b,
    );

    _hourController = FixedExtentScrollController(
      initialItem: widget.use24Hour ? _hour24 : (_hour24 + 11) % 12,
    );
    _minuteController = FixedExtentScrollController(
      initialItem: options.indexOf(_minute).clamp(0, options.length - 1),
    );
    _periodController = FixedExtentScrollController(
      initialItem: _hour24 < 12 ? 0 : 1,
    );
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _periodController.dispose();
    super.dispose();
  }

  int get _totalMinutes => _hour24 * 60 + _minute;

  void _syncHourFrom12({required int hour12Index, required bool isAm}) {
    // hour12Index 0..11 maps to 1..12
    final hour12 = hour12Index + 1;
    if (isAm) {
      _hour24 = hour12 == 12 ? 0 : hour12;
    } else {
      _hour24 = hour12 == 12 ? 12 : hour12 + 12;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final minutes = _minuteOptions;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            widget.title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            formatRequestTime(_totalMinutes, use24Hour: widget.use24Hour),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 32,
              color: AppColors.navBlue,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: _itemExtent * 5,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: _itemExtent,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: widget.use24Hour
                          ? _wheel(
                              controller: _hourController,
                              itemCount: 24,
                              labelBuilder: (i) => i.toString().padLeft(2, '0'),
                              onSelected: (i) => setState(() => _hour24 = i),
                            )
                          : _wheel(
                              controller: _hourController,
                              itemCount: 12,
                              labelBuilder: (i) =>
                                  (i + 1).toString().padLeft(2, '0'),
                              onSelected: (i) => setState(() {
                                _syncHourFrom12(
                                  hour12Index: i,
                                  isAm: _hour24 < 12,
                                );
                              }),
                            ),
                    ),
                    const Text(
                      ':',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 28,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Expanded(
                      child: _wheel(
                        controller: _minuteController,
                        itemCount: minutes.length,
                        labelBuilder: (i) =>
                            minutes[i].toString().padLeft(2, '0'),
                        onSelected: (i) => setState(() => _minute = minutes[i]),
                      ),
                    ),
                    if (!widget.use24Hour)
                      Expanded(
                        child: _wheel(
                          controller: _periodController,
                          itemCount: 2,
                          labelBuilder: (i) => i == 0 ? 'AM' : 'PM',
                          onSelected: (i) => setState(() {
                            final hour12Index = _hourController.selectedItem;
                            _syncHourFrom12(
                              hour12Index: hour12Index,
                              isAm: i == 0,
                            );
                          }),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: Color(0xFFD1D5DB)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_totalMinutes),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Confirm',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int index) labelBuilder,
    required ValueChanged<int> onSelected,
  }) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: _itemExtent,
      perspective: 0.003,
      diameterRatio: 1.4,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onSelected,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: itemCount,
        builder: (context, index) {
          final selected = controller.hasClients
              ? controller.selectedItem == index
              : controller.initialItem == index;
          return Center(
            child: Text(
              labelBuilder(index),
              style: TextStyle(
                fontSize: selected ? 22 : 16,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? AppColors.navBlue : AppColors.textSecondary,
              ),
            ),
          );
        },
      ),
    );
  }
}
