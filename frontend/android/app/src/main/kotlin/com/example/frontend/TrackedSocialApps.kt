package com.example.frontend

import android.content.Context

/**
 * Target social apps for app-triggered screen + face monitoring.
 * Runtime list from [MonitoredAppsCache] (backend); [defaultPackages] is offline fallback.
 */
object TrackedSocialApps {
    const val TELEGRAM = "org.telegram.messenger"

    const val YOUTUBE = "com.google.android.youtube"
    const val INSTAGRAM = "com.instagram.android"
    const val FACEBOOK = "com.facebook.katana"
    const val SNAPCHAT = "com.snapchat.android"
    const val TWITTER = "com.twitter.android"
    const val TWITTER_ALT = "com.x.android"
    const val WHATSAPP = "com.whatsapp"
    const val WHATSAPP_BUSINESS = "com.whatsapp.w4b"
    const val TIKTOK_A = "com.zhiliaoapp.musically"
    const val TIKTOK_B = "com.ss.android.ugc.trill"
    const val TIKTOK_LITE = "com.zhiliaoapp.musically.go"

    val tikTokPackages = setOf(TIKTOK_A, TIKTOK_B, TIKTOK_LITE)

    val whatsAppPackages = setOf(WHATSAPP, WHATSAPP_BUSINESS)

    /** Offline fallback when backend list is not cached yet. */
    val defaultPackages: Set<String> =
        setOf(
            YOUTUBE,
            INSTAGRAM,
            FACEBOOK,
            SNAPCHAT,
            TWITTER,
            TWITTER_ALT,
            WHATSAPP,
            WHATSAPP_BUSINESS,
            TIKTOK_A,
            TIKTOK_B,
            TIKTOK_LITE,
            TELEGRAM,
        )

    /** @deprecated Use [isSocialPackage] with Context */
    val socialPackages: Set<String>
        get() = defaultPackages

    fun isSocialPackage(context: Context, packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) return false
        return MonitoredAppsCache.isMonitored(context, packageName)
    }

    fun isSocialPackage(packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) return false
        return defaultPackages.contains(packageName)
    }

    fun isTikTok(packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) return false
        return tikTokPackages.contains(packageName)
    }

    /**
     * Social apps restricted when Usage Health daily limit is exceeded.
     * WhatsApp stays accessible per product rules.
     */
    fun usageHealthLimitPackages(context: Context): Set<String> {
        return MonitoredAppsCache.getPackages(context)
            .filter { pkg -> !whatsAppPackages.contains(pkg) }
            .toSet()
    }
}
