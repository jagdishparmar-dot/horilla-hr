import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  AuthRepository({required this._dio, required this._storage});

  final Dio _dio;
  final TokenStorage _storage;

  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/login/',
        data: {'username': username, 'password': password},
      );
      final session = AuthSession.fromLoginJson(
        response.data as Map<String, dynamic>,
      );
      await _storage.saveTokens(
        access: session.access,
        refresh: session.refresh,
      );
      return session;
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<bool> hasSession() async {
    final access = await _storage.readAccess();
    return access != null && access.isNotEmpty;
  }

  Future<void> logout() async {
    try {
      final refresh = await _storage.readRefresh();
      if (refresh != null) {
        await _dio.post('/auth/logout/', data: {'refresh': refresh});
      }
    } catch (_) {
      // Best-effort revoke; always clear local tokens.
    } finally {
      await _storage.clear();
    }
  }
}
