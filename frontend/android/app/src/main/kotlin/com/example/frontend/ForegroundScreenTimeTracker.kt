package com.example.frontend

import android.content.Context

/**
 * Real-time foreground screen time: 1s ticks, per-app + total, persisted every 5s.
 * Scoped strictly by [TrackerPrefs.userId] — never mixes users.
 */
object ForegroundScreenTimeTracker {
    private val dbHolder = object {
        fun get(context: Context) = ScreenTimeLocalDatabase.getInstance(context)
    }

    private var activeUserId: String? = null
    private var currentPackage: String? = null
    private var currentAppName: String = ""
    private var lastTickMs: Long = 0L
    private var lastPersistMs: Long = 0L

    fun onUserSessionStarted(context: Context, userId: String) {
        if (userId.isBlank()) return
        activeUserId = userId
        currentPackage = null
        currentAppName = ""
        lastTickMs = 0L
        lastPersistMs = System.currentTimeMillis()
        val db = dbHolder.get(context)
        db.ensureUser(userId)
        db.checkMidnightReset(userId)
        LateNightSleepTracker.onUserSessionStarted(context, userId)
    }

    fun onUserSessionEnded(context: Context) {
        flushSegment(context)
        val userId = activeUserId
        if (!userId.isNullOrBlank()) {
            LateNightSleepTracker.onUserSessionEnded(context)
        }
        activeUserId = null
        currentPackage = null
        currentAppName = ""
        lastTickMs = 0L
    }

    fun onForegroundTick(context: Context, foregroundPackage: String?) {
        val userId = TrackerPrefs.userId(context).trim()
        if (userId.isBlank()) return
        if (activeUserId != userId) {
            onUserSessionStarted(context, userId)
        }

        val db = dbHolder.get(context)
        db.checkMidnightReset(userId)

        val fg =
            foregroundPackage?.takeIf {
                it.isNotBlank() && it != context.packageName
            }

        if (fg != currentPackage) {
            flushSegment(context)
            currentPackage = fg
            currentAppName = fg?.let { AppDisplayName.resolve(context, it) } ?: ""
            lastTickMs = if (fg != null) System.currentTimeMillis() else 0L
            if (fg != null) {
                db.recoverCrashGap(userId, fg, currentAppName)
            }
        }

        if (fg == null) {
            db.touchActive(userId)
            return
        }

        val now = System.currentTimeMillis()
        if (lastTickMs > 0L) {
            val deltaSec = ((now - lastTickMs) / 1000L).toInt().coerceIn(1, 5)
            db.addForegroundSeconds(userId, fg, currentAppName, deltaSec)
        }
        lastTickMs = now
        db.touchActive(userId)

        val sessionSec = db.getForegroundAppSeconds(userId, fg)
        val totalSec = db.getTodayTotalSeconds(userId)
        MonitoringLog.i(
            "TRACKING: $currentAppName | session:${sessionSec}s | total:${totalSec}s",
        )

        if (now - lastPersistMs >= 5_000L) {
            lastPersistMs = now
            db.ensureTotalsReconciled(userId)
        }
    }

    fun buildSnapshot(context: Context, userId: String): Map<String, Any> {
        if (userId.isBlank()) {
            return mapOf(
                "daySeconds" to 0,
                "weekSeconds" to 0,
                "monthSeconds" to 0,
                "topApps" to emptyList<Map<String, Any>>(),
                "weekBarSeconds" to List(7) { 0 },
            )
        }
        val db = dbHolder.get(context)
        db.checkMidnightReset(userId)
        val today = db.getTodayTotalSeconds(userId)
        val weekArchived = db.getWeekArchivedSeconds(userId)
        val monthArchived = db.getMonthArchivedSeconds(userId)
        val weekTotal = weekArchived + today
        val monthTotal = monthArchived + today
        val weekBars = db.getWeekBarSecondsByWeekday(userId)
        val top = db.getTopAppsToday(userId).map { row ->
            val pkg = row["packageName"] as String
            mapOf(
                "packageName" to pkg,
                "appName" to (row["appName"] as String),
                "durationSeconds" to (row["durationSeconds"] as Int),
                "iconPngBase64" to iconOrEmpty(context, pkg),
            )
        }
        return mapOf(
            "daySeconds" to today,
            "weekSeconds" to weekTotal,
            "monthSeconds" to monthTotal,
            "topApps" to top,
            "weekBarSeconds" to weekBars,
        )
    }

    fun foregroundTodaySeconds(context: Context, userId: String, packageName: String): Int {
        if (userId.isBlank() || packageName.isBlank()) return 0
        return dbHolder.get(context).getForegroundAppSeconds(userId, packageName)
    }

    fun checkMidnightReset(context: Context, userId: String): Map<String, Any?> {
        if (userId.isBlank()) return emptyMap()
        return dbHolder.get(context).checkMidnightReset(userId)
    }

    private fun flushSegment(context: Context) {
        lastTickMs = 0L
        val userId = activeUserId ?: TrackerPrefs.userId(context).trim()
        if (userId.isNotBlank()) {
            dbHolder.get(context).touchActive(userId)
        }
    }

    private fun iconOrEmpty(context: Context, packageName: String): String =
        AppIconCache.iconPngBase64(context, packageName)
}
