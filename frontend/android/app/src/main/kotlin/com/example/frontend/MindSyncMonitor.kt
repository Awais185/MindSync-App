package com.example.frontend

import android.content.Context
import com.example.frontend.screenrecording.ScreenRecordingService

/**
 * MindSyncMonitor facade — starts/stops seamless screen chunk capture.
 * Log tag remains [MonitoringLog.TAG] ("MindSyncMonitor").
 */
object MindSyncMonitor {
    private var recordingPackage: String? = null

    fun startRecording(context: Context, packageName: String, appName: String) {
        if (packageName.isBlank()) return
        if (!TrackerPrefs.shouldAllowUsageCollection(context)) return
        if (!MonitoringPolicy.screenRecordingAllowed(context)) return
        if (!ScreenCapturePermissionStore.hasPermission(context)) {
            MonitoringLog.w("Screen recording skipped: screen capture not granted")
            return
        }
        if (recordingPackage == packageName) return
        recordingPackage = packageName
        MonitoringLog.i("SOCIAL TARGET: [$appName] — starting ScreenRecordingService")
        ScreenRecordingService.start(context.applicationContext, packageName, appName)
    }

    fun stopRecording(context: Context) {
        if (recordingPackage == null) return
        MonitoringLog.i("Screen recording stopped — MindSyncMonitor")
        recordingPackage = null
        ScreenRecordingService.stop(context.applicationContext)
    }

    fun onScreenCaptureGranted(context: Context) {
        ScreenRecordingService.onProjectionGranted(context.applicationContext)
    }

    fun isRecording(packageName: String): Boolean = recordingPackage == packageName
}
