/// ClockMe API configuration.
///
/// The live base URL is stored on device and applied at startup. CLI / live
/// API tests may still pass `--dart-define=API_BASE_URL=...`.
class AppConfig {
  AppConfig._();

  static const definedApiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String? _runtimeApiBaseUrl;

  /// Last applied API root, used by Dio and relative media URLs.
  static String get apiBaseUrl {
    final runtime = _runtimeApiBaseUrl;
    if (runtime != null && runtime.isNotEmpty) return runtime;
    if (definedApiBaseUrl.isNotEmpty) {
      return ServerUrl.normalize(definedApiBaseUrl);
    }
    throw StateError('Server URL is not configured');
  }

  static bool get isConfigured {
    final runtime = _runtimeApiBaseUrl;
    if (runtime != null && runtime.isNotEmpty) return true;
    return definedApiBaseUrl.isNotEmpty;
  }

  /// Origin without `/api/v1` — used to resolve relative media URLs.
  static String get mediaOrigin {
    if (!isConfigured) return '';
    return ServerUrl.mediaOrigin(apiBaseUrl);
  }

  static void apply(String apiBaseUrl) {
    _runtimeApiBaseUrl = apiBaseUrl;
  }

  static void clear() {
    _runtimeApiBaseUrl = null;
  }
}

/// Parse, trim, and normalize a ClockMe server address to an `/api/v1` root.
class ServerUrl {
  ServerUrl._();

  static const apiSuffix = '/api/v1';

  /// Returns a canonical `http(s)://host[:port]/api/v1` URL.
  ///
  /// Throws [FormatException] with a short, user-facing [FormatException.message].
  static String normalize(String raw) {
    var text = raw.trim();
    if (text.isEmpty) {
      throw const FormatException('Enter your server address.');
    }
    text = text.replaceAll(RegExp(r'\s+'), '');
    if (!text.contains('://')) {
      text = 'https://$text';
    }

    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) {
      throw const FormatException('That does not look like a valid address.');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const FormatException('Use http:// or https://');
    }
    if (uri.userInfo.isNotEmpty) {
      throw const FormatException('Do not include a username in the address.');
    }

    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (!_hasApiSuffix(path)) {
      path = '$path$apiSuffix';
    }

    return Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      port: uri.hasPort ? uri.port : null,
      path: path,
    ).toString();
  }

  static bool isValid(String raw) {
    try {
      normalize(raw);
      return true;
    } on FormatException {
      return false;
    }
  }

  static String mediaOrigin(String apiBaseUrl) {
    final uri = Uri.parse(apiBaseUrl);
    final path = uri.path.replaceAll(RegExp(r'/api/v1/?$'), '');
    return uri
        .replace(path: path.isEmpty ? '' : path)
        .toString()
        .replaceAll(RegExp(r'/$'), '');
  }

  /// User-facing host, without the `/api/v1` suffix the client appends.
  static String display(String? apiBaseUrl) {
    if (apiBaseUrl == null || apiBaseUrl.trim().isEmpty) return '';
    try {
      return mediaOrigin(normalize(apiBaseUrl));
    } on FormatException {
      return apiBaseUrl.trim();
    }
  }

  static bool _hasApiSuffix(String path) =>
      path == apiSuffix || path.endsWith(apiSuffix);
}
