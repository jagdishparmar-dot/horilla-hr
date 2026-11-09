import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// What HR asked for: `GET /employee/document-request/`.
class DocumentRequirement {
  const DocumentRequirement({
    required this.id,
    required this.title,
    required this.format,
    this.maxSizeMb,
    this.description,
  });

  final int id;
  final String title;

  /// `any`, `pdf`, `jpg`, ... as defined by the server.
  final String format;
  final int? maxSizeMb;
  final String? description;

  factory DocumentRequirement.fromJson(Map<String, dynamic> json) {
    return DocumentRequirement(
      id: _int(json['id']) ?? 0,
      title: _str(json['title']) ?? 'Document',
      format: (_str(json['format']) ?? 'any').toLowerCase(),
      maxSizeMb: _int(json['max_size']),
      description: _str(json['description']),
    );
  }

  bool get acceptsAnyFormat => format == 'any';

  /// Extensions to allow in the file picker; null means no restriction.
  List<String>? get allowedExtensions {
    if (acceptsAnyFormat) return null;
    return format == 'jpg' || format == 'jpeg'
        ? const ['jpg', 'jpeg']
        : [format];
  }

  /// "PDF · up to 2 MB".
  String get ruleLabel {
    final parts = <String>[
      acceptsAnyFormat ? 'Any file type' : format.toUpperCase(),
      if (maxSizeMb != null) 'up to $maxSizeMb MB',
    ];
    return parts.join(' · ');
  }
}

enum DocumentState { upload, review, approved, rejected }

/// One of the signed-in employee's documents: `GET /employee/documents/`.
class DocumentItem {
  const DocumentItem({
    required this.id,
    required this.title,
    required this.status,
    this.fileUrl,
    this.rejectReason,
    this.issueDate,
    this.expiryDate,
    this.requestId,
    this.createdAt,
  });

  final int id;
  final String title;
  final String status;
  final String? fileUrl;
  final String? rejectReason;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final int? requestId;
  final DateTime? createdAt;

  factory DocumentItem.fromJson(Map<String, dynamic> json) {
    return DocumentItem(
      id: _int(json['id']) ?? 0,
      title: _str(json['title']) ?? 'Document',
      status: _str(json['status']) ?? 'requested',
      fileUrl: _str(json['document']),
      rejectReason: _str(json['reject_reason']),
      issueDate: _date(json['issue_date']),
      expiryDate: _date(json['expiry_date']),
      requestId: _int(json['document_request_id']),
      createdAt: _date(json['created_at']),
    );
  }

  bool get hasFile => fileUrl != null;

  /// A "requested" row with no file is waiting on the employee; with a file
  /// it is waiting on HR.
  DocumentState get state {
    switch (status) {
      case 'approved':
        return DocumentState.approved;
      case 'rejected':
        return DocumentState.rejected;
      default:
        return hasFile ? DocumentState.review : DocumentState.upload;
    }
  }

  bool get canUpload =>
      state == DocumentState.upload || state == DocumentState.rejected;

  /// "Upload ID proof" -> "ID proof". The server prefixes requested rows.
  String get displayTitle => title.startsWith('Upload ') && title.length > 7
      ? title.substring(7)
      : title;

  String get fileName {
    final url = fileUrl;
    if (url == null) return displayTitle;
    final last = Uri.tryParse(url)?.pathSegments
        .lastWhere((s) => s.isNotEmpty, orElse: () => '');
    return last == null || last.isEmpty ? displayTitle : last;
  }

  bool get isExpired =>
      expiryDate != null &&
      expiryDate!.isBefore(DateTime.now().subtract(const Duration(days: 1)));

  String get stateLabel => switch (state) {
    DocumentState.upload => 'Upload needed',
    DocumentState.review => 'Under review',
    DocumentState.approved => 'Approved',
    DocumentState.rejected => 'Rejected',
  };

  Color get stateColor => switch (state) {
    DocumentState.upload => const Color(0xFFF59E0B),
    DocumentState.review => const Color(0xFF2F6BFF),
    DocumentState.approved => const Color(0xFF16A34A),
    DocumentState.rejected => const Color(0xFFEF4444),
  };
}

/// A document joined with the rules it must satisfy.
class DocumentEntry {
  const DocumentEntry({required this.document, this.requirement});

  final DocumentItem document;
  final DocumentRequirement? requirement;
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

DateTime? _date(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

/// Human file size for the upload confirmation ("1.4 MB").
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Client-side pre-check mirroring the server's rule, so the user finds out
/// before waiting on an upload. Returns an error message or null when fine.
String? validateUpload({
  required String fileName,
  required int sizeBytes,
  DocumentRequirement? requirement,
}) {
  if (requirement == null) return null;
  final ext = fileName.contains('.')
      ? fileName.split('.').last.toLowerCase()
      : '';
  final allowed = requirement.allowedExtensions;
  if (allowed != null && !allowed.contains(ext)) {
    return 'Please choose a ${requirement.format.toUpperCase()} file.';
  }
  final max = requirement.maxSizeMb;
  if (max != null && sizeBytes > max * 1024 * 1024) {
    return 'That file is ${formatFileSize(sizeBytes)}. The limit is $max MB.';
  }
  return null;
}

String shortDate(DateTime? value) =>
    value == null ? '' : DateFormat('d MMM yyyy').format(value);
