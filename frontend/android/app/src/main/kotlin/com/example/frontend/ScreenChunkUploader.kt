package com.example.frontend

import android.content.Context
import org.json.JSONObject
import java.io.DataOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Multipart upload for 30s screen chunks → POST /api/chunks/screen/ */
object ScreenChunkUploader {
    fun upload(
        context: Context,
        file: File,
        platform: String,
        packageName: String,
        chunkIndex: Int,
        durationSeconds: Int,
        startTimeMs: Long,
        endTimeMs: Long,
    ): Boolean {
        val baseUrl = TrackerPrefs.baseUrl(context)
        val token = TrackerPrefs.token(context)
        if (baseUrl.isBlank() || token.isBlank()) {
            MonitoringLog.w("Screen chunk upload skipped: not signed in")
            return false
        }
        val userId = TrackerPrefs.userId(context)

        val startIso = isoFromMs(startTimeMs)
        val endIso = isoFromMs(endTimeMs)
        val boundary = "----MindSyncBoundary${System.currentTimeMillis()}"
        val sessionId = MonitoringSession.currentSessionId(context)
        val deviceId = MonitoringSession.deviceId(context)

        return try {
            val url = URL("${baseUrl.trimEnd('/')}/api/chunks/screen/")
            val conn =
                (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 12_000
                    readTimeout = 120_000
                    doOutput = true
                    setRequestProperty("Authorization", "Bearer $token")
                    setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
                }

            DataOutputStream(conn.outputStream).use { out ->
                fun writeField(name: String, value: String) {
                    out.writeBytes("--$boundary\r\n")
                    out.writeBytes("Content-Disposition: form-data; name=\"$name\"\r\n\r\n")
                    out.writeBytes("$value\r\n")
                }

                if (userId.isNotBlank()) {
                    writeField("user_id", userId)
                }
                writeField("timestamp", endIso)
                writeField("platform", platform)
                writeField("source_package", packageName)
                writeField("app_name", platform)
                writeField("package_name", packageName)
                writeField("duration_seconds", durationSeconds.toString())
                writeField("chunk_index", chunkIndex.toString())
                writeField("recording_type", "screen")
                writeField("session_id", sessionId)
                writeField("device_id", deviceId)
                writeField("start_time", startIso)
                writeField("end_time", endIso)

                out.writeBytes("--$boundary\r\n")
                out.writeBytes(
                    "Content-Disposition: form-data; name=\"video_clip\"; filename=\"${file.name}\"\r\n",
                )
                out.writeBytes("Content-Type: video/mp4\r\n\r\n")
                file.inputStream().use { input -> input.copyTo(out) }
                out.writeBytes("\r\n--$boundary--\r\n")
                out.flush()
            }

            val responseCode = conn.responseCode
            val ok = responseCode in 200..299
            if (!ok) {
                val errorBody =
                    try {
                        conn.errorStream?.bufferedReader()?.use { it.readText() }
                    } catch (_: Exception) {
                        null
                    }
                TrackerPrefs.saveLastVideoUploadError(
                    context,
                    JSONObject()
                        .put("status", responseCode)
                        .put("body", errorBody ?: "")
                        .toString(),
                )
                MonitoringLog.e("Screen chunk upload failed: ${file.name} | HTTP $responseCode | $errorBody")
            } else {
                val body =
                    try {
                        conn.inputStream.bufferedReader().use { it.readText() }
                    } catch (_: Exception) {
                        ""
                    }
                TrackerPrefs.saveLastVideoUploadError(context, "")
                MonitoringLog.i(
                    "Screen chunk uploaded to server | ${file.name} | HTTP $responseCode | $body",
                )
            }
            conn.disconnect()
            ok
        } catch (exc: Exception) {
            TrackerPrefs.saveLastVideoUploadError(
                context,
                JSONObject()
                    .put("status", "network_error")
                    .put("body", exc.message ?: "upload failed")
                    .toString(),
            )
            MonitoringLog.e("Screen chunk upload failed: ${file.name} | ${exc.message}", exc)
            false
        }
    }

    private fun isoFromMs(ms: Long): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date(ms))
}
