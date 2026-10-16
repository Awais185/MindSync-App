package com.example.frontend

import android.os.Handler
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import com.google.mlkit.vision.common.InputImage
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
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Facial Expression Detection (independent from Face Mood Scan).
 * Front-camera clips (~30s) while a trackable app is foreground.
 * Recording starts only after ML Kit sees a usable face (see [FacePresenceDetector]).
 * Screen capture uses separate 30s MediaProjection chunks in [screenrecording].
 */
class ScheduledFaceCaptureController(
    private val service: BackgroundUsageService,
    private val mainHandler: Handler,
) {
    private val mainExecutor: Executor = ContextCompat.getMainExecutor(service)
    private val uploadExecutor = Executors.newSingleThreadExecutor()
    private val cameraInitExecutor = Executors.newSingleThreadExecutor()
    private val surfaceReleaseExecutor = Executors.newSingleThreadExecutor()

    private enum class CameraRecState {
        IDLE,
        INITIALIZING,
        READY,
        WAITING_FOR_FACE,
        RECORDING,
        STOPPING,
        FINALIZING,
    }

    private var monitoringDb: MonitoringLocalDatabase? = null
    private var camLifecycle: CamLifecycle? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var videoCapture: VideoCapture<Recorder>? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var activeRecording: Recording? = null
    private var pendingRecordAttempt = 0
    private var activeOutputFile: File? = null
    private val captureInFlight = AtomicBoolean(false)

    private var cameraState = CameraRecState.IDLE
    private var recordingStartedAtMs = 0L
    private var recordingDataStarted = false
    private var noDataRetryCount = 0
    private var bindAttempt = 0

    private var activePackage: String = ""
    private var activeAppName: String = ""
    private var sessionActive = false
    private var fiveMinuteTimerScheduled = false
    private var pendingInitialCapture = false
    private var initialCaptureRetryCount = 0

    private val fiveMinuteRunnable = Runnable {
        fiveMinuteTimerScheduled = false
        if (!sessionActive || activePackage.isBlank()) {
            onForegroundSessionEnded()
            return@Runnable
        }
        tryRecordFace(ignoreCooldown = true, reason = "five_minute_timer")
    }

    private val stopRunnable = Runnable { requestStopRecording(force = false) }

    private val faceDetectTimeoutRunnable = Runnable {
        if (cameraState != CameraRecState.WAITING_FOR_FACE) return@Runnable
        MonitoringLog.i(
            "Facial Expression Detection: no face in view — skipping clip | app:$activeAppName",
        )
        service.setCameraForegroundElevated(false)
        scheduleCameraRelease()
        finishCapture(success = false)
    }

    private val releaseCameraRunnable = Runnable {
        unbindCamera()
        cameraState = CameraRecState.IDLE
        MonitoringLog.i("📷 Camera released cleanly — ready for next cycle")
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

    fun attachDatabase(db: MonitoringLocalDatabase) {
        monitoringDb = db
    }

    fun startScheduler() {
        CameraCaptureCoordinator.syncFaceCooldownFromPrefs(service)
    }

    fun stopScheduler() {
        onForegroundSessionEnded()
        uploadExecutor.shutdown()
        cameraInitExecutor.shutdown()
        surfaceReleaseExecutor.shutdown()
    }

    fun onForegroundTargetActive(packageName: String, appName: String, isNewSession: Boolean) {
        if (isNewSession || !sessionActive || activePackage != packageName) {
            sessionActive = true
            activePackage = packageName
            activeAppName = appName
            initialCaptureRetryCount = 0
            TrackerPrefs.setMonitoringSocialSessionPackage(service, packageName)
            mainHandler.removeCallbacks(fiveMinuteRunnable)
            fiveMinuteTimerScheduled = false
            pendingInitialCapture = true
            mainHandler.removeCallbacks(initialCaptureRunnable)
            mainHandler.postDelayed(initialCaptureRunnable, INITIAL_CAPTURE_DELAY_MS)
            return
        }
        if (pendingInitialCapture) return
        if (!fiveMinuteTimerScheduled) scheduleFiveMinuteTimer()
    }

    private val initialCaptureRunnable = Runnable {
        pendingInitialCapture = false
        if (!sessionActive) return@Runnable
        tryRecordFace(ignoreCooldown = true, reason = "foreground_app_opened")
    }

    fun onSocialTargetActive(packageName: String, appName: String, isNewSession: Boolean) {
        onForegroundTargetActive(packageName, appName, isNewSession)
    }

    fun onSocialAppEntered(packageName: String, appName: String) {
        onForegroundTargetActive(packageName, appName, isNewSession = true)
    }

    fun onServiceRestoredWithActiveSocial(packageName: String, appName: String) {
        onForegroundTargetActive(packageName, appName, isNewSession = true)
    }

    fun onForegroundSessionEnded() {
        sessionActive = false
        activePackage = ""
        activeAppName = ""
        pendingInitialCapture = false
        mainHandler.removeCallbacks(initialCaptureRunnable)
        mainHandler.removeCallbacks(fiveMinuteRunnable)
        fiveMinuteTimerScheduled = false
        mainHandler.removeCallbacks(stopRunnable)
        mainHandler.removeCallbacks(faceDetectTimeoutRunnable)
        mainHandler.removeCallbacks(releaseCameraRunnable)
        cancelRecording(success = false, force = true)
    }

    fun onSocialSessionEnded() = onForegroundSessionEnded()

    fun onScreenOffOrLocked() {
        mainHandler.post { onForegroundSessionEnded() }
    }

    fun release() {
        onForegroundSessionEnded()
    }

    private fun scheduleFiveMinuteTimer() {
        if (!sessionActive) return
        mainHandler.removeCallbacks(fiveMinuteRunnable)
        fiveMinuteTimerScheduled = true
        mainHandler.postDelayed(fiveMinuteRunnable, FIVE_MINUTE_MS)
    }

    private fun tryRecordFace(ignoreCooldown: Boolean, reason: String) {
        if (!TrackerPrefs.shouldAllowUsageCollection(service)) return
        if (!MonitoringPolicy.heavyCaptureAllowed(service)) {
            MonitoringLog.i(
                "Facial Expression Detection: deferred (battery, power saver, or thermal)",
            )
            if (sessionActive) scheduleFiveMinuteTimer()
            return
        }
        if (TrackerPrefs.faceVerified(service) && !TrackerPrefs.unlockFaceSessionOk(service)) {
            MonitoringLog.i(
                "Facial Expression Detection: waiting for unlock face match before recording",
            )
            if (sessionActive) scheduleFiveMinuteTimer()
            BackgroundUsageService.requestUnlockFaceVerify(service)
            return
        }
        if (
            ContextCompat.checkSelfPermission(
                service,
                android.Manifest.permission.CAMERA,
            ) != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            MonitoringLog.w(
                "Facial Expression Detection: camera permission denied — enable Camera in Settings",
            )
            if (sessionActive) scheduleFiveMinuteTimer()
            return
        }
        if (activePackage.isBlank()) return
        if (CameraCaptureCoordinator.isFaceMoodVerifyInProgress()) {
            mainHandler.postDelayed({ tryRecordFace(ignoreCooldown, reason) }, 2_500L)
            return
        }
        if (captureInFlight.get() || CameraCaptureCoordinator.isFacialExpressionRecording()) {
            if (reason == "foreground_app_opened" && initialCaptureRetryCount < MAX_INITIAL_CAPTURE_RETRIES) {
                initialCaptureRetryCount++
                mainHandler.postDelayed({ tryRecordFace(ignoreCooldown, reason) }, CAMERA_RETRY_DELAY_MS)
            }
            return
        }
        if (!CameraCaptureCoordinator.tryAcquireFacialExpressionRecording(service, reason, ignoreCooldown)) {
            if (reason == "foreground_app_opened" && initialCaptureRetryCount < MAX_INITIAL_CAPTURE_RETRIES) {
                initialCaptureRetryCount++
                mainHandler.postDelayed({ tryRecordFace(ignoreCooldown, reason) }, CAMERA_RETRY_DELAY_MS)
                return
            }
            if (!ignoreCooldown) {
                val remaining = CameraCaptureCoordinator.faceCooldownRemainingMs(service)
                if (remaining > 0) scheduleFiveMinuteTimer()
            }
            return
        }
        initialCaptureRetryCount = 0
        noDataRetryCount = 0
        bindAttempt = 0
        recordFaceChunk(attempt = 0)
    }

    private fun recordFaceChunk(attempt: Int) {
        if (!captureInFlight.compareAndSet(false, true)) {
            CameraCaptureCoordinator.releaseFacialExpressionRecording(service, success = false)
            return
        }
        bindAttempt = attempt
        cameraState = CameraRecState.INITIALIZING
        recordingDataStarted = false
        recordingStartedAtMs = 0L
        service.setCameraForegroundElevated(true)
        MonitoringLog.i(
            "Facial Expression Detection: ${FACE_DURATION_SECONDS}s recording starting | app:$activeAppName | attempt:${attempt + 1}",
        )
        cameraInitExecutor.execute {
            try {
                val provider = ProcessCameraProvider.getInstance(service).get()
                mainHandler.post { bindAndRecord(provider, attempt) }
            } catch (e: Exception) {
                MonitoringLog.e("Face recording failed: camera init — ${e.message}", e)
                handleBindFailure(e.message ?: "camera_init", attempt)
            }
        }
    }

    private fun bindAndRecord(provider: ProcessCameraProvider, attempt: Int) {
        if (!sessionActive) {
            finishCapture(success = false)
            return
        }
        cameraProvider = provider
        try {
            unbindCameraImmediate()
            val lifecycle = CamLifecycle().also { camLifecycle = it }
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
            pendingRecordAttempt = attempt
            val preview =
                Preview.Builder().build().also { p ->
                    p.setSurfaceProvider { request ->
                        val st =
                            android.graphics.SurfaceTexture(0).apply {
                                setDefaultBufferSize(16, 16)
                            }
                        val surface = Surface(st)
                        request.provideSurface(surface, surfaceReleaseExecutor) {
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
            analysis.setAnalyzer(cameraInitExecutor) { proxy ->
                analyzeFrameForFace(proxy, capture)
            }
            provider.bindToLifecycle(
                lifecycle,
                CameraSelector.DEFAULT_FRONT_CAMERA,
                preview,
                capture,
                analysis,
            )
            cameraState = CameraRecState.WAITING_FOR_FACE
            MonitoringLog.i(
                "Facial Expression Detection: waiting for face before ${FACE_DURATION_SECONDS}s record | app:$activeAppName",
            )
            mainHandler.removeCallbacks(faceDetectTimeoutRunnable)
            mainHandler.postDelayed(faceDetectTimeoutRunnable, FACE_DETECT_TIMEOUT_MS)
        } catch (e: Exception) {
            MonitoringLog.e("Face recording failed: camera bind — ${e.message}", e)
            handleBindFailure(e.message ?: "camera_bind", attempt)
        }
    }

    private fun analyzeFrameForFace(
        proxy: ImageProxy,
        capture: VideoCapture<Recorder>,
    ) {
        if (cameraState != CameraRecState.WAITING_FOR_FACE) {
            proxy.close()
            return
        }
        val mediaImage = proxy.image
        if (mediaImage == null) {
            proxy.close()
            return
        }
        val input =
            InputImage.fromMediaImage(
                mediaImage,
                proxy.imageInfo.rotationDegrees,
            )
        FacePresenceDetector.detectPresence(input) { present ->
            proxy.close()
            if (!present || cameraState != CameraRecState.WAITING_FOR_FACE) {
                return@detectPresence
            }
            mainHandler.post {
                if (cameraState != CameraRecState.WAITING_FOR_FACE) return@post
                mainHandler.removeCallbacks(faceDetectTimeoutRunnable)
                cameraState = CameraRecState.READY
                imageAnalysis?.clearAnalyzer()
                startRecordingIfReady(capture, pendingRecordAttempt)
            }
        }
    }

    private fun startRecordingIfReady(capture: VideoCapture<Recorder>, attempt: Int) {
        if (!sessionActive || cameraState != CameraRecState.READY) {
            finishCapture(success = false)
            return
        }
        val outFile = File(service.cacheDir, "face_scheduled_${System.currentTimeMillis()}.mp4")
        activeOutputFile = outFile
        try {
            val session =
                capture.output
                    .prepareRecording(service, FileOutputOptions.Builder(outFile).build())
                    .start(mainExecutor) { event ->
                        when (event) {
                            is VideoRecordEvent.Start -> {
                                recordingDataStarted = true
                                recordingStartedAtMs = System.currentTimeMillis()
                                cameraState = CameraRecState.RECORDING
                                MonitoringLog.i(
                                    "Facial Expression Detection: camera READY — recording | app:$activeAppName",
                                )
                                scheduleFullDurationStop()
                            }
                            is VideoRecordEvent.Finalize -> handleFinalize(event, outFile, attempt)
                        }
                    }
            activeRecording = session
            cameraState = CameraRecState.RECORDING
            recordingStartedAtMs = System.currentTimeMillis()
            // Fallback stop if Start event is delayed on this OEM.
            mainHandler.postDelayed(stopRunnable, CHUNK_MS + CAMERA_READY_DELAY_MS)
        } catch (e: Exception) {
            MonitoringLog.e("Face recording failed: start — ${e.message}", e)
            handleBindFailure(e.message ?: "record_start", attempt)
        }
    }

    private fun scheduleFullDurationStop() {
        mainHandler.removeCallbacks(stopRunnable)
        val elapsed = (System.currentTimeMillis() - recordingStartedAtMs).coerceAtLeast(0L)
        val remaining = (CHUNK_MS - elapsed).coerceAtLeast(MIN_RECORD_BEFORE_STOP_MS)
        mainHandler.postDelayed(stopRunnable, remaining)
    }

    private fun requestStopRecording(force: Boolean) {
        if (cameraState == CameraRecState.IDLE || cameraState == CameraRecState.FINALIZING) return
        if (!force) {
            val started = if (recordingStartedAtMs > 0L) recordingStartedAtMs else System.currentTimeMillis()
            val elapsed = System.currentTimeMillis() - started
            if (elapsed < MIN_RECORD_BEFORE_STOP_MS) {
                mainHandler.postDelayed(
                    { requestStopRecording(force = false) },
                    MIN_RECORD_BEFORE_STOP_MS - elapsed,
                )
                return
            }
        }
        if (cameraState == CameraRecState.STOPPING) return
        cameraState = CameraRecState.STOPPING
        try {
            activeRecording?.stop()
        } catch (e: Exception) {
            MonitoringLog.w("Face recording stop skipped: ${e.message}")
        }
    }

    private fun handleFinalize(event: VideoRecordEvent.Finalize, outFile: File, attempt: Int) {
        cameraState = CameraRecState.FINALIZING
        activeRecording = null
        mainHandler.removeCallbacks(stopRunnable)
        service.setCameraForegroundElevated(false)

        val errMsg = event.cause?.message.orEmpty()
        val noValidData =
            event.error == VideoRecordEvent.Finalize.ERROR_NO_VALID_DATA ||
                errMsg.contains("NO_VALID_DATA", ignoreCase = true) ||
                errMsg.contains("no valid data", ignoreCase = true)

        val hasBytes = outFile.exists() && outFile.length() > 4096L
        val ok = !event.hasError() && hasBytes

        if (ok) {
            persistAndUploadFace(outFile)
            scheduleCameraRelease()
            finishCapture(success = true)
            return
        }

        MonitoringLog.e("Face video save failed: ${errMsg.ifBlank { "record_finalize" }} | App: $activeAppName")
        CameraCaptureCoordinator.markFaceCaptureFailed(errMsg.ifBlank { "record_finalize" })
        outFile.delete()

        if (noValidData && noDataRetryCount < MAX_NO_DATA_RETRIES && sessionActive) {
            noDataRetryCount++
            MonitoringLog.w("⚠️ Face recording retrying — previous attempt had no data")
            captureInFlight.set(false)
            cameraState = CameraRecState.IDLE
            scheduleCameraRelease()
            CameraCaptureCoordinator.releaseFacialExpressionRecording(service, success = false)
            mainHandler.postDelayed(
                { recordFaceChunk(attempt = attempt) },
                NO_DATA_RETRY_DELAY_MS,
            )
            return
        }

        if (!ok && attempt + 1 < MAX_CAMERA_RETRIES && sessionActive) {
            captureInFlight.set(false)
            cameraState = CameraRecState.IDLE
            scheduleCameraRelease()
            CameraCaptureCoordinator.releaseFacialExpressionRecording(service, success = false)
            mainHandler.postDelayed(
                { recordFaceChunk(attempt + 1) },
                CAMERA_RETRY_DELAY_MS,
            )
            return
        }

        scheduleCameraRelease()
        finishCapture(success = false)
    }

    private fun handleBindFailure(reason: String, attempt: Int) {
        service.setCameraForegroundElevated(false)
        scheduleCameraRelease()
        if (attempt + 1 < MAX_CAMERA_RETRIES && sessionActive) {
            captureInFlight.set(false)
            CameraCaptureCoordinator.releaseFacialExpressionRecording(service, success = false)
            mainHandler.postDelayed({ recordFaceChunk(attempt + 1) }, CAMERA_RETRY_DELAY_MS)
        } else {
            CameraCaptureCoordinator.markFaceCaptureFailed(reason)
            finishCapture(success = false)
        }
    }

    private fun scheduleCameraRelease() {
        mainHandler.removeCallbacks(releaseCameraRunnable)
        mainHandler.postDelayed(releaseCameraRunnable, CAMERA_RELEASE_DELAY_MS)
    }

    private fun finishCapture(success: Boolean) {
        captureInFlight.set(false)
        activeOutputFile = null
        service.setCameraForegroundElevated(false)
        CameraCaptureCoordinator.releaseFacialExpressionRecording(service, success = success)
        if (sessionActive) scheduleFiveMinuteTimer()
    }

    private fun cancelRecording(success: Boolean, force: Boolean) {
        mainHandler.removeCallbacks(stopRunnable)
        requestStopRecording(force = force)
        if (force) {
            mainHandler.removeCallbacks(releaseCameraRunnable)
            unbindCamera()
            cameraState = CameraRecState.IDLE
            if (captureInFlight.get()) finishCapture(success = success)
        }
    }

    private fun unbindCameraImmediate() {
        try {
            cameraProvider?.unbindAll()
        } catch (_: Exception) {
        }
        camLifecycle?.destroy()
        camLifecycle = null
        videoCapture = null
        imageAnalysis?.clearAnalyzer()
        imageAnalysis = null
    }

    private fun unbindCamera() {
        unbindCameraImmediate()
        cameraProvider = null
        activeOutputFile = null
        mainHandler.removeCallbacks(faceDetectTimeoutRunnable)
    }

    private fun persistAndUploadFace(tempFile: File) {
        val appNameSnapshot = activeAppName.ifBlank { AppDisplayName.resolve(service, activePackage) }
        val packageSnapshot = activePackage
        uploadExecutor.execute {
            try {
                val requireIdentity = TrackerPrefs.faceVerified(service)
                val identityOk =
                    if (requireIdentity) {
                        FacialExpressionUploader.verifyVideoIdentity(service, tempFile)
                    } else {
                        true
                    }
                if (requireIdentity && !identityOk) {
                    MonitoringLog.i(
                        "Face clip discarded — enrolled user not matched in recording | app:$appNameSnapshot",
                    )
                    tempFile.delete()
                    return@execute
                }
                val persisted = MonitoringStorage.persistFaceClip(service, tempFile)
                tempFile.delete()
                val recordedAt = System.currentTimeMillis()
                val rowId =
                    monitoringDb?.insertFacialExpression(
                        appName = appNameSnapshot,
                        filePath = persisted.absolutePath,
                        recordedAtMs = recordedAt,
                        durationSeconds = FACE_DURATION_SECONDS,
                    ) ?: -1L
                val ts =
                    SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(recordedAt))
                if (rowId > 0) {
                    MonitoringLog.i(
                        "✅ Face video saved — App: $appNameSnapshot | Duration: ${FACE_DURATION_SECONDS}s | Time: $ts",
                    )
                } else {
                    MonitoringLog.e(
                        "❌ DB save failed — File exists on disk but not saved | Path: ${persisted.absolutePath} | Error: insert returned $rowId",
                    )
                }
                val uploaded =
                    FacialExpressionUploader.upload(
                        context = service,
                        file = persisted,
                        sourceType = "scheduled_background",
                        sourceAppName = appNameSnapshot,
                        sourcePackageName = packageSnapshot,
                        durationSeconds = FACE_DURATION_SECONDS,
                        verifyFace = identityOk,
                        clientTimestampMs = recordedAt,
                        recordingType = "facial_expression_detection",
                    )
                if (!uploaded) {
                    if (requireIdentity) {
                        MonitoringLog.w(
                            "Face clip upload failed — kept locally for retry with identity check",
                        )
                    }
                    MonitoringUploadQueue.enqueueFaceClip(
                        service,
                        persisted.absolutePath,
                        appNameSnapshot,
                        packageSnapshot,
                        FACE_DURATION_SECONDS,
                        recordedAt,
                    )
                }
            } catch (e: Exception) {
                MonitoringLog.e(
                    "❌ DB save failed — File exists on disk but not saved | Path: ${tempFile.absolutePath} | Error: ${e.message}",
                    e,
                )
                tempFile.delete()
            } finally {
                mainHandler.post {
                    unbindCamera()
                    cameraState = CameraRecState.IDLE
                }
            }
        }
    }

    companion object {
        private const val CHUNK_MS = 30_000L
        private const val FIVE_MINUTE_MS = 5 * 60 * 1000L
        private const val FACE_DURATION_SECONDS = 30
        private const val INITIAL_CAPTURE_DELAY_MS = 1_200L
        private const val CAMERA_READY_DELAY_MS = 1_500L
        private const val MIN_RECORD_BEFORE_STOP_MS = 5_000L
        private const val CAMERA_RELEASE_DELAY_MS = 600L
        private const val CAMERA_RETRY_DELAY_MS = 2_000L
        private const val NO_DATA_RETRY_DELAY_MS = 2_000L
        private const val MAX_CAMERA_RETRIES = 3
        private const val MAX_INITIAL_CAPTURE_RETRIES = 8
        private const val MAX_NO_DATA_RETRIES = 3
        private const val FACE_DETECT_TIMEOUT_MS = 12_000L
    }
}
