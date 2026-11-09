import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/dio_client.dart';
import '../home/models.dart';
import 'models.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(ref.watch(dioProvider));
});

class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.date,
    this.clockIn,
    this.clockOut,
    this.clockInDate,
    this.clockOutDate,
    this.workedHour,
    this.overtime,
    this.overtimeSeconds = 0,
    this.atWorkSeconds = 0,
    this.minimumHour,
    this.hoursPending,
    this.shiftId,
    this.workTypeId,
    this.shiftName,
    this.shiftStart,
    this.shiftEnd,
    this.isLate = false,
    this.isEarlyOut = false,
    this.isHoliday = false,
    this.overtimeApproved = false,
    this.isValidated = false,
    this.isRequestPending = false,
    this.punches = const [],
  });

  final int id;
  final DateTime date;
  final String? clockIn;
  final String? clockOut;
  final String? clockInDate;
  final String? clockOutDate;
  final String? workedHour;
  final String? overtime;
  final int overtimeSeconds;
  final int atWorkSeconds;
  final String? minimumHour;
  final String? hoursPending;
  final int? shiftId;
  final int? workTypeId;
  final String? shiftName;
  final String? shiftStart;
  final String? shiftEnd;
  final bool isLate;
  final bool isEarlyOut;
  final bool isHoliday;
  final bool overtimeApproved;
  final bool isValidated;
  final bool isRequestPending;
  final List<HomePunch> punches;

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    final dateRaw = json['attendance_date'] as String? ?? '';
    return AttendanceRecord(
      id: json['id'] as int? ?? 0,
      date: DateTime.tryParse(dateRaw) ?? DateTime.now(),
      clockIn: _fmtTime(json['attendance_clock_in']),
      clockOut: _fmtTime(json['attendance_clock_out']),
      clockInDate: _fmtDate(json['attendance_clock_in_date']),
      clockOutDate: _fmtDate(json['attendance_clock_out_date']),
      workedHour: json['attendance_worked_hour'] as String?,
      overtime: json['attendance_overtime'] as String?,
      overtimeSeconds: _asInt(json['overtime_second']) ?? 0,
      atWorkSeconds: _asInt(json['at_work_second']) ?? 0,
      minimumHour: json['minimum_hour'] as String?,
      hoursPending: json['hours_pending'] as String?,
      shiftId: _asInt(json['shift_id']),
      workTypeId: _asInt(json['work_type_id']),
      shiftName: json['shift_name'] as String?,
      shiftStart: json['shift_start'] as String?,
      shiftEnd: json['shift_end'] as String?,
      isLate: json['is_late'] as bool? ?? false,
      isEarlyOut: json['is_early_out'] as bool? ?? false,
      isHoliday: json['is_holiday'] as bool? ?? false,
      overtimeApproved: json['attendance_overtime_approve'] as bool? ?? false,
      isValidated: json['attendance_validated'] as bool? ?? false,
      isRequestPending:
          (json['is_validate_request'] as bool? ?? false) &&
          !(json['is_validate_request_approved'] as bool? ?? false),
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

  static String? _fmtDate(dynamic raw) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    return text.length >= 10 ? text.substring(0, 10) : text;
  }
}

class AttendanceRangePayload {
  const AttendanceRangePayload({
    required this.records,
    this.context = const {},
  });

  final List<AttendanceRecord> records;
  final Map<String, AttendanceDayContext> context;
}

class AttendanceRepository {
  AttendanceRepository(this._dio);

  final Dio _dio;
  static final _dateFmt = DateFormat('yyyy-MM-dd');

  /// Null until we learn whether this API build has `/mobile/work-schedule/`.
  bool? _hasDedicatedScheduleEndpoint;
  HomeWorkSchedule? _homeScheduleTemplate;

  void clearScheduleCache() {
    _homeScheduleTemplate = null;
    _hasDedicatedScheduleEndpoint = null;
  }

  Future<AttendanceRangePayload> fetchMyAttendance({
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
      return _parseRange(response.data);
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  /// Assigned shift for [from]–[to]. Off days have `has_schedule: false`
  /// and null times — the API no longer invents 09:00–17:00.
  ///
  /// Prefers `GET /mobile/work-schedule/`. Older APIs 404 that path, so we
  /// reuse `work_schedule` from `GET /mobile/home/` and stamp it onto the
  /// requested week by weekday.
  Future<HomeWorkSchedule> fetchWorkSchedule({
    required DateTime from,
    required DateTime to,
  }) async {
    if (_hasDedicatedScheduleEndpoint != false) {
      try {
        final response = await _dio.get(
          '/mobile/work-schedule/',
          queryParameters: {
            'from_date': _dateFmt.format(from),
            'to_date': _dateFmt.format(to),
          },
        );
        _hasDedicatedScheduleEndpoint = true;
        final data = response.data;
        if (data is Map) {
          return HomeWorkSchedule.fromJson(Map<String, dynamic>.from(data));
        }
        throw ApiException('Unexpected work schedule response');
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) throwApi(e);
        _hasDedicatedScheduleEndpoint = false;
      }
    }
    return _scheduleFromHome(from: from, to: to);
  }

  Future<HomeWorkSchedule> _scheduleFromHome({
    required DateTime from,
    required DateTime to,
  }) async {
    var template = _homeScheduleTemplate;
    if (template == null) {
      try {
        final response = await _dio.get('/mobile/home/');
        final payload = response.data;
        if (payload is! Map) {
          throw ApiException('Unexpected home response');
        }
        final raw = payload['work_schedule'];
        if (raw is! Map) {
          throw ApiException('No work schedule assigned');
        }
        template = HomeWorkSchedule.fromJson(Map<String, dynamic>.from(raw));
        _homeScheduleTemplate = template;
      } on DioException catch (e) {
        throwApi(e);
      }
    }
    return template.projectOntoRange(
      from: from,
      to: to,
      today: template.companyToday,
    );
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

  AttendanceRangePayload _parseRange(dynamic data) {
    List<dynamic> rows = const [];
    List<dynamic> flags = const [];
    if (data is Map) {
      final results = data['results'];
      rows = results is List ? results : const [];
      final context = data['day_context'];
      flags = context is List ? context : const [];
    } else if (data is List) {
      rows = data;
    }

    final records = rows
        .whereType<Map>()
        .map((e) => AttendanceRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final context = <String, AttendanceDayContext>{};
    for (final raw in flags.whereType<Map>()) {
      final json = Map<String, dynamic>.from(raw);
      final date = DateTime.tryParse(json['date'] as String? ?? '');
      if (date == null) continue;
      context['${date.year}-${date.month}-${date.day}'] =
          AttendanceDayContext.fromJson(json);
    }
    return AttendanceRangePayload(records: records, context: context);
  }
}
