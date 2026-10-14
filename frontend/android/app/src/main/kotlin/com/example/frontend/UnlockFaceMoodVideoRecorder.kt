package com.example.frontend

import android.os.Handler
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * After unlock image verify succeeds, records a short front-camera mood video (7s)
 * without changing the still-image verify-track flow.
 */
object UnlockFaceMoodVideoRecorder {
    private const val VIDEO_MS = 7_000L
    private val inFlight = AtomicBoolean(false)
    private val uploadExecutor = Executors.newSingleThreadExecutor()
    private val cameraExecutor = Executors.newSingleThreadExecutor()

    fun scheduleAfterUnlockMatch(service: BackgroundUsageService, mainHandler: Handler) {
        if (!inFlight.compareAndSet(false, true)) return
        cameraExecutor.execute {
            try {
                if (!CameraCaptureCoordinator.tryAcquireUnlockMoodVideo(service)) {
                    return@execute
                }
                val provider = ProcessCameraProvider.getInstance(service).get()
                mainHandler.post {
                    recordClip(service, mainHandler, provider)
                }
            } catch (e: Exception) {
                MonitoringLog.w("Unlock mood video skipped: ${e.message}")
                inFlight.set(false)
            }
        }
    }

    private fun recordClip(
        service: BackgroundUsageService,
        mainHandler: Handler,
        provider: ProcessCameraProvider,
    ) {
        val lifecycle = CamLifecycle()
        var recording: Recording? = null
        val outFile = File(service.cacheDir, "unlock_mood_${System.currentTimeMillis()}.mp4")

        fun cleanupCamera() {
            try {
                provider.unbindAll()
            } catch (_: Exception) {
            }
            lifecycle.destroy()
            service.setCameraForegroundElevated(false)
            CameraCaptureCoordinator.releaseUnlockMoodVideo()
            inFlight.set(false)
        }

        val stopRunnable =
            Runnable {
                try {
                    recording?.stop()
                } catch (_: Exception) {
                }
            }

        try {
            provider.unbindAll()
            val recorder =
                Recorder.Builder()
                    .setQualitySelector(
                        QualitySelector.fromOrderedList(
                            listOf(Quality.SD, Quality.LOWEST),
                            FallbackStrategy.lowerQualityOrHigherThan(Quality.SD),
                        ),
                    )
                    .build()
            val capture = VideoCapture.withOutput(recorder)
            val preview =
                Preview.Builder().build().also { p ->
                    p.setSurfaceProvider { request ->
                        val st =
                            android.graphics.SurfaceTexture(0).apply {
                                setDefaultBufferSize(16, 16)
                            }
                        val surface = Surface(st)
                        request.provideSurface(surface, Executors.newSingleThreadExecutor()) {
                            try {
                                surface.release()
                                st.release()
                            } catch (_: Exception) {
                            }
                        }
                    }
                }
            service.setCameraForegroundElevated(true)
            provider.bindToLifecycle(
                lifecycle,
                CameraSelector.DEFAULT_FRONT_CAMERA,
                preview,
                capture,
            )
            recording =
                capture.output
                    .prepareRecording(service, FileOutputOptions.Builder(outFile).build())
                    .start(ContextCompat.getMainExecutor(service)) { event ->
                        if (event is VideoRecordEvent.Finalize) {
                            mainHandler.removeCallbacks(stopRunnable)
                            cleanupCamera()
                            val ok =
                                !event.hasError() && outFile.exists() && outFile.length() > 4096L
                            if (ok) {
                                uploadExecutor.execute {
                                    val uploaded = UnlockFaceMoodVideoUploader.upload(service, outFile)
                                    if (uploaded) {
                                        MonitoringLog.i("Unlock mood video saved to database (7s)")
                                    }
                                    runCatching { outFile.delete() }
                                }
                            } else {
                                outFile.delete()
                                MonitoringLog.w("Unlock mood video record failed")
                            }
                        }
                    }
            mainHandler.postDelayed(stopRunnable, VIDEO_MS)
        } catch (e: Exception) {
            mainHandler.removeCallbacks(stopRunnable)
            outFile.delete()
            cleanupCamera()
            MonitoringLog.w("Unlock mood video bind failed: ${e.message}")
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
}
