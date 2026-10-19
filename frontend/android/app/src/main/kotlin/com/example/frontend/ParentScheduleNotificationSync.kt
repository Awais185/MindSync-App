package com.example.frontend

import android.content.Context
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/** POST parent bedtime/wakeup events to Django for the in-app notification center. */
object ParentScheduleNotificationSync {
    private val executor = Executors.newSingleThreadExecutor()

    fun post(context: Context, kind: String) {
        val base = TrackerPrefs.baseUrl(context.applicationContext).trim()
        val token = TrackerPrefs.token(context.applicationContext).trim()
        if (base.isBlank() || token.isBlank()) return
        executor.execute {
            try {
                val url = URL("${base.trimEnd('/')}/api/auth/notifications/parent-schedule/")
                val conn =
                    (url.openConnection() as HttpURLConnection).apply {
                        requestMethod = "POST"
                        connectTimeout = 12_000
                        readTimeout = 20_000
                        doOutput = true
                        setRequestProperty("Authorization", "Bearer $token")
                        setRequestProperty("Content-Type", "application/json")
                    }
                val payload = JSONObject().put("kind", kind).toString()
                conn.outputStream.use { it.write(payload.toByteArray(Charsets.UTF_8)) }
                val code = conn.responseCode
                conn.disconnect()
                MonitoringLog.i("Parent schedule in-app notify ($kind) HTTP $code")
            } catch (e: Exception) {
                MonitoringLog.w("Parent schedule in-app notify failed: ${e.message}")
            }
        }
    }
}
