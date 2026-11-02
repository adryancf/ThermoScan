import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/core/storage/token_storage.dart';
import 'package:thermoscan/features/auth/data/auth_repository.dart';
import 'package:thermoscan/features/auth/domain/auth_user.dart';

enum AuthStatus {
  initializing,
  unauthenticated,
  authenticated,
}

class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.infoMessage,
  });

  const AuthState.initializing()
      : status = AuthStatus.initializing,
        user = null,
        infoMessage = null;

  const AuthState.unauthenticated({this.infoMessage})
      : status = AuthStatus.unauthenticated,
        user = null;

  const AuthState.authenticated(AuthUser this.user)
      : status = AuthStatus.authenticated,
        infoMessage = null;

  final AuthStatus status;
  final AuthUser? user;
  final String? infoMessage;

  bool get isAuthenticated =>
      status == AuthStatus.authenticated && user != null;
  bool get mustChangePassword =>
      isAuthenticated && (user?.mustChangePassword ?? false);

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? infoMessage,
    bool clearInfoMessage = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      infoMessage:
          clearInfoMessage ? null : (infoMessage ?? this.infoMessage),
    );
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  final tokenStorage = ref.watch(tokenStorageProvider);
  return AuthController(
    repository: repository,
    tokenStorage: tokenStorage,
  )..checkSession();
});

class AuthController extends StateNotifier<AuthState> {
  AuthController({
    required this.repository,
    required this.tokenStorage,
  }) : super(const AuthState.initializing());

  final AuthRepository repository;
  final TokenStorage tokenStorage;

  Future<void> checkSession() async {
    state = const AuthState.initializing();
    final minDisplayTimer = Future.delayed(const Duration(milliseconds: 2800));
    try {
      final accessToken = await tokenStorage.getAccessToken();
      final refreshToken = await tokenStorage.getRefreshToken();

      if ((accessToken == null || accessToken.isEmpty) &&
          (refreshToken == null || refreshToken.isEmpty)) {
        await minDisplayTimer;
        state = const AuthState.unauthenticated();
        return;
      }

      final me = await repository.getMe();
      await minDisplayTimer;
      state = AuthState.authenticated(me);
    } catch (_) {
      await tokenStorage.clearTokens();
      await minDisplayTimer;
      state = const AuthState.unauthenticated();
    }
  }

  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    final session = await repository.login(
      email: email,
      password: password,
    );
    await tokenStorage.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
    state = AuthState.authenticated(session.user);
    return session.user;
  }

  /// Changes the user's password and, per design.md Section 3 & SCR-03,
  /// clears local credentials and routes back to Login with the notice:
  /// "Password updated. Please log in again."
  Future<void> changePasswordAndRequireRelogin({
    required String currentPassword,
    required String newPassword,
  }) async {
    final newSession = await repository.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );

    // Revoke the newly issued session so no orphan session remains active
    await repository.logout(refreshToken: newSession.refreshToken);
    await tokenStorage.clearTokens();

    state = const AuthState.unauthenticated(
      infoMessage: 'Password updated. Please log in again.',
    );
  }

  Future<void> refreshProfile() async {
    try {
      final me = await repository.getMe();
      if (state.isAuthenticated) {
        state = AuthState.authenticated(me);
      }
    } catch (_) {
      // Keep current cached user if background refresh fails
    }
  }

  Future<AuthUser> updateOwnProfile({
    required String name,
    required String email,
  }) async {
    final updated = await repository.updateOwnProfile(
      name: name,
      email: email,
    );
    state = AuthState.authenticated(updated);
    return updated;
  }

  Future<void> logout() async {
    final refreshToken = await tokenStorage.getRefreshToken();
    await repository.logout(refreshToken: refreshToken);
    await tokenStorage.clearTokens();
    state = const AuthState.unauthenticated();
  }

  void clearInfoMessage() {
    if (state.infoMessage != null) {
      state = state.copyWith(clearInfoMessage: true);
    }
  }
}
