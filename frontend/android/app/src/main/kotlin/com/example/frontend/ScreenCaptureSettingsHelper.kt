package com.example.frontend

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings

/**
 * Screen recording on Android is **not** a toggle in App info — it is the system
 * MediaProjection dialog launched from [MainActivity.launchScreenCaptureConsent].
 */
object ScreenCaptureSettingsHelper {
    fun openMindSyncAppInfo(context: Context) {
        openMindSyncInSystemSettings(context)
    }

    fun openMindSyncInSystemSettings(context: Context) {
        val appContext = context.applicationContext
        val packageName = appContext.packageName
        val intents =
            listOf(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", packageName, null)
                },
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    Intent(Settings.ACTION_APPLICATION_SETTINGS)
                } else {
                    null
                },
                Intent(Settings.ACTION_SETTINGS),
            ).filterNotNull()

        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                appContext.startActivity(intent)
                return
            } catch (_: Exception) {
                continue
            }
        }
    }
}
