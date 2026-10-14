package com.example.frontend

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * Fallback enforcement when the accessibility service is disabled: polls foreground app
 * (~500ms) and sends the user home when a blocked package is active.
 *
 * Primary blocking is [VideoPlaybackDetectorService] via GLOBAL_ACTION_HOME.
 */
class AppBlockerService : Service() {
    private val handler = Handler(Looper.getMainLooper())

    private val tickRunnable =
        object : Runnable {
            override fun run() {
                if (!TrackerPrefs.hasActiveAppBlockingRules(applicationContext)) {
                    stopSelf()
                    return
                }
                val blocked = BlockEnforcementHelper.packagesToBlock(applicationContext)
                if (blocked.isEmpty()) {
                    stopSelf()
                    return
                }
                val fg = currentForegroundPackage()
                BlockEnforcementHelper.enforceIfBlocked(applicationContext, fg)
                handler.postDelayed(this, TICK_MS)
            }
        }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForeground(NOTIFICATION_ID, notification)
        }
        handler.post(tickRunnable)
    }

    override fun onDestroy() {
        handler.removeCallbacks(tickRunnable)
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("MindSync")
            .setContentText("App blocking is active")
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        mgr.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "MindSync app blocker",
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    private fun currentForegroundPackage(): String? {
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val fromEvents = foregroundPackageFromUsageEvents(manager, now - 120_000L, now)
        if (!fromEvents.isNullOrBlank()) return fromEvents
        val stats = manager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, now - 120_000L, now)
        if (stats.isNullOrEmpty()) return null
        return stats.maxByOrNull { it.lastTimeUsed }?.packageName
    }

    private fun foregroundPackageFromUsageEvents(
        manager: UsageStatsManager,
        beginMs: Long,
        endMs: Long,
    ): String? {
        val events = manager.queryEvents(beginMs, endMs) ?: return null
        var lastPkg: String? = null
        var lastTs = -1L
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val foreground =
                when (event.eventType) {
                    UsageEvents.Event.MOVE_TO_FOREGROUND -> true
                    UsageEvents.Event.ACTIVITY_RESUMED -> true
                    else -> false
                }
            if (foreground && event.timeStamp >= lastTs) {
                lastTs = event.timeStamp
                lastPkg = event.packageName
            }
        }
        return lastPkg
    }

    private fun goHome() {
        if (MindSyncAccessibilityBridge.sendHome()) return
        try {
            val intent =
                Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
            startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "goHome failed: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "AppBlockerService"
        private const val CHANNEL_ID = "mindsync_app_blocker"
        private const val NOTIFICATION_ID = 7312
        private const val TICK_MS = 500L

        fun start(context: Context) {
            if (!TrackerPrefs.hasActiveAppBlockingRules(context.applicationContext)) return
            if (BlockEnforcementHelper.packagesToBlock(context.applicationContext).isEmpty()) return
            val intent = Intent(context, AppBlockerService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.w(TAG, "start failed: ${e.message}")
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, AppBlockerService::class.java))
        }
    }
}
