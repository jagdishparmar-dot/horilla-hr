import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/dio_client.dart';
import 'models.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  return NotificationsRepository(ref.watch(dioProvider));
});

class NotificationsRepository {
  NotificationsRepository(this._dio);

  final Dio _dio;

  Future<List<AppNotification>> fetchAll({int pageSize = 50}) async {
    try {
      final response = await _dio.get(
        '/notifications/notifications/list/all',
        queryParameters: {'page_size': pageSize},
      );
      return _parseList(response.data);
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<AppNotification> markAsRead(int id) async {
    try {
      final response = await _dio.post('/notifications/notifications/$id/');
      return AppNotification.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<void> markAllAsRead() async {
    try {
      await _dio.post('/notifications/notifications/bulk-read/');
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _dio.delete('/notifications/notifications/$id/');
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<void> deleteAll() async {
    try {
      await _dio.delete('/notifications/notifications/bulk-delete/');
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  List<AppNotification> _parseList(dynamic data) {
    List<dynamic> rows;
    if (data is Map<String, dynamic>) {
      final results = data['results'];
      if (results is List) {
        rows = results;
      } else {
        rows = const [];
      }
    } else if (data is List) {
      rows = data;
    } else {
      rows = const [];
    }

    return rows
        .whereType<Map>()
        .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e)))
        .where((n) => !n.deleted)
        .toList();
  }
}
