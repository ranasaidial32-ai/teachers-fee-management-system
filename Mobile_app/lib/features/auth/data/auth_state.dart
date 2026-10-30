/// features/auth/data/auth_state.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../../../core/services/storage_service.dart';
import '../../../core/constants/app_constants.dart';

enum AuthStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
  error,
}

class AuthState extends Equatable {
  const AuthState({
    this.status       = AuthStatus.initial,
    this.userId,
    this.userName,
    this.userEmail,
    this.role,
    this.avatarId,
    this.errorMessage,
  });

  final AuthStatus status;
  final String?    userId;
  final String?    userName;
  final String?    userEmail;
  final String?    role;
  final int?       avatarId;
  final String?    errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isLoading       => status == AuthStatus.loading;
  bool get isInitial       => status == AuthStatus.initial;
  bool get isTeacher       => role == AppConstants.roleTeacher;
  bool get isStudent       => role == AppConstants.roleStudent;
  bool get hasError        => status == AuthStatus.error;
  bool get hasAvatar       =>
      avatarId != null && avatarId! >= 1 && avatarId! <= 5;

  AuthState copyWith({
    AuthStatus? status,
    String?     userId,
    String?     userName,
    String?     userEmail,
    String?     role,
    int?        avatarId,
    bool        clearAvatarId = false,
    String?     errorMessage,
  }) =>
      AuthState(
        status:       status       ?? this.status,
        userId:       userId       ?? this.userId,
        userName:     userName     ?? this.userName,
        userEmail:    userEmail    ?? this.userEmail,
        role:         role         ?? this.role,
        avatarId:     clearAvatarId ? null : avatarId ?? this.avatarId,
        errorMessage: errorMessage ?? this.errorMessage,
      );

  factory AuthState.initial()       => const AuthState(status: AuthStatus.initial);
  factory AuthState.loading()       => const AuthState(status: AuthStatus.loading);
  factory AuthState.unauthenticated() =>
      const AuthState(status: AuthStatus.unauthenticated);
  factory AuthState.error(String m) =>
      AuthState(status: AuthStatus.error, errorMessage: m);

  factory AuthState.authenticated({
    required String userId,
    required String userName,
    required String userEmail,
    required String role,
    int?            avatarId,
  }) =>
      AuthState(
        status:    AuthStatus.authenticated,
        userId:    userId,
        userName:  userName,
        userEmail: userEmail,
        role:      role,
        avatarId:  avatarId,
      );

  @override
  List<Object?> get props =>
      [status, userId, userName, userEmail, role, avatarId, errorMessage];

  @override
  String toString() =>
      'AuthState(status:$status, role:$role, avatarId:$avatarId)';
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class AuthStateNotifier extends StateNotifier<AuthState> {
  AuthStateNotifier({required this.storageService})
      : super(AuthState.initial()) {
    _restoreSession();
  }

  final StorageService storageService;

  // ── Session Restore ─────────────────────────────────────────────────────────
  Future<void> _restoreSession() async {
    // FIX: Every code path MUST set state to something other than `initial`.
    // If state stays `initial`, the splash listener never fires and the app
    // is frozen on the splash page forever.
    try {
      debugPrint('AuthState: restoring session...');

      final isLoggedIn = await storageService.isLoggedIn();
      debugPrint('AuthState: isLoggedIn=$isLoggedIn');

      if (!isLoggedIn) {
        state = AuthState.unauthenticated();
        debugPrint('AuthState: → unauthenticated (no token)');
        return;
      }

      // Read all stored values independently — if one fails the others still work
      final userId    = await _safeRead(() => storageService.getUserId());
      final userName  = await _safeRead(() => storageService.getUserName());
      final userEmail = await _safeRead(() => storageService.getUserEmail());
      final userRole  = await _safeRead(() => storageService.getUserRole());

      // FIX: avatarId read is now wrapped in its own try/catch so if the
      // key doesn't exist yet it returns null gracefully instead of crashing
      final avatarId  = await _safeReadInt(() => storageService.getAvatarId());

      debugPrint(
        'AuthState: userId=$userId role=$userRole avatarId=$avatarId',
      );

      if (userId == null || userRole == null) {
        // Token exists but profile is incomplete — clear and re-login
        await storageService.clearAll();
        state = AuthState.unauthenticated();
        debugPrint('AuthState: → unauthenticated (incomplete profile)');
        return;
      }

      // Check refresh token expiry
      final refreshExpiry = await _safeRead(
        () => storageService.getRefreshExpiry(),
      );

      if (refreshExpiry != null) {
        final expiry = DateTime.tryParse(refreshExpiry);
        if (expiry != null && expiry.isBefore(DateTime.now())) {
          await storageService.clearAll();
          state = AuthState.unauthenticated();
          debugPrint('AuthState: → unauthenticated (refresh expired)');
          return;
        }
      }

      state = AuthState.authenticated(
        userId:    userId,
        userName:  userName ?? 'User',
        userEmail: userEmail ?? '',
        role:      userRole,
        avatarId:  avatarId,
      );
      debugPrint('AuthState: → authenticated (role=$userRole)');

    } catch (e, stack) {
      // FIX: ALWAYS transition out of initial even on unexpected errors.
      // Without this, any exception leaves state=initial and splash freezes.
      debugPrint('AuthState: _restoreSession FAILED: $e');
      debugPrint(stack.toString());
      state = AuthState.unauthenticated();
    }
  }

  // ── Safe read helpers ───────────────────────────────────────────────────────
  // Wraps individual storage reads so one bad key doesn't crash everything.

  Future<String?> _safeRead(Future<String?> Function() fn) async {
    try {
      return await fn();
    } catch (e) {
      debugPrint('AuthState: _safeRead error: $e');
      return null;
    }
  }

  Future<int?> _safeReadInt(Future<int?> Function() fn) async {
    try {
      return await fn();
    } catch (e) {
      debugPrint('AuthState: _safeReadInt error: $e');
      return null;
    }
  }

  // ── Login Success ────────────────────────────────────────────────────────────
  Future<void> onLoginSuccess({
    required String userId,
    required String userName,
    required String userEmail,
    required String role,
    required String accessToken,
    required String refreshToken,
    required String refreshExpiry,
    int?            avatarId,
  }) async {
    state = AuthState.loading();

    await storageService.saveTokens(
      accessToken:   accessToken,
      refreshToken:  refreshToken,
      refreshExpiry: refreshExpiry,
    );

    // Save core profile (existing signature — no avatarId param)
    await storageService.saveUserProfile(
      id:    userId,
      name:  userName,
      email: userEmail,
      role:  role,
    );

    // Save avatarId separately
    if (avatarId != null) {
      await storageService.saveAvatarId(avatarId);
    }

    state = AuthState.authenticated(
      userId:    userId,
      userName:  userName,
      userEmail: userEmail,
      role:      role,
      avatarId:  avatarId,
    );
  }

  // ── Logout ───────────────────────────────────────────────────────────────────
  Future<void> logout() async {
    state = AuthState.loading();
    await storageService.clearAll();
    state = AuthState.unauthenticated();
  }

  // ── Update Profile ────────────────────────────────────────────────────────────
  Future<void> updateProfile({
    String? newName,
    int?    newAvatarId,
  }) async {
    if (!state.isAuthenticated) return;

    if (newName != null) {
      await storageService.saveUserName(newName);
    }
    if (newAvatarId != null) {
      await storageService.saveAvatarId(newAvatarId);
    }

    state = state.copyWith(
      userName: newName,
      avatarId: newAvatarId,
    );
  }

  void setError(String message) => state = AuthState.error(message);

  void clearError() {
    if (state.hasError) state = AuthState.unauthenticated();
  }
}