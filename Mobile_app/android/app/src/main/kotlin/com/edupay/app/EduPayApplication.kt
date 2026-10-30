package com.edupay.app

import android.app.Application
import android.util.Log
import androidx.work.Configuration
import androidx.work.WorkManager

class EduPayApplication : Application(), Configuration.Provider {

    companion object {
        private const val TAG = "EduPay:Application"
    }

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "EduPayApplication.onCreate() — initializing WorkManager")

        try {
            WorkManager.initialize(this, workManagerConfiguration)
            Log.i(TAG, "WorkManager initialized successfully ✓")
        } catch (e: IllegalStateException) {
            // Already initialized — safe to ignore on hot restart
            Log.w(TAG, "WorkManager already initialized: ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "WorkManager initialization failed: ${e.message}", e)
        }
    }

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setMinimumLoggingLevel(Log.INFO)
            .build()
}