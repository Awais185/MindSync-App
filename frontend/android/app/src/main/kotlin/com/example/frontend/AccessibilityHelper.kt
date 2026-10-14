package com.example.frontend

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings

object AccessibilityHelper {
    fun isVideoDetectorEnabled(context: Context): Boolean {
        val expected = ComponentName(context, VideoPlaybackDetectorService::class.java)
        val enabled =
            Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ) ?: return false
        return enabled.split(':').any { part ->
            val cn = ComponentName.unflattenFromString(part.trim())
            cn != null && cn == expected
        }
    }

    fun openAccessibilitySettings(context: Context) {
        context.startActivity(
            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )
    }
}
