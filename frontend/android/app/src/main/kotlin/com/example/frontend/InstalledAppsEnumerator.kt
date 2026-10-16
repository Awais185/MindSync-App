package com.example.frontend

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build

/**
 * Launchable, blockable apps for Parent → App Restrictions.
 * Excludes core OS packages; keeps priority consumer apps even when pre-installed.
 */
object InstalledAppsEnumerator {
    val priorityPackages: Set<String> = setOf(
        "com.google.android.youtube",
        "com.google.android.apps.youtube.music",
        "com.facebook.katana",
        "com.facebook.lite",
        "com.whatsapp",
        "com.whatsapp.w4b",
        "com.zhiliaoapp.musically",
        "com.ss.android.ugc.trill",
        "com.zhiliaoapp.musically.go",
        "com.instagram.android",
        "com.instagram.lite",
        "com.snapchat.android",
        "com.netflix.mediaclient",
        "com.android.vending",
        "com.twitter.android",
        "com.x.android",
    )

    private val blockedPrefixes = listOf(
        "com.android.",
        "com.google.android.gms",
        "com.google.android.gsf",
        "com.google.android.ext.",
        "com.google.android.onetimeinitializer",
        "com.google.android.configupdater",
        "com.google.android.partnersetup",
        "com.qualcomm.",
        "com.mediatek.",
        "com.miui.",
        "com.samsung.android.app.telephonyui",
    )

    private val gameHints = listOf(
        "game",
        "pubg",
        "freefire",
        "free.fire",
        "garena",
        "roblox",
        "minecraft",
        "supercell",
        "activision",
        "epicgames",
        "riotgames",
        "ea.game",
        "mojang",
        "king.candycrush",
        "callofduty",
        "fortnite",
        "bgmi",
        "dts.freefire",
    )

    fun enumerate(
        pm: PackageManager,
        selfPackage: String,
        iconForPackage: (String) -> String,
    ): List<Map<String, Any>> {
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val launchable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(launcherIntent, PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(launcherIntent, 0)
        }
        val launchablePackages = launchable
            .mapNotNull { it.activityInfo?.packageName?.trim() }
            .filter { it.isNotEmpty() && it != selfPackage }
            .toSet()

        val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
        val out = mutableListOf<Map<String, Any>>()
        val seen = HashSet<String>()

        for (app in apps) {
            val pkg = app.packageName?.trim() ?: continue
            if (pkg.isEmpty() || pkg == selfPackage || seen.contains(pkg)) continue
            if (!launchablePackages.contains(pkg)) continue
            if (!shouldInclude(app)) continue
            seen.add(pkg)
            val label = app.loadLabel(pm).toString().ifBlank { pkg }
            val isGame = isGameApp(app, pkg)
            out.add(
                mapOf(
                    "package_name" to pkg,
                    "app_label" to label,
                    "is_game" to isGame,
                    "is_priority" to priorityPackages.contains(pkg),
                    "icon_png_base64" to iconForPackage(pkg),
                ),
            )
        }
        return out
    }

    private fun shouldInclude(app: ApplicationInfo): Boolean {
        val pkg = app.packageName.lowercase()
        if (priorityPackages.contains(app.packageName)) return true
        val pureSystem =
            (app.flags and ApplicationInfo.FLAG_SYSTEM) != 0 &&
                (app.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0
        if (pureSystem) return false
        if (blockedPrefixes.any { pkg.startsWith(it) }) {
            if (pkg.contains("youtube") || pkg.contains("vending")) return true
            return false
        }
        return true
    }

    fun isGameApp(app: ApplicationInfo, packageName: String): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (app.category == ApplicationInfo.CATEGORY_GAME) return true
        }
        val v = packageName.lowercase()
        return gameHints.any { v.contains(it) }
    }
}
