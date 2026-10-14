package com.example.frontend

import android.content.ComponentCallbacks2
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.util.Base64
import android.util.LruCache
import java.io.ByteArrayOutputStream

/**
 * In-memory icon cache — avoids repeated PackageManager.getApplicationIcon (MIUI spam).
 * Uses small RGB_565 bitmaps and recycles intermediates to limit heap growth.
 */
object AppIconCache {
    private const val MAX_ENTRIES = 48
    private const val ICON_PX = 48
    private val cache = LruCache<String, String>(MAX_ENTRIES)

    @Volatile
    private var rollingUsageCachedAtMs: Long = 0L

    @Volatile
    private var rollingUsageSnapshot: List<Map<String, Any>>? = null

    private const val ROLLING_CACHE_TTL_MS = 5 * 60 * 1000L

    fun iconPngBase64(context: Context, packageName: String): String {
        if (packageName.isBlank()) return ""
        cache.get(packageName)?.let { return it }
        val encoded =
            try {
                val pm = context.applicationContext.packageManager
                if (!isPackageInstalled(pm, packageName)) return ""
                val drawable = pm.getApplicationIcon(packageName)
                val bmp = drawableToBitmap(drawable, ICON_PX)
                val stream = ByteArrayOutputStream(256)
                bmp.compress(Bitmap.CompressFormat.PNG, 80, stream)
                if (!bmp.isRecycled) {
                    bmp.recycle()
                }
                Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
            } catch (_: Exception) {
                ""
            }
        if (encoded.isNotEmpty()) {
            cache.put(packageName, encoded)
        }
        return encoded
    }

    fun onTrimMemory(level: Int) {
        if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) {
            cache.evictAll()
            rollingUsageSnapshot = null
            rollingUsageCachedAtMs = 0L
        }
    }

    fun invalidateRollingUsage() {
        rollingUsageSnapshot = null
        rollingUsageCachedAtMs = 0L
    }

    fun getRollingUsageIfFresh(): List<Map<String, Any>>? {
        val snapshot = rollingUsageSnapshot ?: return null
        val now = System.currentTimeMillis()
        if (now - rollingUsageCachedAtMs < ROLLING_CACHE_TTL_MS) {
            return snapshot
        }
        return null
    }

    fun putRollingUsage(entries: List<Map<String, Any>>) {
        rollingUsageSnapshot = entries
        rollingUsageCachedAtMs = System.currentTimeMillis()
    }

    private fun isPackageInstalled(
        pm: android.content.pm.PackageManager,
        packageName: String,
    ): Boolean =
        try {
            pm.getApplicationInfo(packageName, 0)
            true
        } catch (_: android.content.pm.PackageManager.NameNotFoundException) {
            false
        }

    private fun drawableToBitmap(drawable: Drawable, px: Int): Bitmap {
        if (drawable is BitmapDrawable) {
            val src = drawable.bitmap
            if (src != null && !src.isRecycled) {
                if (src.width == px && src.height == px) {
                    return src.copy(Bitmap.Config.RGB_565, false)
                }
                val scaled = Bitmap.createScaledBitmap(src, px, px, true)
                if (scaled !== src && !src.isRecycled) {
                    // Do not recycle src — owned by the system drawable.
                }
                return scaled
            }
        }
        val bmp = Bitmap.createBitmap(px, px, Bitmap.Config.RGB_565)
        val canvas = Canvas(bmp)
        drawable.setBounds(0, 0, px, px)
        drawable.draw(canvas)
        return bmp
    }
}
