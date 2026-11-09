import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/dio_client.dart';
import 'directory_models.dart';

final directoryRepositoryProvider = Provider<DirectoryRepository>((ref) {
  return DirectoryRepository(ref.watch(dioProvider));
});

class DirectoryRepository {
  DirectoryRepository(this._dio);

  final Dio _dio;

  static const pageSize = 30;

  Future<DirectoryPage> fetchPage({
    int page = 1,
    String search = '',
    int? departmentId,
  }) async {
    try {
      final response = await _dio.get(
        '/employee/directory/',
        queryParameters: {
          'page': page,
          'page_size': pageSize,
          if (search.trim().isNotEmpty) 'search': search.trim(),
          'department': ?departmentId,
        },
      );
      return DirectoryPage.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<DirectoryDetail> fetchDetail(int id) async {
    try {
      final response = await _dio.get('/employee/directory/$id/');
      return DirectoryDetail.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<WorkSiteInfo> fetchMyWorkSite() async {
    try {
      final response = await _dio.get('/mobile/work-site/');
      return WorkSiteInfo.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throwApi(e);
    }
  }
}

final directoryDetailProvider = FutureProvider.autoDispose
    .family<DirectoryDetail, int>((ref, id) {
      return ref.watch(directoryRepositoryProvider).fetchDetail(id);
    });

final myWorkSiteProvider = FutureProvider.autoDispose<WorkSiteInfo>((ref) {
  return ref.watch(directoryRepositoryProvider).fetchMyWorkSite();
});
