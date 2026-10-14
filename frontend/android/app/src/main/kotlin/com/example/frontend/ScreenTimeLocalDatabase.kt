package com.example.frontend

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Per-user foreground screen time (integer seconds).
 * Tables: [live_session], [daily_records], [live_meta].
 */
class ScreenTimeLocalDatabase(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DB_NAME, null, DB_VERSION) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE $TABLE_LIVE_META (
                user_id TEXT PRIMARY KEY NOT NULL,
                total_seconds INTEGER NOT NULL DEFAULT 0,
                last_reset_date TEXT NOT NULL,
                last_active_ms INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE $TABLE_LIVE_SESSION (
                user_id TEXT NOT NULL,
                app_name TEXT NOT NULL,
                package_name TEXT NOT NULL,
                session_seconds INTEGER NOT NULL DEFAULT 0,
                last_updated INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (user_id, package_name)
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE $TABLE_DAILY (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL,
                date TEXT NOT NULL,
                total_seconds INTEGER NOT NULL DEFAULT 0,
                app_breakdown TEXT NOT NULL DEFAULT '{}',
                created_at TEXT NOT NULL,
                UNIQUE(user_id, date)
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE $TABLE_SLEEP_NIGHT (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL,
                night_date TEXT NOT NULL,
                late_night_activity_minutes INTEGER NOT NULL DEFAULT 0,
                late_night_app_categories TEXT NOT NULL DEFAULT '{}',
                sleep_time_minutes INTEGER NOT NULL DEFAULT 0,
                updated_at TEXT NOT NULL,
                UNIQUE(user_id, night_date)
            )
            """.trimIndent(),
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            onCreate(db)
        }
        if (oldVersion < 3) {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS $TABLE_SLEEP_NIGHT (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id TEXT NOT NULL,
                    night_date TEXT NOT NULL,
                    late_night_activity_minutes INTEGER NOT NULL DEFAULT 0,
                    late_night_app_categories TEXT NOT NULL DEFAULT '{}',
                    sleep_time_minutes INTEGER NOT NULL DEFAULT 0,
                    updated_at TEXT NOT NULL,
                    UNIQUE(user_id, night_date)
                )
                """.trimIndent(),
            )
        }
    }

    fun resetUser(userId: String) {
        if (userId.isBlank()) return
        val db = writableDatabase
        db.delete(TABLE_LIVE_SESSION, "user_id = ?", arrayOf(userId))
        db.delete(TABLE_DAILY, "user_id = ?", arrayOf(userId))
        db.delete(TABLE_SLEEP_NIGHT, "user_id = ?", arrayOf(userId))
        db.delete(TABLE_LIVE_META, "user_id = ?", arrayOf(userId))
    }

    fun ensureUser(userId: String) {
        val today = todayIso()
        val db = writableDatabase
        val exists =
            db.rawQuery(
                "SELECT 1 FROM $TABLE_LIVE_META WHERE user_id = ? LIMIT 1",
                arrayOf(userId),
            ).use { it.moveToFirst() }
        if (!exists) {
            db.insert(
                TABLE_LIVE_META,
                null,
                ContentValues().apply {
                    put("user_id", userId)
                    put("total_seconds", 0)
                    put("last_reset_date", today)
                    put("last_active_ms", System.currentTimeMillis())
                },
            )
        }
    }

    fun checkMidnightReset(userId: String): Map<String, Any?> {
        if (userId.isBlank()) return emptyMap()
        ensureUser(userId)
        val db = writableDatabase
        val today = todayIso()
        val row =
            db.rawQuery(
                "SELECT total_seconds, last_reset_date FROM $TABLE_LIVE_META WHERE user_id = ?",
                arrayOf(userId),
            ).use { c ->
                if (!c.moveToFirst()) return@use null
                c.getInt(0) to c.getString(1)
            } ?: return emptyMap()

        val (totalSeconds, lastDate) = row
        if (lastDate == today) return emptyMap()

        val breakdown = readAppBreakdownJson(db, userId)
        db.insert(
            TABLE_DAILY,
            null,
            ContentValues().apply {
                put("user_id", userId)
                put("date", lastDate)
                put("total_seconds", totalSeconds)
                put("app_breakdown", breakdown)
                put("created_at", isoNow())
            },
        )

        db.delete(TABLE_LIVE_SESSION, "user_id = ?", arrayOf(userId))
        db.update(
            TABLE_LIVE_META,
            ContentValues().apply {
                put("total_seconds", 0)
                put("last_reset_date", today)
                put("last_active_ms", System.currentTimeMillis())
            },
            "user_id = ?",
            arrayOf(userId),
        )

        return mapOf(
            "total_ms" to (totalSeconds.toLong() * 1000L),
            "date" to lastDate,
        )
    }

    fun addForegroundSeconds(userId: String, packageName: String, appName: String, seconds: Int) {
        if (userId.isBlank() || packageName.isBlank() || seconds <= 0) return
        ensureUser(userId)
        checkMidnightReset(userId)
        val db = writableDatabase
        val now = System.currentTimeMillis()

        val cur =
            db.rawQuery(
                "SELECT session_seconds FROM $TABLE_LIVE_SESSION WHERE user_id = ? AND package_name = ?",
                arrayOf(userId, packageName),
            ).use { c ->
                if (c.moveToFirst()) c.getInt(0) else 0
            }

        val values =
            ContentValues().apply {
                put("user_id", userId)
                put("app_name", appName)
                put("package_name", packageName)
                put("session_seconds", cur + seconds)
                put("last_updated", now)
            }
        db.insertWithOnConflict(
            TABLE_LIVE_SESSION,
            null,
            values,
            SQLiteDatabase.CONFLICT_REPLACE,
        )

        db.execSQL(
            "UPDATE $TABLE_LIVE_META SET total_seconds = total_seconds + ?, last_active_ms = ? WHERE user_id = ?",
            arrayOf(seconds, now, userId),
        )
        reconcileTotals(userId)
    }

    fun touchActive(userId: String) {
        if (userId.isBlank()) return
        writableDatabase.update(
            TABLE_LIVE_META,
            ContentValues().apply { put("last_active_ms", System.currentTimeMillis()) },
            "user_id = ?",
            arrayOf(userId),
        )
    }

    fun recoverCrashGap(userId: String, packageName: String, appName: String, maxGapSeconds: Int = 1800) {
        if (userId.isBlank()) return
        val db = readableDatabase
        val lastActive =
            db.rawQuery(
                "SELECT last_active_ms FROM $TABLE_LIVE_META WHERE user_id = ?",
                arrayOf(userId),
            ).use { c ->
                if (c.moveToFirst()) c.getLong(0) else 0L
            }
        if (lastActive <= 0L) return
        val gapSec = ((System.currentTimeMillis() - lastActive) / 1000L).toInt()
        if (gapSec in 1..maxGapSeconds) {
            addForegroundSeconds(userId, packageName, appName, gapSec)
        }
    }

    fun getTodayTotalSeconds(userId: String): Int {
        if (userId.isBlank()) return 0
        checkMidnightReset(userId)
        reconcileTotals(userId)
        return readableDatabase.rawQuery(
            "SELECT total_seconds FROM $TABLE_LIVE_META WHERE user_id = ?",
            arrayOf(userId),
        ).use { c ->
            if (c.moveToFirst()) c.getInt(0) else 0
        }
    }

    fun getWeekArchivedSeconds(userId: String): Int {
        val (weekStart, weekEnd) = weekRangeIso(excludeToday = true)
        return sumDailyBetween(userId, weekStart, weekEnd)
    }

    fun getMonthArchivedSeconds(userId: String): Int {
        val (monthStart, monthEnd) = monthRangeIso(excludeToday = true)
        return sumDailyBetween(userId, monthStart, monthEnd)
    }

    fun getWeekBarSecondsByWeekday(userId: String): List<Int> {
        val cal = Calendar.getInstance()
        val today = todayIso()
        val out = IntArray(7)
        for (i in 6 downTo 0) {
            val dayCal = cal.clone() as Calendar
            dayCal.add(Calendar.DAY_OF_YEAR, -i)
            val day = dayFmt().format(dayCal.time)
            val sec =
                if (day == today) {
                    getTodayTotalSeconds(userId)
                } else {
                    dailyTotalForDate(userId, day)
                }
            val dow = (dayCal.get(Calendar.DAY_OF_WEEK) + 5) % 7
            out[dow] = sec
        }
        return out.toList()
    }

    fun getTopAppsToday(userId: String, limit: Int = 12): List<Map<String, Any>> {
        if (userId.isBlank()) return emptyList()
        val db = readableDatabase
        return db.rawQuery(
            """
            SELECT app_name, package_name, session_seconds
            FROM $TABLE_LIVE_SESSION
            WHERE user_id = ? AND session_seconds > 0
            ORDER BY session_seconds DESC
            LIMIT ?
            """.trimIndent(),
            arrayOf(userId, limit.toString()),
        ).use { c ->
            val list = mutableListOf<Map<String, Any>>()
            while (c.moveToNext()) {
                list.add(
                    mapOf(
                        "appName" to c.getString(0),
                        "packageName" to c.getString(1),
                        "durationSeconds" to c.getInt(2),
                    ),
                )
            }
            list
        }
    }

    fun getForegroundAppSeconds(userId: String, packageName: String): Int {
        if (userId.isBlank() || packageName.isBlank()) return 0
        return readableDatabase.rawQuery(
            "SELECT session_seconds FROM $TABLE_LIVE_SESSION WHERE user_id = ? AND package_name = ?",
            arrayOf(userId, packageName),
        ).use { c ->
            if (c.moveToFirst()) c.getInt(0) else 0
        }
    }

    fun resetForegroundAppSeconds(userId: String, packageName: String) {
        if (userId.isBlank() || packageName.isBlank()) return
        writableDatabase.execSQL(
            "UPDATE $TABLE_LIVE_SESSION SET session_seconds = 0, last_updated = ? WHERE user_id = ? AND package_name = ?",
            arrayOf(System.currentTimeMillis(), userId, packageName),
        )
    }

    private fun dailyTotalForDate(userId: String, date: String): Int {
        return readableDatabase.rawQuery(
            "SELECT total_seconds FROM $TABLE_DAILY WHERE user_id = ? AND date = ?",
            arrayOf(userId, date),
        ).use { c ->
            if (c.moveToFirst()) c.getInt(0) else 0
        }
    }

    private fun sumDailyBetween(userId: String, start: String, end: String): Int {
        return readableDatabase.rawQuery(
            """
            SELECT COALESCE(SUM(total_seconds), 0)
            FROM $TABLE_DAILY
            WHERE user_id = ? AND date >= ? AND date <= ?
            """.trimIndent(),
            arrayOf(userId, start, end),
        ).use { c ->
            if (c.moveToFirst()) c.getInt(0) else 0
        }
    }

    private fun readAppBreakdownJson(db: SQLiteDatabase, userId: String): String {
        val obj = JSONObject()
        db.rawQuery(
            "SELECT app_name, package_name, session_seconds FROM $TABLE_LIVE_SESSION WHERE user_id = ?",
            arrayOf(userId),
        ).use { c ->
            val apps = JSONArray()
            while (c.moveToNext()) {
                apps.put(
                    JSONObject()
                        .put("app_name", c.getString(0))
                        .put("package_name", c.getString(1))
                        .put("seconds", c.getInt(2)),
                )
            }
            obj.put("apps", apps)
        }
        return obj.toString()
    }

    /** Enforce total_seconds == sum(live_session.session_seconds). */
    private fun reconcileTotals(userId: String) {
        val db = writableDatabase
        val sum =
            db.rawQuery(
                "SELECT COALESCE(SUM(session_seconds), 0) FROM $TABLE_LIVE_SESSION WHERE user_id = ?",
                arrayOf(userId),
            ).use { c ->
                if (c.moveToFirst()) c.getInt(0) else 0
            }
        db.update(
            TABLE_LIVE_META,
            ContentValues().apply { put("total_seconds", sum) },
            "user_id = ?",
            arrayOf(userId),
        )
    }

    /** Public: periodic reconcile from foreground tracker (every ~5s). */
    fun ensureTotalsReconciled(userId: String) {
        if (userId.isBlank()) return
        reconcileTotals(userId)
    }

    /** Past calendar days saved at midnight (excludes today — use live_session for today). */
    fun getDailyHistory(userId: String, limit: Int): List<Map<String, Any>> {
        if (userId.isBlank() || limit <= 0) return emptyList()
        val out = mutableListOf<Map<String, Any>>()
        readableDatabase.rawQuery(
            """
            SELECT date, total_seconds, app_breakdown
            FROM $TABLE_DAILY
            WHERE user_id = ?
            ORDER BY date DESC
            LIMIT ?
            """.trimIndent(),
            arrayOf(userId, limit.toString()),
        ).use { c ->
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "date" to c.getString(0),
                        "totalSeconds" to c.getInt(1),
                        "appBreakdownJson" to (c.getString(2) ?: "{}"),
                    ),
                )
            }
        }
        return out
    }

    /** Sum per-app seconds from archived [daily_records] rows in [startDate, endDate] (inclusive). */
    fun sumAppSecondsFromDailyArchive(
        userId: String,
        startDate: String,
        endDate: String,
    ): Map<String, Int> {
        if (userId.isBlank()) return emptyMap()
        val merged = HashMap<String, Int>()
        readableDatabase.rawQuery(
            """
            SELECT app_breakdown FROM $TABLE_DAILY
            WHERE user_id = ? AND date >= ? AND date <= ?
            """.trimIndent(),
            arrayOf(userId, startDate, endDate),
        ).use { c ->
            while (c.moveToNext()) {
                val raw = c.getString(0) ?: continue
                try {
                    val root = JSONObject(raw)
                    val apps = root.optJSONArray("apps") ?: continue
                    for (i in 0 until apps.length()) {
                        val o = apps.optJSONObject(i) ?: continue
                        val name = o.optString("app_name", "").ifBlank { o.optString("package_name", "") }
                        val sec = o.optInt("seconds", 0)
                        if (name.isNotBlank() && sec > 0) {
                            merged[name] = (merged[name] ?: 0) + sec
                        }
                    }
                } catch (_: Exception) {
                }
            }
        }
        return merged
    }

    data class SleepNightRow(
        val nightDate: String,
        val activityMinutes: Int,
        val sleepMinutes: Int,
        val categoryMinutes: Map<String, Int>,
    )

    fun upsertSleepNightRecord(
        userId: String,
        nightDate: String,
        activityMinutes: Int,
        sleepMinutes: Int,
        categoryMinutes: Map<String, Int>,
    ) {
        if (userId.isBlank() || nightDate.isBlank()) return
        val categoriesJson = JSONObject()
        for ((cat, min) in categoryMinutes) {
            if (min > 0) categoriesJson.put(cat, min)
        }
        writableDatabase.insertWithOnConflict(
            TABLE_SLEEP_NIGHT,
            null,
            ContentValues().apply {
                put("user_id", userId)
                put("night_date", nightDate)
                put("late_night_activity_minutes", activityMinutes.coerceAtLeast(0))
                put("late_night_app_categories", categoriesJson.toString())
                put("sleep_time_minutes", sleepMinutes.coerceAtLeast(0))
                put("updated_at", isoNow())
            },
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    fun getSleepNightRecord(userId: String, nightDate: String): SleepNightRow? {
        if (userId.isBlank() || nightDate.isBlank()) return null
        return readableDatabase.rawQuery(
            """
            SELECT night_date, late_night_activity_minutes, sleep_time_minutes, late_night_app_categories
            FROM $TABLE_SLEEP_NIGHT
            WHERE user_id = ? AND night_date = ?
            LIMIT 1
            """.trimIndent(),
            arrayOf(userId, nightDate),
        ).use { c ->
            if (!c.moveToFirst()) return@use null
            parseSleepNightRow(c)
        }
    }

    fun getSleepNightHistory(userId: String, limit: Int): List<SleepNightRow> {
        if (userId.isBlank() || limit <= 0) return emptyList()
        val out = mutableListOf<SleepNightRow>()
        readableDatabase.rawQuery(
            """
            SELECT night_date, late_night_activity_minutes, sleep_time_minutes, late_night_app_categories
            FROM $TABLE_SLEEP_NIGHT
            WHERE user_id = ?
            ORDER BY night_date DESC
            LIMIT ?
            """.trimIndent(),
            arrayOf(userId, limit.toString()),
        ).use { c ->
            while (c.moveToNext()) {
                parseSleepNightRow(c)?.let { out.add(it) }
            }
        }
        return out
    }

    private fun parseSleepNightRow(c: android.database.Cursor): SleepNightRow? {
        val nightDate = c.getString(0) ?: return null
        val activity = c.getInt(1)
        val sleep = c.getInt(2)
        val catsRaw = c.getString(3) ?: "{}"
        val cats = HashMap<String, Int>()
        try {
            val obj = JSONObject(catsRaw)
            val keys = obj.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                val min = obj.optInt(key, 0)
                if (min > 0) cats[key] = min
            }
        } catch (_: Exception) {
        }
        return SleepNightRow(
            nightDate = nightDate,
            activityMinutes = activity,
            sleepMinutes = sleep,
            categoryMinutes = cats,
        )
    }

    private fun weekRangeIso(excludeToday: Boolean): Pair<String, String> {
        val cal = Calendar.getInstance()
        cal.firstDayOfWeek = Calendar.MONDAY
        cal.set(Calendar.DAY_OF_WEEK, Calendar.MONDAY)
        val start = dayFmt().format(cal.time)
        if (!excludeToday) {
            val endCal = cal.clone() as Calendar
            endCal.add(Calendar.DAY_OF_YEAR, 6)
            return start to dayFmt().format(endCal.time)
        }
        val yesterday = Calendar.getInstance()
        yesterday.add(Calendar.DAY_OF_YEAR, -1)
        val end = dayFmt().format(yesterday.time)
        return start to end
    }

    private fun monthRangeIso(excludeToday: Boolean): Pair<String, String> {
        val cal = Calendar.getInstance()
        cal.set(Calendar.DAY_OF_MONTH, 1)
        val start = dayFmt().format(cal.time)
        if (!excludeToday) {
            return start to todayIso()
        }
        val yesterday = Calendar.getInstance()
        yesterday.add(Calendar.DAY_OF_YEAR, -1)
        return start to dayFmt().format(yesterday.time)
    }

    companion object {
        @Volatile
        private var instance: ScreenTimeLocalDatabase? = null

        fun getInstance(context: Context): ScreenTimeLocalDatabase {
            val app = context.applicationContext
            return instance ?: synchronized(this) {
                instance ?: ScreenTimeLocalDatabase(app).also { instance = it }
            }
        }

        const val DB_NAME = "mindsync_screen_time.db"
        const val DB_VERSION = 3
        const val TABLE_LIVE_META = "live_meta"
        const val TABLE_LIVE_SESSION = "live_session"
        const val TABLE_DAILY = "daily_records"
        const val TABLE_SLEEP_NIGHT = "sleep_night_daily"

        private fun dayFmt(): SimpleDateFormat =
            SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
                timeZone = TimeZone.getDefault()
            }

        fun todayIso(): String = dayFmt().format(Date())

        fun isoNow(): String =
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }.format(Date())
    }
}
