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

class RemoteWorkRequestScreen extends ConsumerStatefulWidget {
  const RemoteWorkRequestScreen({super.key});

  @override
  ConsumerState<RemoteWorkRequestScreen> createState() =>
      _RemoteWorkRequestScreenState();
}

class _RemoteWorkRequestScreenState
    extends ConsumerState<RemoteWorkRequestScreen> {
  static const _maxReason = 150;

  DateTime? _from;
  DateTime? _to;
  LookupItem? _workType;
  List<LookupItem> _workTypes = const [];
  bool _loading = true;
  bool _submitting = false;
  String? _loadError;
  final _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reasonController.addListener(() => setState(() {}));
    _loadWorkTypes();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting &&
      !_loading &&
      _workType != null &&
      _from != null &&
      _to != null;

  Future<void> _loadWorkTypes() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final types = await ref.read(requestsRepositoryProvider).fetchWorkTypes();
      if (!mounted) return;
      setState(() {
        _workTypes = types;
        _workType = _preferRemote(types);
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

  LookupItem? _preferRemote(List<LookupItem> types) {
    for (final type in types) {
      final name = type.name.toLowerCase();
      if (name.contains('remote') ||
          name.contains('wfh') ||
          name.contains('work from home')) {
        return type;
      }
    }
    return null;
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
    final note = _reasonController.text.trim();
    try {
      await ref
          .read(requestsRepositoryProvider)
          .createWorkTypeRequest(
            workTypeId: _workType!.id,
            startDate: _from!,
            endDate: _to!,
            description: note.isEmpty ? 'Remote work request' : note,
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
          'Remote Work',
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
                      onPressed: _loadWorkTypes,
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
                        'Work type',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _LookupDropdown(
                        value: _workType,
                        items: _workTypes,
                        hint: 'Select work type',
                        onChanged: (value) => setState(() => _workType = value),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _workType == null
                            ? 'Pick the work type HR uses for remote work.'
                            : 'Files a work-type request for ${_workType!.name}.',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
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
                                hintText: 'e.g. Working from home this week.',
                                hintStyle: TextStyle(
                                  color: Color(0xFF9CA3AF),
                                  fontWeight: FontWeight.w500,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                contentPadding: EdgeInsets.fromLTRB(
                                  14,
                                  12,
                                  14,
                                  4,
                                ),
                                counterText: '',
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(
                                right: 12,
                                bottom: 10,
                              ),
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

class _LookupDropdown extends StatelessWidget {
  const _LookupDropdown({
    required this.value,
    required this.items,
    required this.hint,
    required this.onChanged,
  });

  final LookupItem? value;
  final List<LookupItem> items;
  final String hint;
  final ValueChanged<LookupItem?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value != null && items.any((item) => item.id == value!.id)
        ? items.firstWhere((item) => item.id == value!.id)
        : null;
    return Container(
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
          hint: Text(hint),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textSecondary,
          ),
          items: [
            for (final item in items)
              DropdownMenuItem(
                value: item,
                child: Text(
                  item.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
          ],
          onChanged: onChanged,
        ),
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
