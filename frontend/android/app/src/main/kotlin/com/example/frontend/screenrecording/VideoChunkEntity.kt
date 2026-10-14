package com.example.frontend.screenrecording

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Room entity for seamless 30s screen capture chunks.
 * Table: video_chunks_analysis (dedicated Room database).
 */
@Entity(tableName = "video_chunks_analysis")
data class VideoChunkEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0L,
    val userId: String,
    val appPackage: String,
    val appName: String,
    val chunkIndex: Int,
    val sessionId: String,
    val startTimeMs: Long,
    val endTimeMs: Long,
    val durationMs: Long,
    val videoData: ByteArray?,
    val filePath: String?,
    val createdAt: Long,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as VideoChunkEntity
        if (id != other.id) return false
        if (videoData != null) {
            if (other.videoData == null) return false
            if (!videoData.contentEquals(other.videoData)) return false
        } else if (other.videoData != null) {
            return false
        }
        return true
    }

    override fun hashCode(): Int {
        var result = id.hashCode()
        result = 31 * result + (videoData?.contentHashCode() ?: 0)
        return result
    }
}
