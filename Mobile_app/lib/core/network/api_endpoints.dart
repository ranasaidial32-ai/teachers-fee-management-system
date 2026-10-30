/// core/network/api_endpoints.dart

class ApiEndpoints {
  ApiEndpoints._();

  // ── Auth ──────────────────────────────────────────────────────────────────
  static const String authRegister      = '/auth/register';
  static const String authLogin         = '/auth/login';
  static const String authRefresh       = '/auth/refresh';
  static const String authLogout        = '/auth/logout';
  static const String authMe            = '/auth/me';
  static const String authFcmToken      = '/auth/fcm-token';
  static const String authUpdateProfile = '/auth/profile';

  // ── Batches ───────────────────────────────────────────────────────────────
  static const String batches = '/batches';
  static String batchById(String id)     => '/batches/$id';
  static String batchEnroll(String id)   => '/batches/$id/enroll';
  static String batchRemoveStudent(String batchId, String studentId)
      => '/batches/$batchId/enroll/$studentId';

  // ── Student Search ────────────────────────────────────────────────────────
  // GET /batches/:id/search-students?name=xxx
  static String batchSearchStudents(String batchId, String name)
      => '/batches/$batchId/search-students?name=${Uri.encodeComponent(name)}';

  // ── Fees ──────────────────────────────────────────────────────────────────
  static String feesForBatch(String batchId) => '/fees/$batchId';
  static const String feesMarkPaid           = '/fees/mark-paid';
  static String studentFeeHistory(String id) => '/fees/student/$id';
  static const String myFees                 = '/fees/my-fees';

  // ── Chat ──────────────────────────────────────────────────────────────────
  static String chatMessages(String batchId)
      => '/chat/$batchId/messages';
  static String deleteMessage(String batchId, String messageId)
      => '/chat/$batchId/messages/$messageId';
  static String messageReaders(String batchId, String messageId)
      => '/chat/$batchId/messages/$messageId/readers';

  // ── Files ─────────────────────────────────────────────────────────────────
  static const String fileUpload              = '/files/upload';
  static String fileDelete(String fileId)     => '/files/$fileId';
  static String fileRefreshUrl(String fileId) => '/files/$fileId/refresh-url';

  // ── Notifications ─────────────────────────────────────────────────────────
  static const String myNotifications             = '/notifications/my';
  static String batchNotificationStats(String id) => '/notifications/batch/$id/stats';
  static const String failedNotifications         = '/notifications/failed';
}