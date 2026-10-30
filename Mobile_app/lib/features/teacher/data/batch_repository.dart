/// features/teacher/data/batch_repository.dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class StudentModel {
  const StudentModel({
    required this.id,
    required this.name,
    required this.email,
    this.enrolledAt,
  });

  final String  id;
  final String  name;
  final String  email;
  final String? enrolledAt;

  factory StudentModel.fromJson(Map<String, dynamic> json) {
    final enrollment = json['Enrollment'] as Map<String, dynamic>?;
    return StudentModel(
      id:         _safeStr(json['id'],    'unknown-id'),
      name:       _safeStr(json['name'],  'Unknown'),
      email:      _safeStr(json['email'], ''),
      enrolledAt: enrollment?['enrolled_at']?.toString(),
    );
  }
}

// ── Student Search Result Model ───────────────────────────────────────────────
// Lightweight model returned by /search-students — no enrollment data.

class StudentSearchResult {
  const StudentSearchResult({
    required this.id,
    required this.name,
    required this.email,
  });

  final String id;
  final String name;
  final String email;

  factory StudentSearchResult.fromJson(Map<String, dynamic> json) =>
      StudentSearchResult(
        id:    _safeStr(json['id'],    ''),
        name:  _safeStr(json['name'],  'Unknown'),
        email: _safeStr(json['email'], ''),
      );
}

// ── Batch Model ───────────────────────────────────────────────────────────────

class BatchModel {
  const BatchModel({
    required this.id,
    required this.name,
    required this.startDate,
    required this.feeAmount,
    required this.durationYears,
    required this.gracePeriodDays,
    required this.isActive,
    required this.teacherId,
    required this.createdAt,
    this.students     = const [],
    this.studentCount = 0,
  });

  final String             id;
  final String             name;
  final String             startDate;
  final int                feeAmount;
  final int                durationYears;
  final int                gracePeriodDays;
  final bool               isActive;
  final String             teacherId;
  final String             createdAt;
  final List<StudentModel> students;
  final int                studentCount;

  factory BatchModel.fromJson(Map<String, dynamic> json) {
    final studentsJson = json['students'] as List<dynamic>? ?? [];
    return BatchModel(
      id:              _safeStr(json['id'],              ''),
      name:            _safeStr(json['name'],             ''),
      startDate:       _safeStr(json['start_date'],       ''),
      feeAmount:       _safeInt(json['fee_amount'],       0),
      durationYears:   _safeInt(json['duration_years'],   1),
      gracePeriodDays: _safeInt(json['grace_period_days'], 7),
      isActive:        _safeBool(json['is_active'],       true),
      teacherId:       _safeStr(json['teacher_id'],       ''),
      createdAt:       _safeStr(json['created_at'],       ''),
      students: studentsJson
          .whereType<Map<String, dynamic>>()
          .map(StudentModel.fromJson)
          .toList(),
      studentCount: _safeInt(
        json['student_count'],
        studentsJson.length,
      ),
    );
  }

  BatchModel copyWith({
    String?             name,
    int?                feeAmount,
    int?                durationYears,
    int?                gracePeriodDays,
    List<StudentModel>? students,
    int?                studentCount,
  }) =>
      BatchModel(
        id:              id,
        name:            name            ?? this.name,
        startDate:       startDate,
        feeAmount:       feeAmount       ?? this.feeAmount,
        durationYears:   durationYears   ?? this.durationYears,
        gracePeriodDays: gracePeriodDays ?? this.gracePeriodDays,
        isActive:        isActive,
        teacherId:       teacherId,
        createdAt:       createdAt,
        students:        students        ?? this.students,
        studentCount:    studentCount    ?? this.studentCount,
      );
}

// ── Safe Type Helpers (module-level) ──────────────────────────────────────────

String _safeStr(dynamic v, [String fallback = '']) {
  if (v == null)   return fallback;
  if (v is String) return v;
  return v.toString();
}

int _safeInt(dynamic v, [int fallback = 0]) {
  if (v == null)   return fallback;
  if (v is int)    return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

bool _safeBool(dynamic v, [bool fallback = true]) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is int)  return v == 1;
  return fallback;
}

// ── Repository Result ─────────────────────────────────────────────────────────

class BatchResult<T> {
  const BatchResult._({this.data, this.error});
  final T?      data;
  final String? error;
  bool get isSuccess => error == null;
  bool get isFailure => error != null;
  factory BatchResult.success(T data) => BatchResult._(data: data);
  factory BatchResult.failure(String e) => BatchResult._(error: e);
}

// ── Repository ────────────────────────────────────────────────────────────────

class BatchRepository {
  BatchRepository({required this.apiClient});
  final ApiClient apiClient;

  // ── Create Batch ────────────────────────────────────────────────────────────
  Future<BatchResult<BatchModel>> createBatch({
    required String name,
    required String startDate,
    required int    feeAmount,
    required int    durationYears,
    required int    gracePeriodDays,
  }) async {
    try {
      debugPrint('═══ CREATE BATCH REQUEST ═══');
      debugPrint(
        'URL: ${apiClient.dio.options.baseUrl}${ApiEndpoints.batches}',
      );
      debugPrint('name: $name');
      debugPrint('start_date: $startDate');
      debugPrint('fee_amount: $feeAmount');
      debugPrint('duration_years: $durationYears');
      debugPrint('grace_period_days: $gracePeriodDays');
      debugPrint('════════════════════════════');

      final response = await apiClient.post(
        ApiEndpoints.batches,
        data: {
          'name':              name.trim(),
          'start_date':        startDate,
          'fee_amount':        feeAmount,
          'duration_years':    durationYears,
          'grace_period_days': gracePeriodDays,
        },
      );

      debugPrint('═══ CREATE BATCH RESPONSE ═══');
      debugPrint('status: ${response.statusCode}');
      debugPrint('data: ${response.data}');
      debugPrint('═════════════════════════════');

      if (response.statusCode == 201) {
        final responseData = response.data;
        if (responseData == null ||
            responseData['data'] == null ||
            responseData['data']['batch'] == null) {
          debugPrint(
            'WARNING: batch null in response — using empty model',
          );
          return BatchResult.failure(
            'Batch created but response was incomplete. Please refresh.',
          );
        }
        final batch = BatchModel.fromJson(
          responseData['data']['batch'] as Map<String, dynamic>,
        );
        return BatchResult.success(batch);
      }

      // Handle 422 validation errors
      if (response.statusCode == 422) {
        final errors   = response.data['errors'] as List<dynamic>?;
        final firstMsg = errors?.isNotEmpty == true
            ? (errors!.first['message'] as String?)
            : null;
        return BatchResult.failure(
          firstMsg ??
              _extractError(response.data) ??
              'Validation failed.',
        );
      }

      return BatchResult.failure(
        _extractError(response.data) ?? 'Failed to create batch.',
      );
    } on DioException catch (e) {
      debugPrint('CREATE BATCH DIO ERROR: ${e.type} — ${e.message}');
      return BatchResult.failure(_handleDioError(e));
    } catch (e, stack) {
      debugPrint('CREATE BATCH UNKNOWN ERROR: $e');
      debugPrint('STACK: $stack');
      return BatchResult.failure('Unexpected error: $e');
    }
  }

  // ── List Batches ────────────────────────────────────────────────────────────
  Future<BatchResult<List<BatchModel>>> listBatches() async {
    try {
      final response = await apiClient.get(ApiEndpoints.batches);

      if (response.statusCode == 200) {
        final batchesJson =
            response.data['data']['batches'] as List<dynamic>? ?? [];
        final batches = batchesJson
            .whereType<Map<String, dynamic>>()
            .map(BatchModel.fromJson)
            .toList();
        return BatchResult.success(batches);
      }
      return BatchResult.failure(
        _extractError(response.data) ?? 'Failed to load batches.',
      );
    } on DioException catch (e) {
      return BatchResult.failure(_handleDioError(e));
    } catch (e) {
      return BatchResult.failure('Unexpected error: $e');
    }
  }

  // ── Get Batch By Id ─────────────────────────────────────────────────────────
  Future<BatchResult<BatchModel>> getBatchById(String batchId) async {
    try {
      final response = await apiClient.get(
        ApiEndpoints.batchById(batchId),
      );

      if (response.statusCode == 200) {
        final batch = BatchModel.fromJson(
          response.data['data']['batch'] as Map<String, dynamic>,
        );
        return BatchResult.success(batch);
      }
      return BatchResult.failure(
        _extractError(response.data) ?? 'Failed to load batch.',
      );
    } on DioException catch (e) {
      return BatchResult.failure(_handleDioError(e));
    } catch (e) {
      return BatchResult.failure('Unexpected error: $e');
    }
  }

  // ── Update Batch ────────────────────────────────────────────────────────────
  Future<BatchResult<BatchModel>> updateBatch({
    required String batchId,
    String?         name,
    int?            feeAmount,
    int?            durationYears,
    int?            gracePeriodDays,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name            != null) body['name']               = name.trim();
      if (feeAmount       != null) body['fee_amount']         = feeAmount;
      if (durationYears   != null) body['duration_years']     = durationYears;
      if (gracePeriodDays != null) body['grace_period_days']  = gracePeriodDays;

      final response = await apiClient.put(
        ApiEndpoints.batchById(batchId),
        data: body,
      );

      if (response.statusCode == 200) {
        final batch = BatchModel.fromJson(
          response.data['data']['batch'] as Map<String, dynamic>,
        );
        return BatchResult.success(batch);
      }
      return BatchResult.failure(
        _extractError(response.data) ?? 'Failed to update batch.',
      );
    } on DioException catch (e) {
      return BatchResult.failure(_handleDioError(e));
    } catch (e) {
      return BatchResult.failure('Unexpected error: $e');
    }
  }

  // ── Search Students ─────────────────────────────────────────────────────────
  // Returns ALL non-enrolled students when [name] is empty,
  // or name-filtered results when [name] has content.
  // Filtering is done SERVER-SIDE for the initial load,
  // then locally in the UI for subsequent keystrokes.
  Future<BatchResult<List<StudentSearchResult>>> searchStudents({
    required String batchId,
    required String name,
  }) async {
    try {
      // Build query params — only send name if non-empty
      final queryParams = name.trim().isNotEmpty
          ? <String, dynamic>{'name': name.trim()}
          : null;

      debugPrint(
        'SEARCH STUDENTS: batchId=$batchId, name="${name.trim()}", '
        'params=$queryParams',
      );

      final response = await apiClient.get(
        '/batches/$batchId/search-students',
        queryParameters: queryParams,
      );

      debugPrint(
        'SEARCH STUDENTS RESPONSE: ${response.statusCode} '
        '→ ${response.data}',
      );

      if (response.statusCode == 200) {
        final studentsJson =
            response.data['data']['students'] as List<dynamic>? ?? [];
        final students = studentsJson
            .whereType<Map<String, dynamic>>()
            .map(StudentSearchResult.fromJson)
            .toList();
        return BatchResult.success(students);
      }

      return BatchResult.failure(
        _extractError(response.data) ?? 'Search failed.',
      );
    } on DioException catch (e) {
      debugPrint('SEARCH STUDENTS DIO ERROR: ${e.type} — ${e.message}');
      return BatchResult.failure(_handleDioError(e));
    } catch (e, stack) {
      debugPrint('SEARCH STUDENTS ERROR: $e\n$stack');
      return BatchResult.failure('Unexpected error: $e');
    }
  }

  // ── Enroll Student ──────────────────────────────────────────────────────────
  Future<BatchResult<bool>> enrollStudent({
    required String batchId,
    required String studentId,
  }) async {
    try {
      final response = await apiClient.post(
        ApiEndpoints.batchEnroll(batchId),
        data: {'student_id': studentId},
      );

      if (response.statusCode == 201) {
        return BatchResult.success(true);
      }
      return BatchResult.failure(
        _extractError(response.data) ?? 'Failed to enroll student.',
      );
    } on DioException catch (e) {
      return BatchResult.failure(_handleDioError(e));
    } catch (e) {
      return BatchResult.failure('Unexpected error: $e');
    }
  }

  // ── Remove Student ──────────────────────────────────────────────────────────
  Future<BatchResult<bool>> removeStudent({
    required String batchId,
    required String studentId,
  }) async {
    try {
      final response = await apiClient.delete(
        ApiEndpoints.batchRemoveStudent(batchId, studentId),
      );

      if (response.statusCode == 200) {
        return BatchResult.success(true);
      }
      return BatchResult.failure(
        _extractError(response.data) ?? 'Failed to remove student.',
      );
    } on DioException catch (e) {
      return BatchResult.failure(_handleDioError(e));
    } catch (e) {
      return BatchResult.failure('Unexpected error: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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
      case DioExceptionType.badResponse:
        final msg = e.response?.data?['message'];
        return msg is String
            ? msg
            : 'Server error (${e.response?.statusCode}).';
      default:
        final msg = e.response?.data?['message'];
        return msg is String ? msg : 'Network error. Please try again.';
    }
  }
}