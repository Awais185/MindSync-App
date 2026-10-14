package com.example.frontend

import android.content.Context
import org.json.JSONObject
import java.io.DataOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/** Uploads 5–10s unlock face clips to POST /api/face/mood-match-video/ (Face Mood Scan video). */
object UnlockFaceMoodVideoUploader {
    private const val DURATION_SEC = 7

    fun upload(context: Context, file: File): Boolean {
        val baseUrl = TrackerPrefs.baseUrl(context)
        val token = TrackerPrefs.token(context)
        if (baseUrl.isBlank() || token.isBlank()) return false

        val boundary = "----MindSyncUnlockMood${System.currentTimeMillis()}"
        val url = URL("${baseUrl.trimEnd('/')}/api/face/mood-match-video/")
        return try {
            val conn =
                (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 15_000
                    readTimeout = 300_000
                    doOutput = true
                    setRequestProperty("Authorization", "Bearer $token")
                    setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
                }
            DataOutputStream(conn.outputStream).use { out ->
                fun field(name: String, value: String) {
                    out.writeBytes("--$boundary\r\n")
                    out.writeBytes("Content-Disposition: form-data; name=\"$name\"\r\n\r\n")
                    out.writeBytes("$value\r\n")
                }
                field("source", "unlock_verify")
                field("duration_seconds", DURATION_SEC.toString())
                out.writeBytes("--$boundary\r\n")
                out.writeBytes(
                    "Content-Disposition: form-data; name=\"video\"; filename=\"${file.name}\"\r\n",
                )
                out.writeBytes("Content-Type: video/mp4\r\n\r\n")
                file.inputStream().use { it.copyTo(out) }
                out.writeBytes("\r\n--$boundary--\r\n")
                out.flush()
            }
            val ok = conn.responseCode in 200..299
            if (!ok) {
                MonitoringLog.w("Unlock mood video upload failed: HTTP ${conn.responseCode}")
            }
            conn.disconnect()
            ok
        } catch (e: Exception) {
            MonitoringLog.w("Unlock mood video upload failed: ${e.message}")
            false
        }
    }
}
