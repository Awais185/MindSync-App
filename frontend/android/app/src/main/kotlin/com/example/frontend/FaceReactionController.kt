package com.example.frontend

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.util.Log
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
import org.json.JSONObject
import java.io.DataOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executor
import java.util.concurrent.Executors

/**
 * Records front-camera reactions during foreground video consumption, uploads to
 * [/api/face/expression/upload/] (facial_expression_capture table + OpenFace AU), then
 * enforces a 10-minute cooldown. Camera is never
 * held open between clips; work runs on the main thread for CameraX binding.
 */
class FaceReactionController(
    private val service: BackgroundUsageService,
    private val mainHandler: Handler,
) {
    private val mainExecutor: Executor = ContextCompat.getMainExecutor(service)
    private val uploadExecutor = Executors.newSingleThreadExecutor()
    private val cameraInitExecutor = Executors.newSingleThreadExecutor()

    private var camLifecycle: CamLifecycle? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var videoCapture: VideoCapture<Recorder>? = null
    private var activeRecording: Recording? = null
    private var isStarting = false
    @Volatile
    private var isUploading = false

    private var pendingPkg = ""
    private var pendingApp = ""

    private val stopClipRunnable = Runnable { stopRecordingClip() }

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

    fun release() {
        mainHandler.removeCallbacks(stopClipRunnable)
        cancelSessionLocked()
        uploadExecutor.shutdown()
        cameraInitExecutor.shutdown()
    }

    fun onScreenOffOrLocked() {
        mainHandler.post {
            TrackerPrefs.clearFaceReactionCooldown(service)
            cancelSessionLocked()
        }
    }

    fun onCameraForegroundDenied() {
        mainHandler.post { cancelSessionLocked() }
    }

    /**
     * @param videoLikely Same heuristic as screen capture (foreground video app + media active).
     */
    fun onVideoConsumptionLikely(
        videoLikely: Boolean,
        packageName: String,
        appDisplayName: String,
        nowMs: Long,
    ) {
        mainHandler.post {
            evaluate(videoLikely, packageName, appDisplayName, nowMs)
        }
    }

    private fun hasCameraPermission(): Boolean {
        return ContextCompat.checkSelfPermission(service, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun evaluate(
        videoLikely: Boolean,
        packageName: String,
        appDisplayName: String,
        nowMs: Long,
    ) {
        // Scheduled 5-minute face capture owns CameraX; parallel sessions caused ERROR_CAMERA_DISABLED.
        if (!videoLikely) {
            cancelSessionLocked()
        }
    }

    private fun beginCameraSession() {
        if (isStarting || activeRecording != null) return
        isStarting = true
        TrackerPrefs.setFaceReactionRecording(service, true)
        TrackerPrefs.saveFaceReactionLastError(service, "")

        cameraInitExecutor.execute {
            try {
                val provider = ProcessCameraProvider.getInstance(service).get()
                mainHandler.post {
                    cameraProvider = provider
                    bindAndStartRecording(provider)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Camera provider failed", e)
                mainHandler.post { failStart(e.message ?: "camera_provider") }
            }
        }
    }

    private fun bindAndStartRecording(provider: ProcessCameraProvider) {
        try {
            val lifecycle = CamLifecycle().also { camLifecycle = it }
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
            videoCapture = capture

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
                            Executors.newSingleThreadExecutor(),
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
            provider.bindToLifecycle(
                lifecycle,
                CameraSelector.DEFAULT_FRONT_CAMERA,
                preview,
                capture,
            )

            val outDir = File(service.cacheDir, "face_reaction").apply { mkdirs() }
            val outFile = File(outDir, "face_${System.currentTimeMillis()}.mp4")
            val recordingSession =
                capture.output
                    .prepareRecording(service, FileOutputOptions.Builder(outFile).build())
                    .start(mainExecutor) { event ->
                        when (event) {
                            is VideoRecordEvent.Finalize -> {
                                activeRecording = null
                                isStarting = false
                                service.setCameraForegroundElevated(false)
                                TrackerPrefs.setFaceReactionRecording(service, false)
                                mainHandler.removeCallbacks(stopClipRunnable)
                                unbindCamera()

                                if (event.hasError()) {
                                    TrackerPrefs.saveFaceReactionLastError(
                                        service,
                                        JSONObject()
                                            .put("cause", event.cause?.message ?: "record_error")
                                            .put("error", event.error.toString())
                                            .toString(),
                                    )
                                    outFile.delete()
                                    return@start
                                }
                                if (!outFile.exists() || outFile.length() < 4096L) {
                                    TrackerPrefs.saveFaceReactionLastError(
                                        service,
                                        """{"cause":"empty_or_small_file"}""",
                                    )
                                    outFile.delete()
                                    return@start
                                }
                                uploadClip(outFile, pendingPkg, pendingApp)
                            }
                            else -> Unit
                        }
                    }
            activeRecording = recordingSession
            isStarting = false
            mainHandler.postDelayed(stopClipRunnable, RECORD_MS_MS)
        } catch (e: Exception) {
            Log.e(TAG, "bind/start failed", e)
            failStart(e.message ?: "bind_failed")
        }
    }

    private fun stopRecordingClip() {
        try {
            activeRecording?.stop()
        } catch (_: Exception) {
        }
    }

    private fun failStart(message: String) {
        isStarting = false
        TrackerPrefs.setFaceReactionRecording(service, false)
        service.setCameraForegroundElevated(false)
        TrackerPrefs.saveFaceReactionLastError(service, """{"cause":"$message"}""")
        unbindCamera()
    }

    private fun cancelSessionLocked() {
        mainHandler.removeCallbacks(stopClipRunnable)
        try {
            activeRecording?.stop()
        } catch (_: Exception) {
        }
        activeRecording = null
        isStarting = false
        TrackerPrefs.setFaceReactionRecording(service, false)
        service.setCameraForegroundElevated(false)
        unbindCamera()
    }

    private fun unbindCamera() {
        try {
            cameraProvider?.unbindAll()
        } catch (_: Exception) {
        }
        camLifecycle?.destroy()
        camLifecycle = null
        cameraProvider = null
        videoCapture = null
    }

    private fun uploadClip(file: File, packageName: String, appName: String) {
        isUploading = true
        uploadExecutor.execute {
            try {
                doUpload(file, packageName, appName)
            } finally {
                isUploading = false
                try {
                    file.delete()
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun doUpload(file: File, packageName: String, appName: String) {
        val ok =
            FacialExpressionUploader.upload(
                context = service,
                file = file,
                sourceType = "video_watch",
                sourceAppName = appName,
                sourcePackageName = packageName,
                durationSeconds = 20,
                verifyFace = true,
            )
        if (ok) {
            TrackerPrefs.saveFaceReactionLastError(service, "")
            val until = System.currentTimeMillis() + COOLDOWN_MS
            TrackerPrefs.setFaceReactionCooldownUntilMs(service, until)
        }
    }

    companion object {
        private const val TAG = "FaceReaction"
        private const val RECORD_MS_MS = 20_000L
        private const val COOLDOWN_MS = 10 * 60 * 1000L
    }
}
