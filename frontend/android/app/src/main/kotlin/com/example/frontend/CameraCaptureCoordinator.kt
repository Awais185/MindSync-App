package com.example.frontend

import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.content.ContextCompat
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Independent capture locks:
 * - [facialExpressionRecording] — 20s Facial Expression Detection (front camera)
 * - [faceMoodVerifyInProgress] — Face Mood Scan unlock still image only
 * - [unlockMoodVideoRecording] — 5–10s unlock mood video (separate session)
 * - [screenRecording] — 30s social screen chunks (MediaProjection)
 *
 * Modules do not block each other except their own single-flight guard.
 */
object CameraCaptureCoordinator {
    private const val TAG = "camera_service"
    private const val EXPRESSION_COOLDOWN_MS = 5 * 60 * 1000L
    private const val CAMERA_RETRY_BACKOFF_MS = 30 * 1000L

    private val facialExpressionRecording = AtomicBoolean(false)
    private val faceMoodVerifyInProgress = AtomicBoolean(false)
    private val unlockMoodVideoRecording = AtomicBoolean(false)
    private val screenRecording = AtomicBoolean(false)

    @Volatile
    private var lastExpressionCaptureCompletedMs = 0L

    fun syncFaceCooldownFromPrefs(context: Context) {
        val persisted = TrackerPrefs.lastScheduledFaceCaptureMs(context)
        if (persisted > lastExpressionCaptureCompletedMs) {
            lastExpressionCaptureCompletedMs = persisted
        }
    }

    @Volatile
    private var lastCameraFailureMs = 0L

    @Volatile
    private var lastCameraFailureReason: String? = null

    fun isFacialExpressionRecording(): Boolean = facialExpressionRecording.get()

    /** @deprecated Use [isFacialExpressionRecording]. */
    fun isFaceRecording(): Boolean = isFacialExpressionRecording()

    fun isScreenRecording(): Boolean = screenRecording.get()

    fun isFaceMoodVerifyInProgress(): Boolean = faceMoodVerifyInProgress.get()

    /** Screen capture must not rotate/renew while front-camera expression clip is active. */
    fun shouldDeferScreenCapture(): Boolean = facialExpressionRecording.get()

    private val deferredScreenActions = java.util.concurrent.ConcurrentLinkedQueue<Runnable>()

    /** Run [action] now, or after the current face expression recording finishes. */
    fun runWhenFaceIdle(action: Runnable) {
        if (!facialExpressionRecording.get()) {
            action.run()
            return
        }
        deferredScreenActions.add(action)
    }

    private fun flushDeferredScreenActions() {
        while (true) {
            val next = deferredScreenActions.poll() ?: break
            try {
                next.run()
            } catch (_: Exception) {
            }
        }
    }

    /**
     * Facial Expression Detection — 20s front-camera clip when a foreground app opens.
     * Independent of Face Mood Scan and screen capture.
     */
    fun tryAcquireFacialExpressionRecording(
        context: Context,
        reason: String,
        ignoreCooldown: Boolean = false,
    ): Boolean {
        if (!MonitoringPolicy.cameraCaptureAllowed(context)) return false
        if (!hasCameraPermission(context)) {
            logUnavailable("Camera permission not granted ($reason)")
            return false
        }
        if (!isCameraAvailable(context)) {
            logUnavailable("Camera unavailable by policy or hardware ($reason)")
            return false
        }
        if (facialExpressionRecording.get()) {
            return false
        }
        val now = System.currentTimeMillis()
        if (!ignoreCooldown && now - lastExpressionCaptureCompletedMs < EXPRESSION_COOLDOWN_MS) {
            return false
        }
        if (lastCameraFailureReason != null &&
            now - lastCameraFailureMs < CAMERA_RETRY_BACKOFF_MS
        ) {
            return false
        }
        if (!facialExpressionRecording.compareAndSet(false, true)) {
            return false
        }
        return true
    }

    fun releaseFacialExpressionRecording(context: Context, success: Boolean) {
        facialExpressionRecording.set(false)
        val now = System.currentTimeMillis()
        if (success) {
            lastExpressionCaptureCompletedMs = now
            lastCameraFailureReason = null
            TrackerPrefs.setLastScheduledFaceCaptureMs(context, now)
        } else {
            lastCameraFailureMs = now
        }
        flushDeferredScreenActions()
    }

    /** @deprecated Use [tryAcquireFacialExpressionRecording]. */
    fun tryAcquireFaceRecording(
        context: Context,
        reason: String,
        ignoreCooldown: Boolean = false,
    ): Boolean = tryAcquireFacialExpressionRecording(context, reason, ignoreCooldown)

    /** @deprecated Use [releaseFacialExpressionRecording]. */
    fun releaseFaceRecording(context: Context, success: Boolean) =
        releaseFacialExpressionRecording(context, success)

    fun markFaceCaptureFailed(reason: String) {
        lastCameraFailureMs = System.currentTimeMillis()
        lastCameraFailureReason = reason
        Log.w(TAG, "Facial expression capture skipped: $reason")
    }

    fun tryAcquireScreenRecording(): Boolean {
        if (screenRecording.get()) {
            return false
        }
        return screenRecording.compareAndSet(false, true)
    }

    fun releaseScreenRecording() {
        screenRecording.set(false)
    }

    /** Face Mood Scan — single still capture after unlock; separate from expression video. */
    fun tryAcquireUnlockVerify(context: Context): Boolean {
        if (faceMoodVerifyInProgress.get()) {
            return false
        }
        return faceMoodVerifyInProgress.compareAndSet(false, true)
    }

    fun releaseUnlockVerify() {
        faceMoodVerifyInProgress.set(false)
    }

    /** Short unlock mood video — independent from still-image verify and expression detection. */
    fun tryAcquireUnlockMoodVideo(context: Context): Boolean {
        if (!MonitoringPolicy.cameraCaptureAllowed(context)) return false
        if (!hasCameraPermission(context)) return false
        if (unlockMoodVideoRecording.get() ||
            facialExpressionRecording.get() ||
            faceMoodVerifyInProgress.get()
        ) {
            return false
        }
        return unlockMoodVideoRecording.compareAndSet(false, true)
    }

    fun releaseUnlockMoodVideo() {
        unlockMoodVideoRecording.set(false)
    }

    fun faceCooldownRemainingMs(context: Context): Long {
        val last = TrackerPrefs.lastScheduledFaceCaptureMs(context)
        if (last <= 0L) return 0L
        val elapsed = System.currentTimeMillis() - last
        return (EXPRESSION_COOLDOWN_MS - elapsed).coerceAtLeast(0L)
    }

    private fun hasCameraPermission(context: Context): Boolean {
        return ContextCompat.checkSelfPermission(context, android.Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun isCameraAvailable(context: Context): Boolean {
        if (!MonitoringPolicy.isScreenInteractive(context)) {
            return false
        }
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && pm.isDeviceIdleMode) {
            return false
        }
        return try {
            val cm = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val ids = cm.cameraIdList
            ids.isNotEmpty()
        } catch (e: Exception) {
            logUnavailable("CameraManager: ${e.message}")
            false
        }
    }

    private fun logUnavailable(message: String) {
        val now = System.currentTimeMillis()
        if (message == lastCameraFailureReason && now - lastCameraFailureMs < 60_000L) {
            return
        }
        lastCameraFailureReason = message
        lastCameraFailureMs = now
        Log.i(TAG, message)
    }
}
