import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final dioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(tokenStorageProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await storage.readAccess();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode != 401) {
          handler.next(error);
          return;
        }

        // Avoid infinite loop on refresh itself.
        final path = error.requestOptions.path;
        if (path.contains('/auth/login') || path.contains('/auth/refresh')) {
          handler.next(error);
          return;
        }

        try {
          final refresh = await storage.readRefresh();
          if (refresh == null || refresh.isEmpty) {
            await storage.clear();
            handler.next(error);
            return;
          }

          final refreshDio = Dio(
            BaseOptions(
              baseUrl: AppConfig.apiBaseUrl,
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
            ),
          );
          final refreshResponse = await refreshDio.post(
            '/auth/refresh/',
            data: {'refresh': refresh},
          );
          final data = refreshResponse.data as Map<String, dynamic>;
          final newAccess = data['access'] as String?;
          final newRefresh = data['refresh'] as String? ?? refresh;
          if (newAccess == null) {
            await storage.clear();
            handler.next(error);
            return;
          }
          await storage.saveTokens(access: newAccess, refresh: newRefresh);

          final opts = error.requestOptions;
          opts.headers['Authorization'] = 'Bearer $newAccess';
          final clone = await dio.fetch(opts);
          handler.resolve(clone);
        } catch (_) {
          await storage.clear();
          handler.next(error);
        }
      },
    ),
  );

  return dio;
});

String messageFromDio(DioException e) {
  final data = e.response?.data;
  if (data is Map) {
    final error = data['error'] ?? data['detail'] ?? data['message'];
    if (error is String && error.isNotEmpty) return error;
    if (error is List && error.isNotEmpty) return error.first.toString();

    // Django form / DRF field errors: { "field": ["msg"] }
    final parts = <String>[];
    data.forEach((key, value) {
      if (key == 'error' || key == 'detail' || key == 'message') return;
      if (value is List && value.isNotEmpty) {
        parts.add('$key: ${value.join(', ')}');
      } else if (value is String && value.isNotEmpty) {
        parts.add('$key: $value');
      }
    });
    if (parts.isNotEmpty) return parts.join('\n');
  }
  if (e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout) {
    return 'Cannot reach Horilla server. Check API_BASE_URL and that runserver is up.';
  }
  return e.message ?? 'Request failed';
}

Never throwApi(DioException e) {
  throw ApiException(messageFromDio(e), statusCode: e.response?.statusCode);
}
