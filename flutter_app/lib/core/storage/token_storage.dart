import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              encryptedSharedPreferences: true,
              // Bootstrap treats a storage failure as signed out, so a bad
              // keystore can be wiped instead of trapping the app on splash.
              resetOnError: true,
            ),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
              synchronizable: false,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _accessKey = 'horilla_access';
  static const _refreshKey = 'horilla_refresh';
  static const _appLockKey = 'horilla_app_lock';
  static const serverUrlKey = 'horilla_server_url';

  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  Future<String?> readAccess() => _storage.read(key: _accessKey);

  Future<String?> readRefresh() => _storage.read(key: _refreshKey);

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }

  /// App lock is off unless the user has explicitly turned it on.
  Future<bool> readAppLock() async {
    try {
      return await _storage.read(key: _appLockKey) == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> writeAppLock(bool enabled) async {
    await _storage.write(key: _appLockKey, value: enabled ? 'true' : 'false');
  }

  Future<String?> readServerUrl() => _storage.read(key: serverUrlKey);

  Future<void> writeServerUrl(String url) =>
      _storage.write(key: serverUrlKey, value: url);

  Future<void> clearServerUrl() => _storage.delete(key: serverUrlKey);
}
