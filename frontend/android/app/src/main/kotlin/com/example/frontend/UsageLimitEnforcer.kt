package com.example.frontend

import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat

/**
 * Enforces Parent Control → Usage Health social media daily limits using live
 * foreground tracking totals from [ScreenTimeLocalDatabase].
 */
object UsageLimitEnforcer {
    private const val NOTIFICATION_ID = 7305

    /** Called every ~1s from the monitoring loop while tracking is active. */
    fun onTrackingTick(context: Context) {
        val appCtx = context.applicationContext
        TrackerPrefs.clearUsageHealthSocialLimitIfExpired(appCtx)
        if (!TrackerPrefs.usageHealthSocialLimitActive(appCtx)) {
            if (TrackerPrefs.isSocialLimitLockActive(appCtx)) {
                TrackerPrefs.clearSocialLimitLock(appCtx)
                cancelLimitNotification(appCtx)
            }
            return
        }

        val limitMinutes = TrackerPrefs.usageHealthSocialLimitMinutes(appCtx)
        if (limitMinutes <= 0) return

        val usedSeconds = todayMonitoredSocialSeconds(appCtx)
        val limitSeconds = limitMinutes * 60
        if (usedSeconds >= limitSeconds && !TrackerPrefs.isSocialLimitLockActive(appCtx)) {
            TrackerPrefs.setSocialLimitLock(appCtx)
            UsageLimitExpiryWorker.schedule(appCtx)
            showLimitReachedNotification(appCtx)
            MonitoringLog.i(
                "Usage Health: limit reached (${usedSeconds}s / ${limitSeconds}s) — blocking social apps",
            )
            BackgroundUsageService.requestImmediateEnforcement(appCtx)
        }
    }

    fun onLimitExpired(context: Context) {
        val appCtx = context.applicationContext
        TrackerPrefs.clearSocialLimitLock(appCtx)
        TrackerPrefs.clearUsageHealthSocialLimit(appCtx)
        TrackerPrefs.markUsageHealthLimitExpired(appCtx)
        resetLimitUsageBaseline(appCtx)
        cancelLimitNotification(appCtx)
        MonitoringLog.i("Usage Health: 12h limit window expired — apps unrestricted")
        BackgroundUsageService.requestImmediateEnforcement(appCtx)
    }

    fun onLimitSaved(context: Context, setAtMs: Long) {
        UsageLimitExpiryWorker.schedule(context.applicationContext, setAtMs)
        TrackerPrefs.clearSocialLimitLock(context.applicationContext)
        cancelLimitNotification(context.applicationContext)
    }

    fun onLimitCleared(context: Context) {
        UsageLimitExpiryWorker.cancel(context.applicationContext)
        TrackerPrefs.clearSocialLimitLock(context.applicationContext)
        cancelLimitNotification(context.applicationContext)
    }

    fun todayMonitoredSocialSeconds(context: Context): Int {
        val uid = TrackerPrefs.userId(context).trim()
        if (uid.isBlank()) return 0
        val db = ScreenTimeLocalDatabase.getInstance(context)
        var total = 0
        for (pkg in MonitoredAppsCache.getPackages(context)) {
            total += db.getForegroundAppSeconds(uid, pkg)
        }
        return total
    }

    private fun resetLimitUsageBaseline(context: Context) {
        val uid = TrackerPrefs.userId(context).trim()
        if (uid.isBlank()) return
        val db = ScreenTimeLocalDatabase.getInstance(context)
        for (pkg in MonitoredAppsCache.getPackages(context)) {
            db.resetForegroundAppSeconds(uid, pkg)
        }
    }

    private fun showLimitReachedNotification(context: Context) {
        val setAt = TrackerPrefs.usageHealthSocialLimitSetAtMs(context)
        val resetAt = setAt + TrackerPrefs.USAGE_HEALTH_LIMIT_EXPIRY_MS
        val resetTime =
            java.text.SimpleDateFormat("h:mm a", java.util.Locale.getDefault())
                .format(java.util.Date(resetAt))
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notification =
            NotificationCompat.Builder(context, BackgroundUsageService.ALERTS_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle("Social media limit reached")
                .setContentText("Apps will be available again at $resetTime")
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .build()
        nm.notify(NOTIFICATION_ID, notification)
    }

    private fun cancelLimitNotification(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(NOTIFICATION_ID)
    }
}
