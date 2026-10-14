package com.example.frontend

/**
 * Saved dev URLs — keep in sync with [MindSync/frontend/lib/config/api_config.dart].
 *
 * USB tether PC: 172.24.168.80:8000
 * Physical phone app: 127.0.0.1:8000 (adb reverse)
 */
object NetworkConfig {
    const val DEV_LAPTOP_HOST = "172.24.168.80"
    const val DEV_BACKEND_PORT = 8000
    const val DEV_LAN_BASE_URL = "http://$DEV_LAPTOP_HOST:$DEV_BACKEND_PORT"
    const val DEV_PHONE_BASE_URL = "http://127.0.0.1:$DEV_BACKEND_PORT"

    fun effectiveBaseUrl(stored: String): String {
        val t = stored.trim().trimEnd('/')
        if (t.isNotEmpty()) return t
        return DEV_PHONE_BASE_URL
    }
}
