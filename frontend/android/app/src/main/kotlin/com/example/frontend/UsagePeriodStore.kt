package com.example.frontend

import android.content.Context
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/**
 * Per-user rolling daily / weekly / monthly totals (device cache).
 * Midnight: roll daily → weekly, reset daily.
 * Every 7 days: roll weekly → monthly, reset weekly.
 * Every 30 days: reset monthly.
 */
object UsagePeriodStore {
    private const val PREFS = "mindsync_usage_periods"
    private const val KEY_LAST_DAY = "last_day_key"
    private const val KEY_WEEK_ANCHOR = "week_anchor_day"
    private const val KEY_MONTH_ANCHOR = "month_anchor_day"
    private const val KEY_DAILY_MS = "daily_ms"
    private const val KEY_WEEKLY_MS = "weekly_ms"
    private const val KEY_MONTHLY_MS = "monthly_ms"

    private fun prefs(context: Context, userId: String) =
        context.getSharedPreferences("$PREFS.$userId", Context.MODE_PRIVATE)

    private fun dayKey(cal: Calendar = Calendar.getInstance()): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(cal.time)

    /** Monday of the calendar week containing [cal]. */
    private fun weekStartKey(cal: Calendar = Calendar.getInstance()): String {
        val c = cal.clone() as Calendar
        val delta = (c.get(Calendar.DAY_OF_WEEK) + 5) % 7
        c.add(Calendar.DAY_OF_YEAR, -delta)
        return dayKey(c)
    }

    private fun monthStartKey(cal: Calendar = Calendar.getInstance()): String {
        val c = cal.clone() as Calendar
        c.set(Calendar.DAY_OF_MONTH, 1)
        return dayKey(c)
    }

    fun onSessionStart(context: Context, userId: String) {
        if (userId.isBlank()) return
        val p = prefs(context, userId)
        val today = dayKey()
        val editor = p.edit()
        var daily = p.getLong(KEY_DAILY_MS, 0L)
        var weekly = p.getLong(KEY_WEEKLY_MS, 0L)
        var monthly = p.getLong(KEY_MONTHLY_MS, 0L)

        val lastDay = p.getString(KEY_LAST_DAY, "") ?: ""
        if (lastDay.isEmpty()) {
            editor
                .putString(KEY_LAST_DAY, today)
                .putString(KEY_WEEK_ANCHOR, today)
                .putString(KEY_MONTH_ANCHOR, today)
                .putLong(KEY_DAILY_MS, 0L)
                .putLong(KEY_WEEKLY_MS, 0L)
                .putLong(KEY_MONTHLY_MS, 0L)
                .apply()
            return
        }

        if (lastDay != today) {
            weekly += daily
            daily = 0L
            editor.putString(KEY_LAST_DAY, today)
        }

        val weekStart = weekStartKey()
        val weekAnchor = p.getString(KEY_WEEK_ANCHOR, weekStart) ?: weekStart
        if (weekAnchor != weekStart) {
            monthly += weekly
            weekly = 0L
            editor.putString(KEY_WEEK_ANCHOR, weekStart)
        }

        val monthStart = monthStartKey()
        val monthAnchor = p.getString(KEY_MONTH_ANCHOR, monthStart) ?: monthStart
        if (monthAnchor != monthStart) {
            monthly = 0L
            editor.putString(KEY_MONTH_ANCHOR, monthStart)
        }

        editor
            .putLong(KEY_DAILY_MS, daily)
            .putLong(KEY_WEEKLY_MS, weekly)
            .putLong(KEY_MONTHLY_MS, monthly)
            .apply()
    }

    fun addForegroundMs(context: Context, userId: String, deltaMs: Long) {
        if (userId.isBlank() || deltaMs <= 0L) return
        onSessionStart(context, userId)
        val p = prefs(context, userId)
        p.edit()
            .putLong(KEY_DAILY_MS, p.getLong(KEY_DAILY_MS, 0L) + deltaMs)
            .apply()
    }

    fun totalsSeconds(context: Context, userId: String): Triple<Int, Int, Int> {
        if (userId.isBlank()) return Triple(0, 0, 0)
        onSessionStart(context, userId)
        val p = prefs(context, userId)
        val daily = (p.getLong(KEY_DAILY_MS, 0L) / 1000L).toInt()
        val weekly = (p.getLong(KEY_WEEKLY_MS, 0L) / 1000L).toInt() + daily
        val monthly = (p.getLong(KEY_MONTHLY_MS, 0L) / 1000L).toInt() + weekly
        return Triple(daily, weekly, monthly)
    }

    fun resetUser(context: Context, userId: String) {
        if (userId.isBlank()) return
        val today = dayKey()
        prefs(context, userId).edit()
            .putString(KEY_LAST_DAY, today)
            .putString(KEY_WEEK_ANCHOR, today)
            .putString(KEY_MONTH_ANCHOR, today)
            .putLong(KEY_DAILY_MS, 0L)
            .putLong(KEY_WEEKLY_MS, 0L)
            .putLong(KEY_MONTHLY_MS, 0L)
            .apply()
    }

    private fun daysBetween(startDay: String, endDay: String): Int {
        return try {
            val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            val s = fmt.parse(startDay) ?: return 0
            val e = fmt.parse(endDay) ?: return 0
            ((e.time - s.time) / (24L * 3600 * 1000)).toInt().coerceAtLeast(0)
        } catch (_: Exception) {
            0
        }
    }
}
