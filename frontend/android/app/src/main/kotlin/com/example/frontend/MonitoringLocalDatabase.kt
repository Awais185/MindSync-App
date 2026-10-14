package com.example.frontend

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * On-device monitoring index (paths + metadata).
 * Table names match product spec: [video_chunks_analysis], [facial_expressions].
 */
class MonitoringLocalDatabase(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DB_NAME, null, DB_VERSION) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE $TABLE_VIDEO_CHUNKS (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                app_name TEXT NOT NULL,
                app_package_name TEXT NOT NULL DEFAULT '',
                chunk_index INTEGER NOT NULL,
                file_path TEXT NOT NULL,
                start_time TEXT NOT NULL,
                end_time TEXT NOT NULL,
                duration_seconds INTEGER NOT NULL DEFAULT 30,
                is_analyzed INTEGER NOT NULL DEFAULT 0,
                session_id TEXT NOT NULL DEFAULT '',
                file_size_bytes INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE $TABLE_FACIAL (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                app_name TEXT NOT NULL,
                file_path TEXT NOT NULL,
                recorded_at TEXT NOT NULL,
                duration_seconds INTEGER NOT NULL
            )
            """.trimIndent(),
        )
        db.execSQL(
            "CREATE INDEX idx_video_chunks_created ON $TABLE_VIDEO_CHUNKS(created_at)",
        )
        db.execSQL(
            "CREATE INDEX idx_facial_recorded ON $TABLE_FACIAL(recorded_at)",
        )
        db.execSQL(
            """
            CREATE TABLE $TABLE_UPLOAD_QUEUE (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL,
                file_path TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                attempts INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE $TABLE_APP_SESSIONS (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                app_name TEXT NOT NULL,
                start_time TEXT NOT NULL,
                end_time TEXT,
                duration_seconds INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent(),
        )
        db.execSQL(
            "CREATE INDEX idx_app_sessions_start ON $TABLE_APP_SESSIONS(start_time)",
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            onCreate(db)
        }
        if (oldVersion < 3) {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS $TABLE_UPLOAD_QUEUE (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    kind TEXT NOT NULL,
                    file_path TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    attempts INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL
                )
                """.trimIndent(),
            )
        }
        if (oldVersion < 4) {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS $TABLE_APP_SESSIONS (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    app_name TEXT NOT NULL,
                    start_time TEXT NOT NULL,
                    end_time TEXT,
                    duration_seconds INTEGER NOT NULL DEFAULT 0
                )
                """.trimIndent(),
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS idx_app_sessions_start ON $TABLE_APP_SESSIONS(start_time)",
            )
        }
        if (oldVersion < 5) {
            runCatching {
                db.execSQL(
                    "ALTER TABLE $TABLE_VIDEO_CHUNKS ADD COLUMN app_package_name TEXT NOT NULL DEFAULT ''",
                )
            }
            runCatching {
                db.execSQL(
                    "ALTER TABLE $TABLE_VIDEO_CHUNKS ADD COLUMN duration_seconds INTEGER NOT NULL DEFAULT 30",
                )
            }
            runCatching {
                db.execSQL(
                    "ALTER TABLE $TABLE_VIDEO_CHUNKS ADD COLUMN is_analyzed INTEGER NOT NULL DEFAULT 0",
                )
            }
        }
        if (oldVersion < 6) {
            runCatching {
                db.execSQL(
                    "ALTER TABLE $TABLE_VIDEO_CHUNKS ADD COLUMN session_id TEXT NOT NULL DEFAULT ''",
                )
            }
        }
        if (oldVersion < 7) {
            runCatching {
                db.execSQL(
                    "ALTER TABLE $TABLE_VIDEO_CHUNKS ADD COLUMN file_size_bytes INTEGER NOT NULL DEFAULT 0",
                )
            }
        }
    }

    /** Ensure [TABLE_VIDEO_CHUNKS] exists before insert (service restart / partial migrations). */
    fun ensureVideoChunksTable() {
        val db = writableDatabase
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS $TABLE_VIDEO_CHUNKS (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                app_name TEXT NOT NULL,
                app_package_name TEXT NOT NULL DEFAULT '',
                chunk_index INTEGER NOT NULL,
                file_path TEXT NOT NULL,
                start_time TEXT NOT NULL,
                end_time TEXT NOT NULL,
                duration_seconds INTEGER NOT NULL DEFAULT 30,
                is_analyzed INTEGER NOT NULL DEFAULT 0,
                session_id TEXT NOT NULL DEFAULT '',
                file_size_bytes INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
            )
            """.trimIndent(),
        )
        runCatching {
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS idx_video_chunks_created ON $TABLE_VIDEO_CHUNKS(created_at)",
            )
        }
    }

    private var openAppSessionId: Long = -1L
    private var openAppSessionStartMs: Long = 0L

    fun openAppSession(appName: String) {
        if (appName.isBlank()) return
        closeOpenAppSession()
        val startMs = System.currentTimeMillis()
        openAppSessionStartMs = startMs
        val values =
            ContentValues().apply {
                put("app_name", appName)
                put("start_time", isoFromMs(startMs))
                put("end_time", null as String?)
                put("duration_seconds", 0)
            }
        openAppSessionId = writableDatabase.insert(TABLE_APP_SESSIONS, null, values)
    }

    fun closeOpenAppSession() {
        if (openAppSessionId <= 0L) return
        val endMs = System.currentTimeMillis()
        val startMs = if (openAppSessionStartMs > 0L) openAppSessionStartMs else endMs
        val duration = ((endMs - startMs) / 1000L).toInt().coerceAtLeast(0)
        val values =
            ContentValues().apply {
                put("end_time", isoFromMs(endMs))
                put("duration_seconds", duration)
            }
        writableDatabase.update(
            TABLE_APP_SESSIONS,
            values,
            "id = ?",
            arrayOf(openAppSessionId.toString()),
        )
        openAppSessionId = -1L
        openAppSessionStartMs = 0L
    }

    fun recoverOpenAppSessionOnRestart() {
        readableDatabase.query(
            TABLE_APP_SESSIONS,
            arrayOf("id"),
            "end_time IS NULL",
            null,
            null,
            null,
            "id DESC",
            "1",
        ).use { c ->
            if (c.moveToFirst()) {
                openAppSessionId = c.getLong(0)
            }
        }
    }

    fun insertVideoChunk(
        appName: String,
        packageName: String,
        chunkIndex: Int,
        filePath: String,
        startTimeMs: Long,
        endTimeMs: Long,
        durationSeconds: Int = 30,
        isAnalyzed: Boolean = false,
        sessionId: String = "",
        fileSizeBytes: Long = 0L,
    ): Long {
        ensureVideoChunksTable()
        val now = isoNow()
        val values =
            ContentValues().apply {
                put("app_name", appName)
                put("app_package_name", packageName)
                put("chunk_index", chunkIndex)
                put("file_path", filePath)
                put("start_time", isoFromMs(startTimeMs))
                put("end_time", isoFromMs(endTimeMs))
                put("duration_seconds", durationSeconds)
                put("is_analyzed", if (isAnalyzed) 1 else 0)
                put("session_id", sessionId)
                put("file_size_bytes", fileSizeBytes)
                put("created_at", now)
            }
        return writableDatabase.insert(TABLE_VIDEO_CHUNKS, null, values)
    }

    fun insertFacialExpression(
        appName: String,
        filePath: String,
        recordedAtMs: Long,
        durationSeconds: Int,
    ): Long {
        val values =
            ContentValues().apply {
                put("app_name", appName)
                put("file_path", filePath)
                put("recorded_at", isoFromMs(recordedAtMs))
                put("duration_seconds", durationSeconds)
            }
        return writableDatabase.insert(TABLE_FACIAL, null, values)
    }

    fun enqueueUpload(filePath: String, payloadJson: String) {
        val kind =
            runCatching {
                org.json.JSONObject(payloadJson).optString("kind", "screen")
            }.getOrDefault("screen")
        val values =
            ContentValues().apply {
                put("kind", kind)
                put("file_path", filePath)
                put("payload_json", payloadJson)
                put("attempts", 0)
                put("created_at", isoNow())
            }
        writableDatabase.insert(TABLE_UPLOAD_QUEUE, null, values)
    }

    fun listPendingUploads(limit: Int): List<PendingUploadRow> {
        val out = mutableListOf<PendingUploadRow>()
        readableDatabase.query(
            TABLE_UPLOAD_QUEUE,
            arrayOf("id", "kind", "file_path", "payload_json"),
            "attempts < ?",
            arrayOf("8"),
            null,
            null,
            "created_at ASC",
            limit.toString(),
        ).use { c ->
            while (c.moveToNext()) {
                out.add(
                    PendingUploadRow(
                        id = c.getLong(0),
                        kind = c.getString(1) ?: "screen",
                        filePath = c.getString(2) ?: "",
                        payloadJson = c.getString(3) ?: "{}",
                    ),
                )
            }
        }
        return out
    }

    fun deleteUpload(id: Long) {
        writableDatabase.delete(TABLE_UPLOAD_QUEUE, "id = ?", arrayOf(id.toString()))
    }

    fun markUploadAttempt(id: Long) {
        writableDatabase.execSQL(
            "UPDATE $TABLE_UPLOAD_QUEUE SET attempts = attempts + 1 WHERE id = ?",
            arrayOf(id),
        )
    }

    data class PendingUploadRow(
        val id: Long,
        val kind: String,
        val filePath: String,
        val payloadJson: String,
    )

    companion object {
        @Volatile
        private var instance: MonitoringLocalDatabase? = null

        fun getInstance(context: Context): MonitoringLocalDatabase {
            val app = context.applicationContext
            return instance ?: synchronized(this) {
                instance ?: MonitoringLocalDatabase(app).also { instance = it }
            }
        }

        fun <T> withDb(context: Context, block: (MonitoringLocalDatabase) -> T): T {
            return block(getInstance(context))
        }

        const val DB_NAME = "mindsync_monitoring.db"
        const val DB_VERSION = 7
        const val TABLE_UPLOAD_QUEUE = "upload_queue"
        const val TABLE_VIDEO_CHUNKS = "video_chunks_analysis"
        const val TABLE_FACIAL = "facial_expressions"
        const val TABLE_APP_SESSIONS = "app_sessions"

        private val isoFormat =
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }

        fun isoNow(): String = isoFromMs(System.currentTimeMillis())

        fun isoFromMs(ms: Long): String = isoFormat.format(Date(ms))
    }
}
