package com.example.frontend

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Handler
import android.os.HandlerThread

/**
 * Polls [UsageStatsManager] on a dedicated background thread so monitoring / recording
 * never blocks on slow binder calls (IUsageStatsManager).
 */
object ForegroundPackageResolver {
    private val workerThread = HandlerThread("mindsync-usage-stats").apply { start() }
    private val workerHandler = Handler(workerThread.looper)

    @Volatile
    var lastPackage: String? = null
        private set

    private var appContext: Context? = null
    private var polling = false

    private val pollRunnable =
        object : Runnable {
            override fun run() {
                val ctx = appContext ?: return
                if (!polling) return
                try {
                    lastPackage = queryForegroundPackage(ctx)
                } catch (e: Exception) {
                    MonitoringLog.w("Foreground package query failed: ${e.message}")
                }
                workerHandler.postDelayed(this, POLL_INTERVAL_MS)
            }
        }

    fun start(context: Context) {
        appContext = context.applicationContext
        polling = true
        workerHandler.removeCallbacks(pollRunnable)
        workerHandler.post(pollRunnable)
    }

    fun stop() {
        polling = false
        workerHandler.removeCallbacks(pollRunnable)
    }

    /** One-shot refresh (still off main thread). */
    fun refreshAsync(onResult: ((String?) -> Unit)? = null) {
        val ctx = appContext
        if (ctx == null) {
            onResult?.invoke(lastPackage)
            return
        }
        workerHandler.post {
            val pkg =
                try {
                    queryForegroundPackage(ctx)
                } catch (_: Exception) {
                    lastPackage
                }
            lastPackage = pkg
            onResult?.invoke(pkg)
        }
    }

    private fun queryForegroundPackage(context: Context): String? {
        val manager =
            context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val fromEvents = foregroundPackageFromUsageEvents(manager, now - 120_000, now)
        if (!fromEvents.isNullOrBlank()) return fromEvents
        val stats =
            manager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                now - 120_000,
                now,
            )
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

    private const val POLL_INTERVAL_MS = 1_000L
}
