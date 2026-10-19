package com.example.frontend

import android.content.Context
import android.graphics.BitmapFactory
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import org.json.JSONObject
import java.io.DataOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale

/**
 * POST still image to [/api/face/verify-track/] (default threshold 80%).
 */
object FaceTrackVerify {
    fun verifyStillImage(
        context: Context,
        imageFile: File,
        applyMatchPause: Boolean = false,
        unlockCapture: Boolean = false,
    ): Boolean {
        val baseUrl = TrackerPrefs.baseUrl(context)
        val token = TrackerPrefs.token(context)
        if (baseUrl.isBlank() || token.isBlank()) return false
        if (!imageFile.exists() || imageFile.length() < 512L) return false

        try {
            val bitmap = BitmapFactory.decodeFile(imageFile.absolutePath) ?: return false
            val image = InputImage.fromBitmap(bitmap, 0)
            val options = FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
                .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
                .build()
            val detector = FaceDetection.getClient(options)
            val faces = Tasks.await(detector.process(image))

            if (faces.isEmpty()) {
                Log.i("FaceTrackVerify", "No face detected by ML Kit, skipping upload")
                return false
            }

            val face = faces.first()
            val rotY = face.headEulerAngleY
            val rotX = face.headEulerAngleX
            val leftEye = face.leftEyeOpenProbability
            val rightEye = face.rightEyeOpenProbability

            val maxRot = if (unlockCapture) 45f else 30f
            if (rotY < -maxRot || rotY > maxRot || rotX < -maxRot || rotX > maxRot) {
                Log.i("FaceTrackVerify", "Face not looking at device (rotY=$rotY, rotX=$rotX), skipping upload")
                return false
            }

            if (!unlockCapture &&
                leftEye != null && leftEye < 0.2f && rightEye != null && rightEye < 0.2f
            ) {
                Log.i("FaceTrackVerify", "Eyes appear closed, skipping upload")
                return false
            }
        } catch (e: Exception) {
            Log.e("FaceTrackVerify", "ML Kit face detection failed", e)
            return false
        }

        val pct = TrackerPrefs.faceMatchPercent(context)
        val threshold =
            if (pct <= 0.0) {
                0.80
            } else {
                (pct / 100.0).coerceIn(0.80, 0.98)
            }
        val thresholdStr = String.format(Locale.US, "%.4f", threshold)
        val boundary = "----MindSyncVerify${System.currentTimeMillis()}"
        val url = URL("${baseUrl.trimEnd('/')}/api/face/verify-track/")
        val conn =
            (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 20_000
                readTimeout = 120_000
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
                field("match_threshold", thresholdStr)
                field("source", "unlock")
                out.writeBytes("--$boundary\r\n")
                out.writeBytes(
                    "Content-Disposition: form-data; name=\"image\"; filename=\"${imageFile.name}\"\r\n",
                )
                out.writeBytes("Content-Type: image/jpeg\r\n\r\n")
                imageFile.inputStream().use { it.copyTo(out) }
                out.writeBytes("\r\n--$boundary--\r\n")
                out.flush()
            }
            val code = conn.responseCode
            val body =
                (if (code in 200..299) conn.inputStream else conn.errorStream)
                    ?.bufferedReader()
                    ?.use { it.readText() }
                    .orEmpty()
            conn.disconnect()
            if (code !in 200..299) {
                Log.w("FaceTrackVerify", "verify-track HTTP $code: $body")
                return false
            }
            val json = runCatching { JSONObject(body) }.getOrNull()
            val matched =
                json?.optBoolean("matched", json?.optBoolean("match", false) ?: false) == true
            if (matched) {
                val moodSaved = json?.optBoolean("mood_saved", false) == true
                val moodMsg = json?.optString("mood_message", "") ?: ""
                if (moodSaved) {
                    Log.i("FaceTrackVerify", "Mood scan saved: $moodMsg")
                } else if (json?.optBoolean("mood_skipped", false) == true) {
                    Log.i("FaceTrackVerify", "Mood scan skipped: $moodMsg")
                } else if (matched) {
                    Log.w("FaceTrackVerify", "Face matched but mood not saved")
                }
            }
            if (matched && applyMatchPause) {
                TrackerPrefs.applyFaceMatchPause(context)
            }
            matched
        } catch (_: Exception) {
            false
        }
    }
}
