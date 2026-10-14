package com.example.frontend

import android.util.Log

/** Terminal / logcat tag for app-triggered screen + face monitoring. */
object MonitoringLog {
    const val TAG = "MindSyncMonitor"

    fun i(message: String) {
        Log.i(TAG, message)
    }

    fun e(message: String, throwable: Throwable? = null) {
        if (throwable != null) {
            Log.e(TAG, message, throwable)
        } else {
            Log.e(TAG, message)
        }
    }

    fun w(message: String) {
        Log.w(TAG, message)
    }
}
