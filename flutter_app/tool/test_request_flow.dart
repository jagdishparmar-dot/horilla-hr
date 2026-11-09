/// Easy CLI smoke test for the mobile request flow (same repos the app uses).
///
/// ```
/// cd flutter_app
/// dart run tool/test_request_flow.dart
/// # or override host / credentials:
/// dart run tool/test_request_flow.dart ^
///   --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1 ^
///   --dart-define=TEST_USERNAME=jagdish.parmar@shreemaruti.com ^
///   --dart-define=TEST_PASSWORD=Demo@12345
/// ```
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:horilla_employee/core/config.dart';
import 'package:horilla_employee/features/attendance/attendance_repository.dart';
import 'package:horilla_employee/features/requests/requests_repository.dart';
import 'package:intl/intl.dart';

const _username = String.fromEnvironment(
  'TEST_USERNAME',
  defaultValue: 'jagdish.parmar@shreemaruti.com',
);
const _password = String.fromEnvironment(
  'TEST_PASSWORD',
  defaultValue: 'Demo@12345',
);

Future<void> main() async {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  stdout.writeln('API: ${AppConfig.apiBaseUrl}');
  stdout.writeln('User: $_username');

  final login = await dio.post(
    '/auth/login/',
    data: {'username': _username, 'password': _password},
  );
  final loginData = login.data as Map<String, dynamic>;
  final access = loginData['access'] as String;
  final employeeId = (loginData['employee'] as Map)['id'] as int;
  dio.options.headers['Authorization'] = 'Bearer $access';
  stdout.writeln('OK login employeeId=$employeeId');

  final requests = RequestsRepository(dio);
  final attendance = AttendanceRepository(dio);

  final balances = await requests.fetchBalances();
  stdout.writeln(
    'OK balances (${balances.length}): '
    '${balances.map((b) => '${b.name}:${b.available}').join(', ')}',
  );

  final list = await requests.fetchRequests();
  stdout.writeln('OK leave list (${list.length})');

  final type = balances.firstWhere(
    (b) => b.available > 0,
    orElse: () => balances.first,
  );
  final start = DateTime.now().add(const Duration(days: 32));
  late final int leaveId;
  try {
    final created = await requests.createLeaveRequest(
      leaveTypeId: type.leaveTypeId,
      startDate: start,
      endDate: start,
      description: 'Flutter dart-run request-flow test',
    );
    leaveId = created.id;
    stdout.writeln('OK leave create #$leaveId via repository JSON');
  } catch (e) {
    final dateFmt = DateFormat('yyyy-MM-dd');
    final form = FormData.fromMap({
      'leave_type_id': type.leaveTypeId,
      'start_date': dateFmt.format(start),
      'end_date': dateFmt.format(start),
      'start_date_breakdown': 'full_day',
      'end_date_breakdown': 'full_day',
      'description': 'Flutter dart-run request-flow test (multipart)',
      'attachment': MultipartFile.fromBytes(
        Uint8List.fromList(
          '%PDF-1.1\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n'.codeUnits,
        ),
        filename: 'note.pdf',
      ),
    });
    final response = await dio.post('/leave/user-request/', data: form);
    leaveId = (response.data as Map)['id'] as int;
    stdout.writeln('OK leave create #$leaveId via multipart ($e)');
  }

  final detail = await requests.fetchRequestDetail(leaveId);
  stdout.writeln(
    'OK leave detail #${detail.id} ${detail.title} ${detail.status.label}',
  );

  final now = DateTime.now();
  final rows = await attendance.fetchMyAttendance(
    from: now.subtract(const Duration(days: 40)),
    to: now.add(const Duration(days: 1)),
  );
  final withShift = rows.records.where((r) => r.shiftId != null && r.workTypeId != null);
  final target = withShift.isNotEmpty ? withShift.first : rows.records.first;
  if (target.shiftId == null) {
    stderr.writeln('FAIL no shift_id on attendance rows');
    exitCode = 1;
    return;
  }

  final createDate = DateTime(now.year, now.month, now.day)
      .subtract(const Duration(days: 13));
  await attendance.submitAttendanceCorrection(
    employeeId: employeeId,
    attendanceDate: createDate,
    clockInDate: createDate,
    clockIn: '09:30',
    clockOutDate: createDate,
    clockOut: '18:00',
    workedHour: '08:30',
    minimumHour: '08:00',
    description: 'Flutter dart-run attendance create',
    shiftId: target.shiftId,
    workTypeId: target.workTypeId ?? 1,
  );
  stdout.writeln(
    'OK attendance create ${DateFormat('yyyy-MM-dd').format(createDate)}',
  );

  await attendance.submitAttendanceCorrection(
    employeeId: employeeId,
    attendanceDate: target.date,
    clockInDate: target.date,
    clockIn: '09:15',
    clockOutDate: target.date,
    clockOut: '18:15',
    workedHour: '09:00',
    minimumHour: target.minimumHour?.substring(0, 5) ?? '08:00',
    description: 'Flutter dart-run attendance update',
    shiftId: target.shiftId,
    workTypeId: target.workTypeId ?? 1,
    existingAttendanceId: target.id,
  );
  stdout.writeln('OK attendance update #${target.id}');

  final home = await dio.get('/mobile/home/');
  final recent = (home.data as Map)['recent_requests'] as List? ?? [];
  stdout.writeln('OK home recent_requests=${recent.length}');
  for (final row in recent.take(5)) {
    stdout.writeln('  $row');
  }

  stdout.writeln('\nAll request-flow checks passed.');
}
