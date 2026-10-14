package com.example.frontend

import android.accessibilityservice.AccessibilityService

/**
 * Holds the live accessibility service so enforcement paths can call
 * [AccessibilityService.performGlobalAction] (GLOBAL_ACTION_HOME).
 */
object MindSyncAccessibilityBridge {
    @Volatile
    private var service: VideoPlaybackDetectorService? = null

    fun attach(svc: VideoPlaybackDetectorService) {
        service = svc
    }

    fun detach(svc: VideoPlaybackDetectorService) {
        if (service === svc) {
            service = null
        }
    }

    fun isAttached(): Boolean = service != null

    fun sendHome(): Boolean {
        val svc = service ?: return false
        return svc.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
    }
}
