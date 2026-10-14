package com.example.frontend.screenrecording

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [VideoChunkEntity::class],
    version = 1,
    exportSchema = false,
)
abstract class VideoChunkDatabase : RoomDatabase() {
    abstract fun videoChunkDao(): VideoChunkDao

    companion object {
        private const val DB_NAME = "mindsync_video_chunks.db"

        @Volatile
        private var instance: VideoChunkDatabase? = null

        fun getInstance(context: Context): VideoChunkDatabase {
            val app = context.applicationContext
            return instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    app,
                    VideoChunkDatabase::class.java,
                    DB_NAME,
                )
                    .fallbackToDestructiveMigration()
                    .build()
                    .also { instance = it }
            }
        }
    }
}
