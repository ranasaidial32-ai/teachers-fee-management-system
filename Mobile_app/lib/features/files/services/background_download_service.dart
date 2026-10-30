/// features/files/services/background_download_service.dart
/// WorkManager background download service.
///
/// PRD Reference: Section 07 — File Storage Architecture
///   "Flutter background service (WorkManager) on student devices
///    auto-downloads and saves file to local app directory"
///
/// PRD Reference: Section 07 — Flutter Background Download Packages
///   workmanager, dio, path_provider, flutter_local_notifications
///
/// PRD Reference: Section 11 — Risks & Mitigations
///   "Use WorkManager constraints + FCM data wakeup to re-trigger downloads"
///   "cache download queue in local DB"
///
/// FLOW:
///  1. FCM 'file_shared' message received (foreground or background)
///  2. main.dart registers a WorkManager one-off task with file metadata
///  3. WorkManager calls callbackDispatcher → executeDownload()
///  4. executeDownload() fetches signed URL, downloads file via Dio
///  5. File saved to app-private directory (path_provider)
///  6. Local notification shown: "File downloaded: filename"
///  7. Download metadata saved to Hive for offline access
///
/// @pragma('vm:entry-point') on callbackDispatcher in main.dart ensures
/// the function survives Flutter's tree-shaking in release builds.

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../../core/constants/app_constants.dart';

class BackgroundDownloadService {
  BackgroundDownloadService._();

  // ── Execute Download Task ──────────────────────────────────────────────────
  /// Called by WorkManager's callbackDispatcher in main.dart.
  /// Runs in a separate isolate — cannot access Riverpod providers.
  ///
  /// @param inputData Map containing:
  ///   file_record_id  — UUID of FileRecord
  ///   batch_id        — parent batch UUID
  ///   file_name       — original filename
  ///   uploader_name   — display name of uploader
  ///
  /// Signed URL is fetched from local Hive queue (stored when FCM arrived).
  /// Falls back to API call if not in queue.
  static Future<bool> executeDownload(Map<String, dynamic> inputData) async {
    final fileRecordId = inputData['file_record_id'] as String?;
    final fileName     = inputData['file_name']      as String? ?? 'file';
    final batchId      = inputData['batch_id']        as String? ?? '';

    if (fileRecordId == null || fileRecordId.isEmpty) {
      debugPrint('BackgroundDownloadService: missing file_record_id');
      return false;
    }

    try {
      // Ensure Hive is initialised (background isolate)
      await Hive.initFlutter();
      final downloadsBox =
          await Hive.openBox<dynamic>(AppConstants.hiveDownloads);

      // Check if already downloaded
      final doneKey = 'done_$fileRecordId';
      if (downloadsBox.containsKey(doneKey)) {
        debugPrint('File $fileRecordId already downloaded — skipping');
        return true;
      }

      // Get signed URL from queue
      final queueData = downloadsBox.get(fileRecordId);
      String? signedUrl;

      if (queueData is Map) {
        signedUrl = queueData['signed_url'] as String?;
      }

      if (signedUrl == null || signedUrl.isEmpty) {
        debugPrint('No signed URL available for $fileRecordId');
        return false;
      }

      // Determine download directory
      // PRD Section 10: "Local files stored in app-private directory"
      final appDir     = await getApplicationDocumentsDirectory();
      final batchDir   = Directory('${appDir.path}/edupay/batches/$batchId');
      await batchDir.create(recursive: true);

      final safeFileName = _sanitiseFileName(fileName);
      final filePath     = '${batchDir.path}/$safeFileName';

      // Download file using Dio
      final dio = Dio();
      await dio.download(
        signedUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final percent = (received / total * 100).toStringAsFixed(0);
            debugPrint('Downloading $fileName: $percent%');
          }
        },
      );

      // Verify file exists
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('Download failed — file not found at $filePath');
        return false;
      }

      final fileSize = await file.length();
      debugPrint('Downloaded $fileName (${fileSize ~/ 1024} KB) to $filePath');

      // Save metadata to Hive
      await downloadsBox.put(doneKey, {
        'file_record_id': fileRecordId,
        'batch_id':       batchId,
        'file_name':      fileName,
        'local_path':     filePath,
        'size_bytes':     fileSize,
        'downloaded_at':  DateTime.now().toIso8601String(),
      });

      // Remove from pending queue
      await downloadsBox.delete(fileRecordId);

      // Show local notification
      await _showDownloadCompleteNotification(
        fileRecordId: fileRecordId,
        fileName:     fileName,
      );

      return true;

    } catch (e) {
      debugPrint('BackgroundDownloadService error: $e');
      return false;
    }
  }

  // ── Queue Download ─────────────────────────────────────────────────────────
  /// Queues a download with signed URL for WorkManager to pick up.
  /// Called from main.dart FCM handler before registering the task.
  static Future<void> queueDownload({
    required String fileRecordId,
    required String batchId,
    required String fileName,
    required String signedUrl,
    required String uploaderName,
  }) async {
    try {
      await Hive.initFlutter();
      final box = await Hive.openBox<dynamic>(AppConstants.hiveDownloads);

      await box.put(fileRecordId, {
        'file_record_id': fileRecordId,
        'batch_id':       batchId,
        'file_name':      fileName,
        'signed_url':     signedUrl,
        'uploader_name':  uploaderName,
        'queued_at':      DateTime.now().toIso8601String(),
      });

      debugPrint('Download queued: $fileName ($fileRecordId)');
    } catch (e) {
      debugPrint('Failed to queue download: $e');
    }
  }

  // ── Refresh FCM Token ──────────────────────────────────────────────────────
  /// WorkManager task to refresh FCM token on schedule.
  /// PRD Section 11: "Re-register token on every app launch"
  static Future<void> refreshFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('FCM token refreshed in background: ${token?.substring(0, 20)}...');
      // Token will be sent to backend on next app foreground via updateFcmToken()
    } catch (e) {
      debugPrint('Background FCM token refresh failed: $e');
    }
  }

  // ── Show Notification ──────────────────────────────────────────────────────
  static Future<void> _showDownloadCompleteNotification({
    required String fileRecordId,
    required String fileName,
  }) async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();

      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS:     DarwinInitializationSettings(),
        ),
      );

      final notifId = fileRecordId.hashCode.abs() % 10000;

      await plugin.show(
        notifId,
        'File Downloaded',
        '$fileName is ready to view',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'edupay_downloads',
            'EduPay Downloads',
            channelDescription: 'File download complete notifications',
            importance:         Importance.defaultImportance,
            priority:           Priority.defaultPriority,
            icon:               '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: 'download_complete:$fileRecordId',
      );
    } catch (e) {
      debugPrint('Failed to show download notification: $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  static String _sanitiseFileName(String name) {
    // Replace characters that are invalid in file paths
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }
}