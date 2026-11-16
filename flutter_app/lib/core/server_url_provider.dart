import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config.dart';
import 'server_url_probe.dart';
import 'storage/token_storage.dart';

class ServerUrlState {
  const ServerUrlState({
    required this.loaded,
    this.apiBaseUrl,
    this.error,
    this.storageError = false,
  });

  final bool loaded;
  final String? apiBaseUrl;
  final String? error;
  final bool storageError;

  bool get isReady =>
      loaded && apiBaseUrl != null && apiBaseUrl!.isNotEmpty && !storageError;

  ServerUrlState copyWith({
    bool? loaded,
    String? apiBaseUrl,
    String? error,
    bool? storageError,
    bool clearError = false,
    bool clearUrl = false,
  }) {
    return ServerUrlState(
      loaded: loaded ?? this.loaded,
      apiBaseUrl: clearUrl ? null : (apiBaseUrl ?? this.apiBaseUrl),
      error: clearError ? null : (error ?? this.error),
      storageError: storageError ?? this.storageError,
    );
  }
}

class ServerUrlNotifier extends StateNotifier<ServerUrlState> {
  ServerUrlNotifier(
    this._storage, {
    bool autoload = true,
    Future<void> Function(String apiBaseUrl)? probe,
  }) : _probe = probe,
       super(const ServerUrlState(loaded: false)) {
    ready = autoload ? _load() : Future.value();
  }

  final TokenStorage _storage;
  final Future<void> Function(String apiBaseUrl)? _probe;

  late Future<void> ready;

  Future<void> reload() {
    ready = _load();
    return ready;
  }

  Future<void> _load() async {
    try {
      final raw = await _storage.readServerUrl();
      if (!mounted) return;
      if (raw == null || raw.trim().isEmpty) {
        AppConfig.clear();
        state = const ServerUrlState(loaded: true);
        return;
      }
      try {
        final url = ServerUrl.normalize(raw);
        AppConfig.apply(url);
        state = ServerUrlState(loaded: true, apiBaseUrl: url);
      } on FormatException {
        AppConfig.clear();
        state = const ServerUrlState(loaded: true);
      }
    } catch (_) {
      if (!mounted) return;
      AppConfig.clear();
      state = const ServerUrlState(
        loaded: true,
        storageError: true,
        error: 'Could not read the saved server address.',
      );
    }
  }

  /// Persists a normalized URL. Returns false when validation or storage fails.
  ///
  /// When the address changes, stored JWT tokens are cleared so the next
  /// session talks to the new server.
  Future<bool> save(String raw) async {
    late final String url;
    try {
      url = ServerUrl.normalize(raw);
    } on FormatException catch (e) {
      state = state.copyWith(
        loaded: true,
        error: e.message,
        storageError: false,
      );
      return false;
    }

    if (_probe != null) {
      try {
        await _probe!(url);
      } on FormatException catch (e) {
        state = state.copyWith(
          loaded: true,
          error: e.message,
          storageError: false,
        );
        return false;
      } catch (_) {
        state = state.copyWith(
          loaded: true,
          error: 'Cannot reach that server. Check the address and try again.',
          storageError: false,
        );
        return false;
      }
    }

    final previous = state.apiBaseUrl;
    try {
      await _storage.writeServerUrl(url);
    } catch (_) {
      state = state.copyWith(
        loaded: true,
        error: 'Could not save the server address.',
        storageError: true,
      );
      return false;
    }

    if (previous != null && previous != url) {
      try {
        await _storage.clear();
      } catch (_) {
        // The new URL is saved; a stale token is still unusable on the new host.
      }
    }

    AppConfig.apply(url);
    if (!mounted) return true;
    state = ServerUrlState(loaded: true, apiBaseUrl: url);
    return true;
  }
}

final serverUrlProvider =
    StateNotifierProvider<ServerUrlNotifier, ServerUrlState>((ref) {
      return ServerUrlNotifier(
        ref.watch(tokenStorageProvider),
        probe: ref.watch(serverUrlProbeProvider),
      );
    });
