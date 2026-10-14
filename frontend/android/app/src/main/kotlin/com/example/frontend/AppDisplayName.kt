package com.example.frontend

import android.content.Context
import android.content.pm.PackageManager

/**
 * Resolves a short, user-visible app title. Handles OEM labels that look like
 * package or component names, and maps well-known packages to familiar names.
 */
object AppDisplayName {

    private val canonical: Map<String, String> = mapOf(
        "com.google.android.apps.youtube.music" to "YouTube Music",
        "com.google.android.googlequicksearchbox" to "Google",
        "com.google.android.apps.searchlite" to "Google",
        "com.android.chrome" to "Chrome",
        "com.chrome.beta" to "Chrome Beta",
        "com.chrome.dev" to "Chrome Dev",
        "com.google.android.gm" to "Gmail",
        "com.google.android.apps.maps" to "Maps",
        "com.google.android.apps.messaging" to "Messages",
        "com.google.android.apps.photos" to "Photos",
        "com.google.android.apps.docs" to "Drive",
        "com.android.vending" to "Play Store",
        "com.whatsapp" to "WhatsApp",
        "com.whatsapp.w4b" to "WhatsApp Business",
        "org.telegram.messenger" to "Telegram",
        "com.instagram.android" to "Instagram",
        "com.facebook.katana" to "Facebook",
        "com.google.android.youtube" to "YouTube",
        "com.zhiliaoapp.musically" to "TikTok",
        "com.ss.android.ugc.trill" to "TikTok",
        "com.snapchat.android" to "Snapchat",
        "com.twitter.android" to "X",
        "com.x.android" to "X",
        "com.reddit.frontpage" to "Reddit",
    )

    fun resolve(context: Context, packageName: String): String {
        canonical[packageName]?.let { return it }
        return try {
            val pm = context.packageManager
            val info = pm.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            val raw = pm.getApplicationLabel(info).toString().trim()
            if (looksTechnical(raw, packageName)) {
                titleFromPackage(packageName)
            } else {
                raw
            }
        } catch (_: Exception) {
            titleFromPackage(packageName)
        }
    }

    private fun looksTechnical(label: String, packageName: String): Boolean {
        if (label.isEmpty()) return true
        if (label == packageName) return true
        val low = label.lowercase()
        if ("activity" in low || "service" in low || "application" in low) return true
        if (label.startsWith("com.") || label.startsWith("org.") || label.startsWith("net.")) {
            if (label.count { it == '.' } >= 2) return true
        }
        if (label.length > 96) return true
        return false
    }

    private fun titleFromPackage(packageName: String): String {
        val base = packageName.substringAfterLast('.').replace('_', ' ').trim()
        if (base.isEmpty()) return packageName
        return base.split("-").joinToString(" ") { part ->
            part.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
        }
    }
}
