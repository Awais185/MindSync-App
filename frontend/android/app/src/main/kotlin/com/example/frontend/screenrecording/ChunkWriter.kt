package com.example.frontend.screenrecording

import android.content.Context
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.example.frontend.CameraCaptureCoordinator
import com.example.frontend.MonitoringLog
import java.io.File
import java.util.UUID

/**
 * Gapless 30s screen chunks via [MediaRecorder.setNextOutputFile] — encoder never stops between segments.
 */
class ChunkWriter(
    private val context: Context,
    private val mainHandler: Handler = Handler(Looper.getMainLooper()),
    private val listener: ChunkListener,
) {
    interface ChunkListener {
        fun onChunkReady(meta: ChunkMeta, tempFile: File)
        fun onRecordingStarted(sessionId: String)
        fun onRecordingStopped()
        fun onError(message: String, recoverable: Boolean)
    }

    data class ChunkMeta(
        val sessionId: String,
        val appPackage: String,
        val appName: String,
        val chunkIndex: Int,
        val startTimeMs: Long,
        val endTimeMs: Long,
        val durationMs: Long,
    )

    private var projection: MediaProjection? = null
    private var mediaRecorder: MediaRecorder? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var currentFile: File? = null
    private var pendingNextFile: File? = null
    private var sessionId: String = ""
    private var appPackage: String = ""
    private var appName: String = ""
    private var chunkIndex: Int = 0
    private var chunkStartedAtMs: Long = 0L
    private var isRecording = false
    private var isTrackRunning = false
    private var shouldContinue = false
    private var lastRotateMs = 0L
    private var gaplessRotateRunnable: Runnable? = null

    fun start(projection: MediaProjection, packageName: String, displayName: String) {
        if (isRecording) {
            if (packageName != appPackage) {
                stop(uploadPartial = true)
                start(projection, packageName, displayName)
            }
            return
        }
        this.projection = projection
        appPackage = packageName
        appName = displayName
        sessionId = UUID.randomUUID().toString()
        chunkIndex = 0
        shouldContinue = true
        beginGaplessRecorder()
    }

    fun stop(uploadPartial: Boolean = true) {
        shouldContinue = false
        cancelWatchdog()
        if (!isRecording) {
            listener.onRecordingStopped()
            return
        }
        if (uploadPartial) {
            safeStopTrack()
        } else {
            releaseRecorderOnly()
        }
        listener.onRecordingStopped()
    }

    fun release() {
        shouldContinue = false
        cancelWatchdog()
        releaseRecorderOnly()
        virtualDisplay?.release()
        virtualDisplay = null
        projection = null
        currentFile = null
        pendingNextFile = null
        isRecording = false
        isTrackRunning = false
    }

    private fun beginGaplessRecorder() {
        if (!shouldContinue || projection == null) return
        if (CameraCaptureCoordinator.shouldDeferScreenCapture()) {
            CameraCaptureCoordinator.runWhenFaceIdle { mainHandler.post { beginGaplessRecorder() } }
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            listener.onError("Gapless chunking requires API 26+", recoverable = false)
            return
        }
        val file0 = createTempChunkFile()
        val file1 = createTempChunkFile()
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
                    -> mainHandler.post { onChunkRotated() }
                }
            }
            recorder.prepare()
            val display =
                projection!!.createVirtualDisplay(
                    "MindSyncScreenChunk",
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
            chunkStartedAtMs = System.currentTimeMillis()
            isRecording = true
            isTrackRunning = true
            listener.onRecordingStarted(sessionId)
            MonitoringLog.i(
                "ScreenRecording: gapless pipeline started | app:$appName | session:$sessionId",
            )
            scheduleWatchdog()
        } catch (e: Exception) {
            recorder.reset()
            recorder.release()
            file0.delete()
            file1.delete()
            listener.onError("Recorder start failed: ${e.message}", recoverable = true)
        }
    }

    private fun onChunkRotated() {
        if (!isRecording || !shouldContinue) return
        if (CameraCaptureCoordinator.shouldDeferScreenCapture()) {
            CameraCaptureCoordinator.runWhenFaceIdle { mainHandler.post { onChunkRotated() } }
            return
        }
        val now = System.currentTimeMillis()
        if (now - lastRotateMs < CHUNK_DURATION_MS - 2_000L) return
        lastRotateMs = now

        val completed = currentFile
        val startedAt = chunkStartedAtMs
        val endedAt = now
        val idx = chunkIndex

        currentFile = pendingNextFile
        chunkStartedAtMs = endedAt
        val nextFile = createTempChunkFile()
        pendingNextFile = nextFile
        try {
            mediaRecorder?.setNextOutputFile(nextFile)
        } catch (e: Exception) {
            MonitoringLog.e("ScreenRecording: setNextOutputFile failed — ${e.message}")
            listener.onError("setNextOutputFile: ${e.message}", recoverable = true)
            return
        }

        if (completed != null && completed.exists() && completed.length() > 1024L) {
            chunkIndex += 1
            deliverChunk(
                ChunkMeta(
                    sessionId = sessionId,
                    appPackage = appPackage,
                    appName = appName,
                    chunkIndex = idx,
                    startTimeMs = startedAt,
                    endTimeMs = endedAt,
                    durationMs = (endedAt - startedAt).coerceAtLeast(0L),
                ),
                completed,
            )
        } else {
            completed?.delete()
        }
        scheduleWatchdog()
    }

    private fun deliverChunk(meta: ChunkMeta, file: File) {
        MonitoringLog.i(
            "ScreenRecording: chunk ${meta.chunkIndex} finalized (${meta.durationMs}ms) | app:${meta.appName}",
        )
        listener.onChunkReady(meta, file)
    }

    private fun safeStopTrack() {
        if (!isRecording) return
        val recorder = mediaRecorder
        val outputFile = currentFile
        val startedAt = chunkStartedAtMs
        val endedAt = System.currentTimeMillis()
        val idx = chunkIndex
        if (isTrackRunning) {
            try {
                recorder?.stop()
            } catch (e: Exception) {
                MonitoringLog.w("ScreenRecording: stop skipped — ${e.message}")
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
        isRecording = false
        currentFile = null
        pendingNextFile = null

        if (outputFile != null && outputFile.exists() && outputFile.length() > 1024L) {
            deliverChunk(
                ChunkMeta(
                    sessionId = sessionId,
                    appPackage = appPackage,
                    appName = appName,
                    chunkIndex = idx,
                    startTimeMs = startedAt,
                    endTimeMs = endedAt,
                    durationMs = (endedAt - startedAt).coerceAtLeast(0L),
                ),
                outputFile,
            )
        } else {
            outputFile?.delete()
        }
    }

    private fun releaseRecorderOnly() {
        cancelWatchdog()
        try {
            if (isTrackRunning) {
                mediaRecorder?.stop()
            }
        } catch (_: Exception) {
        } finally {
            isTrackRunning = false
            try {
                mediaRecorder?.reset()
            } catch (_: Exception) {
            }
            mediaRecorder?.release()
            mediaRecorder = null
        }
        virtualDisplay?.release()
        virtualDisplay = null
        isRecording = false
    }

    private fun scheduleWatchdog() {
        if (!isRecording || !shouldContinue) return
        gaplessRotateRunnable?.let { mainHandler.removeCallbacks(it) }
        val runnable =
            Runnable {
                if (!isRecording || !shouldContinue) return@Runnable
                val elapsed = System.currentTimeMillis() - chunkStartedAtMs
                if (elapsed >= CHUNK_DURATION_MS - 500L) {
                    onChunkRotated()
                }
                if (isRecording && shouldContinue) scheduleWatchdog()
            }
        gaplessRotateRunnable = runnable
        mainHandler.postDelayed(runnable, CHUNK_DURATION_MS)
    }

    private fun cancelWatchdog() {
        gaplessRotateRunnable?.let { mainHandler.removeCallbacks(it) }
        gaplessRotateRunnable = null
    }

    private fun createTempChunkFile(): File {
        val dir = File(context.cacheDir, "screen_chunks_temp").apply { mkdirs() }
        return File(dir, "chunk_${System.currentTimeMillis()}.mp4").apply {
            runCatching { createNewFile() }
        }
    }

    private fun scaledCaptureSize(): Triple<Int, Int, Int> {
        val metrics = context.resources.displayMetrics
        val width = (metrics.widthPixels / 2).coerceIn(360, 720)
        val height = (metrics.heightPixels / 2).coerceIn(640, 1280)
        return Triple(width, height, metrics.densityDpi)
    }

    private fun buildMediaRecorder(): MediaRecorder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }

    companion object {
        private const val CHUNK_DURATION_MS = 30_000L
    }
}
