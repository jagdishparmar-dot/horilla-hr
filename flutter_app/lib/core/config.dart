/// Horilla API configuration.
///
/// Android emulator → host machine: `http://10.0.2.2:8000`
/// iOS simulator → `http://127.0.0.1:8000`
/// Physical device → your LAN IP, e.g. `http://192.168.1.10:8000`
class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    // Physical device / LAN default. Emulator: --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
    defaultValue: 'http://10.118.201.152:8000/api/v1',
  );

  /// Origin without `/api/v1` — used to resolve relative media URLs.
  static String get mediaOrigin {
    final uri = Uri.parse(apiBaseUrl);
    final path = uri.path.replaceAll(RegExp(r'/api/v1/?$'), '');
    return uri.replace(path: path.isEmpty ? '' : path).toString().replaceAll(RegExp(r'/$'), '');
  }
}
