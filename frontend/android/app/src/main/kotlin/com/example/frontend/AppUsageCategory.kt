package com.example.frontend

import android.content.Context

/** Maps foreground packages to analytics categories for late-night activity. */
object AppUsageCategory {
    fun resolve(context: Context, packageName: String?): String {
        if (packageName.isNullOrBlank()) return "Other"
        val pkg = packageName.lowercase()
        if (TrackedSocialApps.isSocialPackage(context, packageName)) {
            return when {
                pkg.contains("youtube") ||
                    pkg.contains("tiktok") ||
                    pkg.contains("video") ||
                    pkg.contains("netflix") ||
                    pkg.contains("twitch") -> "Video"
                else -> "Social Media"
            }
        }
        return when {
            pkg.contains("game") -> "Gaming"
            pkg.contains("news") -> "News & Info"
            pkg.contains("health") || pkg.contains("fitness") -> "Health & Wellness"
            else -> "Other"
        }
    }
}
