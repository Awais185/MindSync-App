package com.example.frontend

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

/**
 * Retries failed screen/face uploads stored in [MonitoringLocalDatabase].
 */
object MonitoringUploadQueue {
    private val executor = Executors.newSingleThreadExecutor()

    fun enqueueScreenChunk(
        context: Context,
        filePath: String,
        appName: String,
        packageName: String,
        chunkIndex: Int,
        durationSeconds: Int,
        startTimeMs: Long,
        endTimeMs: Long,
    ) {
        val payload =
            JSONObject()
                .put("kind", "screen")
                .put("app_name", appName)
                .put("package_name", packageName)
                .put("chunk_index", chunkIndex)
                .put("duration_seconds", durationSeconds)
                .put("start_time_ms", startTimeMs)
                .put("end_time_ms", endTimeMs)
                .toString()
        MonitoringLocalDatabase.withDb(context) { it.enqueueUpload(filePath, payload) }
    }

    fun enqueueFaceClip(
        context: Context,
        filePath: String,
        appName: String,
        packageName: String,
        durationSeconds: Int,
        recordedAtMs: Long,
    ) {
        val payload =
            JSONObject()
                .put("kind", "face")
                .put("app_name", appName)
                .put("package_name", packageName)
                .put("duration_seconds", durationSeconds)
                .put("recorded_at_ms", recordedAtMs)
                .toString()
        MonitoringLocalDatabase.withDb(context) { it.enqueueUpload(filePath, payload) }
    }

    fun processPending(context: Context, maxItems: Int = 3) {
        if (!TrackerPrefs.shouldAllowUsageCollection(context)) return
        executor.execute {
            MonitoringLocalDatabase.withDb(context) { db ->
            for (row in db.listPendingUploads(maxItems)) {
                val file = File(row.filePath)
                if (!file.exists()) {
                    db.deleteUpload(row.id)
                    continue
                }
                val payload = runCatching { JSONObject(row.payloadJson) }.getOrNull() ?: JSONObject()
                val ok =
                    when (row.kind) {
                        "face" ->
                            FacialExpressionUploader.upload(
                                context = context,
                                file = file,
                                sourceType = "social_media",
                                sourceAppName = payload.optString("app_name"),
                                sourcePackageName = payload.optString("package_name"),
                                durationSeconds = payload.optInt("duration_seconds", 30),
                                verifyFace = true,
                                recordingType = "facial_expression_detection",
                                clientTimestampMs = payload.optLong("recorded_at_ms"),
                            )
                        else ->
                            ScreenChunkUploader.upload(
                                context = context,
                                file = file,
                                platform = payload.optString("app_name"),
                                packageName = payload.optString("package_name"),
                                chunkIndex = payload.optInt("chunk_index"),
                                durationSeconds = payload.optInt("duration_seconds"),
                                startTimeMs = payload.optLong("start_time_ms"),
                                endTimeMs = payload.optLong("end_time_ms"),
                            )
                    }
                if (ok) {
                    db.deleteUpload(row.id)
                    MonitoringLog.i("Upload queue delivered: ${row.kind} ${file.name}")
                } else if (row.kind == "face" && TrackerPrefs.faceVerified(context)) {
                    val identityOk = FacialExpressionUploader.verifyVideoIdentity(context, file)
                    if (!identityOk) {
                        db.deleteUpload(row.id)
                        file.delete()
                        MonitoringLog.i("Upload queue: face clip removed — identity no longer matches")
                    } else {
                        db.markUploadAttempt(row.id)
                    }
                } else {
                    db.markUploadAttempt(row.id)
                }
            }
            }
        }
    }
}
