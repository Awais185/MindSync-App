package com.example.frontend

import android.content.Context
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.Looper

/**
 * Singleton MediaProjection holder — acquire once per service lifetime, reuse across chunks.
 */
object MediaProjectionHolder {
    private var projection: MediaProjection? = null
    private var registeredCallback: MediaProjection.Callback? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun acquire(
        context: Context,
        onStopped: () -> Unit,
    ): MediaProjection? {
        projection?.let { return it }
        if (!ScreenCapturePermissionStore.hasPermission(context)) return null
        val grant = ScreenCapturePermissionStore.peekGrant(context) ?: return null
        val mgr =
            context.applicationContext.getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                as MediaProjectionManager
        val created =
            try {
                mgr.getMediaProjection(grant.first, grant.second)
            } catch (_: SecurityException) {
                null
            } catch (_: Exception) {
                null
            } ?: return null

        val callback =
            object : MediaProjection.Callback() {
                override fun onStop() {
                    MonitoringLog.w("MediaProjection stopped by system — will re-acquire from saved grant")
                    releaseCallbackOnly()
                    onStopped()
                }
            }
        registeredCallback = callback
        created.registerCallback(callback, mainHandler)
        projection = created
        return created
    }

    fun current(): MediaProjection? = projection

    /** Drop live projection only — keep saved user consent on disk. */
    fun releaseCallbackOnly() {
        val cb = registeredCallback
        try {
            if (cb != null) projection?.unregisterCallback(cb)
        } catch (_: Exception) {
        }
        try {
            projection?.stop()
        } catch (_: Exception) {
        }
        projection = null
        registeredCallback = null
    }

    fun releaseAll() {
        releaseCallbackOnly()
    }
}
