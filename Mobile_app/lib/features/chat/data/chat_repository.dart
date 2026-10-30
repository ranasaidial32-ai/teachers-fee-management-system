/// features/chat/data/chat_repository.dart

import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class ChatMessagesResponse {
  const ChatMessagesResponse({
    required this.messages,
    required this.hasMore,
    this.nextCursor,
  });
  final List<Map<String, dynamic>> messages;
  final bool                       hasMore;
  final String?                    nextCursor;
}

class MessageReader {
  const MessageReader({
    required this.studentId,
    required this.studentName,
    required this.studentEmail,
    required this.readAt,
  });
  final String   studentId;
  final String   studentName;
  final String   studentEmail;
  final DateTime readAt;

  factory MessageReader.fromJson(Map<String, dynamic> json) => MessageReader(
    studentId:    json['student_id']    as String,
    studentName:  json['student_name']  as String,
    studentEmail: json['student_email'] as String,
    readAt:       DateTime.parse(json['read_at'] as String),
  );
}

class MessageReadersResponse {
  const MessageReadersResponse({
    required this.messageId,
    required this.readerCount,
    required this.readers,
  });
  final String              messageId;
  final int                 readerCount;
  final List<MessageReader> readers;
}

class ChatResult<T> {
  const ChatResult._({this.data, this.error});
  final T?      data;
  final String? error;
  bool get isSuccess => error == null;
  bool get isFailure => error != null;
  factory ChatResult.success(T d) => ChatResult._(data: d);
  factory ChatResult.failure(String e) => ChatResult._(error: e);
}

// ── Repository ────────────────────────────────────────────────────────────────

class ChatRepository {
  ChatRepository({required this.apiClient});
  final ApiClient apiClient;

  // ── Get Messages ────────────────────────────────────────────────────────────
  Future<ChatResult<ChatMessagesResponse>> getMessages({
    required String batchId,
    String?         before,
    int             limit = 30,
  }) async {
    try {
      final params = <String, dynamic>{'limit': limit};
      if (before != null) params['before'] = before;

      final response = await apiClient.get(
        ApiEndpoints.chatMessages(batchId),
        queryParameters: params,
      );

      if (response.statusCode == 200) {
        final data       = response.data['data'] as Map<String, dynamic>;
        final pagination = data['pagination']    as Map<String, dynamic>;
        final msgs       = (data['messages'] as List<dynamic>)
            .map((m) => Map<String, dynamic>.from(m as Map))
            .toList();

        return ChatResult.success(ChatMessagesResponse(
          messages:   msgs,
          hasMore:    pagination['has_more']    as bool,
          nextCursor: pagination['next_cursor'] as String?,
        ));
      }
      return ChatResult.failure(
        _extractError(response.data) ?? 'Failed to load messages.',
      );
    } on DioException catch (e) {
      return ChatResult.failure(_handleDioError(e));
    }
  }

  // ── Get Message Readers ─────────────────────────────────────────────────────
  /// Teacher only — who has read a specific message
  Future<ChatResult<MessageReadersResponse>> getMessageReaders({
    required String batchId,
    required String messageId,
  }) async {
    try {
      final response = await apiClient.get(
        ApiEndpoints.messageReaders(batchId, messageId),
      );

      if (response.statusCode == 200) {
        final data    = response.data['data'] as Map<String, dynamic>;
        final readers = (data['readers'] as List<dynamic>)
            .map((r) => MessageReader.fromJson(Map<String, dynamic>.from(r as Map)))
            .toList();

        return ChatResult.success(MessageReadersResponse(
          messageId:   data['message_id']  as String,
          readerCount: data['reader_count'] as int,
          readers:     readers,
        ));
      }
      return ChatResult.failure(
        _extractError(response.data) ?? 'Failed to load readers.',
      );
    } on DioException catch (e) {
      return ChatResult.failure(_handleDioError(e));
    }
  }

  // ── Delete Message ──────────────────────────────────────────────────────────
  Future<ChatResult<bool>> deleteMessage({
    required String batchId,
    required String messageId,
  }) async {
    try {
      final response = await apiClient.delete(
        ApiEndpoints.deleteMessage(batchId, messageId),
      );
      if (response.statusCode == 200) return ChatResult.success(true);
      return ChatResult.failure(
        _extractError(response.data) ?? 'Failed to delete message.',
      );
    } on DioException catch (e) {
      return ChatResult.failure(_handleDioError(e));
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