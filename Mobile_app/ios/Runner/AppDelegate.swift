/**
 * AppDelegate.swift
 * EduPay iOS Application Delegate.
 *
 * PRD Reference: Section 05 — Notification System
 *   "Register background message handler via FirebaseMessaging.onBackgroundMessage()"
 *   FCM requires UNUserNotificationCenter delegate and
 *   application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
 *   to register for APNs and forward tokens to Firebase.
 *
 * PRD Reference: Section 07 — Smart File Sync
 *   UIApplication.shared.setMinimumBackgroundFetchInterval is set here
 *   to allow periodic background fetch for file download resumption.
 *   WorkManager (flutter_workmanager) registers its own BGTaskScheduler
 *   via its plugin — no manual registration needed here.
 *
 * PRD Reference: Section 10 — Security & Compliance
 *   No PII stored in FCM payloads — the AppDelegate does not log
 *   notification content.
 *
 * FLUTTER EMBEDDING:
 *   FlutterAppDelegate handles all Flutter lifecycle events.
 *   GeneratedPluginRegistrant auto-registers all pub.dev plugins.
 *   No manual plugin registration needed (Flutter 3.x auto-registration).
 */

import UIKit
import Flutter
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // ── Firebase Initialisation ───────────────────────────────────────
        // Must be called before any other Firebase usage.
        // Reads GoogleService-Info.plist automatically.
        // PRD Section 05: Firebase Cloud Messaging
        FirebaseApp.configure()

        // ── UNUserNotificationCenter Delegate ─────────────────────────────
        // Required for FCM to show notifications when app is in foreground.
        // flutter_local_notifications also uses this delegate.
        UNUserNotificationCenter.current().delegate = self

        // ── FCM Messaging Delegate ────────────────────────────────────────
        // Required to receive FCM token refresh callbacks.
        // Token is forwarded to EduPay backend via PATCH /auth/fcm-token
        Messaging.messaging().delegate = self

        // ── Background Fetch Interval ─────────────────────────────────────
        // PRD Section 07: Enable periodic background fetch for file downloads.
        // WorkManager sets its own BGTask identifiers, but this enables
        // the legacy background fetch mode as a fallback.
        application.setMinimumBackgroundFetchInterval(
            UIApplication.backgroundFetchIntervalMinimum
        )

        // ── Register Flutter Plugins ──────────────────────────────────────
        // Auto-registers all pub.dev plugins declared in pubspec.yaml
        GeneratedPluginRegistrant.register(with: self)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // ── APNs Token Registration ───────────────────────────────────────────────
    /**
     * Called when APNs successfully registers the device.
     * Forward the APNs token to Firebase — FCM uses this to send push notifications.
     *
     * PRD Section 05: FCM requires APNs token for iOS delivery.
     */
    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Set APNs token in Firebase Messaging
        Messaging.messaging().apnsToken = deviceToken
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    // ── APNs Registration Failure ─────────────────────────────────────────────
    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Non-fatal: app continues working without push notifications
        // Logged for debugging — no user-facing error shown
        print("[EduPay] APNs registration failed: \(error.localizedDescription)")
    }

    // ── Background URL Session ────────────────────────────────────────────────
    /**
     * Called when a background URL session completes.
     * Required for background file downloads via URLSession.
     * WorkManager (flutter_workmanager) uses this for download continuity.
     *
     * PRD Section 07: "Auto-download teacher files in background"
     */
    override func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    // ── Foreground Notification Presentation ─────────────────────────────────
    /**
     * UNUserNotificationCenterDelegate
     * Called when a notification arrives while the app is in the FOREGROUND.
     *
     * PRD Section 05: Show notification banner even when app is open.
     * completionHandler is called with all options to show alert + badge + sound.
     */
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        // Forward to Firebase Messaging for tracking
        Messaging.messaging().appDidReceiveMessage(userInfo)

        // Show notification even when app is in foreground
        // PRD Section 05: Fee overdue alerts must be prominent
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .badge, .sound, .list])
        } else {
            completionHandler([.alert, .badge, .sound])
        }
    }

    // ── Notification Response (Tap) ───────────────────────────────────────────
    /**
     * Called when the user taps a notification.
     * The Flutter layer (firebase_messaging) handles routing via
     * FirebaseMessaging.onMessageOpenedApp stream in main.dart.
     */
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Messaging.messaging().appDidReceiveMessage(userInfo)
        super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }
}

// ── FCM Messaging Delegate Extension ─────────────────────────────────────────

extension AppDelegate: MessagingDelegate {

    /**
     * Called when Firebase refreshes the FCM registration token.
     *
     * PRD Section 11 — FCM Token Staleness:
     *   "Re-register token on every app launch;
     *    store latest token in DB"
     *
     * The Flutter layer (firebase_messaging) also listens for token refresh
     * via FirebaseMessaging.instance.onTokenRefresh stream and sends the
     * token to backend via PATCH /auth/fcm-token.
     * This delegate method is a redundant safety net.
     */
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }

        // Log in debug — do NOT log in production (token is sensitive)
        #if DEBUG
        print("[EduPay] FCM token refreshed: \(String(token.prefix(20)))...")
        #endif

        // Notify the Flutter layer via NotificationCenter
        // flutter_workmanager and firebase_messaging handle the actual
        // token update to backend
        NotificationCenter.default.post(
            name: Notification.Name("FCMTokenDidRefresh"),
            object: nil,
            userInfo: ["token": token]
        )
    }
}