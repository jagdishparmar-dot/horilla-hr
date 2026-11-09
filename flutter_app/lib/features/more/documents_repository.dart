import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/dio_client.dart';
import '../home/home_provider.dart';
import 'documents_models.dart';
import 'more_models.dart';

final documentsRepositoryProvider = Provider<DocumentsRepository>((ref) {
  return DocumentsRepository(ref.watch(dioProvider));
});

/// The signed-in employee's documents, each joined with the rules HR set.
final documentsProvider = FutureProvider.autoDispose<List<DocumentEntry>>((
  ref,
) async {
  final home = await ref.watch(mobileHomeProvider.future);
  final id = home.employeeId;
  if (id == null) {
    throw Exception('Your account is not linked to an employee record.');
  }
  return ref.watch(documentsRepositoryProvider).fetch(id);
});

class DocumentsRepository {
  DocumentsRepository(this._dio);

  final Dio _dio;

  static List<Map<String, dynamic>> _rows(dynamic data) {
    final raw = data is Map ? data['results'] : data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<DocumentEntry>> fetch(int employeeId) async {
    final List<DocumentItem> documents;
    try {
      final response = await _dio.get(
        '/employee/documents/',
        queryParameters: {'page_size': 100},
      );
      // A manager's list also carries their team's documents; this screen is
      // strictly the caller's own.
      documents = _rows(response.data)
          .where((row) => row['employee_id']?.toString() == '$employeeId')
          .map(DocumentItem.fromJson)
          .toList();
    } on DioException catch (e) {
      throwApi(e);
    }

    // The rules (format, size limit, description) are a nicety: if this call
    // fails the documents themselves are still listed.
    final requirements = <int, DocumentRequirement>{};
    try {
      final response = await _dio.get(
        '/employee/document-request/',
        queryParameters: {'page_size': 100},
      );
      for (final row in _rows(response.data)) {
        final item = DocumentRequirement.fromJson(row);
        requirements[item.id] = item;
      }
    } on DioException {
      // Intentionally ignored.
    }

    final entries = documents
        .map(
          (d) => DocumentEntry(
            document: d,
            requirement: d.requestId == null ? null : requirements[d.requestId],
          ),
        )
        .toList();

    // Anything waiting on the employee first, then newest.
    int rank(DocumentItem d) => switch (d.state) {
      DocumentState.rejected => 0,
      DocumentState.upload => 1,
      DocumentState.review => 2,
      DocumentState.approved => 3,
    };
    entries.sort((a, b) {
      final byRank = rank(a.document).compareTo(rank(b.document));
      if (byRank != 0) return byRank;
      return b.document.id.compareTo(a.document.id);
    });
    return entries;
  }

  /// `PUT /employee/documents/<id>/` with the picked file. Status stays the
  /// server's decision - the app never sends one.
  Future<void> upload(DocumentItem document, XFile file) async {
    final path = file.path;
    if (path.isEmpty) {
      throw ApiException("Couldn't read that file. Please pick it again.");
    }
    try {
      await _dio.put(
        '/employee/documents/${document.id}/',
        data: FormData.fromMap({
          'title': document.title,
          'document': await MultipartFile.fromFile(path, filename: file.name),
        }),
        options: Options(contentType: Headers.multipartFormDataContentType),
      );
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  /// Downloads the file (media is served to signed-in callers only) and
  /// returns the local path to hand to the system viewer.
  Future<String> download(DocumentItem document) async {
    final url = resolveMediaUrl(document.fileUrl);
    if (url == null) throw ApiException('This document has no file yet.');
    final dir = await getTemporaryDirectory();
    final safeName = document.fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final target =
        '${dir.path}${Platform.pathSeparator}${document.id}_$safeName';
    try {
      final response = await _dio.download(
        url,
        target,
        options: Options(headers: {'Accept': '*/*'}),
      );
      final type = response.headers.value('content-type') ?? '';
      if (type.startsWith('text/html') &&
          !safeName.toLowerCase().endsWith('.html')) {
        // An expired session is answered with the login page, not the file.
        await File(target).delete().catchError((_) => File(target));
        throw ApiException('Your session expired. Please sign in again.');
      }
      return target;
    } on DioException catch (e) {
      throwApi(e);
    }
  }
}
