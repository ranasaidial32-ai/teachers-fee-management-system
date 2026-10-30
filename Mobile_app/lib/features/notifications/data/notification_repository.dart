/// features/notifications/data/notification_repository.dart
/// Data layer for notification history API calls.
///
/// PRD Reference: Section 05 — Notification System
///   GET /notifications/my               — student notification history
///   GET /notifications/batch/:id/stats  — teacher delivery stats
///   GET /notifications/failed           — teacher failed notifications

import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.type,
    required this.status,
    required this.fcmPayload,
    this.batchId,
    this.sentAt,
    this.createdAt,
  });

  final String               id;
  final String               type;
  final String               status;
  final Map<String, dynamic> fcmPayload;
  final String?              batchId;
  final String?              sentAt;
  final String?              createdAt;

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final payload = json['fcm_payload'];
    return NotificationModel(
      id:         json['id']          as String,
      type:       json['type']        as String,
      status:     json['status']      as String,
      fcmPayload: payload is Map
          ? Map<String, dynamic>.from(payload)
          : <String, dynamic>{},
      batchId:    json['batch_id']    as String?,
      sentAt:     json['sent_at']     as String?,
      createdAt:  json['created_at']  as String?,
    );
  }
}

// ── Result ────────────────────────────────────────────────────────────────────

class NotifResult<T> {
  const NotifResult._({this.data, this.error});
  final T?      data;
  final String? error;
  bool get isSuccess => error == null;
  bool get isFailure => error != null;
  factory NotifResult.success(T d) => NotifResult._(data: d);
  factory NotifResult.failure(String e) => NotifResult._(error: e);
}

// ── Repository ────────────────────────────────────────────────────────────────

class NotificationRepository {
  NotificationRepository({required this.apiClient});
  final ApiClient apiClient;

  // ── My Notifications ────────────────────────────────────────────────────────
  /// GET /notifications/my
  /// Student view of their notification history.
  Future<NotifResult<List<NotificationModel>>> getMyNotifications({
    String? type,
    int     page  = 1,
    int     limit = 20,
  }) async {
    try {
      final params = <String, dynamic>{'page': page, 'limit': limit};
      if (type != null) params['type'] = type;

      final response = await apiClient.get(
        ApiEndpoints.myNotifications,
        queryParameters: params,
      );

      if (response.statusCode == 200) {
        final notifsJson =
            response.data['data']['notifications'] as List<dynamic>;
        final notifs = notifsJson
            .map((n) => NotificationModel.fromJson(
              n as Map<String, dynamic>,
            ))
            .toList();
        return NotifResult.success(notifs);
      }
      return NotifResult.failure(
        _extractError(response.data) ?? 'Failed to load notifications.',
      );
    } on DioException catch (e) {
      return NotifResult.failure(_handleDioError(e));
    }
  }

  // ── Batch Stats ─────────────────────────────────────────────────────────────
  /// GET /notifications/batch/:batchId/stats
  /// Teacher delivery rate stats for the ≥90% PRD metric.
  Future<NotifResult<Map<String, dynamic>>> getBatchStats({
    required String batchId,
    String?         month,
  }) async {
    try {
      final params = <String, dynamic>{};
      if (month != null) params['month'] = month;

      final response = await apiClient.get(
        ApiEndpoints.batchNotificationStats(batchId),
        queryParameters: params,
      );

      if (response.statusCode == 200) {
        return NotifResult.success(
          response.data['data'] as Map<String, dynamic>,
        );
      }
      return NotifResult.failure(
        _extractError(response.data) ?? 'Failed to load stats.',
      );
    } on DioException catch (e) {
      return NotifResult.failure(_handleDioError(e));
    }
  }

  String? _extractError(dynamic data) {
    if (data is Map) return data['message'] as String?;
    return null;
  }

  String _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out.';
      case DioExceptionType.connectionError:
        return 'Cannot reach server.';
      default:
        final msg = e.response?.data?['message'];
        return msg is String ? msg : 'Network error.';
    }
  }
}