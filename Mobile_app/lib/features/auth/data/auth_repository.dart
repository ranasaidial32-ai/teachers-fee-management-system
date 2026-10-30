/// features/auth/data/auth_repository.dart
/// Added: updateProfile(name, avatarId) — PUT /auth/profile

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/services/storage_service.dart';

// ── Result Types ──────────────────────────────────────────────────────────────

class AuthResult<T> {
  const AuthResult._({this.data, this.error});
  final T?      data;
  final String? error;
  bool get isSuccess => error == null;
  bool get isFailure => error != null;
  factory AuthResult.success(T data) => AuthResult._(data: data);
  factory AuthResult.failure(String error) => AuthResult._(error: error);
}

// ── DTOs ──────────────────────────────────────────────────────────────────────

class UserDto {
  const UserDto({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.avatarId,   // NEW
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final int?   avatarId;

  factory UserDto.fromJson(Map<String, dynamic> json) => UserDto(
    id:       json['id']        as String,
    name:     json['name']      as String,
    email:    json['email']     as String,
    role:     json['role']      as String,
    avatarId: json['avatar_id'] as int?,
  );
}

class AuthTokensDto {
  const AuthTokensDto({
    required this.accessToken,
    required this.refreshToken,
    required this.refreshTokenExpires,
  });

  final String accessToken;
  final String refreshToken;
  final String refreshTokenExpires;

  factory AuthTokensDto.fromJson(Map<String, dynamic> json) => AuthTokensDto(
    accessToken:         json['access_token']          as String,
    refreshToken:        json['refresh_token']         as String,
    refreshTokenExpires: json['refresh_token_expires'] as String,
  );
}

class AuthResponseDto {
  const AuthResponseDto({required this.user, required this.tokens});
  final UserDto       user;
  final AuthTokensDto tokens;
}

// ── Repository ────────────────────────────────────────────────────────────────

class AuthRepository {
  AuthRepository({
    required this.apiClient,
    required this.storageService,
  });

  final ApiClient      apiClient;
  final StorageService storageService;

  // ── Register ───────────────────────────────────────────────────────────────
  Future<AuthResult<AuthResponseDto>> register({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    try {
      final deviceId = await storageService.getDeviceId();
      final fcmToken = await _getFcmToken();

      final response = await apiClient.post(
        ApiEndpoints.authRegister,
        data: {
          'name':      name.trim(),
          'email':     email.trim().toLowerCase(),
          'password':  password,
          'role':      role,
          'device_id': deviceId,
          if (fcmToken != null) 'fcm_token': fcmToken,
        },
      );

      if (response.statusCode == 201) {
        final data   = response.data['data'] as Map<String, dynamic>;
        final user   = UserDto.fromJson(data['user']   as Map<String, dynamic>);
        final tokens = AuthTokensDto.fromJson(data['tokens'] as Map<String, dynamic>);
        return AuthResult.success(AuthResponseDto(user: user, tokens: tokens));
      }
      return AuthResult.failure(_extractError(response.data) ?? 'Registration failed.');
    } on DioException catch (e) {
      return AuthResult.failure(_handleDioError(e));
    } catch (e) {
      return AuthResult.failure('Unexpected error: ${e.toString()}');
    }
  }

  // ── Login ──────────────────────────────────────────────────────────────────
  Future<AuthResult<AuthResponseDto>> login({
    required String email,
    required String password,
  }) async {
    try {
      final deviceId = await storageService.getDeviceId();
      final fcmToken = await _getFcmToken();

      debugPrint('LOGIN → ${apiClient.dio.options.baseUrl}${ApiEndpoints.authLogin}');

      final response = await apiClient.post(
        ApiEndpoints.authLogin,
        data: {
          'email':     email.trim().toLowerCase(),
          'password':  password,
          'device_id': deviceId,
          if (fcmToken != null) 'fcm_token': fcmToken,
        },
      );

      if (response.statusCode == 200) {
        final data   = response.data['data'] as Map<String, dynamic>;
        final user   = UserDto.fromJson(data['user']   as Map<String, dynamic>);
        final tokens = AuthTokensDto.fromJson(data['tokens'] as Map<String, dynamic>);
        return AuthResult.success(AuthResponseDto(user: user, tokens: tokens));
      }
      return AuthResult.failure(
        _extractError(response.data) ?? 'Login failed. Check your credentials.',
      );
    } on DioException catch (e) {
      debugPrint('Login DioException: ${e.type} — ${e.message}');
      return AuthResult.failure(_handleDioError(e));
    } catch (e) {
      return AuthResult.failure('Unexpected error: $e');
    }
  }

  // ── Logout ─────────────────────────────────────────────────────────────────
  Future<AuthResult<bool>> logout() async {
    try {
      final refreshToken = await storageService.getRefreshToken();
      final deviceId     = await storageService.getDeviceId();
      if (refreshToken == null) return AuthResult.success(true);

      final response = await apiClient.post(
        ApiEndpoints.authLogout,
        data: {'refresh_token': refreshToken, 'device_id': deviceId},
      );
      return AuthResult.success(response.statusCode == 200);
    } catch (_) {
      return AuthResult.success(true);
    }
  }

  // ── Get Profile ────────────────────────────────────────────────────────────
  Future<AuthResult<UserDto>> getProfile() async {
    try {
      final response = await apiClient.get(ApiEndpoints.authMe);
      if (response.statusCode == 200) {
        final user = UserDto.fromJson(
          response.data['data']['user'] as Map<String, dynamic>,
        );
        return AuthResult.success(user);
      }
      return AuthResult.failure(_extractError(response.data) ?? 'Failed to fetch profile.');
    } on DioException catch (e) {
      return AuthResult.failure(_handleDioError(e));
    }
  }

  // ── NEW: Update Profile ────────────────────────────────────────────────────
  /// PUT /auth/profile
  /// Sends only the fields the user actually changed.
  /// Both [name] and [avatarId] are optional — pass null to skip.
  Future<AuthResult<UserDto>> updateProfile({
    String? name,
    int?    avatarId,
  }) async {
    try {
      if (name == null && avatarId == null) {
        return AuthResult.failure('Nothing to update.');
      }

      final body = <String, dynamic>{};
      if (name     != null) body['name']      = name.trim();
      if (avatarId != null) body['avatar_id'] = avatarId;

      final response = await apiClient.put(
        ApiEndpoints.authUpdateProfile,
        data: body,
      );

      if (response.statusCode == 200) {
        final user = UserDto.fromJson(
          response.data['data']['user'] as Map<String, dynamic>,
        );
        return AuthResult.success(user);
      }
      return AuthResult.failure(
        _extractError(response.data) ?? 'Profile update failed.',
      );
    } on DioException catch (e) {
      return AuthResult.failure(_handleDioError(e));
    } catch (e) {
      return AuthResult.failure('Unexpected error: $e');
    }
  }

  // ── Update FCM Token ───────────────────────────────────────────────────────
  Future<void> updateFcmToken() async {
    try {
      final fcmToken = await _getFcmToken();
      if (fcmToken == null) return;
      await apiClient.patch(ApiEndpoints.authFcmToken, data: {'fcm_token': fcmToken});
    } catch (e) {
      debugPrint('FCM token update failed (non-fatal): $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Future<String?> _getFcmToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  String? _extractError(dynamic data) {
    if (data is Map) return data['message'] as String?;
    return null;
  }

  String _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timed out. Server may be down.';
      case DioExceptionType.receiveTimeout:
        return 'Server took too long to respond.';
      case DioExceptionType.sendTimeout:
        return 'Request send timed out.';
      case DioExceptionType.connectionError:
        return 'Cannot connect to server. Check your internet connection.';
      case DioExceptionType.badCertificate:
        return 'SSL certificate error.';
      case DioExceptionType.badResponse:
        final msg = e.response?.data?['message'];
        return msg is String ? msg : 'Server error (${e.response?.statusCode}).';
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      default:
        final msg = e.response?.data?['message'];
        return msg is String ? msg : 'Network error. Please try again.';
    }
  }
}