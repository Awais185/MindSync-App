package com.example.frontend

import android.content.Context
import android.content.Intent
import android.widget.Toast

/**
 * Unified app-block enforcement: explicit per-app blocks + social limit lock.
 * Independent from DNS VPN filtering.
 */
object BlockEnforcementHelper {
    private const val TOAST_COOLDOWN_MS = 3_000L
    private var lastToastMs = 0L

    /** Packages that should be sent home when foreground. */
    fun packagesToBlock(context: Context): Set<String> {
        if (!TrackerPrefs.parentalEnforcementEnabled(context)) return emptySet()
        val out = HashSet<String>()
        out.addAll(TrackerPrefs.effectiveBlockedPackages(context))
        if (TrackerPrefs.isSocialLimitLockActive(context)) {
            out.addAll(MonitoredAppsCache.getPackages(context))
        }
        return out
    }

    fun isPackageBlocked(context: Context, packageName: String?): Boolean {
        val pkg = packageName?.trim().orEmpty()
        if (pkg.isBlank() || pkg == context.packageName) return false
        if (ForegroundAppResolver.isIgnorableForeground(pkg)) return false
        val blocked = packagesToBlock(context)
        if (blocked.isEmpty()) return false
        return BlockedPackageMatcher.isBlocked(pkg, blocked)
    }

    /** Send user home when [packageName] is blocked. Returns true if blocked. */
    fun enforceIfBlocked(context: Context, packageName: String?): Boolean {
        if (!isPackageBlocked(context, packageName)) return false
        val pkg = packageName?.trim().orEmpty()
        redirectToHome(context, pkg)
        MonitoringLog.i("App blocked — sent home: $pkg")
        maybeShowBlockedToast(context)
        return true
    }

    /** No debounce — fires every time a blocked package is detected. */
    fun redirectToHome(context: Context, packageName: String) {
        try {
            val intent = Intent(context, BlockedAppOverlayActivity::class.java).apply {
                putExtra(BlockedAppOverlayActivity.EXTRA_BLOCKED_PACKAGE, packageName)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            context.startActivity(intent)
        } catch (_: Exception) {
            // Fallback to sending home
            try {
                MindSyncAccessibilityBridge.sendHome()
            } catch (_: Exception) {
            }
            try {
                val intent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(intent)
            } catch (_: Exception) {
            }
        }
    }

    private fun maybeShowBlockedToast(context: Context) {
        val now = System.currentTimeMillis()
        if (now - lastToastMs < TOAST_COOLDOWN_MS) return
        lastToastMs = now
        val msg =
            if (TrackerPrefs.isSocialLimitLockActive(context)) {
                "Daily social media limit reached. Apps unlock when the limit resets."
            } else {
                "This app is blocked by parental controls."
            }
        Toast.makeText(context.applicationContext, msg, Toast.LENGTH_SHORT).show()
    }
}
