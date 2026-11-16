import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/dio_client.dart';
import '../../core/auth/session_revocation.dart';
import 'auth_repository.dart';
import 'models.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({required this.status, this.session, this.error});

  final AuthStatus status;
  final AuthSession? session;
  final String? error;

  AuthState copyWith({
    AuthStatus? status,
    AuthSession? session,
    String? error,
    bool clearError = false,
    bool clearSession = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      session: clearSession ? null : (session ?? this.session),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._repo)
    : super(const AuthState(status: AuthStatus.unknown)) {
    _bootstrap();
  }

  final AuthRepository _repo;

  Future<void> _bootstrap() async {
    try {
      final has = await _repo.hasSession();
      if (!mounted || state.status != AuthStatus.unknown) return;
      state = AuthState(
        status: has ? AuthStatus.authenticated : AuthStatus.unauthenticated,
      );
    } catch (_) {
      if (!mounted || state.status != AuthStatus.unknown) return;
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  /// Storage was cleared because the server rejected refresh.
  void onSessionRevoked() {
    if (!mounted) return;
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<bool> login(
    String username,
    String password, {
    void Function()? onAttemptFinished,
  }) async {
    state = state.copyWith(clearError: true);
    try {
      final session = await _repo.login(username: username, password: password);
      onAttemptFinished?.call();
      if (!mounted) return true;
      state = AuthState(status: AuthStatus.authenticated, session: session);
      return true;
    } catch (e) {
      onAttemptFinished?.call();
      if (!mounted) return false;
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: userFacingError(e),
      );
      return false;
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    if (!mounted) return;
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Drops stored tokens without calling logout. Password change already
  /// revokes the refresh token on the server.
  Future<void> signOutLocal() async {
    await _repo.clearLocalSession();
    if (!mounted) return;
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final notifier = AuthNotifier(ref.watch(authRepositoryProvider));
  final sub = ref.watch(sessionRevocationProvider).stream.listen((_) {
    notifier.onSessionRevoked();
  });
  ref.onDispose(sub.cancel);
  return notifier;
});
