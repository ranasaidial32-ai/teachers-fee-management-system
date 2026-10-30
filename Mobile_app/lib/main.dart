// lib/main.dart
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'firebase_options.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/services/storage_service.dart';
import 'features/files/services/background_download_service.dart';

// ── FCM Background Handler ────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Re-initialize Firebase in the background isolate
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('FCM background message: ${message.messageId}');

  // NOTE: Do NOT call Workmanager() here — it may not be initialized
  // in the background isolate. Use a simple notification instead.
  try {
    await _handleFCMMessage(message);
  } catch (e) {
    debugPrint('Background FCM handler error (non-fatal): $e');
  }
}

// ── WorkManager Dispatcher ────────────────────────────────────────────────────
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      switch (taskName) {
        case AppConstants.downloadFileTaskName:
          await BackgroundDownloadService.executeDownload(inputData ?? {});
          return true;
        case AppConstants.refreshFcmTokenTaskName:
          await BackgroundDownloadService.refreshFcmToken();
          return true;
        default:
          debugPrint('Unknown WorkManager task: $taskName');
          return false;
      }
    } catch (e) {
      debugPrint('WorkManager task error ($taskName): $e');
      return false;
    }
  });
}

// ── FCM Message Handler ───────────────────────────────────────────────────────
Future<void> _handleFCMMessage(RemoteMessage message) async {
  final data = message.data;
  final type = data['type'] ?? '';

  switch (type) {
    case 'fee_overdue':
      await _showLocalNotification(
        id:      1,
        title:   'Fee Overdue — ${data['batch_name'] ?? ''}',
        body:    'Your fee of ₹${data['amount_due'] ?? ''} for '
                 '${data['month'] ?? ''} is overdue.',
        payload: 'fee_overdue:${data['batch_id'] ?? ''}',
      );

    case 'file_shared':
      // Queue download via WorkManager (only works in foreground/main isolate)
      try {
        await Workmanager().registerOneOffTask(
          'download_${data['file_record_id'] ?? DateTime.now().millisecondsSinceEpoch}',
          AppConstants.downloadFileTaskName,
          inputData: {
            'file_record_id': data['file_record_id'] ?? '',
            'batch_id':       data['batch_id']       ?? '',
            'file_name':      data['file_name']      ?? '',
            'uploader_name':  data['uploader_name']  ?? '',
          },
          constraints: Constraints(
            networkType:           NetworkType.connected,
            requiresBatteryNotLow: false,
          ),
        );
      } catch (e) {
        debugPrint('WorkManager registerOneOffTask failed (non-fatal): $e');
      }

    case 'fee_paid':
      await _showLocalNotification(
        id:      2,
        title:   'Payment Confirmed — ${data['batch_name'] ?? ''}',
        body:    'Your fee of ₹${data['amount_paid'] ?? ''} for '
                 '${data['month'] ?? ''} has been marked as paid.',
        payload: 'fee_paid:${data['batch_id'] ?? ''}',
      );

    default:
      debugPrint('Unhandled FCM type: $type');
  }
}

// ── Local Notifications ───────────────────────────────────────────────────────
final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

Future<void> _showLocalNotification({
  required int    id,
  required String title,
  required String body,
  String?         payload,
}) async {
  const androidDetails = AndroidNotificationDetails(
    AppConstants.fcmChannelId,
    AppConstants.fcmChannelName,
    channelDescription: 'Fee and file notifications from EduPay',
    importance:         Importance.high,
    priority:           Priority.high,
    showWhen:           true,
  );
  const iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );
  const details = NotificationDetails(
    android: androidDetails,
    iOS:     iosDetails,
  );
  await _localNotifications.show(id, title, body, details, payload: payload);
}

// ── Main Entry Point ──────────────────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Global error handlers ─────────────────────────────────────────────────
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('═══ FLUTTER ERROR ═══\n${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('═══ PLATFORM ERROR ═══\n$error\n$stack');
    return true; // Prevent crash
  };

  // ── Orientation ───────────────────────────────────────────────────────────
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor:          Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // ── Hive (must be before everything that uses storage) ───────────────────
  try {
    await Hive.initFlutter();
    await StorageService.initHive();
    debugPrint('Hive initialized ✓');
  } catch (e) {
    debugPrint('Hive init error (non-fatal): $e');
  }

  // ── Firebase ──────────────────────────────────────────────────────────────
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Register background handler AFTER Firebase.initializeApp
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    debugPrint('Firebase initialized ✓');
  } catch (e) {
    debugPrint('Firebase init error (non-fatal): $e');
  }

  // ── Local Notifications ───────────────────────────────────────────────────
  try {
    await _requestNotificationPermission();
    await _initLocalNotifications();
    debugPrint('Local notifications initialized ✓');
  } catch (e) {
    debugPrint('Notification init error (non-fatal): $e');
  }

  // ── WorkManager ───────────────────────────────────────────────────────────
  // WorkManager is initialized in EduPayApplication.kt (Android) before
  // Flutter engine starts. Here we just register the Dart callback dispatcher.
  // This call is safe to fail — the app works without background downloads.
  try {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false, // Set true to see WorkManager logs in debug
    );
    debugPrint('WorkManager callback registered ✓');
  } catch (e) {
    // Non-fatal: app works without WorkManager (no background downloads)
    debugPrint('WorkManager init error (non-fatal): $e');
  }

  // ── FCM foreground listener ───────────────────────────────────────────────
  FirebaseMessaging.onMessage.listen((message) {
    debugPrint('FCM foreground message: ${message.data}');
    _handleFCMMessage(message);
  });

  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    debugPrint('FCM notification tapped: ${message.data}');
    // TODO: Navigate to relevant screen based on message.data['type']
  });

  // ── Run App ───────────────────────────────────────────────────────────────
  runApp(const ProviderScope(child: EduPayApp()));
}

// ── Notification Permission ───────────────────────────────────────────────────
Future<void> _requestNotificationPermission() async {
  await FirebaseMessaging.instance.requestPermission(
    alert:         true,
    announcement:  false,
    badge:         true,
    carPlay:       false,
    criticalAlert: false,
    provisional:   false,
    sound:         true,
  );
}

// ── Local Notifications Init ──────────────────────────────────────────────────
Future<void> _initLocalNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit     = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );

  await _localNotifications.initialize(
    const InitializationSettings(android: androidInit, iOS: iosInit),
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      debugPrint('Notification tapped: ${response.payload}');
    },
  );

  // Create the notification channel (Android 8+)
  const channel = AndroidNotificationChannel(
    AppConstants.fcmChannelId,
    AppConstants.fcmChannelName,
    description: 'Fee and file notifications from EduPay',
    importance:  Importance.high,
  );

  await _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

// ── Root App Widget ───────────────────────────────────────────────────────────
class EduPayApp extends ConsumerWidget {
  const EduPayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title:                      'EduPay',
      debugShowCheckedModeBanner: false,
      theme:                      AppTheme.lightTheme,
      darkTheme:                  AppTheme.darkTheme,
      themeMode:                  ThemeMode.system,
      routerConfig:               router,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              MediaQuery.of(context).textScaler
                  .scale(1.0)
                  .clamp(0.85, 1.2),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}