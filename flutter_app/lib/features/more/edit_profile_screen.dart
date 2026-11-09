import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../home/home_provider.dart';
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
    return MorePage(
      title: 'Edit Profile',
      body: Column(
        children: [
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  const Text(
                    'Name, email and employee ID are managed by HR and cannot be changed here.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    title: 'Contact',
                    children: [
                      _Field(
                        label: 'Mobile number',
                        controller: _phone,
                        keyboard: TextInputType.phone,
                        maxLength: 20,
                        validator: (v) {
                          final value = (v ?? '').trim();
                          if (value.isEmpty) return 'Mobile number is required';
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
                      ),
                      _Field(label: 'City', controller: _city, maxLength: 30),
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
                  const SizedBox(height: 14),
                  SectionCard(
                    title: 'Personal',
                    children: [
                      _Label('Date of birth'),
                      InkWell(
                        onTap: _pickDob,
                        borderRadius: BorderRadius.circular(14),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            suffixIcon: Icon(
                              Icons.calendar_today_rounded,
                              size: 18,
                            ),
                          ),
                          child: Text(
                            _dob == null
                                ? 'Select date'
                                : DateFormat('d MMMM yyyy').format(_dob!),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _dob == null
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _Label('Gender'),
                      _Dropdown(
                        value: _gender,
                        options: _genders,
                        onChanged: (v) => setState(() => _gender = v),
                      ),
                      const SizedBox(height: 14),
                      _Label('Marital status'),
                      _Dropdown(
                        value: _marital,
                        options: _maritalStatuses,
                        onChanged: (v) => setState(() => _marital = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
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
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _save,
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
                          'Save changes',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

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

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.keyboard,
    this.maxLength,
    this.maxLines = 1,
    this.validator,
    this.last = false,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboard;
  final int? maxLength;
  final int maxLines;
  final String? Function(String?)? validator;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(label),
          TextFormField(
            controller: controller,
            keyboardType: keyboard,
            maxLength: maxLength,
            maxLines: maxLines,
            validator: validator,
            decoration: const InputDecoration(counterText: ''),
          ),
        ],
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(),
      hint: const Text('Select'),
      items: [
        for (final option in options)
          DropdownMenuItem(value: option, child: Text(humanize(option))),
      ],
      onChanged: onChanged,
    );
  }
}
