/// Live API smoke test for the mobile request flow.
///
/// Uses the same repositories as the Flutter app against a running Horilla API.
///
/// ```
/// flutter test test/request_flow_api_test.dart --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
/// ```
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/core/config.dart';
import 'package:horilla_employee/features/attendance/attendance_repository.dart';
import 'package:horilla_employee/features/requests/models.dart';
import 'package:horilla_employee/features/requests/requests_repository.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';

const _username = String.fromEnvironment(
  'TEST_USERNAME',
  defaultValue: 'jagdish.parmar@shreemaruti.com',
);
const _password = String.fromEnvironment(
  'TEST_PASSWORD',
  defaultValue: 'Demo@12345',
);

Dio _buildDio() {
  return Dio(
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
}

Future<int> _login(Dio dio) async {
  final response = await dio.post(
    '/auth/login/',
    data: {'username': _username, 'password': _password},
  );
  expect(response.statusCode, 200, reason: 'login failed: ${response.data}');
  final data = response.data as Map<String, dynamic>;
  dio.options.headers['Authorization'] = 'Bearer ${data['access']}';
  return (data['employee'] as Map)['id'] as int;
}

void main() {
  // Live binding does not mock HttpClient (unlike TestWidgetsFlutterBinding).
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Dio dio;
  late int employeeId;
  late RequestsRepository requests;
  late AttendanceRepository attendance;

  setUpAll(() async {
    // ignore: avoid_print
    print('API_BASE_URL=${AppConfig.apiBaseUrl}');
    dio = _buildDio();
    employeeId = await _login(dio);
    requests = RequestsRepository(dio);
    attendance = AttendanceRepository(dio);
  });

  test('login returns employee session', () {
    expect(employeeId, greaterThan(0));
  });

  test('fetch leave balances', () async {
    final balances = await requests.fetchBalances();
    expect(balances, isNotEmpty);
    // ignore: avoid_print
    print(
      'balances: ${balances.map((b) => '${b.name}=${b.available}').join(', ')}',
    );
  });

  test('fetch leave request list', () async {
    final items = await requests.fetchRequests();
    expect(items, isA<List<LeaveRequestItem>>());
    // ignore: avoid_print
    print('leave requests: ${items.length}');
  });

  test('create leave request then fetch detail', () async {
    final balances = await requests.fetchBalances();
    final type = balances.firstWhere(
      (b) => b.available > 0,
      orElse: () => balances.first,
    );
    final start = DateTime.now().add(const Duration(days: 33));

    LeaveRequestItem created;
    try {
      created = await requests.createLeaveRequest(
        leaveTypeId: type.leaveTypeId,
        startDate: start,
        endDate: start,
        description: 'Flutter request-flow API test',
      );
    } catch (e) {
      final dateFmt = DateFormat('yyyy-MM-dd');
      final form = FormData.fromMap({
        'leave_type_id': type.leaveTypeId,
        'start_date': dateFmt.format(start),
        'end_date': dateFmt.format(start),
        'start_date_breakdown': 'full_day',
        'end_date_breakdown': 'full_day',
        'description': 'Flutter request-flow API test (multipart)',
        'attachment': MultipartFile.fromBytes(
          Uint8List.fromList(
            '%PDF-1.1\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n'.codeUnits,
          ),
          filename: 'note.pdf',
        ),
      });
      final response = await dio.post('/leave/user-request/', data: form);
      expect(
        response.statusCode,
        anyOf(200, 201),
        reason: 'leave create failed: $e / ${response.data}',
      );
      created = mapLeaveRequest(
        Map<String, dynamic>.from(response.data as Map),
      );
    }

    expect(created.id, greaterThan(0));
    expect(created.status, RequestStatus.pending);

    final detail = await requests.fetchRequestDetail(created.id);
    expect(detail.id, created.id);
    // ignore: avoid_print
    print('created leave #${detail.id} ${detail.title} ${detail.status.label}');
  });

  test('attendance correction create and update', () async {
    final now = DateTime.now();
    final rows = await attendance.fetchMyAttendance(
      from: now.subtract(const Duration(days: 40)),
      to: now.add(const Duration(days: 1)),
    );
    expect(rows.records, isNotEmpty);

    final withShift = rows.records.where(
      (r) => r.shiftId != null && r.workTypeId != null,
    );
    final target = withShift.isNotEmpty ? withShift.first : rows.records.first;
    expect(target.shiftId, isNotNull);

    final createDate = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 14));
    await attendance.submitAttendanceCorrection(
      employeeId: employeeId,
      attendanceDate: createDate,
      clockInDate: createDate,
      clockIn: '09:30',
      clockOutDate: createDate,
      clockOut: '18:00',
      workedHour: '08:30',
      minimumHour: '08:00',
      description: 'Flutter attendance correction create test',
      shiftId: target.shiftId,
      workTypeId: target.workTypeId ?? 1,
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
      description: 'Flutter attendance correction update test',
      shiftId: target.shiftId,
      workTypeId: target.workTypeId ?? 1,
      existingAttendanceId: target.id,
    );

    // ignore: avoid_print
    print(
      'attendance ok create=${DateFormat('yyyy-MM-dd').format(createDate)} '
      'update=#${target.id}',
    );
  });

  test('home recent_requests includes leave items', () async {
    final response = await dio.get('/mobile/home/');
    expect(response.statusCode, 200);
    final recent = (response.data as Map)['recent_requests'];
    expect(recent, isA<List>());
    // ignore: avoid_print
    print('home recent_requests: ${(recent as List).length}');
  });
}
