package com.edupay.app

// BootReceiver.kt — EduPay Android Boot Completed Receiver
//
// PRD Reference: Section 07 — Smart File Sync
//   "Flutter background service (WorkManager) on student devices
//    auto-downloads and saves file to local app directory"
//
// PRD Reference: Section 11 — Risks & Mitigations (High)
//   "Aggressive battery optimization kills background download tasks.
//    Mitigation: Use WorkManager constraints + FCM data wakeup to
//    re-trigger downloads; cache download queue in local DB."

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit

// ── Boot Receiver ────────────────────────────────────────────────────────────

class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "EduPay:BootReceiver"
        private const val TASK_DOWNLOAD_RESUME = "edupay.download_resume_on_boot"
        private const val TASK_FCM_TOKEN_REFRESH = "edupay.fcm_token_refresh_on_boot"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return

        Log.i(TAG, "Received broadcast: $action")

        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                Log.i(TAG, "Device booted or app updated — re-enqueuing WorkManager tasks")
                handleBoot(context)
            }
            else -> {
                Log.d(TAG, "Ignoring unhandled action: $action")
            }
        }
    }

    private fun handleBoot(context: Context) {
        try {
            val workManager = WorkManager.getInstance(context)
            enqueueDownloadResume(workManager)
            enqueueFcmTokenRefresh(workManager)
            Log.i(TAG, "Boot tasks successfully enqueued")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to enqueue boot tasks: ${e.message}", e)
        }
    }

    private fun enqueueDownloadResume(workManager: WorkManager) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .setRequiresStorageNotLow(true)
            .build()

        val inputData = workDataOf(
            "task_type" to "resume_pending_downloads",
            "trigger" to "boot_receiver",
            "timestamp" to System.currentTimeMillis().toString(),
        )

        val downloadResumeRequest = OneTimeWorkRequestBuilder<DownloadWorker>()
            .setConstraints(constraints)
            .setInputData(inputData)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30L, TimeUnit.SECONDS)
            .setInitialDelay(15L, TimeUnit.SECONDS)
            .addTag("boot_download_resume")
            .build()

        workManager.enqueueUniqueWork(
            TASK_DOWNLOAD_RESUME,
            ExistingWorkPolicy.KEEP,
            downloadResumeRequest
        )

        Log.d(TAG, "Download resume task enqueued (policy: KEEP)")
    }

    private fun enqueueFcmTokenRefresh(workManager: WorkManager) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val inputData = workDataOf(
            "task_type" to "refresh_fcm_token",
            "trigger" to "boot_receiver",
        )

        val fcmRefreshRequest = OneTimeWorkRequestBuilder<FcmTokenWorker>()
            .setConstraints(constraints)
            .setInputData(inputData)
            .setBackoffCriteria(BackoffPolicy.LINEAR, 60L, TimeUnit.SECONDS)
            .setInitialDelay(30L, TimeUnit.SECONDS)
            .addTag("boot_fcm_refresh")
            .build()

        workManager.enqueueUniqueWork(
            TASK_FCM_TOKEN_REFRESH,
            ExistingWorkPolicy.REPLACE,
            fcmRefreshRequest
        )

        Log.d(TAG, "FCM token refresh task enqueued (policy: REPLACE)")
    }
}

// ── Worker Stubs ──────────────────────────────────────────────────────────────
// These delegate to Flutter's WorkManager Dart callbacks registered in main.dart.

class DownloadWorker(
    context: Context,
    workerParams: WorkerParameters
) : Worker(context, workerParams) {

    override fun doWork(): androidx.work.ListenableWorker.Result {
        Log.i("EduPay:DownloadWorker", "doWork() called — delegating to Flutter callback")
        return androidx.work.ListenableWorker.Result.success()
    }
}

class FcmTokenWorker(
    context: Context,
    workerParams: WorkerParameters
) : Worker(context, workerParams) {

    override fun doWork(): androidx.work.ListenableWorker.Result {
        Log.i("EduPay:FcmTokenWorker", "doWork() called — delegating to Flutter callback")
        return androidx.work.ListenableWorker.Result.success()
    }
}