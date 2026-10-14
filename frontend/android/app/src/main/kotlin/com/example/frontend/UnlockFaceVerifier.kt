package com.example.frontend

import android.Manifest
import android.content.pm.PackageManager
import android.os.Handler
import android.util.Log
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import org.json.JSONObject
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * After device unlock ([Intent.ACTION_USER_PRESENT]), silently captures one front-camera JPEG
 * (no visible preview), POSTs to [/api/face/verify-track/], and sets
 * [TrackerPrefs.setUnlockFaceSessionOk] when similarity meets the server threshold (default 50%).
 *
 * After a successful match, no further scans for 5 minutes. After that window, one re-scan runs;
 * if it fails, retries every 1 minute until matched (then another 5-minute pause).
 */
class UnlockFaceVerifier(
    private val service: BackgroundUsageService,
    private val mainHandler: Handler,
) {
    private val executor = Executors.newSingleThreadExecutor()
    private val surfaceReleaseExecutor = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private val scheduleLock = Any()
    private var lastScheduleWallMs = 0L
    private var retryScheduled = false

    private val retryRunnable =
        Runnable {
            retryScheduled = false
            if (!MonitoringPolicy.isScreenInteractive(service)) return@Runnable
            if (TrackerPrefs.isUnlockFaceCooldownActive(service)) return@Runnable
            if (!TrackerPrefs.faceVerified(service)) return@Runnable
            scheduleVerifyAfterUnlock(forceRetry = true)
        }

    fun cancelPendingRetries() {
        mainHandler.removeCallbacks(retryRunnable)
        retryScheduled = false
    }

    fun scheduleVerifyAfterUnlock(forceRetry: Boolean = false) {
        if (!TrackerPrefs.faceVerified(service)) {
            TrackerPrefs.setUnlockFaceSessionOk(service, true)
            TrackerPrefs.saveUnlockFaceLastError(service, "")
            cancelPendingRetries()
            return
        }
        if (TrackerPrefs.isUnlockFaceCooldownActive(service)) {
            TrackerPrefs.setUnlockFaceSessionOk(service, true)
            TrackerPrefs.saveUnlockFaceLastError(service, "")
            cancelPendingRetries()
            return
        }
        if (TrackerPrefs.shouldResetSessionAfterPause(service)) {
            TrackerPrefs.setUnlockFaceSessionOk(service, false)
            TrackerPrefs.clearFaceMatchPause(service)
        }
        if (TrackerPrefs.unlockFaceSessionOk(service) && !forceRetry) {
            cancelPendingRetries()
            return
        }
        if (!MonitoringPolicy.isScreenInteractive(service)) {
            return
        }
        if (service.resolveMonitoredSocialForeground() != null) {
            Log.d(TAG, "Unlock verify deferred — monitored social app is foreground")
            return
        }
        if (CameraCaptureCoordinator.isFacialExpressionRecording()) {
            Log.d(TAG, "Unlock verify deferred — facial expression recording active")
            return
        }
        if (ContextCompat.checkSelfPermission(service, Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            TrackerPrefs.setUnlockFaceSessionOk(service, false)
            TrackerPrefs.saveUnlockFaceLastError(service, """{"cause":"no_camera_permission"}""")
            Log.w(TAG, "Unlock verify skipped: camera permission missing")
            scheduleRetryIfNeeded()
            return
        }
        synchronized(scheduleLock) {
            val now = System.currentTimeMillis()
            if (!forceRetry && now - lastScheduleWallMs < 4000L) {
                return
            }
            lastScheduleWallMs = now
        }
        executor.execute {
            if (!busy.compareAndSet(false, true)) {
                return@execute
            }
            if (!CameraCaptureCoordinator.tryAcquireUnlockVerify(service)) {
                busy.set(false)
                scheduleRetryIfNeeded()
                return@execute
            }
            try {
                var waited = 0
                // Brief yield if expression video is finishing; screen capture does not use the camera.
                while (
                    CameraCaptureCoordinator.isFacialExpressionRecording() &&
                    waited < 3_000
                ) {
                    Thread.sleep(400)
                    waited += 400
                }
                val gate = java.util.concurrent.CountDownLatch(1)
                val allowed = java.util.concurrent.atomic.AtomicBoolean(false)
                mainHandler.post {
                    try {
                        service.setCameraForegroundElevated(true)
                        allowed.set(MonitoringPolicy.cameraCaptureAllowed(service))
                    } finally {
                        gate.countDown()
                    }
                }
                gate.await(3, java.util.concurrent.TimeUnit.SECONDS)
                if (!allowed.get()) {
                    mainHandler.post { service.setCameraForegroundElevated(false) }
                    Log.w(TAG, "Unlock verify skipped: camera capture not allowed (battery/power)")
                    scheduleRetryIfNeeded()
                    return@execute
                }
                runCaptureAndVerify()
            } catch (e: Exception) {
                Log.w(TAG, "unlock verify failed: ${e.message}")
                mainHandler.post {
                    TrackerPrefs.setUnlockFaceSessionOk(service, false)
                    TrackerPrefs.saveUnlockFaceLastError(
                        service,
                        JSONObject().put("cause", e.message ?: "verify_error").toString(),
                    )
                    scheduleRetryIfNeeded()
                }
            } finally {
                CameraCaptureCoordinator.releaseUnlockVerify()
                busy.set(false)
            }
        }
    }

    private fun scheduleRetryIfNeeded() {
        if (TrackerPrefs.isUnlockFaceCooldownActive(service)) {
            cancelPendingRetries()
            return
        }
        if (TrackerPrefs.unlockFaceSessionOk(service)) {
            cancelPendingRetries()
            return
        }
        if (!MonitoringPolicy.isScreenInteractive(service)) {
            cancelPendingRetries()
            return
        }
        if (service.resolveMonitoredSocialForeground() != null) {
            return
        }
        if (CameraCaptureCoordinator.isFacialExpressionRecording()) {
            return
        }
        if (retryScheduled) return
        retryScheduled = true
        mainHandler.postDelayed(retryRunnable, TrackerPrefs.FACE_MATCH_RETRY_MS)
        Log.d(TAG, "Scheduling silent unlock face retry in ${TrackerPrefs.FACE_MATCH_RETRY_MS / 1000}s")
    }

    private fun runCaptureAndVerify() {
        TrackerPrefs.setUnlockFaceSessionOk(service, false)

        val done = CountDownLatch(1)
        val capturedHolder = arrayOfNulls<File>(1)
        val errorHolder = arrayOfNulls<String>(1)

        mainHandler.post {
            val lifecycle = CamLifecycle()
            var provider: ProcessCameraProvider? = null

            fun cleanup() {
                try {
                    provider?.unbindAll()
                } catch (_: Exception) {
                }
                try {
                    lifecycle.destroy()
                } catch (_: Exception) {
                }
                service.setCameraForegroundElevated(false)
                done.countDown()
            }

            try {
                provider = ProcessCameraProvider.getInstance(service).get()
                val imageCapture =
                    ImageCapture.Builder()
                        .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
                        .setFlashMode(ImageCapture.FLASH_MODE_AUTO)
                        .build()
                val preview =
                    Preview.Builder().build().also { p ->
                        p.setSurfaceProvider { request ->
                            val surfaceTexture =
                                android.graphics.SurfaceTexture(0).apply {
                                    setDefaultBufferSize(16, 16)
                                }
                            val surface = Surface(surfaceTexture)
                            request.provideSurface(
                                surface,
                                surfaceReleaseExecutor,
                            ) {
                                try {
                                    surface.release()
                                    surfaceTexture.release()
                                } catch (_: Exception) {
                                }
                            }
                        }
                    }

                service.setCameraForegroundElevated(true)
                provider.unbindAll()
                provider.bindToLifecycle(
                    lifecycle,
                    CameraSelector.DEFAULT_FRONT_CAMERA,
                    preview,
                    imageCapture,
                )
                val outFile =
                    File(service.cacheDir, "unlock_face_${System.currentTimeMillis()}.jpg").apply {
                        parentFile?.mkdirs()
                    }
                val opts = ImageCapture.OutputFileOptions.Builder(outFile).build()
                mainHandler.postDelayed({
                    if (!MonitoringPolicy.isScreenInteractive(service)) {
                        errorHolder[0] = "screen_off"
                        cleanup()
                        return@postDelayed
                    }
                    imageCapture.takePicture(
                        opts,
                        ContextCompat.getMainExecutor(service),
                        object : ImageCapture.OnImageSavedCallback {
                            override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                                capturedHolder[0] = outFile
                                cleanup()
                            }

                            override fun onError(exc: ImageCaptureException) {
                                errorHolder[0] = exc.message ?: "capture"
                                try {
                                    outFile.delete()
                                } catch (_: Exception) {
                                }
                                cleanup()
                            }
                        },
                    )
                }, 900L)
            } catch (e: Exception) {
                errorHolder[0] = e.message ?: "bind"
                cleanup()
            }
        }

        val finished = done.await(20, TimeUnit.SECONDS)
        if (!finished) {
            mainHandler.post {
                try {
                    ProcessCameraProvider.getInstance(service).get().unbindAll()
                } catch (_: Exception) {
                }
                service.setCameraForegroundElevated(false)
            }
            errorHolder[0] = "timeout"
        }

        if (!MonitoringPolicy.isScreenInteractive(service)) {
            return
        }

        val err = errorHolder[0]
        val file = capturedHolder[0]
        if (err != null) {
            TrackerPrefs.setUnlockFaceSessionOk(service, false)
            TrackerPrefs.saveUnlockFaceLastError(service, """{"cause":"$err"}""")
            Log.w(TAG, "Unlock capture failed: $err")
            scheduleRetryIfNeeded()
            return
        }
        if (file == null || !file.exists() || file.length() < 512L) {
            TrackerPrefs.setUnlockFaceSessionOk(service, false)
            TrackerPrefs.saveUnlockFaceLastError(service, """{"cause":"empty_capture"}""")
            Log.w(TAG, "Unlock capture empty")
            scheduleRetryIfNeeded()
            return
        }

        val ok = FaceTrackVerify.verifyStillImage(service, file)
        try {
            file.delete()
        } catch (_: Exception) {
        }

        if (ok) {
            TrackerPrefs.applyFaceMatchPause(service)
            TrackerPrefs.setUnlockFaceSessionOk(service, true)
            TrackerPrefs.saveUnlockFaceLastError(service, "")
            cancelPendingRetries()
            Log.i(TAG, "Unlock face matched — mood/media paused for 5 minutes")
            service.onUnlockFaceVerifiedForTracking()
            UnlockFaceMoodVideoRecorder.scheduleAfterUnlockMatch(service, mainHandler)
        } else {
            TrackerPrefs.setUnlockFaceSessionOk(service, false)
            Log.d(TAG, "Unlock face below threshold — retry in 1 minute while screen is on")
            scheduleRetryIfNeeded()
        }
    }

    private class CamLifecycle : LifecycleOwner {
        private val registry = LifecycleRegistry(this)

        init {
            registry.currentState = Lifecycle.State.RESUMED
        }

        fun destroy() {
            registry.currentState = Lifecycle.State.DESTROYED
        }

        override val lifecycle: Lifecycle
            get() = registry
    }

    companion object {
        private const val TAG = "UnlockFaceVerifier"
    }
}
