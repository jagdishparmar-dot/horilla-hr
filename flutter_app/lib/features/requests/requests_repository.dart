import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/dio_client.dart';
import 'models.dart';

final requestsRepositoryProvider = Provider<RequestsRepository>((ref) {
  return RequestsRepository(ref.watch(dioProvider));
});

class RequestsRepository {
  RequestsRepository(this._dio);

  final Dio _dio;
  static final _dateFmt = DateFormat('yyyy-MM-dd');

  Future<List<LeaveBalance>> fetchBalances({int pageSize = 50}) async {
    try {
      final response = await _dio.get(
        '/leave/available-leave/',
        queryParameters: {'page_size': pageSize},
      );
      return _parseBalances(response.data);
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<List<LeaveRequestItem>> fetchRequests({int pageSize = 50}) async {
    try {
      final response = await _dio.get(
        '/leave/user-request/',
        queryParameters: {'page_size': pageSize},
      );
      return _parseRequests(response.data);
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<LeaveRequestItem> fetchRequestDetail(int id) async {
    try {
      final response = await _dio.get('/leave/user-request/$id/');
      return mapLeaveRequest(Map<String, dynamic>.from(response.data as Map));
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<LeaveRequestItem> createLeaveRequest({
    required int leaveTypeId,
    required DateTime startDate,
    required DateTime endDate,
    required String description,
    String startBreakdown = 'full_day',
    String endBreakdown = 'full_day',
  }) async {
    try {
      final response = await _dio.post(
        '/leave/user-request/',
        data: {
          'leave_type_id': leaveTypeId,
          'start_date': _dateFmt.format(startDate),
          'end_date': _dateFmt.format(endDate),
          'start_date_breakdown': startBreakdown,
          'end_date_breakdown': endBreakdown,
          'description': description,
        },
      );
      return mapLeaveRequest(Map<String, dynamic>.from(response.data as Map));
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  /// Leave, attendance corrections, work-type, and shift requests for this employee.
  Future<List<LeaveRequestItem>> fetchMine({int? employeeId}) async {
    final leave = await fetchRequests();
    final extras = await Future.wait([
      _safeList(
        () => _fetchOwned(
          '/attendance/attendance-request/',
          employeeId,
        ).then((rows) => rows.map(mapAttendanceRequest).toList()),
      ),
      _safeList(
        () => _fetchOwned(
          '/base/worktype-requests/',
          employeeId,
        ).then((rows) => rows.map(mapWorkTypeRequest).toList()),
      ),
      _safeList(
        () => _fetchOwned(
          '/base/shift-requests/',
          employeeId,
        ).then((rows) => rows.map(mapShiftRequest).toList()),
      ),
    ]);
    final items = <LeaveRequestItem>[
      ...leave,
      ...extras[0],
      ...extras[1],
      ...extras[2],
    ];
    items.sort((a, b) {
      final byDate = b.startDate.compareTo(a.startDate);
      if (byDate != 0) return byDate;
      return b.id.compareTo(a.id);
    });
    return items;
  }

  Future<List<LookupItem>> fetchWorkTypes() async {
    try {
      final response = await _dio.get('/base/worktypes/');
      return _parseLookups(response.data, 'work_type');
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<List<LookupItem>> fetchShifts() async {
    try {
      final response = await _dio.get('/base/employee-shift/');
      return _parseLookups(response.data, 'employee_shift');
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<void> createWorkTypeRequest({
    required int workTypeId,
    required DateTime startDate,
    required DateTime endDate,
    required String description,
  }) async {
    try {
      await _dio.post(
        '/base/worktype-requests/',
        data: {
          'work_type_id': workTypeId,
          'requested_date': _dateFmt.format(startDate),
          'requested_till': _dateFmt.format(endDate),
          'description': description,
          'is_permanent_work_type': false,
        },
      );
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<void> createShiftRequest({
    required int shiftId,
    required DateTime startDate,
    required DateTime endDate,
    required String description,
  }) async {
    try {
      await _dio.post(
        '/base/shift-requests/',
        data: {
          'shift_id': shiftId,
          'requested_date': _dateFmt.format(startDate),
          'requested_till': _dateFmt.format(endDate),
          'description': description,
          'is_permanent_shift': false,
        },
      );
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<void> cancelRequest(LeaveRequestItem item) async {
    try {
      switch (item.source) {
        case RequestSource.leave:
          if (item.status == RequestStatus.approved) {
            await _dio.put('/leave/cancel/${item.id}/', data: const {});
          } else {
            await _dio.delete('/leave/user-request/${item.id}/');
          }
        case RequestSource.attendance:
          await _dio.put(
            '/attendance/attendance-request-cancel/${item.id}',
            data: const {},
          );
        case RequestSource.workType:
          await _dio.put(
            '/base/worktype-requests-cancel/${item.id}/',
            data: const {},
          );
        case RequestSource.shift:
          await _dio.post(
            '/base/shift-request-cancel/${item.id}',
            data: const {},
          );
      }
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchOwned(
    String path,
    int? employeeId,
  ) async {
    final response = await _dio.get(path, queryParameters: {'page_size': 100});
    return _results(response.data)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((row) => _ownedBy(row, employeeId))
        .toList();
  }

  Future<List<LeaveRequestItem>> _safeList(
    Future<List<LeaveRequestItem>> Function() load,
  ) async {
    try {
      return await load();
    } catch (_) {
      return const [];
    }
  }

  List<LeaveBalance> _parseBalances(dynamic data) {
    final rows = _results(data);
    return rows
        .whereType<Map>()
        .map((e) => mapLeaveBalance(Map<String, dynamic>.from(e)))
        .toList();
  }

  List<LeaveRequestItem> _parseRequests(dynamic data) {
    final rows = _results(data);
    return rows
        .whereType<Map>()
        .map((e) => mapLeaveRequest(Map<String, dynamic>.from(e)))
        .toList();
  }

  List<dynamic> _results(dynamic data) {
    if (data is Map<String, dynamic>) {
      final results = data['results'];
      if (results is List) return results;
      return const [];
    }
    if (data is List) return data;
    return const [];
  }

  List<LookupItem> _parseLookups(dynamic data, String nameKey) {
    final rows = data is List ? data : _results(data);
    return rows
        .whereType<Map>()
        .map((raw) {
          final json = Map<String, dynamic>.from(raw);
          return LookupItem(
            id: json['id'] as int? ?? 0,
            name: json[nameKey] as String? ?? 'Untitled',
          );
        })
        .where((item) => item.id != 0)
        .toList();
  }
}

bool _ownedBy(Map<String, dynamic> json, int? employeeId) {
  if (employeeId == null) return false;
  final raw = json['employee_id'];
  if (raw is int) return raw == employeeId;
  if (raw is String) return int.tryParse(raw) == employeeId;
  if (raw is Map) return raw['id'] == employeeId;
  return false;
}

String? _hhmm(dynamic raw) {
  if (raw == null) return null;
  final text = raw.toString().trim();
  if (text.isEmpty || text == 'None') return null;
  final parts = text.split(':');
  if (parts.length < 2) return text;
  return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
}

DateTime _parseDay(dynamic raw, [DateTime? fallback]) {
  if (raw is String) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed;
  }
  return fallback ?? DateTime.now();
}

RequestStatus _flagStatus(Map<String, dynamic> json) {
  if (json['canceled'] == true) return RequestStatus.cancelled;
  if (json['approved'] == true) return RequestStatus.approved;
  return RequestStatus.pending;
}

int _spanDays(DateTime start, DateTime end) {
  final days = end.difference(start).inDays + 1;
  return days < 1 ? 1 : days;
}

LeaveBalance mapLeaveBalance(Map<String, dynamic> json) {
  final leaveType = json['leave_type_id'];
  Map<String, dynamic>? typeMap;
  if (leaveType is Map) {
    typeMap = Map<String, dynamic>.from(leaveType);
  }

  final name = typeMap?['name'] as String? ?? 'Leave';
  final leaveTypeId = typeMap?['id'] as int? ?? json['id'] as int? ?? 0;
  final available = json['available_days'] as num? ?? 0;
  final carry = json['carryforward_days'] as num? ?? 0;
  final total = json['total_leave_days'] as num? ?? (available + carry);
  final used = json['leave_taken'] as num? ?? 0;

  return LeaveBalance(
    id: json['id'] as int? ?? leaveTypeId,
    leaveTypeId: leaveTypeId,
    name: name,
    available: available + carry,
    used: used,
    total: total,
    unit: _inferUnit(name, typeMap?['period_in'] as String?),
    kind: _inferBalanceKind(name),
  );
}

LeaveRequestItem mapLeaveRequest(Map<String, dynamic> json) {
  final leaveType = json['leave_type_id'];
  String title = 'Leave';
  if (leaveType is Map) {
    title = leaveType['name'] as String? ?? title;
  } else if (leaveType is String) {
    title = leaveType;
  }

  final start =
      DateTime.tryParse(json['start_date'] as String? ?? '') ?? DateTime.now();
  final end = DateTime.tryParse(json['end_date'] as String? ?? '') ?? start;

  final description = json['description'] as String?;
  final kind = _inferRequestKind(title);
  return LeaveRequestItem(
    id: json['id'] as int? ?? 0,
    title: title,
    status: RequestStatusX.fromApi(json['status'] as String?),
    requestedDays: json['requested_days'] as num? ?? 1,
    startDate: start,
    endDate: end,
    kind: kind,
    reason: description,
    rejectionReason: json['reject_reason'] as String?,
    source: RequestSource.leave,
    durationOverride: _permissionWindow(description),
  );
}

LeaveRequestItem mapAttendanceRequest(Map<String, dynamic> json) {
  final requested = _decodeMap(json['requested_data']);
  final day = _parseDay(json['attendance_date']);
  final clockIn = _hhmm(
    requested?['attendance_clock_in'] ?? json['attendance_clock_in'],
  );
  final clockOut = _hhmm(
    requested?['attendance_clock_out'] ?? json['attendance_clock_out'],
  );
  final window = clockIn == null
      ? null
      : clockOut == null
      ? clockIn
      : '$clockIn to $clockOut';
  return LeaveRequestItem(
    id: json['id'] as int? ?? 0,
    title: 'Attendance correction',
    status: RequestStatus.pending,
    requestedDays: 1,
    startDate: day,
    endDate: day,
    kind: RequestKind.other,
    reason: json['request_description'] as String?,
    source: RequestSource.attendance,
    durationOverride: window,
  );
}

LeaveRequestItem mapWorkTypeRequest(Map<String, dynamic> json) {
  final name = json['work_type_name'] as String? ?? 'Work type';
  final start = _parseDay(json['requested_date']);
  final end = _parseDay(json['requested_till'], start);
  return LeaveRequestItem(
    id: json['id'] as int? ?? 0,
    title: name,
    status: _flagStatus(json),
    requestedDays: _spanDays(start, end),
    startDate: start,
    endDate: end,
    kind: _inferRequestKind(name),
    reason: json['description'] as String?,
    source: RequestSource.workType,
  );
}

LeaveRequestItem mapShiftRequest(Map<String, dynamic> json) {
  final name = json['shift_name'] as String? ?? 'Shift change';
  final start = _parseDay(json['requested_date']);
  final end = _parseDay(json['requested_till'], start);
  return LeaveRequestItem(
    id: json['id'] as int? ?? 0,
    title: name,
    status: _flagStatus(json),
    requestedDays: _spanDays(start, end),
    startDate: start,
    endDate: end,
    kind: RequestKind.other,
    reason: json['description'] as String?,
    source: RequestSource.shift,
  );
}

Map<String, dynamic>? _decodeMap(dynamic raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String && raw.trim().isNotEmpty && raw != 'None') {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }
  return null;
}

String? _permissionWindow(String? description) {
  if (description == null) return null;
  final match = RegExp(r'Permission\s+(\d{2}:\d{2})\s*[–-]\s*(\d{2}:\d{2})')
      .firstMatch(description);
  if (match == null) return null;
  return '${match.group(1)} to ${match.group(2)}';
}

BalanceUnit _inferUnit(String name, String? periodIn) {
  final text = name.toLowerCase();
  if (text.contains('permission') || text.contains('hour')) {
    return BalanceUnit.hours;
  }
  if (periodIn == 'hour') return BalanceUnit.hours;
  return BalanceUnit.days;
}

BalanceKind _inferBalanceKind(String name) {
  final text = name.toLowerCase();
  if (text.contains('remote')) return BalanceKind.remote;
  if (text.contains('permission')) return BalanceKind.permission;
  if (text.contains('casual')) return BalanceKind.casual;
  if (text.contains('annual') ||
      text.contains('vacation') ||
      text.contains('paid')) {
    return BalanceKind.annual;
  }
  return BalanceKind.other;
}

RequestKind _inferRequestKind(String name) {
  final text = name.toLowerCase();
  if (text.contains('remote')) return RequestKind.remote;
  if (text.contains('permission')) return RequestKind.permission;
  if (text.contains('casual')) return RequestKind.casual;
  if (text.contains('early')) return RequestKind.early;
  if (text.contains('annual') ||
      text.contains('vacation') ||
      text.contains('paid')) {
    return RequestKind.annual;
  }
  return RequestKind.other;
}
