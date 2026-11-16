import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_revocation.dart';
import '../config.dart';
import '../server_url_provider.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

export '../storage/token_storage.dart' show TokenStorage, tokenStorageProvider;

const _connectTimeout = Duration(seconds: 20);
const _receiveTimeout = Duration(seconds: 30);

/// Bumped after a refresh saves a new access token so cached Bearer headers
/// are rebuilt.
final accessGenerationProvider = StateProvider<int>((ref) => 0);

final dioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(tokenStorageProvider);
  final revocation = ref.watch(sessionRevocationProvider);
  final baseUrl = ref.watch(
    serverUrlProvider.select((state) => state.apiBaseUrl),
  );
  if (baseUrl == null || baseUrl.isEmpty) {
    throw StateError('Server URL is not configured');
  }
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: _connectTimeout,
      receiveTimeout: _receiveTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  installAuthInterceptor(
    dio: dio,
    storage: storage,
    onSessionRevoked: revocation.notify,
    onAccessRefreshed: () {
      ref.read(accessGenerationProvider.notifier).state =
          ref.read(accessGenerationProvider) + 1;
    },
    refreshDioFactory: () => newPlainDio(baseUrl: baseUrl),
  );

  return dio;
});

/// Dio with the same timeouts as the API client and no auth interceptor.
Dio newPlainDio({String? baseUrl}) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl ?? AppConfig.apiBaseUrl,
      connectTimeout: _connectTimeout,
      receiveTimeout: _receiveTimeout,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );
}

/// Attaches Bearer auth and a single-flight refresh on 401.
@visibleForTesting
void installAuthInterceptor({
  required Dio dio,
  required TokenStorage storage,
  required void Function() onSessionRevoked,
  Dio Function()? refreshDioFactory,
  void Function()? onAccessRefreshed,
}) {
  final coordinator = _RefreshCoordinator(
    storage: storage,
    onSessionRevoked: onSessionRevoked,
    refreshDioFactory: refreshDioFactory,
    onAccessRefreshed: onAccessRefreshed,
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
        if (!_shouldRefresh(error)) {
          handler.next(error);
          return;
        }

        try {
          final access = await coordinator.resolve(error.requestOptions);
          if (access == null || access.isEmpty) {
            handler.next(error);
            return;
          }

          final opts = error.requestOptions;
          opts.extra['authRetried'] = true;
          opts.headers['Authorization'] = 'Bearer $access';
          final clone = await dio.fetch(opts);
          handler.resolve(clone);
        } on DioException catch (e) {
          handler.next(e);
        } catch (_) {
          handler.next(error);
        }
      },
    ),
  );
}

bool _shouldRefresh(DioException error) {
  if (error.response?.statusCode != 401) return false;
  if (error.requestOptions.extra['authRetried'] == true) return false;
  final path = error.requestOptions.path;
  if (path.contains('/auth/login') ||
      path.contains('/auth/refresh') ||
      path.contains('/auth/logout')) {
    return false;
  }
  return true;
}

class _RefreshCoordinator {
  _RefreshCoordinator({
    required this.storage,
    required this.onSessionRevoked,
    this.refreshDioFactory,
    this.onAccessRefreshed,
  });

  final TokenStorage storage;
  final void Function() onSessionRevoked;
  final Dio Function()? refreshDioFactory;
  final void Function()? onAccessRefreshed;

  Future<String?>? _inFlight;

  Future<String?> resolve(RequestOptions failed) async {
    final pending = _inFlight;
    if (pending != null) return pending;

    final current = await storage.readAccess();
    final started = _inFlight;
    if (started != null) return started;

    final failedAuth = failed.headers['Authorization']?.toString();
    if (current != null &&
        current.isNotEmpty &&
        failedAuth != null &&
        failedAuth != 'Bearer $current') {
      return current;
    }
    return _start();
  }

  Future<String?> _start() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _perform();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<String?> _perform() async {
    final refresh = await storage.readRefresh();
    if (refresh == null || refresh.isEmpty) {
      await _wipe();
      return null;
    }

    final createdHere = refreshDioFactory == null;
    final refreshDio = refreshDioFactory?.call() ?? newPlainDio();
    try {
      final response = await refreshDio.post(
        '/auth/refresh/',
        data: {'refresh': refresh},
      );
      final data = response.data;
      if (data is! Map) {
        await _wipe();
        return null;
      }
      final newAccess = data['access'];
      final newRefresh = data['refresh'];
      // Rotation blacklists the refresh we just sent. A body without a new
      // refresh string is a failed rotation, not a reason to keep the old one.
      if (newAccess is! String ||
          newAccess.isEmpty ||
          newRefresh is! String ||
          newRefresh.isEmpty) {
        await _wipe();
        return null;
      }
      try {
        await storage.saveTokens(access: newAccess, refresh: newRefresh);
      } catch (_) {
        await _wipe();
        return null;
      }
      onAccessRefreshed?.call();
      return newAccess;
    } on DioException catch (e) {
      if (_refreshRejected(e)) {
        await _wipe();
      }
      return null;
    } finally {
      if (createdHere) refreshDio.close();
    }
  }

  bool _refreshRejected(DioException e) {
    final code = e.response?.statusCode;
    return code == 401 || code == 403;
  }

  Future<void> _wipe() async {
    try {
      await storage.clear();
    } catch (_) {
      // Still leave the shell: the refresh token is already unusable.
    }
    onSessionRevoked();
  }
}

String? _plainServerMessage(Object? data) {
  if (data is! Map) return null;
  final error = data['error'] ?? data['detail'] ?? data['message'];
  if (error is String && error.trim().isNotEmpty) return error.trim();
  if (error is List && error.isNotEmpty) {
    final first = error.first;
    if (first is String && first.trim().isNotEmpty) return first.trim();
  }

  // Django form / DRF field errors: { "field": ["msg"] }
  final parts = <String>[];
  data.forEach((key, value) {
    if (key == 'error' || key == 'detail' || key == 'message') return;
    if (value is List && value.isNotEmpty) {
      final texts = value.whereType<String>().where((item) => item.isNotEmpty);
      if (texts.isNotEmpty) parts.add('$key: ${texts.join(', ')}');
    } else if (value is String && value.isNotEmpty) {
      parts.add('$key: $value');
    }
  });
  if (parts.isNotEmpty) return parts.join('\n');
  return null;
}

String messageFromDio(DioException e) {
  final server = _plainServerMessage(e.response?.data);
  if (server != null) return server;

  final code = e.response?.statusCode;
  final offline =
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      (e.type == DioExceptionType.unknown && e.response == null);
  if (offline) {
    return 'Cannot reach the server. Check your connection and try again.';
  }
  if (code == 401) {
    if (e.requestOptions.path.contains('/auth/login')) {
      return 'Those credentials were not accepted.';
    }
    return 'Your session expired. Please sign in again.';
  }
  if (code == 403) return "You don't have permission to do that.";
  if (code == 429) return 'Too many attempts. Wait a moment and try again.';
  return 'Something went wrong. Please try again.';
}

/// Short copy for snackbars and error panels. Never returns a Dio dump.
String userFacingError(Object error) {
  if (error is DioException) return messageFromDio(error);
  if (error is ApiException) return error.message;
  var text = error.toString().trim();
  const prefix = 'Exception: ';
  if (text.startsWith(prefix)) text = text.substring(prefix.length).trim();
  if (text.startsWith('DioException') ||
      text.contains('API_BASE_URL') ||
      text.contains('runserver')) {
    return 'Cannot reach the server. Check your connection and try again.';
  }
  if (text.isEmpty || text.contains('StackTrace')) {
    return 'Something went wrong. Please try again.';
  }
  return text;
}

Never throwApi(DioException e) {
  throw ApiException(messageFromDio(e), statusCode: e.response?.statusCode);
}
