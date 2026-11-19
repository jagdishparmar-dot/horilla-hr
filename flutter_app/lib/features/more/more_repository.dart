import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/dio_client.dart';
import 'more_models.dart';

final moreRepositoryProvider = Provider<MoreRepository>((ref) {
  return MoreRepository(ref.watch(dioProvider));
});

class MoreRepository {
  MoreRepository(this._dio);

  final Dio _dio;

  /// Handles both paginated (`{results: [...]}`) and bare-list responses.
  static List<Map<String, dynamic>> _rows(dynamic data) {
    final raw = data is Map ? data['results'] : data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // -- Profile --------------------------------------------------------------

  Future<ProfileBundle> fetchProfile(int employeeId) async {
    final EmployeeProfile profile;
    try {
      final response = await _dio.get('/employee/employees/$employeeId/');
      profile = EmployeeProfile.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throwApi(e);
    }

    // Work and bank details are supporting information: if either call fails
    // the profile itself is still worth showing.
    final extras = await Future.wait<Object?>([
      profile.workInfoId == null
          ? Future<Object?>.value(null)
          : _optional(() async {
              final r = await _dio.get(
                '/employee/employee-work-information/${profile.workInfoId}/',
              );
              return WorkInfo.fromJson(
                Map<String, dynamic>.from(r.data as Map),
              );
            }),
      profile.bankDetailsId == null
          ? Future<Object?>.value(null)
          : _optional(() async {
              final r = await _dio.get(
                '/employee/employee-bank-details/${profile.bankDetailsId}/',
              );
              return BankInfo.fromJson(
                Map<String, dynamic>.from(r.data as Map),
              );
            }),
    ]);
    return ProfileBundle(
      profile: profile,
      work: extras[0] as WorkInfo?,
      bank: extras[1] as BankInfo?,
    );
  }

  Future<Object?> _optional(Future<Object?> Function() call) async {
    try {
      return await call();
    } catch (_) {
      return null;
    }
  }

  /// Partial update of the caller's own record. Only the fields the server
  /// allows an employee to change are accepted.
  Future<void> updateProfile(
    int employeeId,
    Map<String, dynamic> fields,
  ) async {
    try {
      await _dio.put('/employee/employees/$employeeId/', data: fields);
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  // -- Payroll --------------------------------------------------------------

  Future<List<PayslipItem>> fetchPayslips() async {
    try {
      final response = await _dio.get(
        '/payroll/payslip/',
        queryParameters: {'page_size': 100},
      );
      final items = _rows(response.data)
          .map(PayslipItem.fromJson)
          .where((p) => p.isIssued)
          .toList();
      items.sort((a, b) => b.endDate.compareTo(a.endDate));
      return items;
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  /// The signed-in employee's expense claims. A manager's response also
  /// includes their reports, so [employeeId] is applied again here.
  Future<List<ExpenseClaim>> fetchClaims(int employeeId) async {
    try {
      final response = await _dio.get(
        '/payroll/reimbusement/',
        queryParameters: {'page_size': 100},
      );
      return claimsForEmployee(
        _rows(response.data).map(ExpenseClaim.fromJson).toList(),
        employeeId,
      );
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  /// Files a reimbursement for [employeeId]. The receipt is required.
  Future<void> fileClaim({
    required int employeeId,
    required ClaimDraft draft,
  }) async {
    if (draft.filePath.isEmpty) {
      throw ApiException('Attach the receipt before filing.');
    }
    try {
      await _dio.post(
        '/payroll/reimbusement/',
        data: FormData.fromMap({
          ...draft.fields,
          'employee_id': '$employeeId',
          'attachment': await MultipartFile.fromFile(
            draft.filePath,
            filename: draft.fileName,
          ),
        }),
        options: Options(contentType: Headers.multipartFormDataContentType),
      );
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  /// Downloads a claim receipt. Media is only served to a signed-in caller.
  Future<String> downloadClaimFile(String url) async {
    final resolved = resolveMediaUrl(url);
    if (resolved == null) throw ApiException('This receipt has no file.');
    final dir = await getTemporaryDirectory();
    final name = claimFileName(url).replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path = '${dir.path}${Platform.pathSeparator}$name';
    try {
      final response = await _dio.download(
        resolved,
        path,
        options: Options(headers: {'Accept': '*/*'}),
      );
      final type = response.headers.value('content-type') ?? '';
      if (type.startsWith('text/html') &&
          !name.toLowerCase().endsWith('.html')) {
        await File(path).delete().catchError((_) => File(path));
        throw ApiException('Your session expired. Please sign in again.');
      }
      return path;
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  /// Saves the payslip file and returns its local path.
  ///
  /// Asks for a PDF first. When the server has no PDF renderer it answers
  /// with an error, and the HTML payslip is saved instead.
  Future<String> downloadPayslip(int id) async {
    final pdf = await _downloadPayslip(id, pdf: true);
    if (pdf != null) return pdf;
    final html = await _downloadPayslip(id, pdf: false);
    if (html != null) return html;
    throw ApiException('This payslip could not be downloaded.');
  }

  Future<String?> _downloadPayslip(int id, {required bool pdf}) async {
    try {
      final response = await _dio.get<List<int>>(
        '/payroll/payslip-download/$id',
        queryParameters: pdf ? {'format': 'pdf'} : null,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Accept': pdf ? 'application/pdf' : 'text/html'},
          validateStatus: (code) => code != null && code < 600,
        ),
      );
      final status = response.statusCode;
      if (status == 403) {
        throw ApiException(
          "You don't have permission to do that.",
          statusCode: 403,
        );
      }
      if (status == 404) {
        throw ApiException('This payslip could not be found.', statusCode: 404);
      }
      final kind = payslipFileKind(
        statusCode: status,
        contentType: response.headers.value('content-type'),
      );
      final bytes = response.data;
      if (kind == null || bytes == null || bytes.isEmpty) return null;
      if (pdf && kind != PayslipFileKind.pdf) return null;
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}${Platform.pathSeparator}${payslipFileName(id, kind)}';
      await File(path).writeAsBytes(bytes, flush: true);
      return path;
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  /// The signed-in employee's contracts. A payroll admin's list is the whole
  /// company, so [employeeId] is sent and applied again on the result.
  Future<List<ContractItem>> fetchContracts(int employeeId) async {
    try {
      final response = await _dio.get(
        '/payroll/contract/',
        queryParameters: {'page_size': 100, 'employee_id': employeeId},
      );
      return contractsForEmployee(
        _rows(response.data).map(ContractItem.fromJson).toList(),
        employeeId,
      );
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  /// Downloads a contract file the media server only gives to signed-in callers.
  Future<String> downloadContractFile(ContractItem contract) async {
    final url = resolveMediaUrl(contract.documentUrl);
    if (url == null) throw ApiException('No file is attached.');
    final dir = await getTemporaryDirectory();
    final leaf = url.split('/').last.split('?').first;
    final safe = leaf.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final name = safe.isEmpty ? 'contract-${contract.id}' : safe;
    final path = '${dir.path}${Platform.pathSeparator}${contract.id}_$name';
    try {
      final response = await _dio.download(
        url,
        path,
        options: Options(headers: {'Accept': '*/*'}),
      );
      final type = response.headers.value('content-type') ?? '';
      if (type.startsWith('text/html') &&
          !name.toLowerCase().endsWith('.html')) {
        await File(path).delete().catchError((_) => File(path));
        throw ApiException('Your session expired. Please sign in again.');
      }
      return path;
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  // -- Policies -------------------------------------------------------------

  Future<List<PolicyItem>> fetchPolicies() async {
    try {
      final response = await _dio.get(
        '/employee/policies/',
        queryParameters: {'page_size': 100},
      );
      return _rows(response.data).map(PolicyItem.fromJson).toList();
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  // -- Help desk ------------------------------------------------------------

  Future<List<TicketItem>> fetchTickets() async {
    try {
      final response = await _dio.get(
        '/helpdesk/ticket/',
        queryParameters: {'page_size': 100},
      );
      final items = _rows(response.data).map(TicketItem.fromJson).toList();
      items.sort((a, b) {
        if (a.status.isOpen != b.status.isOpen) return a.status.isOpen ? -1 : 1;
        return b.id.compareTo(a.id);
      });
      return items;
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<List<TicketTypeItem>> fetchTicketTypes() async {
    try {
      final response = await _dio.get(
        '/helpdesk/ticket-type/',
        queryParameters: {'page_size': 100},
      );
      return _rows(response.data).map(TicketTypeItem.fromJson).toList();
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<List<TicketDepartment>> fetchTicketDepartments() async {
    try {
      final response = await _dio.get(
        '/helpdesk/department-manager/',
        queryParameters: {'page_size': 100},
      );
      final seen = <int>{};
      final departments = <TicketDepartment>[];
      for (final row in _rows(response.data)) {
        final dept = row['department'];
        if (dept is! Map) continue;
        final id = dept['id'] is int ? dept['id'] as int : null;
        final name = dept['department']?.toString();
        if (id == null || name == null || !seen.add(id)) continue;
        final manager = row['manager'];
        departments.add(
          TicketDepartment(
            id: id,
            name: name,
            managerName: manager is Map
                ? manager['get_full_name']?.toString()
                : null,
          ),
        );
      }
      departments.sort((a, b) => a.name.compareTo(b.name));
      return departments;
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<TicketItem> createTicket({
    required String title,
    required String description,
    required int ticketTypeId,
    required int departmentId,
    required String priority,
  }) async {
    try {
      final response = await _dio.post(
        '/helpdesk/ticket/',
        data: {
          'title': title,
          'description': description,
          'ticket_type_id': ticketTypeId,
          'priority': priority,
          'assigning_type': 'department',
          'raised_on': departmentId.toString(),
        },
      );
      return TicketItem.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<List<TicketComment>> fetchComments(int ticketId) async {
    try {
      final response = await _dio.get(
        '/helpdesk/ticket/$ticketId/comment/',
        queryParameters: {'page_size': 100},
      );
      final items = _rows(response.data).map(TicketComment.fromJson).toList();
      items.sort((a, b) {
        final left = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
        final right = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
        return left.compareTo(right);
      });
      return items;
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<void> addComment(int ticketId, String text) async {
    try {
      await _dio.post(
        '/helpdesk/ticket/$ticketId/comment/',
        data: {'comment': text},
      );
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<List<FaqItem>> fetchFaqs() async {
    try {
      final response = await _dio.get(
        '/helpdesk/faq/',
        queryParameters: {'page_size': 100},
      );
      return _rows(response.data).map(FaqItem.fromJson).toList();
    } on DioException catch (e) {
      throwApi(e);
    }
  }
}
