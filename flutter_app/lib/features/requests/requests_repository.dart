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

  final start = DateTime.tryParse(json['start_date'] as String? ?? '') ??
      DateTime.now();
  final end =
      DateTime.tryParse(json['end_date'] as String? ?? '') ?? start;

  return LeaveRequestItem(
    id: json['id'] as int? ?? 0,
    title: title,
    status: RequestStatusX.fromApi(json['status'] as String?),
    requestedDays: json['requested_days'] as num? ?? 1,
    startDate: start,
    endDate: end,
    kind: _inferRequestKind(title),
    reason: json['description'] as String?,
    rejectionReason: json['reject_reason'] as String?,
  );
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
