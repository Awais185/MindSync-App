package com.example.frontend.screenrecording

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import com.example.frontend.MediaProjectionHolder
import com.example.frontend.MonitoringLog
import com.example.frontend.MonitoringPolicy
import com.example.frontend.MonitoringStorage
import com.example.frontend.MonitoringUploadQueue
import com.example.frontend.ScreenCapturePermissionStore
import com.example.frontend.ScreenChunkUploader
import com.example.frontend.TrackerPrefs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Dedicated foreground service for seamless 30s screen chunks → Room [VideoChunkEntity].
 * Does not use the camera / CameraX pipeline.
 */
class ScreenRecordingService : Service(), ChunkWriter.ChunkListener {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val serviceJob = SupervisorJob()
    private val mainScope = CoroutineScope(serviceJob + Dispatchers.Main.immediate)
    private val ioScope = CoroutineScope(serviceJob + Dispatchers.IO)

    private var chunkWriter: ChunkWriter? = null
    private var activePackage: String = ""
    private var activeAppName: String = ""

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        chunkWriter = ChunkWriter(applicationContext, mainHandler, this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val pkg = intent.getStringExtra(EXTRA_PACKAGE).orEmpty()
                val name = intent.getStringExtra(EXTRA_APP_NAME).orEmpty()
                if (pkg.isBlank()) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                startRecordingInternal(pkg, name)
            }
            ACTION_STOP -> stopRecordingInternal()
            ACTION_PROJECTION_GRANTED -> {
                if (activePackage.isNotBlank()) {
                    startRecordingInternal(activePackage, activeAppName)
                }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        chunkWriter?.release()
        chunkWriter = null
        serviceJob.cancel()
        super.onDestroy()
    }

    private fun startRecordingInternal(packageName: String, appName: String) {
        if (!TrackerPrefs.shouldAllowUsageCollection(this)) return
        if (!MonitoringPolicy.screenRecordingAllowed(this)) {
            MonitoringLog.w("ScreenRecordingService: paused — battery/power policy")
            return
        }
        if (!ScreenCapturePermissionStore.hasPermission(this)) {
            MonitoringLog.w("ScreenRecordingService: MediaProjection not granted")
            return
        }
        activePackage = packageName
        activeAppName = appName.ifBlank { packageName }
        promoteForeground()
        val projection =
            MediaProjectionHolder.acquire(this) {
                mainHandler.post {
                    if (activePackage.isNotBlank()) {
                        startRecordingInternal(activePackage, activeAppName)
                    }
                }
            }
        if (projection == null) {
            MonitoringLog.e("ScreenRecordingService: MediaProjection unavailable — open MindSync to renew screen capture")
            return
        }
        chunkWriter?.start(projection, packageName, activeAppName)
    }

    private fun stopRecordingInternal() {
        chunkWriter?.stop(uploadPartial = true)
        activePackage = ""
        activeAppName = ""
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_DETACH)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(false)
        }
        stopSelf()
    }

    private fun promoteForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MindSync")
            .setContentText("Screen activity is being recorded")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel =
            NotificationChannel(
                CHANNEL_ID,
                "Screen recording",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Continuous screen chunk capture for wellness monitoring"
                setShowBadge(false)
            }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    override fun onRecordingStarted(sessionId: String) {
        MonitoringLog.i("ScreenRecordingService: session started $sessionId | app:$activeAppName")
    }

    override fun onRecordingStopped() {
        MonitoringLog.i("ScreenRecordingService: pipeline stopped")
    }

    override fun onChunkReady(meta: ChunkWriter.ChunkMeta, tempFile: File) {
        val userId = TrackerPrefs.userId(applicationContext)
        ioScope.launch {
            persistChunkAsync(meta, tempFile, userId)
        }
    }

    override fun onError(message: String, recoverable: Boolean) {
        MonitoringLog.e("ScreenRecordingService: $message")
        if (recoverable && activePackage.isNotBlank()) {
            mainHandler.postDelayed(
                { startRecordingInternal(activePackage, activeAppName) },
                1_500L,
            )
        }
    }

    private suspend fun persistChunkAsync(
        meta: ChunkWriter.ChunkMeta,
        tempFile: File,
        userId: String,
    ) {
        val ts =
            SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(meta.endTimeMs))
        try {
            if (!tempFile.exists() || tempFile.length() <= 0L) {
                MonitoringLog.e(
                    "❌ DB save failed — File exists on disk but not saved | Path: ${tempFile.absolutePath} | Error: empty file",
                )
                tempFile.delete()
                return
            }
            val bytes = tempFile.readBytes()
            val persisted =
                MonitoringStorage.persistScreenChunk(applicationContext, tempFile, meta.chunkIndex)
            tempFile.delete()
            val entity =
                VideoChunkEntity(
                    userId = userId,
                    appPackage = meta.appPackage,
                    appName = meta.appName,
                    chunkIndex = meta.chunkIndex,
                    sessionId = meta.sessionId,
                    startTimeMs = meta.startTimeMs,
                    endTimeMs = meta.endTimeMs,
                    durationMs = meta.durationMs.coerceAtLeast(CHUNK_DURATION_MS - 500L),
                    videoData = bytes,
                    filePath = persisted.absolutePath,
                    createdAt = System.currentTimeMillis(),
                )
            val db = VideoChunkDatabase.getInstance(applicationContext)
            val rowId = db.videoChunkDao().insertChunk(entity)
            val sizeMb = String.format(Locale.US, "%.1f", bytes.size / (1024.0 * 1024.0))
            MonitoringLog.i(
                "✅ Video chunk saved to DB — App: ${meta.appName} | Size: ${sizeMb}MB | Time: $ts | row:$rowId | chunk:${meta.chunkIndex}",
            )
            uploadChunkAsync(meta, persisted)
        } catch (e: Exception) {
            MonitoringLog.e(
                "❌ DB save failed — File exists on disk but not saved | Path: ${tempFile.absolutePath} | Error: ${e.message}",
                e,
            )
            tempFile.delete()
        }
    }

    private fun uploadChunkAsync(meta: ChunkWriter.ChunkMeta, file: File) {
        ioScope.launch {
            try {
                val durationSec = (meta.durationMs / 1000L).toInt().coerceIn(1, 120)
                val uploaded =
                    ScreenChunkUploader.upload(
                        context = applicationContext,
                        file = file,
                        platform = meta.appName,
                        packageName = meta.appPackage,
                        chunkIndex = meta.chunkIndex,
                        durationSeconds = durationSec,
                        startTimeMs = meta.startTimeMs,
                        endTimeMs = meta.endTimeMs,
                    )
                if (!uploaded) {
                    MonitoringUploadQueue.enqueueScreenChunk(
                        applicationContext,
                        file.absolutePath,
                        meta.appName,
                        meta.appPackage,
                        meta.chunkIndex,
                        durationSec,
                        meta.startTimeMs,
                        meta.endTimeMs,
                    )
                }
                MonitoringUploadQueue.processPending(applicationContext, maxItems = 2)
            } catch (e: Exception) {
                MonitoringLog.e("ScreenRecordingService: upload failed — ${e.message}")
            }
        }
    }

    companion object {
        const val ACTION_START = "com.example.frontend.screenrecording.START"
        const val ACTION_STOP = "com.example.frontend.screenrecording.STOP"
        const val ACTION_PROJECTION_GRANTED = "com.example.frontend.screenrecording.PROJECTION_GRANTED"
        const val EXTRA_PACKAGE = "package_name"
        const val EXTRA_APP_NAME = "app_name"
        private const val CHANNEL_ID = "mindsync_screen_recording"
        private const val NOTIFICATION_ID = 7310
        private const val CHUNK_DURATION_MS = 30_000L

        fun start(context: Context, packageName: String, appName: String) {
            val intent =
                Intent(context, ScreenRecordingService::class.java).apply {
                    action = ACTION_START
                    putExtra(EXTRA_PACKAGE, packageName)
                    putExtra(EXTRA_APP_NAME, appName)
                }
            context.applicationContext.startForegroundService(intent)
        }

        fun stop(context: Context) {
            val intent =
                Intent(context, ScreenRecordingService::class.java).apply {
                    action = ACTION_STOP
                }
            context.applicationContext.startService(intent)
        }

        fun onProjectionGranted(context: Context) {
            val intent =
                Intent(context, ScreenRecordingService::class.java).apply {
                    action = ACTION_PROJECTION_GRANTED
                }
            context.applicationContext.startForegroundService(intent)
        }
    }
}
