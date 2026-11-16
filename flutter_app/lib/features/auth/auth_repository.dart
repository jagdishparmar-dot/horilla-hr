import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/dio_client.dart';
import '../../core/storage/token_storage.dart';
import 'models.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    dio: ref.watch(dioProvider),
    storage: ref.watch(tokenStorageProvider),
  );
});

class AuthRepository {
  AuthRepository({required this._dio, required this._storage, this._logoutDio});

  final Dio _dio;
  final TokenStorage _storage;

  /// No Authorization header and no refresh interceptor. Logout only needs
  /// the refresh token in the body, so an expired access token is irrelevant.
  final Dio? _logoutDio;

  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/login/',
        data: {'username': username, 'password': password},
      );
      final data = response.data;
      if (data is! Map) {
        throw ApiException('Sign-in did not return a session. Try again.');
      }
      final json = Map<String, dynamic>.from(data);
      final access = json['access'];
      final refresh = json['refresh'];
      if (access is! String ||
          access.isEmpty ||
          refresh is! String ||
          refresh.isEmpty) {
        throw ApiException('Sign-in did not return a session. Try again.');
      }
      final session = AuthSession.fromLoginJson(json);
      await _storage.saveTokens(access: access, refresh: refresh);
      return session;
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<bool> hasSession() async {
    final access = await _storage.readAccess();
    final refresh = await _storage.readRefresh();
    return access != null &&
        access.isNotEmpty &&
        refresh != null &&
        refresh.isNotEmpty;
  }

  Future<void> logout() async {
    final owned = _logoutDio == null;
    final plain = _logoutDio ?? newPlainDio();
    try {
      final refresh = await _storage.readRefresh();
      if (refresh != null && refresh.isNotEmpty) {
        await plain.post('/auth/logout/', data: {'refresh': refresh});
      }
    } catch (_) {
      // Best-effort revoke; always clear local tokens.
    } finally {
      if (owned) plain.close();
      await clearLocalSession();
    }
  }

  Future<void> clearLocalSession() async {
    try {
      await _storage.clear();
    } catch (_) {}
  }

  /// Emails the web password-reset link. [identifier] is a username or email.
  Future<String> requestPasswordReset(String identifier) async {
    final owned = _logoutDio == null;
    final dio = _logoutDio ?? newPlainDio();
    try {
      final response = await dio.post(
        '/auth/forgot-password/',
        data: {'email': identifier},
      );
      final data = response.data;
      if (data is Map) {
        final message = data['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
      return 'If an account exists, a reset link has been sent.';
    } on DioException catch (e) {
      throwApi(e);
    } finally {
      if (owned) dio.close();
    }
  }
}
