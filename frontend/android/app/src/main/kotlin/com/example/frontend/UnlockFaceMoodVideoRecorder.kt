package com.example.frontend

import android.os.Handler
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import com.google.mlkit.vision.common.InputImage
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * After unlock still-image identity match, records a 30s front-camera clip for OpenFace
 * (uploaded as scheduled background / device unlock) and mood pipeline.
 */
object UnlockFaceMoodVideoRecorder {
    private const val VIDEO_MS = 30_000L
    private const val FACE_WAIT_MS = 15_000L
    private const val DURATION_SEC = 30
    private val inFlight = AtomicBoolean(false)
    private val uploadExecutor = Executors.newSingleThreadExecutor()
    private val cameraExecutor = Executors.newSingleThreadExecutor()
    private val analysisExecutor = Executors.newSingleThreadExecutor()

    fun scheduleAfterUnlockMatch(service: BackgroundUsageService, mainHandler: Handler) {
        if (!inFlight.compareAndSet(false, true)) return
        if (!MonitoringPolicy.cameraCaptureAllowed(service)) {
            inFlight.set(false)
            return
        }
        cameraExecutor.execute {
            try {
                if (!CameraCaptureCoordinator.tryAcquireUnlockMoodVideo(service)) {
                    inFlight.set(false)
                    return@execute
                }
                val provider = ProcessCameraProvider.getInstance(service).get()
                mainHandler.post {
                    recordClip(service, mainHandler, provider)
                }
            } catch (e: Exception) {
                MonitoringLog.w("Unlock OpenFace video skipped: ${e.message}")
                CameraCaptureCoordinator.releaseUnlockMoodVideo()
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
        var imageAnalysis: ImageAnalysis? = null
        var faceSeen = false
        val outFile = File(service.cacheDir, "unlock_openface_${System.currentTimeMillis()}.mp4")

        fun cleanupCamera() {
            try {
                imageAnalysis?.clearAnalyzer()
                provider.unbindAll()
            } catch (_: Exception) {
            }
            lifecycle.destroy()
            service.setCameraForegroundElevated(false)
            CameraCaptureCoordinator.releaseUnlockMoodVideo()
            inFlight.set(false)
        }

        val faceTimeoutRunnable =
            Runnable {
                if (!faceSeen) {
                    MonitoringLog.w("Unlock OpenFace video: no face — aborting")
                    try {
                        recording?.stop()
                    } catch (_: Exception) {
                    }
                    outFile.delete()
                    cleanupCamera()
                }
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
                        request.provideSurface(surface, analysisExecutor) {
                            try {
                                surface.release()
                                st.release()
                            } catch (_: Exception) {
                            }
                        }
                    }
                }
            val analysis =
                ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
            imageAnalysis = analysis
            analysis.setAnalyzer(analysisExecutor) { proxy ->
                if (faceSeen) {
                    proxy.close()
                    return@setAnalyzer
                }
                val mediaImage = proxy.image
                if (mediaImage == null) {
                    proxy.close()
                    return@setAnalyzer
                }
                val input =
                    InputImage.fromMediaImage(
                        mediaImage,
                        proxy.imageInfo.rotationDegrees,
                    )
                FacePresenceDetector.detectPresence(input) { present ->
                    proxy.close()
                    if (present) {
                        faceSeen = true
                        mainHandler.post {
                            mainHandler.removeCallbacks(faceTimeoutRunnable)
                            startRecording(
                                service,
                                mainHandler,
                                capture,
                                outFile,
                                stopRunnable,
                                cleanupCamera = { cleanupCamera() },
                                recordingHolder = { recording = it },
                            )
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
                analysis,
            )
            mainHandler.postDelayed(faceTimeoutRunnable, FACE_WAIT_MS)
        } catch (e: Exception) {
            mainHandler.removeCallbacks(faceTimeoutRunnable)
            outFile.delete()
            cleanupCamera()
            MonitoringLog.w("Unlock OpenFace video bind failed: ${e.message}")
        }
    }

    private fun startRecording(
        service: BackgroundUsageService,
        mainHandler: Handler,
        capture: VideoCapture<Recorder>,
        outFile: File,
        stopRunnable: Runnable,
        cleanupCamera: () -> Unit,
        recordingHolder: (Recording?) -> Unit,
    ) {
        try {
            val session =
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
                                    val uploaded =
                                        FacialExpressionUploader.upload(
                                            context = service,
                                            file = outFile,
                                            sourceType = "scheduled_background",
                                            sourceAppName = "Device unlock",
                                            sourcePackageName = "",
                                            durationSeconds = DURATION_SEC,
                                            verifyFace = false,
                                            identityPreverified = true,
                                            recordingType = "facial_expression_detection",
                                        )
                                    if (uploaded) {
                                        MonitoringLog.i(
                                            "Unlock OpenFace clip uploaded (${DURATION_SEC}s)",
                                        )
                                    } else {
                                        MonitoringLog.w("Unlock OpenFace clip upload failed")
                                    }
                                    runCatching { outFile.delete() }
                                }
                            } else {
                                outFile.delete()
                                MonitoringLog.w("Unlock OpenFace video record failed")
                            }
                        }
                    }
            recordingHolder(session)
            mainHandler.postDelayed(stopRunnable, VIDEO_MS)
        } catch (e: Exception) {
            cleanupCamera()
            outFile.delete()
            MonitoringLog.w("Unlock OpenFace record start failed: ${e.message}")
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
