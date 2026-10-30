/// core/constants/app_constants.dart
/// Application-wide constant values.
///
/// Centralised constants prevent magic strings/numbers scattered across
/// the codebase and make PRD-specified values easy to update.

class AppConstants {
  AppConstants._();

  // ── API ───────────────────────────────────────────────────────────────────
  // Base URL — override for production in a flavour/env config
  static const String apiBaseUrl     = 'http://192.168.1.2:5000/api/v1'; // Android emulator
  static const String apiBaseUrlProd = 'https://192.168.1.2:5000/api/v1';

  // HTTP timeouts
  static const int connectTimeoutMs  = 10000; // 10 seconds
  static const int receiveTimeoutMs  = 30000; // 30 seconds

  // ── Socket.IO ─────────────────────────────────────────────────────────────
  static const String socketBaseUrl     = 'http://192.168.1.2:5000';
  static const String socketBaseUrlProd = 'wss://192.168.1.2:5000';

  // PRD Section 01: "Chat latency <500ms"
  static const int socketConnectTimeout = 5000;
  static const int socketPingInterval   = 25000;
  static const int socketPingTimeout    = 60000;

  // ── Secure Storage Keys ───────────────────────────────────────────────────
  static const String keyAccessToken   = 'access_token';
  static const String keyRefreshToken  = 'refresh_token';
  static const String keyUserId        = 'user_id';
  static const String keyUserRole      = 'user_role';
  static const String keyAvatarId  = 'avatar_id';   // NEW
  static const String keyUserName      = 'user_name';
  static const String keyUserEmail     = 'user_email';
  static const String keyDeviceId      = 'device_id';
  static const String keyRefreshExpiry = 'refresh_token_expires';

  // ── Hive Box Names ────────────────────────────────────────────────────────
  static const String hiveMessages     = 'messages_box';
  static const String hiveFees         = 'fees_box';
  static const String hiveBatches      = 'batches_box';
  static const String hiveDownloads    = 'downloads_box';
  static const String hiveSettings     = 'settings_box';

  // ── WorkManager Task Names ────────────────────────────────────────────────
  // PRD Section 07: Background file downloads
  static const String downloadFileTaskName   = 'edupay.download_file';
  static const String refreshFcmTokenTaskName = 'edupay.refresh_fcm_token';

  // ── File / Storage ────────────────────────────────────────────────────────
  // PRD Section 11: "Enforce max file size (e.g., 25 MB)"
  static const int maxFileSizeBytes = 26214400; // 25 MB
  static const int maxFileSizeMb    = 25;

  // PRD Section 07: Files deleted from server after 12h
  static const int fileServerExpiryHours = 12;

  // Supported file extensions for display (PRD Section 06)
  static const List<String> supportedImageTypes = ['jpg', 'jpeg', 'png', 'webp'];
  static const List<String> supportedDocTypes   = ['pdf', 'docx', 'xlsx', 'zip'];
  static const List<String> supportedAudioTypes = ['aac', 'ogg', 'mp3', 'mp4'];

  // ── Pagination ────────────────────────────────────────────────────────────
  static const int chatPageSize    = 30;
  static const int feePageSize     = 12;
  static const int batchPageSize   = 20;

  // ── Fee / Billing ─────────────────────────────────────────────────────────
  // PRD Section 04: Payment Status States
  static const String statusPending = 'pending';
  static const String statusOverdue = 'overdue';
  static const String statusPaid    = 'paid';

  // ── User Roles ────────────────────────────────────────────────────────────
  // PRD Section 02: Role Definitions
  static const String roleTeacher = 'teacher';
  static const String roleStudent = 'student';

  // ── UI ────────────────────────────────────────────────────────────────────
  static const double borderRadius     = 12.0;
  static const double borderRadiusSm   = 8.0;
  static const double borderRadiusLg   = 16.0;
  static const double cardPadding      = 16.0;
  static const double screenPadding    = 20.0;
  static const double bottomNavHeight  = 60.0;

  // Animation durations
  static const int animDurationFast    = 200;  // ms
  static const int animDurationNormal  = 350;  // ms
  static const int animDurationSlow    = 500;  // ms

  // ── Voice Recording ───────────────────────────────────────────────────────
  static const int maxVoiceRecordSeconds = 300; // 5 minutes max

  // ── FCM Notification Channel ──────────────────────────────────────────────
  static const String fcmChannelId   = 'edupay_channel';
  static const String fcmChannelName = 'EduPay Notifications';

  // ── Route Names ───────────────────────────────────────────────────────────
  static const String routeSplash       = '/';
  static const String routeLogin        = '/login';
  static const String routeRegister     = '/register';
  static const String routeTeacherHome  = '/teacher/home';
  static const String routeStudentHome  = '/student/home';
  static const String routeBatchDetail  = '/batch/:id';
  static const String routeChat         = '/chat/:batchId';
  static const String routeFeeDetail    = '/fees/:batchId';
  static const String routeProfile      = '/profile';
  static const String routeNotifications = '/notifications';
}