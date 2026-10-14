package com.example.frontend.screenrecording

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy

@Dao
interface VideoChunkDao {
    /** Blocking insert — called from [Dispatchers.IO] only (avoids KSP suspend/Long clash). */
    @Insert(onConflict = OnConflictStrategy.ABORT)
    fun insertChunk(chunk: VideoChunkEntity): Long
}
