package com.example.frontend

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar

/**
 * Daily bedtime / wake-up local notifications + in-app notification sync.
 */
object BedtimeScheduleHelper {
    const val ACTION_BEDTIME = "com.example.frontend.action.BEDTIME_ALARM"
    const val ACTION_WAKEUP = "com.example.frontend.action.WAKEUP_ALARM"
    private const val REQ_BEDTIME = 8801
    private const val REQ_WAKEUP = 8802

    fun schedule(
        context: Context,
        sleepHour: Int,
        sleepMinute: Int,
        wakeHour: Int,
        wakeMinute: Int,
    ) {
        val appCtx = context.applicationContext
        val prefs = appCtx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putInt(KEY_SLEEP_H, sleepHour)
            .putInt(KEY_SLEEP_M, sleepMinute)
            .putInt(KEY_WAKE_H, wakeHour)
            .putInt(KEY_WAKE_M, wakeMinute)
            .apply()

        scheduleDaily(appCtx, ACTION_BEDTIME, REQ_BEDTIME, sleepHour, sleepMinute)
        scheduleDaily(appCtx, ACTION_WAKEUP, REQ_WAKEUP, wakeHour, wakeMinute)
        MonitoringLog.i("Bedtime schedule set: sleep $sleepHour:$sleepMinute wake $wakeHour:$wakeMinute")
    }

    fun restoreFromPrefs(context: Context) {
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.contains(KEY_SLEEP_H)) return
        schedule(
            context,
            prefs.getInt(KEY_SLEEP_H, 22),
            prefs.getInt(KEY_SLEEP_M, 0),
            prefs.getInt(KEY_WAKE_H, 7),
            prefs.getInt(KEY_WAKE_M, 0),
        )
    }

    private fun scheduleDaily(
        context: Context,
        action: String,
        requestCode: Int,
        hour: Int,
        minute: Int,
    ) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent =
            Intent(context, BedtimeScheduleReceiver::class.java).apply {
                this.action = action
            }
        val pending =
            PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        val trigger = nextTriggerMillis(hour, minute)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    trigger,
                    pending,
                )
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, trigger, pending)
            }
        } catch (e: SecurityException) {
            alarmManager.set(AlarmManager.RTC_WAKEUP, trigger, pending)
            MonitoringLog.w("Bedtime alarm inexact (exact alarm permission missing): ${e.message}")
        }
    }

    private fun nextTriggerMillis(hour: Int, minute: Int): Long {
        val cal = Calendar.getInstance()
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        cal.set(Calendar.HOUR_OF_DAY, hour.coerceIn(0, 23))
        cal.set(Calendar.MINUTE, minute.coerceIn(0, 59))
        if (cal.timeInMillis <= System.currentTimeMillis()) {
            cal.add(Calendar.DAY_OF_YEAR, 1)
        }
        return cal.timeInMillis
    }

    private const val PREFS = "mindsync_bedtime_schedule"
    private const val KEY_SLEEP_H = "sleep_hour"
    private const val KEY_SLEEP_M = "sleep_minute"
    private const val KEY_WAKE_H = "wake_hour"
    private const val KEY_WAKE_M = "wake_minute"
}
