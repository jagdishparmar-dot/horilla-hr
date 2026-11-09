import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/config.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

String? resolveMediaUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http')) return url;
  return '${AppConfig.mediaOrigin}$url';
}

String? _str(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty || text == 'null' ? null : text;
}

int? _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _double(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

DateTime? _date(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

/// "male" / "single_parent" -> "Male" / "Single parent".
String humanize(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return '';
  final spaced = text.replaceAll('_', ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// Rich-text bodies written in the web editor arrive as HTML. The app renders
/// plain text, so tags are stripped and the common entities decoded.
String stripHtml(String? html) {
  var text = html ?? '';
  text = text
      .replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(r'</\s*(p|div|li|h[1-6])\s*>', caseSensitive: false),
        '\n',
      )
      .replaceAll(RegExp(r'<\s*li[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// "09:00:00" / "9:05" -> "9:05 AM". Anything unparseable is returned as-is.
String formatClock(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(raw.trim());
  if (match == null) return raw;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return raw;
  return DateFormat.jm().format(DateTime(2000, 1, 1, hour, minute));
}

final _money = NumberFormat('#,##0.00');
String formatMoney(num value) => _money.format(value);

/// 13.0 -> "13", 12.5 -> "12.5".
String formatCount(num value) =>
    value == value.roundToDouble() ? value.round().toString() : '$value';

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

class EmployeeProfile {
  const EmployeeProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.email,
    this.phone,
    this.badgeId,
    this.avatarUrl,
    this.address,
    this.city,
    this.state,
    this.country,
    this.zip,
    this.dob,
    this.gender,
    this.maritalStatus,
    this.qualification,
    this.experience,
    this.children,
    this.emergencyContact,
    this.emergencyContactName,
    this.emergencyContactRelation,
    this.workInfoId,
    this.bankDetailsId,
  });

  final int id;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final String? badgeId;
  final String? avatarUrl;
  final String? address;
  final String? city;
  final String? state;
  final String? country;
  final String? zip;
  final DateTime? dob;
  final String? gender;
  final String? maritalStatus;
  final String? qualification;
  final int? experience;
  final int? children;
  final String? emergencyContact;
  final String? emergencyContactName;
  final String? emergencyContactRelation;
  final int? workInfoId;
  final int? bankDetailsId;

  factory EmployeeProfile.fromJson(Map<String, dynamic> json) {
    return EmployeeProfile(
      id: _int(json['id']) ?? 0,
      firstName: _str(json['employee_first_name']) ?? '',
      lastName: _str(json['employee_last_name']) ?? '',
      email: _str(json['email']),
      phone: _str(json['phone']),
      badgeId: _str(json['badge_id']),
      avatarUrl: _str(json['employee_profile']),
      address: _str(json['address']),
      city: _str(json['city']),
      state: _str(json['state']),
      country: _str(json['country']),
      zip: _str(json['zip']),
      dob: _date(json['dob']),
      gender: _str(json['gender']),
      maritalStatus: _str(json['marital_status']),
      qualification: _str(json['qualification']),
      experience: _int(json['experience']),
      children: _int(json['children']),
      emergencyContact: _str(json['emergency_contact']),
      emergencyContactName: _str(json['emergency_contact_name']),
      emergencyContactRelation: _str(json['emergency_contact_relation']),
      workInfoId: _int(json['employee_work_info_id']),
      bankDetailsId: _int(json['employee_bank_details_id']),
    );
  }

  String get fullName => '$firstName $lastName'.trim();

  /// Address lines that actually have content, joined for display.
  String? get fullAddress {
    final cityLine = [
      city,
      state,
      zip,
    ].whereType<String>().where((e) => e.isNotEmpty).join(', ');
    final parts = [
      address,
      cityLine,
      country,
    ].whereType<String>().where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join('\n');
  }

  bool get hasEmergencyContact =>
      emergencyContact != null ||
      emergencyContactName != null ||
      emergencyContactRelation != null;
}

class WorkInfo {
  const WorkInfo({
    this.jobPosition,
    this.department,
    this.managerName,
    this.shift,
    this.workType,
    this.employeeType,
    this.company,
    this.location,
    this.workEmail,
    this.workPhone,
    this.dateJoining,
  });

  final String? jobPosition;
  final String? department;
  final String? managerName;
  final String? shift;
  final String? workType;
  final String? employeeType;
  final String? company;
  final String? location;
  final String? workEmail;
  final String? workPhone;
  final DateTime? dateJoining;

  factory WorkInfo.fromJson(Map<String, dynamic> json) {
    final manager = [
      _str(json['reporting_manager_first_name']),
      _str(json['reporting_manager_last_name']),
    ].whereType<String>().join(' ').trim();
    return WorkInfo(
      jobPosition: _str(json['job_position_name']),
      department: _str(json['department_name']),
      managerName: manager.isEmpty ? null : manager,
      shift: _str(json['shift_name']),
      workType: _str(json['work_type_name']),
      employeeType: _str(json['employee_type_name']),
      company: _str(json['company_name']),
      location: _str(json['location']),
      workEmail: _str(json['email']),
      workPhone: _str(json['mobile']),
      dateJoining: _date(json['date_joining']),
    );
  }

  /// "2y 3m", "5m" or "New" — time since joining.
  String? get tenureLabel {
    final joined = dateJoining;
    if (joined == null) return null;
    final now = DateTime.now();
    var months = (now.year - joined.year) * 12 + now.month - joined.month;
    if (now.day < joined.day) months -= 1;
    if (months < 0) return null;
    final years = months ~/ 12;
    final rest = months % 12;
    if (years > 0) return rest == 0 ? '${years}y' : '${years}y ${rest}m';
    if (rest > 0) return '${rest}m';
    return 'New';
  }
}

class BankInfo {
  const BankInfo({this.bankName, this.accountNumber, this.branch});

  final String? bankName;
  final String? accountNumber;
  final String? branch;

  factory BankInfo.fromJson(Map<String, dynamic> json) {
    return BankInfo(
      bankName: _str(json['bank_name']),
      accountNumber: _str(json['account_number']),
      branch: _str(json['branch']),
    );
  }

  /// Only the last four digits are shown on screen.
  String? get maskedAccount {
    final number = accountNumber;
    if (number == null) return null;
    if (number.length <= 4) return number;
    return '•••• ${number.substring(number.length - 4)}';
  }
}

class ProfileBundle {
  const ProfileBundle({required this.profile, this.work, this.bank});

  final EmployeeProfile profile;
  final WorkInfo? work;
  final BankInfo? bank;
}

// ---------------------------------------------------------------------------
// Payroll
// ---------------------------------------------------------------------------

class PayLine {
  const PayLine({required this.title, required this.amount});

  final String title;
  final double amount;
}

class PayslipItem {
  const PayslipItem({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.basicPay,
    required this.grossPay,
    required this.deduction,
    required this.netPay,
    required this.allowances,
    required this.deductions,
    this.workingDays,
    this.paidDays,
    this.unpaidDays,
    this.lossOfPay,
  });

  final int id;
  final DateTime startDate;
  final DateTime endDate;
  final String status;
  final double basicPay;
  final double grossPay;
  final double deduction;
  final double netPay;
  final List<PayLine> allowances;
  final List<PayLine> deductions;
  final double? workingDays;
  final double? paidDays;
  final double? unpaidDays;

  /// Pay already taken off basic for unpaid days (informational).
  final double? lossOfPay;

  static const _deductionKeys = [
    'basic_pay_deductions',
    'gross_pay_deductions',
    'pretax_deductions',
    'post_tax_deductions',
    'tax_deductions',
    'net_deductions',
  ];

  static List<PayLine> _lines(dynamic raw) {
    if (raw is! List) return const [];
    final lines = <PayLine>[];
    for (final row in raw.whereType<Map>()) {
      final title = _str(row['title']) ?? _str(row['name']);
      final amount = _double(row['amount']);
      if (title == null || amount == null) continue;
      lines.add(PayLine(title: title, amount: amount));
    }
    return lines;
  }

  factory PayslipItem.fromJson(Map<String, dynamic> json) {
    final start = _date(json['start_date']) ?? DateTime.now();
    final end = _date(json['end_date']) ?? start;
    final head = json['pay_head_data'];
    final data = head is Map ? Map<String, dynamic>.from(head) : const {};
    return PayslipItem(
      id: _int(json['id']) ?? 0,
      startDate: start,
      endDate: end,
      status: _str(json['status']) ?? 'draft',
      basicPay: _double(json['basic_pay']) ?? 0,
      grossPay: _double(json['gross_pay']) ?? 0,
      deduction: _double(json['deduction']) ?? 0,
      netPay: _double(json['net_pay']) ?? 0,
      allowances: _lines(data['allowances']),
      deductions: [for (final key in _deductionKeys) ..._lines(data[key])],
      workingDays: _double(data['working_days']),
      paidDays: _double(data['paid_days']),
      unpaidDays: _double(data['unpaid_days']),
      lossOfPay: _double(data['loss_of_pay']),
    );
  }

  bool get hasAttendanceSummary =>
      workingDays != null || paidDays != null || unpaidDays != null;

  /// Drafts and payslips still under review are not meant for the employee.
  bool get isIssued => status == 'confirmed' || status == 'paid';

  bool get isPaid => status == 'paid';

  String get statusLabel => switch (status) {
    'paid' => 'Paid',
    'confirmed' => 'Confirmed',
    'review_ongoing' => 'In review',
    _ => 'Draft',
  };

  String get periodLabel {
    final sameMonth =
        startDate.year == endDate.year && startDate.month == endDate.month;
    if (sameMonth && startDate.day == 1) {
      return DateFormat('MMMM yyyy').format(startDate);
    }
    final fmt = DateFormat('d MMM yyyy');
    return '${fmt.format(startDate)} – ${fmt.format(endDate)}';
  }
}

// ---------------------------------------------------------------------------
// Policies
// ---------------------------------------------------------------------------

class PolicyItem {
  const PolicyItem({required this.id, required this.title, required this.body});

  final int id;
  final String title;
  final String body;

  factory PolicyItem.fromJson(Map<String, dynamic> json) {
    return PolicyItem(
      id: _int(json['id']) ?? 0,
      title: _str(json['title']) ?? 'Policy',
      body: stripHtml(json['body']?.toString()),
    );
  }
}

// ---------------------------------------------------------------------------
// Help desk
// ---------------------------------------------------------------------------

class TicketTypeItem {
  const TicketTypeItem({
    required this.id,
    required this.title,
    required this.prefix,
  });

  final int id;
  final String title;
  final String prefix;

  factory TicketTypeItem.fromJson(Map<String, dynamic> json) {
    return TicketTypeItem(
      id: _int(json['id']) ?? 0,
      title: _str(json['title']) ?? 'Ticket',
      prefix: _str(json['prefix']) ?? 'TKT',
    );
  }
}

/// A department tickets can be forwarded to, with the manager who handles it.
class TicketDepartment {
  const TicketDepartment({
    required this.id,
    required this.name,
    this.managerName,
  });

  final int id;
  final String name;
  final String? managerName;
}

enum TicketStatus { fresh, inProgress, onHold, resolved, canceled }

extension TicketStatusX on TicketStatus {
  static TicketStatus fromApi(String? raw) => switch (raw) {
    'in_progress' => TicketStatus.inProgress,
    'on_hold' => TicketStatus.onHold,
    'resolved' => TicketStatus.resolved,
    'canceled' => TicketStatus.canceled,
    _ => TicketStatus.fresh,
  };

  String get label => switch (this) {
    TicketStatus.fresh => 'New',
    TicketStatus.inProgress => 'In progress',
    TicketStatus.onHold => 'On hold',
    TicketStatus.resolved => 'Resolved',
    TicketStatus.canceled => 'Canceled',
  };

  Color get color => switch (this) {
    TicketStatus.fresh => const Color(0xFF2F6BFF),
    TicketStatus.inProgress => const Color(0xFFF59E0B),
    TicketStatus.onHold => const Color(0xFF8B5CF6),
    TicketStatus.resolved => const Color(0xFF16A34A),
    TicketStatus.canceled => const Color(0xFF6B7280),
  };

  bool get isOpen =>
      this == TicketStatus.fresh ||
      this == TicketStatus.inProgress ||
      this == TicketStatus.onHold;
}

class TicketItem {
  const TicketItem({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.typeTitle,
    required this.prefix,
    required this.createdAt,
    this.deadline,
    this.resolvedAt,
    this.forwardedTo,
    this.assignees = const [],
  });

  final int id;
  final String title;
  final String description;
  final TicketStatus status;
  final String priority;
  final String typeTitle;
  final String prefix;
  final DateTime? createdAt;
  final DateTime? deadline;
  final DateTime? resolvedAt;
  final String? forwardedTo;
  final List<String> assignees;

  factory TicketItem.fromJson(Map<String, dynamic> json) {
    final type = json['ticket_type'] is Map
        ? Map<String, dynamic>.from(json['ticket_type'] as Map)
        : const <String, dynamic>{};
    final assigned = json['assigned_to'] is List
        ? (json['assigned_to'] as List)
              .whereType<Map>()
              .map((e) => _str(e['get_full_name']))
              .whereType<String>()
              .toList()
        : <String>[];
    return TicketItem(
      id: _int(json['id']) ?? 0,
      title: _str(json['title']) ?? 'Ticket',
      description: stripHtml(json['description']?.toString()),
      status: TicketStatusX.fromApi(_str(json['status'])),
      priority: _str(json['priority']) ?? 'low',
      typeTitle: _str(type['title']) ?? 'Ticket',
      prefix: _str(type['prefix']) ?? 'TKT',
      createdAt: _date(json['created_date']),
      deadline: _date(json['deadline']),
      resolvedAt: _date(json['resolved_date']),
      forwardedTo: _str(json['raised_on_display']),
      assignees: assigned,
    );
  }

  String get code => '$prefix-${id.toString().padLeft(3, '0')}';

  String get priorityLabel => humanize(priority);

  Color get priorityColor => switch (priority) {
    'high' => const Color(0xFFEF4444),
    'medium' => const Color(0xFFF59E0B),
    _ => const Color(0xFF22B8E8),
  };
}

class TicketComment {
  const TicketComment({
    required this.id,
    required this.author,
    required this.text,
    required this.date,
    required this.authorId,
  });

  final int id;
  final String author;
  final int? authorId;
  final String text;
  final DateTime? date;

  factory TicketComment.fromJson(Map<String, dynamic> json) {
    final employee = json['employee_id'] is Map
        ? Map<String, dynamic>.from(json['employee_id'] as Map)
        : const <String, dynamic>{};
    return TicketComment(
      id: _int(json['id']) ?? 0,
      author: _str(employee['get_full_name']) ?? 'Employee',
      authorId: _int(employee['id']),
      text: stripHtml(json['comment']?.toString()),
      date: DateTime.tryParse(json['date']?.toString() ?? '')?.toLocal(),
    );
  }
}

class FaqItem {
  const FaqItem({
    required this.id,
    required this.question,
    required this.answer,
    this.category,
  });

  final int id;
  final String question;
  final String answer;
  final String? category;

  factory FaqItem.fromJson(Map<String, dynamic> json) {
    final category = json['category'] is Map
        ? _str((json['category'] as Map)['title'])
        : null;
    return FaqItem(
      id: _int(json['id']) ?? 0,
      question: _str(json['question']) ?? '',
      answer: stripHtml(json['answer']?.toString()),
      category: category,
    );
  }
}

// ---------------------------------------------------------------------------
// Activity feed
// ---------------------------------------------------------------------------

enum ActivityKind { clockIn, clockOut, notification }

class ActivityEvent {
  const ActivityEvent({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.at,
    this.unread = false,
    this.accent,
  });

  final ActivityKind kind;
  final String title;
  final String subtitle;
  final DateTime at;
  final bool unread;
  final Color? accent;
}
