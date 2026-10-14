package com.example.frontend

import android.content.Context
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Tracks late-night screen activity (22:00–05:00) and sleep (continuous screen-off in that window).
 *
 * - Screen ON during the window → late-night activity (+ per-category when a foreground app is known).
 * - Screen OFF during the window → sleep time.
 * - Activity at e.g. 00:30 counts as late-night activity, not sleep; sleep resumes after screen off.
 */
object LateNightSleepTracker {
    private const val PREFS = "mindsync_late_night_sleep"
    private const val KEY_USER = "user_id"
    private const val KEY_NIGHT_DATE = "night_date"
    private const val KEY_ACTIVITY_SEC = "activity_sec"
    private const val KEY_SLEEP_SEC = "sleep_sec"
    private const val KEY_CATEGORIES = "categories_json"
    private const val KEY_LAST_MS = "last_event_ms"
    private const val KEY_SCREEN_ON = "screen_on"

    private val lock = Any()

    fun onUserSessionStarted(context: Context, userId: String) {
        if (userId.isBlank()) return
        synchronized(lock) {
            val prefs = prefs(context)
            if (prefs.getString(KEY_USER, "") != userId) {
                flushLiveToDatabase(context, userId)
                prefs.edit().clear().apply()
                prefs.edit().putString(KEY_USER, userId).apply()
                initLiveState(context, userId, MonitoringPolicy.isScreenInteractive(context))
            }
        }
    }

    fun onUserSessionEnded(context: Context) {
        synchronized(lock) {
            val userId = prefs(context).getString(KEY_USER, "") ?: ""
            if (userId.isNotBlank()) {
                flushLiveToDatabase(context, userId)
            }
            prefs(context).edit().clear().apply()
        }
    }

    fun onScreenOn(context: Context) {
        tick(context, screenOn = true, foregroundPackage = null)
    }

    fun onScreenOff(context: Context) {
        tick(context, screenOn = false, foregroundPackage = null)
    }

    /** Called ~1 Hz while the tracker service is running. */
    fun tick(context: Context, screenOn: Boolean, foregroundPackage: String?) {
        val userId = TrackerPrefs.userId(context).trim()
        if (userId.isBlank() || !TrackerPrefs.shouldAllowUsageCollection(context)) return
        synchronized(lock) {
            ensureLiveSession(context, userId, screenOn)
            val now = System.currentTimeMillis()
            val prefs = prefs(context)
            val lastMs = prefs.getLong(KEY_LAST_MS, now)
            if (now > lastMs) {
                applyInterval(
                    context = context,
                    userId = userId,
                    fromMs = lastMs,
                    toMs = now,
                    screenOn = prefs.getBoolean(KEY_SCREEN_ON, screenOn),
                    foregroundPackage = foregroundPackage,
                )
            }
            prefs.edit()
                .putLong(KEY_LAST_MS, now)
                .putBoolean(KEY_SCREEN_ON, screenOn)
                .apply()
            maybeFlushToDatabase(context, userId, now)
        }
    }

    fun buildSnapshot(context: Context, userId: String): Map<String, Any> {
        if (userId.isBlank()) return emptySnapshot()
        synchronized(lock) {
            flushLiveToDatabase(context, userId)
        }
        val db = ScreenTimeLocalDatabase.getInstance(context.applicationContext)
        val now = System.currentTimeMillis()
        val displayNightDate = resolveDisplayNightDate(now)
        val live = readLiveRecord(context, userId, displayNightDate)
        val byDayActivity = IntArray(7)
        val byDaySleep = IntArray(7)
        val weekCategories = HashMap<String, Int>()

        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        val dayMs = 24L * 3600 * 1000
        val oldest = cal.apply { add(Calendar.DAY_OF_YEAR, -6) }.timeInMillis

        for (idx in 0 until 7) {
            val dayCal = Calendar.getInstance()
            dayCal.timeInMillis = oldest + idx * dayMs
            val nightDate = dayFmt().format(dayCal.time)
            val row =
                if (nightDate == displayNightDate && live != null) {
                    live
                } else {
                    db.getSleepNightRecord(userId, nightDate)?.let {
                        LiveNightRecord(
                            activityMinutes = it.activityMinutes,
                            sleepMinutes = it.sleepMinutes,
                            categoryMinutes = it.categoryMinutes,
                        )
                    }
                }
            byDayActivity[idx] = row?.activityMinutes ?: 0
            byDaySleep[idx] = row?.sleepMinutes ?: 0
            row?.categoryMinutes?.forEach { (cat, min) ->
                weekCategories.merge(cat, min, Int::plus)
            }
        }

        val tonightActivity =
            live?.activityMinutes
                ?: db.getSleepNightRecord(userId, displayNightDate ?: "")?.activityMinutes
                ?: 0
        val tonightSleep =
            live?.sleepMinutes
                ?: db.getSleepNightRecord(userId, displayNightDate ?: "")?.sleepMinutes
                ?: 0
        val tonightCategories =
            live?.categoryMinutes
                ?: db.getSleepNightRecord(userId, displayNightDate ?: "")?.categoryMinutes
                ?: emptyMap()

        return mapOf(
            "sleepTonightMinutes" to tonightSleep,
            "lateNightTonightMinutes" to tonightActivity,
            "lateNightCategoriesTonight" to tonightCategories,
            "sleepWeekMinutes" to byDaySleep.sum(),
            "lateNightWeekMinutes" to byDayActivity.sum(),
            "lateNightByDayMinutes" to byDayActivity.toList(),
            "sleepByDayMinutes" to byDaySleep.toList(),
            "lateNightCategoriesWeek" to weekCategories,
        )
    }

    fun getSleepNightArchive(context: Context, userId: String, limit: Int): List<Map<String, Any>> {
        if (userId.isBlank()) return emptyList()
        synchronized(lock) {
            flushLiveToDatabase(context, userId)
        }
        return ScreenTimeLocalDatabase.getInstance(context.applicationContext)
            .getSleepNightHistory(userId, limit)
            .map { row ->
                mapOf(
                    "nightDate" to row.nightDate,
                    "lateNightActivityMinutes" to row.activityMinutes,
                    "sleepTimeMinutes" to row.sleepMinutes,
                    "lateNightAppCategories" to row.categoryMinutes,
                )
            }
    }

    private data class LiveNightRecord(
        val activityMinutes: Int,
        val sleepMinutes: Int,
        val categoryMinutes: Map<String, Int>,
    )

    private fun emptySnapshot(): Map<String, Any> =
        mapOf(
            "sleepTonightMinutes" to 0,
            "lateNightTonightMinutes" to 0,
            "lateNightCategoriesTonight" to emptyMap<String, Int>(),
            "sleepWeekMinutes" to 0,
            "lateNightWeekMinutes" to 0,
            "lateNightByDayMinutes" to List(7) { 0 },
            "sleepByDayMinutes" to List(7) { 0 },
            "lateNightCategoriesWeek" to emptyMap<String, Int>(),
        )

    private fun ensureLiveSession(context: Context, userId: String, screenOn: Boolean) {
        val prefs = prefs(context)
        if (prefs.getString(KEY_USER, "") != userId) {
            prefs.edit().clear().putString(KEY_USER, userId).apply()
            initLiveState(context, userId, screenOn)
            return
        }
        if (!prefs.contains(KEY_LAST_MS)) {
            initLiveState(context, userId, screenOn)
        }
        val nightDate = nightDateKey(System.currentTimeMillis())
        val storedNight = prefs.getString(KEY_NIGHT_DATE, null)
        if (nightDate != null && storedNight != null && storedNight != nightDate) {
            flushLiveToDatabase(context, userId)
            initLiveState(context, userId, screenOn)
        } else if (nightDate == null && storedNight != null) {
            flushLiveToDatabase(context, userId)
            initLiveState(context, userId, screenOn)
        } else if (nightDate != null && storedNight == null) {
            prefs.edit().putString(KEY_NIGHT_DATE, nightDate).apply()
        }
    }

    private fun initLiveState(context: Context, userId: String, screenOn: Boolean) {
        val nightDate = nightDateKey(System.currentTimeMillis())
        prefs(context).edit()
            .putString(KEY_USER, userId)
            .putString(KEY_NIGHT_DATE, nightDate ?: "")
            .putInt(KEY_ACTIVITY_SEC, 0)
            .putInt(KEY_SLEEP_SEC, 0)
            .putString(KEY_CATEGORIES, "{}")
            .putLong(KEY_LAST_MS, System.currentTimeMillis())
            .putBoolean(KEY_SCREEN_ON, screenOn)
            .apply()
    }

    private fun applyInterval(
        context: Context,
        userId: String,
        fromMs: Long,
        toMs: Long,
        screenOn: Boolean,
        foregroundPackage: String?,
    ) {
        if (toMs <= fromMs) return
        var cursor = fromMs
        while (cursor < toMs) {
            val nextBoundary = nextSegmentBoundary(cursor, toMs)
            val mid = (cursor + nextBoundary) / 2L
            if (isInLateNightWindow(mid)) {
                val nightDate = nightDateKey(mid) ?: run {
                    cursor = nextBoundary
                    continue
                }
                ensureNightDate(context, nightDate)
                val seconds = ((nextBoundary - cursor) / 1000L).toInt().coerceAtLeast(0)
                if (seconds <= 0) {
                    cursor = nextBoundary
                    continue
                }
                val prefs = prefs(context)
                if (screenOn) {
                    val cur = prefs.getInt(KEY_ACTIVITY_SEC, 0)
                    prefs.edit().putInt(KEY_ACTIVITY_SEC, cur + seconds).apply()
                    if (!foregroundPackage.isNullOrBlank()) {
                        val category = AppUsageCategory.resolve(context, foregroundPackage)
                        val cats = readCategoriesJson(prefs.getString(KEY_CATEGORIES, "{}") ?: "{}")
                        cats.merge(category, seconds, Int::plus)
                        prefs.edit().putString(KEY_CATEGORIES, categoriesToJson(cats)).apply()
                    }
                } else {
                    val cur = prefs.getInt(KEY_SLEEP_SEC, 0)
                    prefs.edit().putInt(KEY_SLEEP_SEC, cur + seconds).apply()
                }
            }
            cursor = nextBoundary
        }
    }

    private fun ensureNightDate(context: Context, nightDate: String) {
        val prefs = prefs(context)
        val stored = prefs.getString(KEY_NIGHT_DATE, "") ?: ""
        if (stored != nightDate) {
            val userId = prefs.getString(KEY_USER, "") ?: ""
            if (userId.isNotBlank() && stored.isNotBlank()) {
                flushLiveToDatabase(context, userId)
            }
            prefs.edit()
                .putString(KEY_NIGHT_DATE, nightDate)
                .putInt(KEY_ACTIVITY_SEC, 0)
                .putInt(KEY_SLEEP_SEC, 0)
                .putString(KEY_CATEGORIES, "{}")
                .apply()
        }
    }

    /** Split at 05:00 and 22:00 local boundaries within (from, to]. */
    private fun nextSegmentBoundary(fromMs: Long, toMs: Long): Long {
        val candidates = mutableListOf(toMs)
        val cal = Calendar.getInstance()
        cal.timeInMillis = fromMs
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        repeat(3) {
            for (hour in intArrayOf(5, 22)) {
                val probe = cal.clone() as Calendar
                probe.set(Calendar.HOUR_OF_DAY, hour)
                probe.set(Calendar.MINUTE, 0)
                var boundary = probe.timeInMillis
                if (boundary <= fromMs) {
                    probe.add(Calendar.DAY_OF_YEAR, 1)
                    boundary = probe.timeInMillis
                }
                if (boundary in (fromMs + 1)..toMs) {
                    candidates.add(boundary)
                }
            }
            cal.add(Calendar.DAY_OF_YEAR, 1)
        }
        return candidates.minOrNull() ?: toMs
    }

    private fun isInLateNightWindow(ms: Long): Boolean {
        val cal = Calendar.getInstance()
        cal.timeInMillis = ms
        val hour = cal.get(Calendar.HOUR_OF_DAY)
        return hour >= 22 || hour < 5
    }

    /** Night anchor date: 22:00–23:59 → today; 00:00–04:59 → yesterday. */
    fun nightDateKey(ms: Long): String? {
        val cal = Calendar.getInstance()
        cal.timeInMillis = ms
        val hour = cal.get(Calendar.HOUR_OF_DAY)
        return when {
            hour >= 22 -> dayFmt().format(cal.time)
            hour < 5 -> {
                cal.add(Calendar.DAY_OF_YEAR, -1)
                dayFmt().format(cal.time)
            }
            else -> null
        }
    }

    private fun readLiveRecord(context: Context, userId: String, nightDate: String?): LiveNightRecord? {
        if (nightDate.isNullOrBlank()) return null
        val prefs = prefs(context)
        if (prefs.getString(KEY_USER, "") != userId) return null
        if (prefs.getString(KEY_NIGHT_DATE, "") != nightDate) return null
        val activitySec = prefs.getInt(KEY_ACTIVITY_SEC, 0)
        val sleepSec = prefs.getInt(KEY_SLEEP_SEC, 0)
        val cats = readCategoriesJson(prefs.getString(KEY_CATEGORIES, "{}") ?: "{}")
        return LiveNightRecord(
            activityMinutes = (activitySec + 59) / 60,
            sleepMinutes = (sleepSec + 59) / 60,
            categoryMinutes = cats.mapValues { (_, sec) -> (sec + 59) / 60 },
        )
    }

    private fun maybeFlushToDatabase(context: Context, userId: String, nowMs: Long) {
        val prefs = prefs(context)
        val lastFlush = prefs.getLong("last_flush_ms", 0L)
        if (nowMs - lastFlush >= 60_000L) {
            flushLiveToDatabase(context, userId)
            prefs.edit().putLong("last_flush_ms", nowMs).apply()
        }
    }

    private fun flushLiveToDatabase(context: Context, userId: String) {
        if (userId.isBlank()) return
        val prefs = prefs(context)
        if (prefs.getString(KEY_USER, "") != userId) return
        val nightDate = prefs.getString(KEY_NIGHT_DATE, "") ?: ""
        if (nightDate.isBlank()) return
        val activityMin = (prefs.getInt(KEY_ACTIVITY_SEC, 0) + 59) / 60
        val sleepMin = (prefs.getInt(KEY_SLEEP_SEC, 0) + 59) / 60
        val cats =
            readCategoriesJson(prefs.getString(KEY_CATEGORIES, "{}") ?: "{}")
                .mapValues { (_, sec) -> (sec + 59) / 60 }
        if (activityMin == 0 && sleepMin == 0 && cats.isEmpty()) return
        ScreenTimeLocalDatabase.getInstance(context.applicationContext).upsertSleepNightRecord(
            userId = userId,
            nightDate = nightDate,
            activityMinutes = activityMin,
            sleepMinutes = sleepMin,
            categoryMinutes = cats,
        )
    }

    private fun readCategoriesJson(raw: String): HashMap<String, Int> {
        val out = HashMap<String, Int>()
        try {
            val obj = JSONObject(raw)
            val keys = obj.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                val sec = obj.optInt(key, 0)
                if (sec > 0) out[key] = sec
            }
        } catch (_: Exception) {
        }
        return out
    }

    private fun categoriesToJson(cats: Map<String, Int>): String {
        val obj = JSONObject()
        for ((k, v) in cats) {
            if (v > 0) obj.put(k, v)
        }
        return obj.toString()
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Night anchor for UI: in-window uses live night; daytime shows last completed night. */
    private fun resolveDisplayNightDate(nowMs: Long): String? {
        nightDateKey(nowMs)?.let { return it }
        val cal = Calendar.getInstance()
        cal.timeInMillis = nowMs
        val hour = cal.get(Calendar.HOUR_OF_DAY)
        if (hour in 5 until 22) {
            cal.add(Calendar.DAY_OF_YEAR, -1)
            return dayFmt().format(cal.time)
        }
        return null
    }

    private fun dayFmt(): SimpleDateFormat =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = TimeZone.getDefault()
        }
}
