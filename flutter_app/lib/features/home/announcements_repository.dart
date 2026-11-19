import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/dio_client.dart';
import 'announcement_models.dart';

final announcementsRepositoryProvider = Provider<AnnouncementsRepository>((
  ref,
) {
  return AnnouncementsRepository(ref.watch(dioProvider));
});

final announcementsProvider =
    FutureProvider.autoDispose<List<AnnouncementItem>>((ref) {
      return ref.watch(announcementsRepositoryProvider).fetchAll();
    });

final announcementDetailProvider = FutureProvider.autoDispose
    .family<AnnouncementItem, int>((ref, id) {
      return ref.watch(announcementsRepositoryProvider).fetchDetail(id);
    });

class AnnouncementsRepository {
  AnnouncementsRepository(this._dio);

  final Dio _dio;

  /// Audience-scoped announcements, newest first, across every page.
  Future<List<AnnouncementItem>> fetchAll() async {
    final items = <AnnouncementItem>[];
    var page = 1;
    while (page <= 20) {
      final AnnouncementPage parsed;
      try {
        final response = await _dio.get(
          '/base/announcement-view',
          queryParameters: {'page': page, 'page_size': 50},
        );
        parsed = AnnouncementPage.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
      } on DioException catch (e) {
        throwApi(e);
      }
      items.addAll(parsed.items);
      if (!parsed.hasNext) break;
      page++;
    }
    return items;
  }

  /// Full announcement. The server marks it viewed when this succeeds.
  Future<AnnouncementItem> fetchDetail(int id) async {
    try {
      final response = await _dio.get('/base/announcement-view/$id');
      return AnnouncementItem.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throwApi(e);
    }
  }
}
