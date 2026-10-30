/// core/network/api_client.dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../services/storage_service.dart';
import 'api_endpoints.dart';

class ApiClient {
  ApiClient({
    required this.storageService,
    required this.onTokenExpired,
  }) {
    _dio = _buildDio();
    _dio.interceptors.add(_AuthInterceptor(
      storageService: storageService,
      dio:            _dio,
      onTokenExpired: onTokenExpired,
    ));

    // ✅ Always add log interceptor in debug mode
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody:  true,
        responseBody: true,
        logPrint:     (obj) => debugPrint('DIO: $obj'),
      ));
    }
  }

  final StorageService storageService;
  final VoidCallback   onTokenExpired;
  late final Dio       _dio;

  Dio get dio => _dio;

  // ── Builder ───────────────────────────────────────────────────────────────
  Dio _buildDio() {
    // ✅ FIXED: Always use dev URL in debug mode
    final baseUrl = kDebugMode
        ? AppConstants.apiBaseUrl
        : AppConstants.apiBaseUrlProd;

    debugPrint('╔══════════════════════════════════╗');
    debugPrint('║      API CLIENT INITIALIZED      ║');
    debugPrint('║ kDebugMode: $kDebugMode');
    debugPrint('║ baseUrl: $baseUrl');
    debugPrint('╚══════════════════════════════════╝');

    return Dio(
      BaseOptions(
        baseUrl:        baseUrl,
        connectTimeout: const Duration(
          milliseconds: AppConstants.connectTimeoutMs,
        ),
        receiveTimeout: const Duration(
          milliseconds: AppConstants.receiveTimeoutMs,
        ),
        headers: {
          'Content-Type': 'application/json',
          'Accept':       'application/json',
        },
        validateStatus: (status) {
          // Accept all status codes — handle errors in interceptor/caller
          return status != null && status < 500;
        },
      ),
    );
  }

  // ── Convenience Methods ───────────────────────────────────────────────────

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      _dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: options,
      );

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      _dio.post<T>(
        path,
        data:            data,
        queryParameters: queryParameters,
        options:         options,
      );

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Options? options,
  }) =>
      _dio.put<T>(path, data: data, options: options);

  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Options? options,
  }) =>
      _dio.patch<T>(path, data: data, options: options);

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Options? options,
  }) =>
      _dio.delete<T>(path, data: data, options: options);

  /// Multipart file upload
  Future<Response<T>> uploadFile<T>(
    String path,
    FormData formData, {
    ProgressCallback? onSendProgress,
  }) =>
      _dio.post<T>(
        path,
        data:    formData,
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
        ),
        onSendProgress: onSendProgress,
      );
}

// ── Auth Interceptor ──────────────────────────────────────────────────────────
class _AuthInterceptor extends Interceptor {
  _AuthInterceptor({
    required this.storageService,
    required this.dio,
    required this.onTokenExpired,
  });

  final StorageService storageService;
  final Dio            dio;
  final VoidCallback   onTokenExpired;

  bool _isRefreshing = false;

  // ✅ FIXED: Use Completer<Response> instead of broken _QueuedRequest
  final List<Completer<Response<dynamic>>> _pendingCompleters = [];

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final skipAuth = options.extra['skipAuth'] == true;
    if (skipAuth) {
      handler.next(options);
      return;
    }

    final token = await storageService.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;

    if (response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    final errorCode = response?.data?['code'] as String? ?? '';

    if (errorCode != 'TOKEN_EXPIRED') {
      handler.next(err);
      return;
    }

    // ✅ FIXED: Proper queue handling with Completer
    if (_isRefreshing) {
      final completer = Completer<Response<dynamic>>();
      _pendingCompleters.add(completer);
      try {
        final result = await completer.future;
        handler.resolve(result);
      } catch (e) {
        handler.next(err);
      }
      return;
    }

    _isRefreshing = true;

    try {
      final refreshToken = await storageService.getRefreshToken();
      final deviceId     = await storageService.getDeviceId();

      if (refreshToken == null) {
        throw Exception('No refresh token available');
      }

      final refreshDio = Dio(BaseOptions(
        baseUrl: dio.options.baseUrl,
      ));

      final refreshResponse = await refreshDio.post(
        ApiEndpoints.authRefresh,
        data: {
          'refresh_token': refreshToken,
          'device_id':     deviceId,
        },
        options: Options(extra: {'skipAuth': true}),
      );

      if (refreshResponse.statusCode == 200) {
        final tokens          = refreshResponse.data['data']['tokens'];
        final newAccessToken  = tokens['access_token']          as String;
        final newRefreshToken = tokens['refresh_token']         as String;
        final newExpiry       = tokens['refresh_token_expires'] as String;

        await storageService.saveTokens(
          accessToken:   newAccessToken,
          refreshToken:  newRefreshToken,
          refreshExpiry: newExpiry,
        );

        // Retry original request
        final retryOptions = err.requestOptions;
        retryOptions.headers['Authorization'] = 'Bearer $newAccessToken';
        final retryResponse = await dio.fetch(retryOptions);

        // ✅ FIXED: Complete all pending requests properly
        for (final completer in _pendingCompleters) {
          completer.complete(retryResponse);
        }
        _pendingCompleters.clear();

        handler.resolve(retryResponse);
      } else {
        throw Exception(
          'Token refresh failed: ${refreshResponse.statusCode}',
        );
      }
    } catch (refreshError) {
      debugPrint('Token refresh failed: $refreshError');

      // ✅ FIXED: Reject all pending completers
      for (final completer in _pendingCompleters) {
        completer.completeError(refreshError);
      }
      _pendingCompleters.clear();

      await storageService.clearAll();
      onTokenExpired();

      handler.next(err);
    } finally {
      _isRefreshing = false;
    }
  }
}