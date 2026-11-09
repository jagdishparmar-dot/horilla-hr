import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import 'models.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    required this.status,
    this.session,
    this.error,
  });

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
  AuthNotifier(this._repo) : super(const AuthState(status: AuthStatus.unknown)) {
    _bootstrap();
  }

  final AuthRepository _repo;

  Future<void> _bootstrap() async {
    final has = await _repo.hasSession();
    state = AuthState(
      status: has ? AuthStatus.authenticated : AuthStatus.unauthenticated,
    );
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(clearError: true);
    try {
      final session = await _repo.login(username: username, password: password);
      state = AuthState(status: AuthStatus.authenticated, session: session);
      return true;
    } catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: e.toString(),
      );
      return false;
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});
