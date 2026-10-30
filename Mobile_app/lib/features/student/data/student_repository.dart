/// features/student/data/student_repository.dart
/// Data layer for student-specific API operations.
///
/// PRD Reference: Section 02 — Student Role
///   "View payment status & history"
///   "Receive overdue notifications"
///   "Participate in batch chat"
///
/// PRD Reference: Section 09 — Fee API Endpoints
///   GET /fees/my-fees           — Student's own fee history
///   GET /batches                — Student's enrolled batches

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../teacher/data/batch_repository.dart';
import '../../teacher/data/fee_repository.dart';

// ── Student Fee Summary ───────────────────────────────────────────────────────

class StudentFeeSummary {
  const StudentFeeSummary({
    required this.currentMonth,
    required this.totalDue,
    required this.paid,
    required this.pending,
    required this.overdue,
    required this.total,
    required this.fees,
  });

  final String       currentMonth;
  final int          totalDue;
  final int          paid;
  final int          pending;
  final int          overdue;
  final int          total;
  final List<FeeModel> fees;

  factory StudentFeeSummary.fromJson(Map<String, dynamic> json) {
    final summary  = json['current_month_summary'] as Map<String, dynamic>;
    final feesJson = json['fees'] as List<dynamic>;

    return StudentFeeSummary(
      currentMonth: json['current_month'] as String,
      totalDue:     summary['total_due']  as int,
      paid:         summary['paid']       as int,
      pending:      summary['pending']    as int,
      overdue:      summary['overdue']    as int,
      total:        summary['total']      as int,
      fees: feesJson
          .map((f) => FeeModel.fromJson(f as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ── Result ────────────────────────────────────────────────────────────────────

class StudentResult<T> {
  const StudentResult._({this.data, this.error});
  final T?      data;
  final String? error;
  bool get isSuccess => error == null;
  bool get isFailure => error != null;
  factory StudentResult.success(T d) => StudentResult._(data: d);
  factory StudentResult.failure(String e) => StudentResult._(error: e);
}

// ── Repository ────────────────────────────────────────────────────────────────

class StudentRepository {
  StudentRepository({required this.apiClient});
  final ApiClient apiClient;

  // ── My Fees ─────────────────────────────────────────────────────────────────
  /// GET /fees/my-fees
  /// PRD Section 02: "View payment status & history"
  Future<StudentResult<StudentFeeSummary>> getMyFees({
    String? month,
    int     page  = 1,
    int     limit = 12,
  }) async {
    try {
      final params = <String, dynamic>{'page': page, 'limit': limit};
      if (month != null) params['month'] = month;

      final response = await apiClient.get(
        ApiEndpoints.myFees,
        queryParameters: params,
      );

      if (response.statusCode == 200) {
        final summary = StudentFeeSummary.fromJson(
          response.data['data'] as Map<String, dynamic>,
        );
        return StudentResult.success(summary);
      }
      return StudentResult.failure(
        _extractError(response.data) ?? 'Failed to load fees.',
      );
    } on DioException catch (e) {
      return StudentResult.failure(_handleDioError(e));
    }
  }

  // ── My Batches ───────────────────────────────────────────────────────────────
  /// GET /batches
  /// Student sees enrolled batches with teacher info.
  Future<StudentResult<List<BatchModel>>> getMyBatches() async {
    try {
      final response = await apiClient.get(ApiEndpoints.batches);

      if (response.statusCode == 200) {
        final batchesJson =
            response.data['data']['batches'] as List<dynamic>;
        final batches = batchesJson
            .map((b) => BatchModel.fromJson(b as Map<String, dynamic>))
            .toList();
        return StudentResult.success(batches);
      }
      return StudentResult.failure(
        _extractError(response.data) ?? 'Failed to load batches.',
      );
    } on DioException catch (e) {
      return StudentResult.failure(_handleDioError(e));
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String? _extractError(dynamic data) {
    if (data is Map) return data['message'] as String?;
    return null;
  }

  String _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Check your internet.';
      case DioExceptionType.connectionError:
        return 'Cannot reach server. Check your internet.';
      default:
        final msg = e.response?.data?['message'];
        return msg is String ? msg : 'Network error. Please try again.';
    }
  }
}