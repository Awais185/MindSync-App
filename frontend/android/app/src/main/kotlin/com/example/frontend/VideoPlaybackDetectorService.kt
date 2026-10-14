package com.example.frontend

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.util.Log
import android.view.accessibility.AccessibilityEvent

/**
 * MindSync accessibility service:
 * - Blocks listed apps on every foreground/content event (no one-time latch)
 * - Signals [BackgroundUsageService] when a tracked video app opens
 */
class VideoPlaybackDetectorService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
        MindSyncAccessibilityBridge.attach(this)
        Log.i(TAG, "MindSync accessibility connected (app blocking + video detection)")
        if (TrackerPrefs.hasActiveAppBlockingRules(this)) {
            AppBlockerService.start(this)
        }
    }

    override fun onDestroy() {
        MindSyncAccessibilityBridge.detach(this)
        super.onDestroy()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        if (BlockEnforcementHelper.packagesToBlock(this).isNotEmpty()) {
            AppBlockerService.start(this)
        }
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val type = event.eventType
        if (
            type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            type != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
        ) {
            return
        }

        val pkg = event.packageName?.toString()?.trim().orEmpty()
        if (pkg.isBlank() || pkg == packageName) return
        if (ForegroundAppResolver.isIgnorableForeground(pkg)) return

        // Fresh prefs read on every event — never cache blocked list in the service.
        if (BlockEnforcementHelper.isPackageBlocked(this, pkg)) {
            redirectToHome()
            return
        }

        if (type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        if (pkg !in VIDEO_PACKAGES) return

        val intent =
            android.content.Intent(this, BackgroundUsageService::class.java).apply {
                action = BackgroundUsageService.ACTION_VIDEO_APP_FOREGROUND
                putExtra(BackgroundUsageService.EXTRA_VIDEO_PACKAGE, pkg)
            }
        try {
            BackgroundUsageService.deliverStartFromAccessibility(this, intent)
        } catch (e: Exception) {
            Log.w(TAG, "Could not signal video foreground: ${e.message}")
        }
    }

    override fun onInterrupt() {}

    /** Redirect to home on every blocked-app detection — no debounce or latch. */
    private fun redirectToHome() {
        try {
            performGlobalAction(GLOBAL_ACTION_HOME)
        } catch (_: Exception) {
        }
        try {
            val intent =
                Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
            startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "redirectToHome failed: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "MindSyncA11y"

        val VIDEO_PACKAGES: Set<String> =
            TrackedSocialApps.socialPackages +
                setOf(
                    "com.netflix.mediaclient",
                    "com.amazon.avod.thirdpartyclient",
                    "com.disney.disneyplus",
                    "in.startv.hotstar",
                )
    }
}
