package com.example.frontend

import android.content.Context
import java.io.File

/** Durable local paths for monitoring videos (survive cache clears). */
object MonitoringStorage {
    private const val ROOT = "mindsync_monitoring"

    fun screenChunksDir(context: Context): File =
        File(context.filesDir, "$ROOT/screen_chunks").apply { mkdirs() }

    fun faceClipsDir(context: Context): File =
        File(context.filesDir, "$ROOT/face_clips").apply { mkdirs() }

    fun persistScreenChunk(context: Context, tempFile: File, chunkIndex: Int): File {
        val dest =
            File(
                screenChunksDir(context),
                "screen_${System.currentTimeMillis()}_$chunkIndex.mp4",
            )
        tempFile.copyTo(dest, overwrite = true)
        return dest
    }

    fun persistFaceClip(context: Context, tempFile: File): File {
        val dest = File(faceClipsDir(context), "face_${System.currentTimeMillis()}.mp4")
        tempFile.copyTo(dest, overwrite = true)
        return dest
    }

    /** Delete local monitoring videos older than [maxAgeMs] (default 12h). */
    fun purgeVideosOlderThan(context: Context, maxAgeMs: Long) {
        val cutoff = System.currentTimeMillis() - maxAgeMs
        for (dir in listOf(screenChunksDir(context), faceClipsDir(context))) {
            dir.listFiles()?.forEach { file ->
                if (file.isFile && file.lastModified() < cutoff) {
                    runCatching { file.delete() }
                }
            }
        }
    }

    const val DEFAULT_RETENTION_MS = 12L * 60L * 60L * 1000L
}
