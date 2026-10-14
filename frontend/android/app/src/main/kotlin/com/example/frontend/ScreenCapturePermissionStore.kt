package com.example.frontend

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Parcel
import android.util.Base64
/**
 * Persists MediaProjection consent across app restarts (one-time user grant).
 * Uses Parcel bytes — [Intent.toUri] often fails for projection tokens.
 */
object ScreenCapturePermissionStore {
    private const val PREFS = "mindsync_screen_capture_grant"
    private const val KEY_RESULT_CODE = "result_code"
    private const val KEY_DATA_URI = "data_uri"
    private const val KEY_INTENT_BLOB = "intent_blob"
    private const val KEY_USER_GRANTED = "user_granted_once"

    private var memoryResultCode: Int? = null
    private var memoryData: Intent? = null

    private fun prefs(ctx: Context): SharedPreferences =
        ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun syncFromDisk(context: Context) {
        if (memoryResultCode != null && memoryData != null) return
        val p = prefs(context)
        val code = p.getInt(KEY_RESULT_CODE, Int.MIN_VALUE)
        if (code == Int.MIN_VALUE) return

        val blob = p.getString(KEY_INTENT_BLOB, null)
        if (!blob.isNullOrBlank()) {
            try {
                val bytes = Base64.decode(blob, Base64.NO_WRAP)
                val parcel = Parcel.obtain()
                parcel.unmarshall(bytes, 0, bytes.size)
                parcel.setDataPosition(0)
                memoryData = Intent.CREATOR.createFromParcel(parcel)
                parcel.recycle()
                memoryResultCode = code
                return
            } catch (_: Exception) {
                memoryData = null
                memoryResultCode = null
            }
        }

        val uri = p.getString(KEY_DATA_URI, null)
        if (!uri.isNullOrBlank()) {
            try {
                memoryData = Intent.parseUri(uri, Intent.URI_INTENT_SCHEME)
                memoryResultCode = code
            } catch (_: Exception) {
                clear(context)
            }
        }
    }

    fun save(context: Context, resultCode: Int, data: Intent?) {
        if (resultCode != Activity.RESULT_OK || data == null) {
            clear(context)
            return
        }
        memoryResultCode = resultCode
        memoryData = Intent(data)
        val editor =
            prefs(context).edit()
                .putInt(KEY_RESULT_CODE, resultCode)
                .putBoolean(KEY_USER_GRANTED, true)
        try {
            val parcel = Parcel.obtain()
            memoryData!!.writeToParcel(parcel, 0)
            val blob = Base64.encodeToString(parcel.marshall(), Base64.NO_WRAP)
            parcel.recycle()
            editor.putString(KEY_INTENT_BLOB, blob)
            try {
                editor.putString(KEY_DATA_URI, memoryData!!.toUri(Intent.URI_INTENT_SCHEME))
            } catch (_: Exception) {
                editor.remove(KEY_DATA_URI)
            }
            editor.apply()
            TrackerPrefs.markScreenCaptureOnboardingDone(context)
        } catch (_: Exception) {
            editor.clear().apply()
            memoryResultCode = null
            memoryData = null
        }
    }

    fun hasPermission(context: Context): Boolean {
        syncFromDisk(context)
        return memoryResultCode == Activity.RESULT_OK && memoryData != null
    }

    /** User completed the system screen-capture dialog at least once (token may need renewal). */
    fun userGrantedOnce(context: Context): Boolean {
        syncFromDisk(context)
        return prefs(context).getBoolean(KEY_USER_GRANTED, false)
    }

    /** Returns persisted consent without clearing it (safe to call repeatedly). */
    fun peekGrant(context: Context): Pair<Int, Intent>? {
        syncFromDisk(context)
        val code = memoryResultCode ?: return null
        val grantData = memoryData ?: return null
        if (code != Activity.RESULT_OK) return null
        return code to Intent(grantData)
    }

    fun clear(context: Context) {
        memoryResultCode = null
        memoryData = null
        prefs(context).edit().clear().apply()
    }

    /** Clears memory only — keeps disk grant (e.g. after projection service stopped). */
    fun invalidateMemoryGrant() {
        memoryResultCode = null
        memoryData = null
    }
}
