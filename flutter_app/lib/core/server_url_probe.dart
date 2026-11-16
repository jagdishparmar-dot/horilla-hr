import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config.dart';

const probeTimeout = Duration(seconds: 8);

/// Confirms [apiBaseUrl] is a reachable ClockMe host before it is stored.
///
/// Hits `{origin}/health/`, which is unauthenticated and identifies the
/// product. Throws [FormatException] with a short user-facing message.
Future<void> probeClockMeServer(String apiBaseUrl, {Dio? dio}) async {
  final origin = ServerUrl.mediaOrigin(apiBaseUrl);
  final owned = dio == null;
  final client =
      dio ??
      Dio(
        BaseOptions(
          baseUrl: origin,
          connectTimeout: probeTimeout,
          receiveTimeout: probeTimeout,
          headers: const {'Accept': 'application/json'},
        ),
      );
  client.options.baseUrl = origin;
  try {
    final response = await client.get<dynamic>('/health/');
    if (_isClockMeHealth(response.statusCode, response.data)) return;
    throw const FormatException('That address is not a ClockMe server.');
  } on FormatException {
    rethrow;
  } on DioException catch (e) {
    if (_isOffline(e)) {
      throw const FormatException(
        'Cannot reach that server. Check the address and try again.',
      );
    }
    throw const FormatException('That address is not a ClockMe server.');
  } finally {
    if (owned) client.close();
  }
}

bool _isClockMeHealth(int? statusCode, Object? data) {
  if (statusCode != 200 || data is! Map) return false;
  return data['product']?.toString().toLowerCase() == 'clockme';
}

bool _isOffline(DioException e) {
  return e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      (e.type == DioExceptionType.unknown && e.response == null);
}

final serverUrlProbeProvider =
    Provider<Future<void> Function(String apiBaseUrl)>(
      (ref) => probeClockMeServer,
    );
