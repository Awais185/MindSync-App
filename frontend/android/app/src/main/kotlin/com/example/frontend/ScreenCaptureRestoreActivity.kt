package com.example.frontend

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle

/**
 * Transparent activity to renew MediaProjection when the saved token expired.
 * Started from the background service (throttled) so the user is not sent to MindSync home.
 */
class ScreenCaptureRestoreActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (ScreenCapturePermissionStore.hasPermission(this)) {
            BackgroundUsageService.notifyScreenCaptureGranted(applicationContext)
            finish()
            return
        }
        val mgr = getSystemService(MediaProjectionManager::class.java)
        val captureIntent =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                mgr.createScreenCaptureIntent(
                    MediaProjectionConfig.createConfigForDefaultDisplay(),
                )
            } else {
                mgr.createScreenCaptureIntent()
            }
        @Suppress("DEPRECATION")
        startActivityForResult(captureIntent, REQUEST_CODE)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE) {
            ScreenCapturePermissionStore.save(this, resultCode, data)
            if (ScreenCapturePermissionStore.hasPermission(this)) {
                BackgroundUsageService.notifyScreenCaptureGranted(applicationContext)
            }
        }
        finish()
    }

    companion object {
        private const val REQUEST_CODE = 7302
        private const val PREFS = "mindsync_screen_capture_restore"
        private const val KEY_LAST_ATTEMPT_MS = "last_attempt_ms"
        private const val MIN_INTERVAL_FIRST_MS = 3 * 60 * 1000L
        private const val MIN_INTERVAL_RENEW_MS = 30 * 60 * 1000L

        /**
         * Background services must NOT auto-open the MediaProjection dialog.
         * Permission is requested once from Flutter onboarding or an explicit user action.
         */
        @Deprecated("Use requestExplicitly from MainActivity / user tap only")
        fun requestIfNeeded(context: Context) {
            // Intentionally no-op: avoids repeated system prompts while user is in other apps.
            if (!ScreenCapturePermissionStore.hasPermission(context.applicationContext)) {
                MonitoringLog.w(
                    "Screen capture not active — grant once in MindSync onboarding or Settings",
                )
            }
        }

        /** User-initiated grant (onboarding button, home screen, MainActivity channel). */
        fun requestExplicitly(context: Context) {
            val app = context.applicationContext
            if (ScreenCapturePermissionStore.hasPermission(app)) return
            if (!TrackerPrefs.shouldAllowUsageCollection(app)) return
            val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val now = System.currentTimeMillis()
            if (now - prefs.getLong(KEY_LAST_ATTEMPT_MS, 0L) < 2_000L) return
            prefs.edit().putLong(KEY_LAST_ATTEMPT_MS, now).apply()
            MonitoringLog.i("Requesting screen capture permission (user-initiated)")
            val intent =
                Intent(app, ScreenCaptureRestoreActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            try {
                app.startActivity(intent)
            } catch (e: Exception) {
                MonitoringLog.w("Screen capture consent activity failed: ${e.message}")
            }
        }
    }
}
