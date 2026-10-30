// lib/features/teacher/data/fee_repository.dart
library;

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class FeeStudentInfo {
  const FeeStudentInfo({
    required this.id,
    required this.name,
    required this.email,
  });
  final String id;
  final String name;
  final String email;

  factory FeeStudentInfo.fromJson(Map<String, dynamic> json) =>
      FeeStudentInfo(
        id:    json['id']    as String,
        name:  json['name']  as String,
        email: json['email'] as String,
      );
}

// FIX: Add BatchInfo so student_fee_page.dart can access fee.batch.name
class BatchInfo {
  const BatchInfo({
    required this.id,
    required this.name,
  });
  final String id;
  final String name;

  factory BatchInfo.fromJson(Map<String, dynamic> json) => BatchInfo(
    id:   json['id']   as String,
    name: json['name'] as String,
  );
}

class FeeModel {
  const FeeModel({
    required this.id,
    required this.batchId,
    required this.studentId,
    required this.billingMonth,
    required this.amountDue,
    required this.status,
    this.paidAt,
    this.notificationSentAt,
    this.student,
    // FIX: batch field added
    this.batch,
    this.createdAt,
  });

  final String          id;
  final String          batchId;
  final String          studentId;
  final String          billingMonth;
  final int             amountDue;
  final String          status;      // 'pending' | 'overdue' | 'paid'
  final String?         paidAt;
  final String?         notificationSentAt;
  final FeeStudentInfo? student;
  // FIX: batch info — populated when backend includes batch relation
  final BatchInfo?      batch;
  final String?         createdAt;

  // Convenience getters
  bool get isPaid    => status == 'paid';
  bool get isOverdue => status == 'overdue';
  bool get isPending => status == 'pending';

  factory FeeModel.fromJson(Map<String, dynamic> json) {
    final studentJson = json['student'] as Map<String, dynamic>?;
    // FIX: parse batch if present in API response
    final batchJson   = json['batch']   as Map<String, dynamic>?;

    return FeeModel(
      id:                 json['id']                  as String,
      batchId:            json['batch_id']             as String,
      studentId:          json['student_id']           as String,
      billingMonth:       json['billing_month']        as String,
      amountDue:          json['amount_due']           as int,
      status:             json['status']               as String,
      paidAt:             json['paid_at']              as String?,
      notificationSentAt: json['notification_sent_at'] as String?,
      student: studentJson != null
          ? FeeStudentInfo.fromJson(studentJson)
          : null,
      // FIX: parse batch or construct stub from batchId
      batch: batchJson != null
          ? BatchInfo.fromJson(batchJson)
          : (json['batch_id'] != null
              ? BatchInfo(
                  id:   json['batch_id'] as String,
                  name: json['batch_name'] as String? ?? 'Batch',
                )
              : null),
      createdAt: json['created_at'] as String?,
    );
  }
}

class FeeSummary {
  const FeeSummary({
    required this.total,
    required this.paid,
    required this.pending,
    required this.overdue,
  });
  final int total;
  final int paid;
  final int pending;
  final int overdue;

  double get paidPercent => total > 0 ? (paid / total * 100) : 0;

  factory FeeSummary.fromJson(Map<String, dynamic> json) => FeeSummary(
    total:   json['total']   as int,
    paid:    json['paid']    as int,
    pending: json['pending'] as int,
    overdue: json['overdue'] as int,
  );
}

class BatchFeeResponse {
  const BatchFeeResponse({
    required this.billingMonth,
    required this.summary,
    required this.fees,
  });
  final String         billingMonth;
  final FeeSummary     summary;
  final List<FeeModel> fees;
}

// ── Result ────────────────────────────────────────────────────────────────────
class FeeResult<T> {
  const FeeResult._({this.data, this.error});
  final T?      data;
  final String? error;
  bool get isSuccess => error == null;
  bool get isFailure => error != null;
  factory FeeResult.success(T d) => FeeResult._(data: d);
  factory FeeResult.failure(String e) => FeeResult._(error: e);
}

// ── Repository ────────────────────────────────────────────────────────────────
class FeeRepository {
  FeeRepository({required this.apiClient});
  final ApiClient apiClient;

  /// GET /fees/:batchId?month=YYYY-MM
  Future<FeeResult<BatchFeeResponse>> getBatchFees({
    required String batchId,
    String?         month,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (month != null) queryParams['month'] = month;

      final response = await apiClient.get(
        ApiEndpoints.feesForBatch(batchId),
        queryParameters: queryParams,
      );

      if (response.statusCode == 200) {
        final data     = response.data['data'] as Map<String, dynamic>;
        final feesJson = data['fees'] as List<dynamic>;
        return FeeResult.success(BatchFeeResponse(
          billingMonth: data['billing_month'] as String,
          summary: FeeSummary.fromJson(
            data['summary'] as Map<String, dynamic>,
          ),
          fees: feesJson
              .map((f) => FeeModel.fromJson(f as Map<String, dynamic>))
              .toList(),
        ));
      }
      return FeeResult.failure(
        _extractError(response.data) ?? 'Failed to load fees.',
      );
    } on DioException catch (e) {
      return FeeResult.failure(_handleDioError(e));
    }
  }

  /// PUT /fees/mark-paid
  Future<FeeResult<FeeModel>> markPaid(String feeId) async {
    try {
      final response = await apiClient.put(
        ApiEndpoints.feesMarkPaid,
        data: {'fee_id': feeId},
      );
      if (response.statusCode == 200) {
        final fee = FeeModel.fromJson(
          response.data['data']['fee'] as Map<String, dynamic>,
        );
        return FeeResult.success(fee);
      }
      return FeeResult.failure(
        _extractError(response.data) ?? 'Failed to mark as paid.',
      );
    } on DioException catch (e) {
      return FeeResult.failure(_handleDioError(e));
    }
  }

  /// GET /fees/student/:id
  Future<FeeResult<List<FeeModel>>> getStudentFeeHistory({
    required String studentId,
    String?         batchId,
    int             page  = 1,
    int             limit = 12,
  }) async {
    try {
      final params = <String, dynamic>{'page': page, 'limit': limit};
      if (batchId != null) params['batch_id'] = batchId;

      final response = await apiClient.get(
        ApiEndpoints.studentFeeHistory(studentId),
        queryParameters: params,
      );

      if (response.statusCode == 200) {
        final feesJson = response.data['data']['fees'] as List<dynamic>;
        return FeeResult.success(
          feesJson
              .map((f) => FeeModel.fromJson(f as Map<String, dynamic>))
              .toList(),
        );
      }
      return FeeResult.failure(
        _extractError(response.data) ?? 'Failed to load history.',
      );
    } on DioException catch (e) {
      return FeeResult.failure(_handleDioError(e));
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
        return 'Request timed out.';
      case DioExceptionType.connectionError:
        return 'Cannot reach server.';
      default:
        final msg = e.response?.data?['message'];
        return msg is String ? msg : 'Network error.';
    }
  }
}