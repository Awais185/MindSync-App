package com.example.frontend

/**
 * Fallback when Flutter has not yet pushed [TrackerPrefs] base URL.
 * Physical phone (USB): 127.0.0.1:8000 with `adb reverse tcp:8000 tcp:8000`.
 */
object NetworkConfig {
    const val DEV_BACKEND_PORT = 8000
    const val DEV_PHONE_BASE_URL = "http://127.0.0.1:$DEV_BACKEND_PORT"

    fun effectiveBaseUrl(stored: String): String {
        val t = stored.trim().trimEnd('/')
        if (t.isNotEmpty()) return t
        return DEV_PHONE_BASE_URL
    }
}
