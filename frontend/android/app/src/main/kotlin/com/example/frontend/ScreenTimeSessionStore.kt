package com.example.frontend

import android.content.Context
import android.os.PowerManager
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Per-user foreground screen-on session time for Flutter/RN parity:
 * accumulated ms for local calendar day + optional open segment while interactive.
 *
 * Midnight rollover exposes a one-shot pending payload for [POST /api/screentime/save-day/].
 */
object ScreenTimeSessionStore {
    private const val PREFS = "mindsync_screen_time_session_store"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun dayFmt(): SimpleDateFormat =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = TimeZone.getDefault()
        }

    private fun isInteractive(context: Context): Boolean {
        val pm = context.applicationContext.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isInteractive
    }

    private fun calendarDayIso(context: Context): String =
        dayFmt().format(Date())

    private fun accumKey(userId: String) = "accum_ms_$userId"

    private fun segKey(userId: String) = "seg_start_ms_$userId"

    private fun calDayKey(userId: String) = "cal_day_$userId"

    private fun pendingMsKey(userId: String) = "pending_midnight_ms_$userId"

    private fun pendingDateKey(userId: String) = "pending_midnight_date_$userId"

    fun activeUserId(context: Context): String? =
        prefs(context).getString("active_user_id", null)

    fun flushOpenSegment(context: Context, userId: String) {
        val p = prefs(context)
        val seg = p.getLong(segKey(userId), 0L)
        if (seg <= 0L) return
        val now = System.currentTimeMillis()
        val delta = (now - seg).coerceAtLeast(0L)
        val accum = p.getLong(accumKey(userId), 0L)
        p.edit()
            .putLong(accumKey(userId), accum + delta)
            .remove(segKey(userId))
            .apply()
    }

    /**
     * Rolls local calendar day if needed; moves yesterday total into pending_* keys (once).
     */
    fun rollCalendarIfNeeded(context: Context, userId: String) {
        if (userId.isBlank()) return
        val p = prefs(context)
        val today = calendarDayIso(context)
        val storedDay = p.getString(calDayKey(userId), null)
        if (storedDay.isNullOrBlank()) {
            p.edit().putString(calDayKey(userId), today).apply()
            return
        }
        if (storedDay == today) return

        flushOpenSegment(context, userId)
        val totalMs = p.getLong(accumKey(userId), 0L).coerceAtLeast(0L)
        p.edit()
            .putLong(pendingMsKey(userId), totalMs)
            .putString(pendingDateKey(userId), storedDay)
            .putString(calDayKey(userId), today)
            .putLong(accumKey(userId), 0L)
            .remove(segKey(userId))
            .apply()

        val active = p.getString("active_user_id", null)
        if (active == userId && isInteractive(context)) {
            p.edit().putLong(segKey(userId), System.currentTimeMillis()).apply()
        }
    }

    fun startSession(context: Context, userId: String) {
        if (userId.isBlank()) return
        val p = prefs(context)
        p.edit().putString("active_user_id", userId).apply()
        rollCalendarIfNeeded(context, userId)
        if (!isInteractive(context)) return
        flushOpenSegment(context, userId)
        p.edit().putLong(segKey(userId), System.currentTimeMillis()).apply()
    }

    fun endSession(context: Context, userId: String) {
        if (userId.isBlank()) return
        val p = prefs(context)
        flushOpenSegment(context, userId)
        val active = p.getString("active_user_id", null)
        if (active == userId) {
            p.edit().remove("active_user_id").apply()
        }
        p.edit().remove(segKey(userId)).apply()
    }

    fun onScreenOff(context: Context) {
        val uid = prefs(context).getString("active_user_id", null) ?: return
        flushOpenSegment(context, uid)
        prefs(context).edit().remove(segKey(uid)).apply()
    }

    fun onScreenOn(context: Context) {
        val p = prefs(context)
        val uid = p.getString("active_user_id", null) ?: return
        rollCalendarIfNeeded(context, uid)
        if (!isInteractive(context)) return
        flushOpenSegment(context, uid)
        p.edit().putLong(segKey(uid), System.currentTimeMillis()).apply()
    }

    fun getTodayMs(context: Context, userId: String): Long {
        if (userId.isBlank()) return 0L
        rollCalendarIfNeeded(context, userId)
        val p = prefs(context)
        var accum = p.getLong(accumKey(userId), 0L).coerceAtLeast(0L)
        val active = p.getString("active_user_id", null)
        if (active != userId) return accum
        val seg = p.getLong(segKey(userId), 0L)
        if (seg <= 0L || !isInteractive(context)) return accum
        val now = System.currentTimeMillis()
        accum += (now - seg).coerceAtLeast(0L)
        return accum.coerceAtLeast(0L)
    }

    /**
     * Consumes pending midnight save payload produced by [rollCalendarIfNeeded].
     */
    fun consumeMidnightPending(context: Context, userId: String): Map<String, Any?> {
        if (userId.isBlank()) return emptyMap()
        val p = prefs(context)
        val ms = p.getLong(pendingMsKey(userId), 0L)
        val date = p.getString(pendingDateKey(userId), null)
        if (ms <= 0L || date.isNullOrBlank()) return emptyMap()
        p.edit()
            .remove(pendingMsKey(userId))
            .remove(pendingDateKey(userId))
            .apply()
        return mapOf(
            "total_ms" to ms,
            "date" to date,
        )
    }

    fun checkMidnightReset(context: Context, userId: String): Map<String, Any?> {
        if (userId.isBlank()) return emptyMap()
        rollCalendarIfNeeded(context, userId)
        return consumeMidnightPending(context, userId)
    }
}
