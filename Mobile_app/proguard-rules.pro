# ============================================================
# proguard-rules.pro — EduPay Android ProGuard / R8 Rules
#
# PRD Reference: Section 10 — Security & Compliance
#   "Role-based access control (RBAC) on all endpoints"
#   R8 minification must not strip security-critical classes.
#
# PRD Reference: Section 08 — Tech Stack
#   Firebase, WorkManager, Hive, Socket.IO all require
#   specific keep rules to survive R8 aggressive shrinking.
#
# Applied in app/build.gradle release buildType:
#   proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'),
#                 'proguard-rules.pro'
#
# PACKAGE: com.edupay.app (from android/app/build.gradle)
# ============================================================

# ── EduPay Application Classes ───────────────────────────────────────────────

# Keep all EduPay application classes — prevents stripping of
# BootReceiver, MainActivity, and any future platform channels
-keep class com.edupay.app.** { *; }
-keepclassmembers class com.edupay.app.** { *; }

# ── Flutter Engine ────────────────────────────────────────────────────────────

# Flutter embedding classes — must survive minification
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.embedding.android.** { *; }
-keep class io.flutter.embedding.engine.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.app.** { *; }
-dontwarn io.flutter.**

# ── Firebase Cloud Messaging ──────────────────────────────────────────────────
# PRD Section 05: FCM data messages delivered even when app closed
# notification.service.js error codes handled:
#   messaging/registration-token-not-registered
#   messaging/invalid-registration-token
#   messaging/invalid-argument

-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.firebase.messaging.FirebaseMessagingService { *; }
-keep class com.google.firebase.messaging.RemoteMessage { *; }
-keep class com.google.firebase.iid.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# FCM token classes — must not be stripped
# Token rotation on each login (PRD Section 10)
-keepclassmembers class com.google.firebase.messaging.FirebaseMessaging {
    public *;
}

# ── WorkManager ───────────────────────────────────────────────────────────────
# PRD Section 07: "workmanager (background tasks)"
# Background file downloads via WorkManager
# BootReceiver.kt re-enqueues pending downloads after reboot

-keep class androidx.work.** { *; }
-keep class androidx.work.impl.** { *; }
-keep class androidx.work.WorkManager { *; }
-keep class androidx.work.Worker { *; }
-keep class androidx.work.ListenableWorker { *; }
-keep class androidx.work.CoroutineWorker { *; }
-keepclassmembers class * extends androidx.work.Worker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
-keepclassmembers class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
-dontwarn androidx.work.**

# WorkManager task names from AppConstants:
#   edupay.download_file
#   edupay.refresh_fcm_token
-keep class * {
    @androidx.work.WorkerFactory *;
}

# ── AndroidX & Startup ────────────────────────────────────────────────────────
# InitializationProvider used in AndroidManifest.xml for
# WorkManager custom initialisation

-keep class androidx.startup.** { *; }
-keep class androidx.startup.InitializationProvider { *; }
-dontwarn androidx.startup.**

# ── Kotlin ────────────────────────────────────────────────────────────────────
# kotlin_version = '1.9.22' (from android/build.gradle)

-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-keep class kotlinx.** { *; }
-keepclassmembers class **$WhenMappings {
    <fields>;
}
-keepclassmembers class kotlin.Metadata {
    public <methods>;
}
-dontwarn kotlin.**
-dontwarn kotlinx.**

# Kotlin coroutines — required for WorkManager CoroutineWorker
-keepclassmembernames class kotlinx.** {
    volatile <fields>;
}
-keepclassmembers class kotlin.coroutines.** { *; }

# ── Hive Local Database ───────────────────────────────────────────────────────
# Hive box names from AppConstants:
#   messages_box, fees_box, batches_box, downloads_box, settings_box
# PRD Section 11: "cache download queue in local DB"

-keep class com.hivedb.** { *; }
-keepclassmembers class ** {
    @com.hive.** *;
}
# Hive TypeAdapters — generated classes must survive
-keep class **$HiveFieldsAdapter { *; }
-keep class ** implements com.hive.TypeAdapter { *; }

# ── Dio / OkHttp ─────────────────────────────────────────────────────────────
# PRD Section 07: "dio (HTTP download)"
# Used in background_download_service.dart

-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-keep class okio.** { *; }

# ── Socket.IO ─────────────────────────────────────────────────────────────────
# PRD Section 06: "Chat powered by WebSocket (Socket.IO)"
# socket_io_client: ^2.0.3+1

-keep class io.socket.** { *; }
-keep class io.socket.client.** { *; }
-keep class io.socket.engineio.** { *; }
-dontwarn io.socket.**

# ── File Provider ─────────────────────────────────────────────────────────────
# PRD Section 10: "Local files stored in app-private directory"
# FileProvider authority: com.edupay.app.fileprovider

-keep class androidx.core.content.FileProvider { *; }
-keepclassmembers class androidx.core.content.FileProvider { *; }

# ── JSON Serialisation ────────────────────────────────────────────────────────
# Prevents R8 from stripping serialised model fields
# Used in FCM payload parsing and API response models

-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keepattributes SourceFile,LineNumberTable
-keepattributes Exceptions

# Gson (if used by any plugin)
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory { *; }
-keep class * implements com.google.gson.JsonSerializer { *; }
-keep class * implements com.google.gson.JsonDeserializer { *; }
-dontwarn com.google.gson.**

# ── Lifecycle / AppCompat ─────────────────────────────────────────────────────
# androidx.lifecycle:lifecycle-process:2.7.0 (from app/build.gradle)

-keep class androidx.lifecycle.** { *; }
-keep interface androidx.lifecycle.** { *; }
-keepclassmembers class * {
    @androidx.lifecycle.OnLifecycleEvent *;
}
-dontwarn androidx.lifecycle.**

# ── MultiDex ─────────────────────────────────────────────────────────────────
# multiDexEnabled true (from app/build.gradle defaultConfig)

-keep class androidx.multidex.** { *; }
-dontwarn androidx.multidex.**

# ── Cloudflare R2 / AWS SDK ───────────────────────────────────────────────────
# PRD Section 07: Cloudflare R2 signed URLs
# File downloads via signed URLs — no AWS SDK on client side,
# but keep URL parsing classes

-keep class com.amazonaws.** { *; }
-dontwarn com.amazonaws.**

# ── Security — Prevent Reverse Engineering ────────────────────────────────────
# PRD Section 10: Security & Compliance
# JWT access token expires in 15 min (PRD Section 10)
# Tokens stored in flutter_secure_storage (Keystore-backed)

# Rename all non-public identifiers aggressively
-repackageclasses 'com.edupay.obf'
-allowaccessmodification

# Remove logging in release builds (no PII leakage via logs)
# PRD Section 10: "No PII stored in FCM notification payloads"
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int i(...);
    public static int w(...);
    public static int d(...);
    public static int e(...);
}

# ── Suppress Common Warnings ──────────────────────────────────────────────────

-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
-dontwarn java.lang.invoke.**
-dontwarn sun.misc.**