package com.example.frontend

import android.content.Context
import org.json.JSONObject
import java.io.DataOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Uploads 20s front-camera clips to POST /api/face/expression/upload/
 * ([facial_expression_capture] on server) or /api/face/chunk/ fallback.
 */
object FacialExpressionUploader {
    fun upload(
        context: Context,
        file: File,
        sourceType: String,
        sourceAppName: String,
        sourcePackageName: String,
        durationSeconds: Int = 20,
        verifyFace: Boolean = true,
        clientTimestampMs: Long = System.currentTimeMillis(),
        recordingType: String = "face_camera",
    ): Boolean {
        val baseUrl = TrackerPrefs.baseUrl(context)
        val token = TrackerPrefs.token(context)
        if (baseUrl.isBlank() || token.isBlank()) return false

        if (verifyFace) {
            val frame = extractVideoFrameJpeg(context, file) ?: run {
                MonitoringLog.w("Face upload skipped: could not extract verification frame")
                return false
            }
            val matched = FaceTrackVerify.verifyStillImage(context, frame)
            try {
                frame.delete()
            } catch (_: Exception) {
            }
            if (!matched) {
                MonitoringLog.w("Face upload skipped: face verification failed")
                return false
            }
        }

        val boundary = "----MindSyncExpr${System.currentTimeMillis()}"
        val primaryUrl = "${baseUrl.trimEnd('/')}/api/face/expression/upload/"
        val fallbackUrl = "${baseUrl.trimEnd('/')}/api/face/chunk/"
        return uploadMultipart(
            file,
            primaryUrl,
            fallbackUrl,
            boundary,
            token,
            sourceType,
            sourceAppName,
            sourcePackageName,
            durationSeconds,
            context,
            clientTimestampMs,
            recordingType,
            verifyFace,
        )
    }

    private fun uploadMultipart(
        file: File,
        primaryUrl: String,
        fallbackUrl: String,
        boundary: String,
        token: String,
        sourceType: String,
        sourceAppName: String,
        sourcePackageName: String,
        durationSeconds: Int,
        context: Context,
        clientTimestampMs: Long,
        recordingType: String,
        verifyFace: Boolean,
    ): Boolean {
        var ok =
            postMultipart(
                primaryUrl,
                boundary,
                token,
                file,
                sourceType,
                sourceAppName,
                sourcePackageName,
                durationSeconds,
                context,
                clientTimestampMs,
                recordingType,
                verifyFace,
            )
        if (!ok) {
            ok =
                postMultipart(
                    fallbackUrl,
                    boundary,
                    token,
                    file,
                    sourceType,
                    sourceAppName,
                    sourcePackageName,
                    durationSeconds,
                    context,
                    clientTimestampMs,
                    recordingType,
                    verifyFace,
                )
        }
        return ok
    }

    private fun postMultipart(
        urlString: String,
        boundary: String,
        token: String,
        file: File,
        sourceType: String,
        sourceAppName: String,
        sourcePackageName: String,
        durationSeconds: Int,
        context: Context,
        clientTimestampMs: Long,
        recordingType: String,
        verifyFace: Boolean,
    ): Boolean {
        val url = URL(urlString)
        val conn =
            (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 15_000
                readTimeout = 300_000
                doOutput = true
                setRequestProperty("Authorization", "Bearer $token")
                setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
            }
        return try {
            DataOutputStream(conn.outputStream).use { out ->
                fun field(name: String, value: String) {
                    out.writeBytes("--$boundary\r\n")
                    out.writeBytes("Content-Disposition: form-data; name=\"$name\"\r\n\r\n")
                    out.writeBytes("$value\r\n")
                }
                field("source_type", sourceType)
                field("source_app_name", sourceAppName)
                field("source_package_name", sourcePackageName)
                field("duration_seconds", durationSeconds.toString())
                field("recording_type", recordingType)
                field("verify_face", if (verifyFace) "true" else "false")
                field("run_mood_scan", "false")
                field("client_timestamp_ms", clientTimestampMs.toString())
                field("session_id", MonitoringSession.currentSessionId(context))
                field("device_id", MonitoringSession.deviceId(context))
                field("captured_at", clientTimestampMs.toString())
                TrackerPrefs.userId(context).takeIf { it.isNotBlank() }?.let {
                    field("user_id", it)
                }
                out.writeBytes("--$boundary\r\n")
                val videoFieldName = "video"
                out.writeBytes(
                    "Content-Disposition: form-data; name=\"$videoFieldName\"; filename=\"${file.name}\"\r\n",
                )
                out.writeBytes("Content-Type: video/mp4\r\n\r\n")
                file.inputStream().use { it.copyTo(out) }
                out.writeBytes("\r\n--$boundary--\r\n")
                out.flush()
            }
            val code = conn.responseCode
            val ok = code in 200..299
            if (!ok) {
                val err =
                    try {
                        conn.errorStream?.bufferedReader()?.use { it.readText() }
                    } catch (_: Exception) {
                        null
                    }
                TrackerPrefs.saveFaceReactionLastError(
                    context,
                    JSONObject().put("expression_upload", code).put("body", err ?: "").toString(),
                )
            }
            conn.inputStream?.close()
            conn.disconnect()
            ok
        } catch (e: Exception) {
            TrackerPrefs.saveFaceReactionLastError(
                context,
                JSONObject().put("expression_upload", "network").put("body", e.message ?: "").toString(),
            )
            false
        }
    }

    /** Extract one JPEG frame and verify against enrolled profile before persisting clips. */
    fun verifyVideoIdentity(context: Context, video: File): Boolean {
        val frame = extractVideoFrameJpeg(context, video) ?: return false
        return try {
            FaceTrackVerify.verifyStillImage(context, frame)
        } finally {
            try {
                frame.delete()
            } catch (_: Exception) {
            }
        }
    }

    private fun extractVideoFrameJpeg(context: Context, video: File): File? {
        return try {
            val retriever = android.media.MediaMetadataRetriever()
            retriever.setDataSource(video.absolutePath)
            val bitmap =
                retriever.getFrameAtTime(
                    500_000,
                    android.media.MediaMetadataRetriever.OPTION_CLOSEST,
                )
            retriever.release()
            if (bitmap == null) return null
            val out = File(context.cacheDir, "expr_verify_${System.currentTimeMillis()}.jpg")
            java.io.FileOutputStream(out).use {
                bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 88, it)
            }
            bitmap.recycle()
            out
        } catch (_: Exception) {
            null
        }
    }
}
