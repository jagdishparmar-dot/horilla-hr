import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../home/home_provider.dart';
import '../home/home_typography.dart';
import 'more_models.dart';
import 'more_providers.dart';
import 'more_repository.dart';
import 'more_widgets.dart';

/// Edits the contact, personal and emergency fields the server lets an
/// employee change on their own record.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key, required this.profile});

  final EmployeeProfile profile;

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  static final _phonePattern = RegExp(r'^\+?[\d\s\-\(\)]{7,20}$');
  static const _genders = ['male', 'female', 'other'];
  static const _maritalStatuses = ['single', 'married', 'divorced'];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _country;
  late final TextEditingController _zip;
  late final TextEditingController _emergencyName;
  late final TextEditingController _emergencyRelation;
  late final TextEditingController _emergencyPhone;
  DateTime? _dob;
  String? _gender;
  String? _marital;
  bool _busy = false;

  EmployeeProfile get _p => widget.profile;

  static const _fieldDecoration = InputDecoration(
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    filled: false,
    isDense: true,
    contentPadding: EdgeInsets.zero,
    counterText: '',
  );

  @override
  void initState() {
    super.initState();
    _phone = TextEditingController(text: _p.phone ?? '');
    _address = TextEditingController(text: _p.address ?? '');
    _city = TextEditingController(text: _p.city ?? '');
    _state = TextEditingController(text: _p.state ?? '');
    _country = TextEditingController(text: _p.country ?? '');
    _zip = TextEditingController(text: _p.zip ?? '');
    _emergencyName = TextEditingController(text: _p.emergencyContactName ?? '');
    _emergencyRelation = TextEditingController(
      text: _p.emergencyContactRelation ?? '',
    );
    _emergencyPhone = TextEditingController(text: _p.emergencyContact ?? '');
    _dob = _p.dob;
    _gender = _genders.contains(_p.gender) ? _p.gender : null;
    _marital = _maritalStatuses.contains(_p.maritalStatus)
        ? _p.maritalStatus
        : null;
  }

  @override
  void dispose() {
    for (final c in [
      _phone,
      _address,
      _city,
      _state,
      _country,
      _zip,
      _emergencyName,
      _emergencyRelation,
      _emergencyPhone,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Only fields that differ from what the server returned are sent.
  Map<String, dynamic> _changes() {
    final changes = <String, dynamic>{};
    void text(String key, TextEditingController c, String? original) {
      final value = c.text.trim();
      if (value != (original ?? '')) changes[key] = value;
    }

    text('phone', _phone, _p.phone);
    text('address', _address, _p.address);
    text('city', _city, _p.city);
    text('state', _state, _p.state);
    text('country', _country, _p.country);
    text('zip', _zip, _p.zip);
    text('emergency_contact_name', _emergencyName, _p.emergencyContactName);
    text(
      'emergency_contact_relation',
      _emergencyRelation,
      _p.emergencyContactRelation,
    );
    text('emergency_contact', _emergencyPhone, _p.emergencyContact);
    if (_dob != null && _dob != _p.dob) {
      changes['dob'] = DateFormat('yyyy-MM-dd').format(_dob!);
    }
    if (_gender != null && _gender != _p.gender) changes['gender'] = _gender;
    if (_marital != null && _marital != _p.maritalStatus) {
      changes['marital_status'] = _marital;
    }
    return changes;
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1940),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final changes = _changes();
    if (changes.isEmpty) {
      showSnack(context, 'Nothing to update');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(moreRepositoryProvider).updateProfile(_p.id, changes);
      ref.invalidate(profileBundleProvider);
      ref.invalidate(mobileHomeProvider);
      if (!mounted) return;
      showSnack(context, 'Profile updated');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, cleanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: HomeType.of(context),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Material(
            color: moreCanvas,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 36,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0x33767680),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  SizedBox(
                    height: 48,
                    child: Center(
                      child: Text(
                        'Edit Profile',
                        textAlign: TextAlign.center,
                        style: HomeType.headline(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: moreText,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Form(
                      key: _formKey,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        children: [
                          Container(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F3FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 1),
                                  child: HugeIcon(
                                    icon: HugeIcons.strokeRoundedShield01,
                                    color: moreBlue,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Name, email and employee ID are managed by HR and cannot be changed here.',
                                    style: HomeType.body(
                                      color: moreSecondary,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          _Group(
                            title: 'Contact',
                            children: [
                              _Field(
                                label: 'Mobile number',
                                controller: _phone,
                                keyboard: TextInputType.phone,
                                maxLength: 20,
                                validator: (v) {
                                  final value = (v ?? '').trim();
                                  if (value.isEmpty) {
                                    return 'Mobile number is required';
                                  }
                                  if (!_phonePattern.hasMatch(value)) {
                                    return 'Enter a valid number (7-20 digits, optional +)';
                                  }
                                  return null;
                                },
                              ),
                              _Field(
                                label: 'Address',
                                controller: _address,
                                maxLength: 200,
                                maxLines: 3,
                                stacked: true,
                              ),
                              _Field(
                                label: 'City',
                                controller: _city,
                                maxLength: 30,
                              ),
                              _Field(
                                label: 'State',
                                controller: _state,
                                maxLength: 100,
                              ),
                              _Field(
                                label: 'Country',
                                controller: _country,
                                maxLength: 100,
                              ),
                              _Field(
                                label: 'Zip code',
                                controller: _zip,
                                maxLength: 20,
                                last: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _Group(
                            title: 'Personal',
                            children: [
                              _TapRow(
                                label: 'Date of birth',
                                value: _dob == null
                                    ? 'Select date'
                                    : DateFormat('d MMMM yyyy').format(_dob!),
                                placeholder: _dob == null,
                                onTap: _pickDob,
                              ),
                              _DropdownRow(
                                label: 'Gender',
                                value: _gender,
                                options: _genders,
                                onChanged: (v) => setState(() => _gender = v),
                              ),
                              _DropdownRow(
                                label: 'Marital status',
                                value: _marital,
                                options: _maritalStatuses,
                                onChanged: (v) => setState(() => _marital = v),
                                last: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _Group(
                            title: 'Emergency contact',
                            children: [
                              _Field(
                                label: 'Name',
                                controller: _emergencyName,
                                maxLength: 20,
                              ),
                              _Field(
                                label: 'Relation',
                                controller: _emergencyRelation,
                                maxLength: 20,
                              ),
                              _Field(
                                label: 'Phone',
                                controller: _emergencyPhone,
                                keyboard: TextInputType.phone,
                                maxLength: 15,
                                last: true,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  _EditProfileActions(
                    busy: _busy,
                    onCancel: () => Navigator.of(context).maybePop(),
                    onSave: _save,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditProfileActions extends StatelessWidget {
  const _EditProfileActions({
    required this.busy,
    required this.onCancel,
    required this.onSave,
  });

  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: moreHairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: moreText,
                    disabledForegroundColor: moreMuted,
                    side: const BorderSide(color: Color(0xFFD1D5DB)),
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: shape,
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
                  onPressed: busy ? null : onSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: moreBlue,
                    disabledBackgroundColor: moreBlue.withValues(alpha: 0.35),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: shape,
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Text(
            title.toUpperCase(),
            style: HomeType.body(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: moreMuted,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: cardDecoration(radius: 16),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.keyboard,
    this.maxLength,
    this.maxLines = 1,
    this.validator,
    this.last = false,
    this.stacked = false,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboard;
  final int? maxLength;
  final int maxLines;
  final String? Function(String?)? validator;
  final bool last;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      controller: controller,
      keyboardType: keyboard,
      maxLength: maxLength,
      maxLines: maxLines,
      validator: validator,
      textAlign: stacked ? TextAlign.start : TextAlign.end,
      style: HomeType.headline(
        fontWeight: FontWeight.w500,
        fontSize: stacked ? 14 : 15,
        color: moreText,
      ),
      decoration: _EditProfileScreenState._fieldDecoration.copyWith(
        hintText: label,
        hintStyle: HomeType.body(color: moreMuted, fontSize: 15),
        errorStyle: HomeType.body(color: moreRed, fontSize: 11),
      ),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: HomeType.body(fontSize: 15, color: moreSecondary),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F3FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: field,
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 124,
                      child: Text(
                        label,
                        style: HomeType.body(
                          fontSize: 15,
                          color: moreSecondary,
                        ),
                      ),
                    ),
                    Expanded(child: field),
                  ],
                ),
        ),
        if (!last)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Divider(height: 1, color: moreHairline),
          ),
      ],
    );
  }
}

class _TapRow extends StatelessWidget {
  const _TapRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = false,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: HomeType.body(fontSize: 15, color: moreSecondary),
                  ),
                ),
                Text(
                  value,
                  style: HomeType.headline(
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    color: placeholder ? moreMuted : moreText,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFC7C7CC),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Divider(height: 1, color: moreHairline),
        ),
      ],
    );
  }
}

class _DropdownRow extends StatelessWidget {
  const _DropdownRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.last = false,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: HomeType.body(fontSize: 15, color: moreSecondary),
                ),
              ),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButtonFormField<String>(
                    initialValue: value,
                    isExpanded: true,
                    icon: const Icon(
                      Icons.unfold_more_rounded,
                      color: Color(0xFFC7C7CC),
                      size: 18,
                    ),
                    decoration: _EditProfileScreenState._fieldDecoration,
                    hint: Text(
                      'Select',
                      textAlign: TextAlign.end,
                      style: HomeType.body(color: moreMuted, fontSize: 15),
                    ),
                    style: HomeType.headline(
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                      color: moreText,
                    ),
                    alignment: AlignmentDirectional.centerEnd,
                    selectedItemBuilder: (context) => [
                      for (final option in options)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            humanize(option),
                            textAlign: TextAlign.end,
                            style: HomeType.headline(
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                              color: moreText,
                            ),
                          ),
                        ),
                    ],
                    items: [
                      for (final option in options)
                        DropdownMenuItem(
                          value: option,
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(
                            humanize(option),
                            textAlign: TextAlign.end,
                          ),
                        ),
                    ],
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!last)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Divider(height: 1, color: moreHairline),
          ),
      ],
    );
  }
}
