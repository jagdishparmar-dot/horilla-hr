import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/dio_client.dart';
import '../home/models.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(ref.watch(dioProvider));
});

class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.date,
    this.clockIn,
    this.clockOut,
    this.workedHour,
    this.overtime,
    this.overtimeSeconds = 0,
    this.minimumHour,
    this.shiftId,
    this.workTypeId,
    this.shiftName,
    this.shiftStart,
    this.shiftEnd,
    this.isLate = false,
    this.isHoliday = false,
    this.punches = const [],
  });

  final int id;
  final DateTime date;
  final String? clockIn;
  final String? clockOut;
  final String? workedHour;
  final String? overtime;
  final int overtimeSeconds;
  final String? minimumHour;
  final int? shiftId;
  final int? workTypeId;
  final String? shiftName;
  final String? shiftStart;
  final String? shiftEnd;
  final bool isLate;
  final bool isHoliday;
  final List<HomePunch> punches;

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    final dateRaw = json['attendance_date'] as String? ?? '';
    return AttendanceRecord(
      id: json['id'] as int? ?? 0,
      date: DateTime.tryParse(dateRaw) ?? DateTime.now(),
      clockIn: _fmtTime(json['attendance_clock_in']),
      clockOut: _fmtTime(json['attendance_clock_out']),
      workedHour: json['attendance_worked_hour'] as String?,
      overtime: json['attendance_overtime'] as String?,
      overtimeSeconds: json['overtime_second'] as int? ?? 0,
      minimumHour: json['minimum_hour'] as String?,
      shiftId: _asInt(json['shift_id']),
      workTypeId: _asInt(json['work_type_id']),
      shiftName: json['shift_name'] as String?,
      shiftStart: json['shift_start'] as String?,
      shiftEnd: json['shift_end'] as String?,
      isLate: json['is_late'] as bool? ?? false,
      isHoliday: json['is_holiday'] as bool? ?? false,
      punches: (json['activities'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => HomePunch.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    if (value is Map && value['id'] != null) return _asInt(value['id']);
    return null;
  }

  static String? _fmtTime(dynamic raw) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    // API may return "HH:MM:SS" or "HH:MM".
    final parts = text.split(':');
    if (parts.length >= 2) {
      return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
    }
    return text;
  }
}

class AttendanceRepository {
  AttendanceRepository(this._dio);

  final Dio _dio;
  static final _dateFmt = DateFormat('yyyy-MM-dd');

  Future<List<AttendanceRecord>> fetchMyAttendance({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final response = await _dio.get(
        '/attendance/my-attendance/',
        queryParameters: {
          'from_date': _dateFmt.format(from),
          'to_date': _dateFmt.format(to),
          'page_size': 100,
        },
      );
      return _parseList(response.data);
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  /// Create or update an attendance correction request.
  ///
  /// Uses `POST /attendance/attendance-request/` for a new day and
  /// `PUT /attendance/attendance-request/<id>` when a row already exists.
  Future<void> submitAttendanceCorrection({
    required int employeeId,
    required DateTime attendanceDate,
    required DateTime clockInDate,
    required String clockIn,
    required DateTime? clockOutDate,
    required String? clockOut,
    required String workedHour,
    required String minimumHour,
    required String description,
    required int? shiftId,
    required int? workTypeId,
    int? existingAttendanceId,
  }) async {
    final body = <String, dynamic>{
      'employee_id': employeeId,
      'attendance_date': _dateFmt.format(attendanceDate),
      'attendance_clock_in_date': _dateFmt.format(clockInDate),
      'attendance_clock_in': clockIn,
      'attendance_clock_out_date': clockOutDate == null
          ? ''
          : _dateFmt.format(clockOutDate),
      'attendance_clock_out': clockOut ?? '',
      'attendance_worked_hour': workedHour,
      'minimum_hour': minimumHour,
      'request_description': description,
      'shift_id': ?shiftId,
      'work_type_id': ?workTypeId,
    };

    try {
      if (existingAttendanceId != null) {
        await _dio.put(
          '/attendance/attendance-request/$existingAttendanceId',
          data: body,
        );
      } else {
        await _dio.post('/attendance/attendance-request/', data: body);
      }
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  List<AttendanceRecord> _parseList(dynamic data) {
    List<dynamic> rows;
    if (data is Map<String, dynamic>) {
      final results = data['results'];
      rows = results is List ? results : const [];
    } else if (data is List) {
      rows = data;
    } else {
      rows = const [];
    }

    return rows
        .whereType<Map>()
        .map((e) => AttendanceRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
