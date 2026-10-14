package com.example.frontend

import android.content.Context

/**
 * Resolves foreground packages for monitoring:
 * - [resolveTrackableForeground] — any user app (face capture, screen-time ticks)
 * - [resolveSocialForeground] — synced social targets only (screen recording)
 */
object ForegroundAppResolver {
    /** Packages that must never be treated as foreground targets for monitoring. */
    val systemExclusionPackages: Set<String> =
        setOf(
            "android",
            "com.miui.home",
            "com.android.launcher",
            "com.android.launcher3",
            "com.google.android.apps.nexuslauncher",
            "com.sec.android.app.launcher",
            "com.oneplus.launcher",
            "com.oppo.launcher",
            "com.huawei.android.launcher",
            "com.tcl.android.launcher",
            "com.motorola.launcher3",
            "com.nothing.launcher",
            "com.android.systemui",
            "com.miui.systemui",
            "com.samsung.android.app.launcher",
            "com.transsion.hilauncher",
            "com.bbk.launcher2",
        )

    fun isIgnorableForeground(packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) return true
        if (packageName == "android") return true
        val p = packageName.lowercase()
        if (p.contains("launcher")) return true
        if (systemExclusionPackages.contains(packageName)) return true
        if (p.startsWith("com.android.systemui")) return true
        if (p.contains("systemui")) return true
        return false
    }

    /**
     * Any non-launcher, non-system, non-self foreground app — used for 20s face clips
     * and per-app screen-time while the user is actively in an app.
     */
    fun resolveTrackableForeground(
        rawForeground: String?,
        selfPackage: String,
    ): String? {
        val raw = rawForeground?.trim().orEmpty()
        if (raw.isBlank() || raw == selfPackage) return null
        if (isIgnorableForeground(raw)) return null
        return raw
    }

    /**
     * Returns a monitored social package only when [rawForeground] is explicitly in the
     * synced target-app list. Launcher / system UI → null (user left the social app).
     */
    fun resolveSocialForeground(context: Context, rawForeground: String?, selfPackage: String): String? {
        val raw = rawForeground?.trim().orEmpty()
        if (raw.isBlank() || raw == selfPackage) return null
        if (isIgnorableForeground(raw)) return null
        if (TrackedSocialApps.isSocialPackage(context, raw)) return raw
        return null
    }

    /** Same as [resolveSocialForeground] — no sticky grace for launcher or non-target apps. */
    fun resolveRecordingForeground(
        context: Context,
        rawForeground: String?,
        selfPackage: String,
    ): String? = resolveSocialForeground(context, rawForeground, selfPackage)

    fun clearSocialSticky() {
        // Kept for callers after session end; sticky resolution removed.
    }
}
