package com.example.frontend

import android.content.Context
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Rolling 30s screen chunks for monitored social apps.
 *
 * One MediaProjection + MediaRecorder + VirtualDisplay session stays alive while the social
 * app is foreground. Chunks rotate via [MediaRecorder.setNextOutputFile] + [setMaxDuration]
 * so the encoder pipeline is never torn down between segments.
 */
class VideoCaptureController(
    private val context: Context,
    /** Elevate/clear MediaProjection FGS type (API 34+ must be true before getMediaProjection). */
    private val onProjectionCaptureActive: (Boolean) -> Unit = { },
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val chunkSaveExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val chunkUploadExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val projectionManager =
        context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

    private var monitoringDb: MonitoringLocalDatabase? = null
    private var mediaProjection: MediaProjection? = null
    private var mediaRecorder: MediaRecorder? = null
    private var virtualDisplay: VirtualDisplay? = null
    /** File currently being written by MediaRecorder. */
    private var currentFile: File? = null
    /** Next file pre-registered via setNextOutputFile for seamless rotation. */
    private var pendingNextFile: File? = null
    private var currentAppName: String = "Other"
    private var currentPackage: String = "unknown"
    private var currentRecordingStartedAtMs: Long = 0L
    private var isRecording = false
    /** True while a monitored social app session should keep producing 30s chunks. */
    private var shouldContinue = false
    /** True from first chunk until [stopIfNeeded] / screen off. */
    private var sessionActive = false
    private var nextChunkIndex: Int = 0
    private var projectionStartRetries = 0
    private var lastProjectionFailureLogMs = 0L
    private var activeSessionPackage: String? = null
    private var gaplessRotationSupported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
    private var lastChunkRotateMs = 0L
    private var gaplessRotateRunnable: Runnable? = null
    private var isTrackRunning = false
    private var pendingGaplessRotation = false
    private var pendingSessionStart: Pair<String, String>? = null

    private fun runRecoveryCheck() {
        if (!shouldContinue || isRecording) return
        if (activeSessionPackage.isNullOrBlank()) return
        if (CameraCaptureCoordinator.shouldDeferScreenCapture()) {
            CameraCaptureCoordinator.runWhenFaceIdle {
                mainHandler.post { runRecoveryCheck() }
            }
            return
        }
        MonitoringLog.w("Screen chunk recovery — restarting rolling recorder")
        startGaplessRecording(currentAppName, currentPackage)
    }

    private val recoveryRunnable = Runnable { runRecoveryCheck() }

    /** Pre-bind MediaProjection using saved consent (main thread). */
    fun warmUpProjection() {
        if (!ScreenCapturePermissionStore.hasPermission(context)) return
        if (CameraCaptureCoordinator.shouldDeferScreenCapture()) {
            CameraCaptureCoordinator.runWhenFaceIdle { warmUpProjection() }
            return
        }
        mainHandler.post {
            if (!shouldContinue && !sessionActive && !TrackerPrefs.shouldAllowUsageCollection(context)) {
                return@post
            }
            onProjectionCaptureActive(true)
            val projection = ensureProjection()
            if (projection == null) {
                onProjectionCaptureActive(false)
                logProjectionFailureThrottled(
                    "Screen recording warmup failed — saved consent may need renewal",
                )
            } else {
                MonitoringLog.i("Screen recording ready (saved MediaProjection consent)")
            }
        }
    }

    fun attachDatabase(db: MonitoringLocalDatabase) {
        monitoringDb = db
    }

    fun updatePlayback(
        shouldRecord: Boolean,
        platform: String,
        packageName: String,
        appDisplayName: String = platform,
    ) {
        if (!MonitoringPolicy.screenRecordingAllowed(context)) {
            if (!shouldRecord) {
                stopIfNeeded(logAppClosed = false)
            } else if (isRecording || sessionActive) {
                MonitoringLog.w("Screen recording paused — battery/power policy")
                endSession(uploadPartialChunk = true, notifyProjectionInactive = true)
            }
            return
        }
        if (!TrackerPrefs.shouldAllowUsageCollection(context) ||
            !ScreenCapturePermissionStore.hasPermission(context)
        ) {
            if (!ScreenCapturePermissionStore.hasPermission(context) && shouldRecord) {
                logProjectionFailureThrottled("Screen recording skipped: MediaProjection permission missing")
            }
            stopIfNeeded(logAppClosed = false)
            return
        }

        if (!shouldRecord) {
            stopIfNeeded(logAppClosed = isRecording || sessionActive)
            activeSessionPackage = null
            return
        }

        shouldContinue = true
        currentAppName = appDisplayName.ifBlank { platform }

        if (isRecording && packageName != currentPackage) {
            endSession(uploadPartialChunk = true, notifyProjectionInactive = false)
            activeSessionPackage = null
            nextChunkIndex = 0
            projectionStartRetries = 0
        }

        currentPackage = packageName

        if (isRecording) {
            return
        }

        val isNewSession = activeSessionPackage != packageName
        if (isNewSession) {
        nextChunkIndex = 0
            projectionStartRetries = 0
            activeSessionPackage = packageName
        }

        if (sessionActive) {
            scheduleRecoveryCheck()
            return
        }

        startSessionRecording(currentAppName, currentPackage)
    }

    private fun stopIfNeeded(logAppClosed: Boolean) {
        val wasActive = isRecording || sessionActive
        shouldContinue = false
        activeSessionPackage = null
        projectionStartRetries = 0
        mainHandler.removeCallbacks(recoveryRunnable)
        endSession(uploadPartialChunk = wasActive, notifyProjectionInactive = true)
        if (logAppClosed && wasActive) {
            MonitoringLog.i("Recording stopped — app closed")
        }
    }

    fun onScreenLockedOrOff() {
        shouldContinue = false
        activeSessionPackage = null
        projectionStartRetries = 0
        mainHandler.removeCallbacks(recoveryRunnable)
        endSession(uploadPartialChunk = isRecording, notifyProjectionInactive = true)
        if (mediaProjection == null) {
        onProjectionCaptureActive(false)
        }
    }

    fun onForegroundTypeDenied() {
        shouldContinue = false
        activeSessionPackage = null
        projectionStartRetries = 0
        endSession(uploadPartialChunk = isRecording, notifyProjectionInactive = true)
        releaseProjection()
        onProjectionCaptureActive(false)
        MonitoringLog.e("Screen recording stopped: foreground service type denied")
    }

    fun release() {
        shouldContinue = false
        activeSessionPackage = null
        projectionStartRetries = 0
        mainHandler.removeCallbacks(recoveryRunnable)
        endSession(uploadPartialChunk = true, notifyProjectionInactive = true)
        releaseProjection()
        onProjectionCaptureActive(false)
        chunkSaveExecutor.shutdown()
        chunkUploadExecutor.shutdown()
    }

    private fun scaledCaptureSize(): Triple<Int, Int, Int> {
        val metrics = context.resources.displayMetrics
        val width = (metrics.widthPixels / 2).coerceIn(360, 720)
        val height = (metrics.heightPixels / 2).coerceIn(640, 1280)
        val density = metrics.densityDpi
        return Triple(width, height, density)
    }

    private fun startSessionRecording(appName: String, packageName: String) {
        if (CameraCaptureCoordinator.shouldDeferScreenCapture()) {
            pendingSessionStart = appName to packageName
            CameraCaptureCoordinator.runWhenFaceIdle {
                pendingSessionStart?.let { (n, p) ->
                    pendingSessionStart = null
                    startSessionRecording(n, p)
                }
            }
            return
        }
        if (!sessionActive && !CameraCaptureCoordinator.tryAcquireScreenRecording()) {
            MonitoringLog.w("Screen recording lock busy — retry scheduled")
            mainHandler.postDelayed({ startSessionRecording(appName, packageName) }, 400L)
            return
        }
        sessionActive = true
        onProjectionCaptureActive(true)
        val startupDelay = if (mediaProjection != null) 0L else 300L
        mainHandler.postDelayed({
            if (!shouldContinue && !sessionActive) {
                releaseSessionLockIfIdle()
                onProjectionCaptureActive(false)
                return@postDelayed
            }
            startGaplessRecording(appName, packageName)
        }, startupDelay)
    }

    private fun startGaplessRecording(appName: String, packageName: String) {
        if (!shouldContinue || !sessionActive || isRecording) return
        if (CameraCaptureCoordinator.shouldDeferScreenCapture()) {
            CameraCaptureCoordinator.runWhenFaceIdle { startGaplessRecording(appName, packageName) }
            return
        }
        val projection = ensureProjection()
        if (projection == null) {
            if (shouldContinue && projectionStartRetries < 5) {
                projectionStartRetries += 1
                mainHandler.postDelayed(
                    { startGaplessRecording(appName, packageName) },
                    if (projectionStartRetries == 1) 200L else 500L,
                )
                return
            }
            projectionStartRetries = 0
            logProjectionFailureThrottled(
                "Screen recording failed: MediaProjection unavailable (re-grant screen capture in MindSync)",
            )
            scheduleRecoveryCheck()
            return
        }
        projectionStartRetries = 0
        if (gaplessRotationSupported) {
            beginGaplessRecorder(appName, packageName, projection)
        } else {
            beginLegacyRecorder(appName, packageName, projection)
        }
    }

    private fun endSession(uploadPartialChunk: Boolean, notifyProjectionInactive: Boolean) {
        if (isRecording) {
            stopActiveRecorder(uploadPartialChunk = uploadPartialChunk)
        }
        sessionActive = false
        releaseSessionLockIfIdle()
        if (notifyProjectionInactive) {
            onProjectionCaptureActive(false)
        }
        TrackerPrefs.setRecordingState(context, false, "", "")
    }

    private fun releaseSessionLockIfIdle() {
        if (!sessionActive && !isRecording) {
            CameraCaptureCoordinator.releaseScreenRecording()
        }
    }

    private fun createChunkTempFile(): File {
        val outputDir = File(context.filesDir, "video_chunks").apply { mkdirs() }
        val outputFile = File(outputDir, "chunk_${System.currentTimeMillis()}.mp4")
        runCatching { outputFile.createNewFile() }
        return outputFile
    }

    private fun buildMediaRecorder(): MediaRecorder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }

    private fun beginGaplessRecorder(
        appName: String,
        packageName: String,
        projection: MediaProjection,
    ) {
        val file0 = createChunkTempFile()
        val file1 = createChunkTempFile()
        val (width, height, density) = scaledCaptureSize()

        val recorder = buildMediaRecorder()
        try {
            recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            recorder.setVideoEncodingBitRate(1_200_000)
            recorder.setVideoFrameRate(10)
            recorder.setVideoSize(width, height)
            recorder.setOutputFile(file0.absolutePath)
            recorder.setNextOutputFile(file1)
            recorder.setMaxDuration(CHUNK_DURATION_MS.toInt())
            recorder.setOnInfoListener { _, what, _ ->
                when (what) {
                    MediaRecorder.MEDIA_RECORDER_INFO_NEXT_OUTPUT_FILE_STARTED,
                    MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED,
                    -> mainHandler.post { onGaplessChunkRotated() }
                }
            }
            recorder.prepare()

            val display =
                projection.createVirtualDisplay(
                "MindSyncVideoCapture",
                width,
                height,
                density,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                recorder.surface,
                null,
                null,
            )

            recorder.start()
            mediaRecorder = recorder
            virtualDisplay = display
            currentFile = file0
            pendingNextFile = file1
            currentAppName = appName
            currentPackage = packageName
            currentRecordingStartedAtMs = System.currentTimeMillis()
            isRecording = true
            isTrackRunning = true
            TrackerPrefs.setRecordingState(context, true, appName, packageName)
            onProjectionCaptureActive(true)
            MonitoringLog.i(
                "Screen recording started (gapless 30s chunks) | app:$appName | chunk:$nextChunkIndex | ${width}x$height",
            )
            scheduleGaplessRotationWatchdog()
            scheduleRecoveryCheck()
        } catch (e: Exception) {
            recorder.reset()
            recorder.release()
            file0.delete()
            file1.delete()
            virtualDisplay?.release()
            virtualDisplay = null
            mediaRecorder = null
            currentFile = null
            pendingNextFile = null
            isRecording = false
            MonitoringLog.e("Screen recording start failed: ${e.message}", e)
            if (shouldContinue && sessionActive) {
                mainHandler.postDelayed({ startGaplessRecording(appName, packageName) }, 500L)
            } else {
                endSession(uploadPartialChunk = false, notifyProjectionInactive = true)
            }
        }
    }

    /** API < 26 fallback — still avoids unnecessary projection restarts. */
    private var legacyRotateRunnable: Runnable? = null

    private fun beginLegacyRecorder(
        appName: String,
        packageName: String,
        projection: MediaProjection,
    ) {
        val outputFile = createChunkTempFile()
        val (width, height, density) = scaledCaptureSize()
        val recorder = buildMediaRecorder()
        try {
            recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            recorder.setVideoEncodingBitRate(1_200_000)
            recorder.setVideoFrameRate(10)
            recorder.setVideoSize(width, height)
            recorder.setOutputFile(outputFile.absolutePath)
            recorder.prepare()
            val display =
                projection.createVirtualDisplay(
                    "MindSyncVideoCapture",
                    width,
                    height,
                    density,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                    recorder.surface,
                    null,
                    null,
                )
            recorder.start()
            mediaRecorder = recorder
            virtualDisplay = display
            currentFile = outputFile
            currentAppName = appName
            currentPackage = packageName
            currentRecordingStartedAtMs = System.currentTimeMillis()
            isRecording = true
            isTrackRunning = true
            TrackerPrefs.setRecordingState(context, true, appName, packageName)
            onProjectionCaptureActive(true)
            legacyRotateRunnable =
                Runnable {
                    if (!isRecording || !shouldContinue) return@Runnable
                    finalizeLegacyChunkAndContinue()
                }
            mainHandler.postDelayed(legacyRotateRunnable!!, CHUNK_DURATION_MS)
            scheduleRecoveryCheck()
        } catch (e: Exception) {
            recorder.reset()
            recorder.release()
            outputFile.delete()
            isRecording = false
            MonitoringLog.e("Legacy screen recording start failed: ${e.message}", e)
        }
    }

    private fun finalizeLegacyChunkAndContinue() {
        if (!isRecording) return
        val completed = currentFile
        val startedAt = currentRecordingStartedAtMs
        val endedAt = System.currentTimeMillis()
        val idx = nextChunkIndex
        stopActiveRecorder(uploadPartialChunk = false)
        if (completed != null && completed.exists() && completed.length() > 1024L) {
            nextChunkIndex += 1
            enqueueChunkPersist(completed, idx, startedAt, endedAt)
        } else {
            completed?.delete()
        }
        if (shouldContinue && sessionActive) {
            mainHandler.postDelayed({ startGaplessRecording(currentAppName, currentPackage) }, 300L)
        }
    }

    private fun onGaplessChunkRotated() {
        if (!isRecording || !shouldContinue || !sessionActive) return
        if (CameraCaptureCoordinator.shouldDeferScreenCapture()) {
            pendingGaplessRotation = true
            CameraCaptureCoordinator.runWhenFaceIdle {
                if (pendingGaplessRotation) {
                    pendingGaplessRotation = false
                    onGaplessChunkRotated()
                }
            }
            return
        }
        val now = System.currentTimeMillis()
        if (now - lastChunkRotateMs < CHUNK_DURATION_MS - 2_000L) return
        lastChunkRotateMs = now

        val completed = currentFile
        val startedAt = currentRecordingStartedAtMs
        val endedAt = System.currentTimeMillis()
        val idx = nextChunkIndex

        currentFile = pendingNextFile
        currentRecordingStartedAtMs = endedAt

        val nextFile = createChunkTempFile()
        pendingNextFile = nextFile
        try {
            mediaRecorder?.setNextOutputFile(nextFile)
        } catch (e: Exception) {
            MonitoringLog.e("setNextOutputFile failed: ${e.message}", e)
            scheduleRecoveryCheck()
            return
        }

        if (completed != null && completed.exists() && completed.length() > 1024L) {
            nextChunkIndex += 1
            enqueueChunkPersist(completed, idx, startedAt, endedAt)
            MonitoringLog.i(
                "30 sec video chunk rotated (gapless) | app:$currentAppName | chunk:$idx",
            )
        } else {
            completed?.delete()
        }
        scheduleGaplessRotationWatchdog()
        scheduleRecoveryCheck()
    }

    /** OEM fallback when MediaRecorder rotation callbacks are delayed or missing. */
    private fun scheduleGaplessRotationWatchdog() {
        if (!gaplessRotationSupported || !isRecording) return
        gaplessRotateRunnable?.let { mainHandler.removeCallbacks(it) }
        val runnable =
            Runnable {
                if (!isRecording || !shouldContinue || !sessionActive) return@Runnable
                val elapsed = System.currentTimeMillis() - currentRecordingStartedAtMs
                if (elapsed >= CHUNK_DURATION_MS - 500L) {
                    onGaplessChunkRotated()
                }
                if (isRecording && shouldContinue && sessionActive) {
                    scheduleGaplessRotationWatchdog()
                }
            }
        gaplessRotateRunnable = runnable
        mainHandler.postDelayed(runnable, CHUNK_DURATION_MS)
    }

    private fun cancelGaplessRotationWatchdog() {
        gaplessRotateRunnable?.let { mainHandler.removeCallbacks(it) }
        gaplessRotateRunnable = null
    }

    /** Stops the active recorder at session end only — never between gapless chunks. */
    private fun stopActiveRecorder(uploadPartialChunk: Boolean) {
        cancelGaplessRotationWatchdog()
        legacyRotateRunnable?.let { mainHandler.removeCallbacks(it) }
        legacyRotateRunnable = null
        if (!isRecording) return

        val recorder = mediaRecorder
        val outputFile = currentFile
        val startedAt = currentRecordingStartedAtMs
        val endedAt = System.currentTimeMillis()
        val chunkIndexForUpload = nextChunkIndex
        val appName = currentAppName
        val packageName = currentPackage

        if (isTrackRunning) {
        try {
            recorder?.stop()
            } catch (e: Exception) {
                MonitoringLog.w("Screen recorder stop skipped: ${e.message}")
                saveOrphanChunkIfPresent(outputFile, chunkIndexForUpload, startedAt, endedAt, appName, packageName)
            } finally {
                isTrackRunning = false
                try {
                    recorder?.reset()
        } catch (_: Exception) {
                }
                recorder?.release()
            }
        } else {
            try {
                recorder?.reset()
            } catch (_: Exception) {
            }
            recorder?.release()
        }
            mediaRecorder = null
            virtualDisplay?.release()
            virtualDisplay = null
            currentFile = null
        pendingNextFile = null
            isRecording = false

        if (
            uploadPartialChunk &&
            outputFile != null &&
            outputFile.exists() &&
            outputFile.length() > 1024L
        ) {
            nextChunkIndex += 1
            enqueueChunkPersist(
                outputFile,
                chunkIndexForUpload,
                startedAt,
                endedAt,
                appName,
                packageName,
            )
        } else {
            saveOrphanChunkIfPresent(outputFile, chunkIndexForUpload, startedAt, endedAt, appName, packageName)
            outputFile?.delete()
        }
    }

    /** Save a finalized file that exists on disk even if MediaRecorder stop failed. */
    private fun saveOrphanChunkIfPresent(
        file: File?,
        chunkIndex: Int,
        startMs: Long,
        endMs: Long,
        appName: String,
        packageName: String,
    ) {
        if (file == null || !file.exists() || file.length() <= 1024L) return
        nextChunkIndex += 1
        MonitoringLog.w(
            "Screen chunk orphan save — file on disk but recorder stop failed | app:$appName | chunk:$chunkIndex",
        )
        enqueueChunkPersist(file, chunkIndex, startMs, endMs, appName, packageName)
    }

    private fun enqueueChunkPersist(
        tempFile: File,
        chunkIndex: Int,
        startMs: Long,
        endMs: Long,
        appName: String = currentAppName,
        packageName: String = currentPackage,
    ) {
        val durationSeconds =
            ((endMs - startMs) / 1000L).toInt().coerceIn(1, CHUNK_DURATION_SEC)
        chunkSaveExecutor.execute {
            persistChunkMetadata(
                tempFile = tempFile,
                durationSeconds = durationSeconds,
                appName = appName,
                packageName = packageName,
                chunkIndex = chunkIndex,
                startMs = startMs,
                endMs = endMs,
            )
        }
        MonitoringLog.i(
            "30 sec video chunk finalized — saving async | app:$appName | chunk:$chunkIndex",
        )
    }

    private fun scheduleRecoveryCheck() {
        if (!shouldContinue || !sessionActive) return
        mainHandler.removeCallbacks(recoveryRunnable)
        mainHandler.postDelayed(recoveryRunnable, RECOVERY_DELAY_MS)
    }

    private fun persistChunkMetadata(
        tempFile: File,
        durationSeconds: Int,
        appName: String,
        packageName: String,
        chunkIndex: Int,
        startMs: Long,
        endMs: Long,
    ) {
        val fileSizeBytes = tempFile.length()
        try {
            if (!tempFile.exists() || fileSizeBytes <= 0L) {
                MonitoringLog.e(
                    "❌ DB save failed — File exists on disk but not saved | Path: ${tempFile.absolutePath} | Error: empty file",
                )
                tempFile.delete()
                return
            }
            val persisted = MonitoringStorage.persistScreenChunk(context, tempFile, chunkIndex)
            tempFile.delete()
            if (!persisted.exists() || persisted.length() <= 0L) {
                MonitoringLog.e(
                    "❌ DB save failed — File exists on disk but not saved | Path: ${tempFile.absolutePath} | Error: persist copy empty",
                )
                return
            }
            val db = monitoringDb ?: MonitoringLocalDatabase.getInstance(context)
            db.ensureVideoChunksTable()
            val sessionId = MonitoringSession.currentSessionId(context)
            val rowId =
                db.insertVideoChunk(
                    appName = appName,
                    packageName = packageName,
                    chunkIndex = chunkIndex,
                    filePath = persisted.absolutePath,
                    startTimeMs = startMs,
                    endTimeMs = endMs,
                    durationSeconds = durationSeconds,
                    isAnalyzed = false,
                    sessionId = sessionId,
                    fileSizeBytes = persisted.length(),
                )
            val chunkDurationMs = (endMs - startMs).coerceAtLeast(0L)
            MonitoringSession.recordChunkCompleted(context, chunkDurationMs)
            val ts =
                java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US)
                    .format(java.util.Date(endMs))
            val sizeMb = String.format(java.util.Locale.US, "%.1f", persisted.length() / (1024.0 * 1024.0))
            if (rowId > 0) {
                MonitoringLog.i(
                    "✅ Video chunk saved to DB — App: $appName | Size: ${sizeMb}MB | Time: $ts | chunk:$chunkIndex | session:$sessionId",
                )
            } else {
                MonitoringLog.e(
                    "❌ DB save failed — File exists on disk but not saved | Path: ${persisted.absolutePath} | Error: insert returned $rowId",
                )
            }
            val fileForUpload = persisted
            chunkUploadExecutor.execute {
                try {
                    val uploaded =
                        ScreenChunkUploader.upload(
                            context = context,
                            file = fileForUpload,
                            platform = appName,
                            packageName = packageName,
                            chunkIndex = chunkIndex,
                            durationSeconds = durationSeconds,
                            startTimeMs = startMs,
                            endTimeMs = endMs,
                        )
                    if (uploaded) {
                        MonitoringLog.i(
                            "SCREEN CHUNK UPLOADED ✓ | app:$appName | chunk:$chunkIndex | session:$sessionId",
                        )
                    } else {
                        MonitoringUploadQueue.enqueueScreenChunk(
                context,
                            fileForUpload.absolutePath,
                            appName,
                            packageName,
                            chunkIndex,
                            durationSeconds,
                            startMs,
                            endMs,
                        )
                    }
                    MonitoringUploadQueue.processPending(context, maxItems = 2)
                } catch (e: Exception) {
                    MonitoringLog.e("SCREEN CHUNK UPLOAD FAILED | chunk:$chunkIndex | ${e.message}")
                }
            }
        } catch (e: Exception) {
            MonitoringLog.e(
                "❌ DB save failed — File exists on disk but not saved | Path: ${tempFile.absolutePath} | Error: ${e.message}",
                e,
            )
            tempFile.delete()
        }
    }

    private fun ensureProjection(): MediaProjection? {
        onProjectionCaptureActive(true)
        mediaProjection?.let { return it }
        val acquired =
            MediaProjectionHolder.acquire(context) {
                mediaProjection = null
                if (shouldContinue && sessionActive) {
                    mainHandler.postDelayed(
                        { startGaplessRecording(currentAppName, currentPackage) },
                        500L,
                    )
                }
            }
        mediaProjection = acquired
        return acquired
    }

    private fun releaseProjection() {
        MediaProjectionHolder.releaseAll()
        mediaProjection = null
    }

    private fun logProjectionFailureThrottled(message: String) {
        val now = System.currentTimeMillis()
        if (now - lastProjectionFailureLogMs < 30_000L) return
        lastProjectionFailureLogMs = now
        MonitoringLog.e(message)
    }

    companion object {
        private const val CHUNK_DURATION_MS = 30_000L
        private const val CHUNK_DURATION_SEC = 30
        /** If rolling recorder stalls, attempt recovery without resetting session counters. */
        private const val RECOVERY_DELAY_MS = 2_000L
    }
}
