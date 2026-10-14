package com.example.frontend

import android.content.Context
import java.util.UUID

/** Per social-app foreground session id (upload metadata). */
object MonitoringSession {
    private const val PREFS = "mindsync_monitoring_session"
    private const val KEY_SESSION_ID = "session_id"
    private const val KEY_PACKAGE = "package"
    private const val KEY_STARTED_MS = "started_ms"
    private const val KEY_TOTAL_RECORDED_MS = "total_recorded_ms"
    private const val KEY_CHUNK_COUNT = "chunk_count"

    fun onSocialAppStarted(context: Context, packageName: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val currentPkg = prefs.getString(KEY_PACKAGE, "") ?: ""
        if (currentPkg == packageName && !(prefs.getString(KEY_SESSION_ID, "") ?: "").isBlank()) {
            return
        }
        val now = System.currentTimeMillis()
        prefs.edit()
            .putString(KEY_PACKAGE, packageName)
            .putString(KEY_SESSION_ID, UUID.randomUUID().toString())
            .putLong(KEY_STARTED_MS, now)
            .putLong(KEY_TOTAL_RECORDED_MS, 0L)
            .putInt(KEY_CHUNK_COUNT, 0)
            .apply()
        MonitoringLog.i("Recording session started | session:${currentSessionId(context)} | app:$packageName")
    }

    fun onSocialAppEnded(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val sessionId = prefs.getString(KEY_SESSION_ID, "") ?: ""
        val totalMs = prefs.getLong(KEY_TOTAL_RECORDED_MS, 0L)
        val chunks = prefs.getInt(KEY_CHUNK_COUNT, 0)
        if (sessionId.isNotBlank()) {
            MonitoringLog.i(
                "Recording session ended | session:$sessionId | chunks:$chunks | duration_ms:$totalMs",
            )
        }
        prefs.edit()
            .remove(KEY_SESSION_ID)
            .remove(KEY_PACKAGE)
            .remove(KEY_STARTED_MS)
            .remove(KEY_TOTAL_RECORDED_MS)
            .remove(KEY_CHUNK_COUNT)
            .apply()
    }

    fun recordChunkCompleted(context: Context, durationMs: Long) {
        if (durationMs <= 0L) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val total = prefs.getLong(KEY_TOTAL_RECORDED_MS, 0L) + durationMs
        val chunks = prefs.getInt(KEY_CHUNK_COUNT, 0) + 1
        prefs.edit()
            .putLong(KEY_TOTAL_RECORDED_MS, total)
            .putInt(KEY_CHUNK_COUNT, chunks)
            .apply()
    }

    fun sessionDurationMs(context: Context): Long {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val started = prefs.getLong(KEY_STARTED_MS, 0L)
        if (started <= 0L) return prefs.getLong(KEY_TOTAL_RECORDED_MS, 0L)
        return (System.currentTimeMillis() - started).coerceAtLeast(0L)
    }

    fun currentSessionId(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_SESSION_ID, "")
            ?.takeIf { it.isNotBlank() }
            ?: UUID.randomUUID().toString()

    /** Active social-app package for an in-progress recording session, if any. */
    fun activePackage(context: Context): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_PACKAGE, "")
            ?.takeIf { it.isNotBlank() }

    fun sessionAgeMs(context: Context): Long {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val started = prefs.getLong(KEY_STARTED_MS, 0L)
        if (started <= 0L) return Long.MAX_VALUE
        return (System.currentTimeMillis() - started).coerceAtLeast(0L)
    }

    fun isRecordingSessionActive(context: Context, maxAgeMs: Long): Boolean {
        val pkg = activePackage(context) ?: return false
        if (pkg.isBlank()) return false
        return sessionAgeMs(context) <= maxAgeMs
    }

    fun deviceId(context: Context): String {
        return try {
            android.provider.Settings.Secure.getString(
                context.contentResolver,
                android.provider.Settings.Secure.ANDROID_ID,
            ) ?: "unknown"
        } catch (_: Exception) {
            "unknown"
        }
    }
}
