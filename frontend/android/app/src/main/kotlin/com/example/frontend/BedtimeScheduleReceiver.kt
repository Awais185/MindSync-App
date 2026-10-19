package com.example.frontend

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Fires daily bedtime / wake-up OS notifications and reschedules the next alarm.
 */
class BedtimeScheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        val appCtx = context.applicationContext
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = appCtx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val alerts =
                NotificationChannel(
                    BackgroundUsageService.ALERTS_CHANNEL_ID,
                    "MindSync alerts",
                    NotificationManager.IMPORTANCE_HIGH,
                )
            manager.createNotificationChannel(alerts)
        }

        val isBedtime = action == BedtimeScheduleHelper.ACTION_BEDTIME
        val title = if (isBedtime) "Sleep time" else "Good morning"
        val body =
            if (isBedtime) {
                "Good Night your sleeping time has arrived, so please go to sleep."
            } else {
                "Good morning! Time to start your day."
            }

        val notification =
            NotificationCompat.Builder(appCtx, BackgroundUsageService.ALERTS_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .build()

        try {
            NotificationManagerCompat.from(appCtx).notify(
                if (isBedtime) NOTIF_BEDTIME else NOTIF_WAKEUP,
                notification,
            )
        } catch (_: SecurityException) {
            MonitoringLog.w("Bedtime notification blocked — POST_NOTIFICATIONS not granted")
        }

        ParentScheduleNotificationSync.post(appCtx, if (isBedtime) "bedtime" else "wakeup")
        BedtimeScheduleHelper.restoreFromPrefs(appCtx)
    }

    companion object {
        private const val NOTIF_BEDTIME = 8810
        private const val NOTIF_WAKEUP = 8811
    }
}
