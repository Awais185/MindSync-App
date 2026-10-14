package com.example.frontend

import android.content.Context
import java.util.concurrent.ConcurrentHashMap

/**
 * Loads category domain lists from assets and matches queries.
 */
object DnsBlocklist {
    private const val ASSET_SOCIAL = "dns/social_media_domains.txt"
    private const val ASSET_GAMING = "dns/gaming_domains.txt"
    private const val ASSET_ENTERTAINMENT = "dns/entertainment_domains.txt"

    private val cache = ConcurrentHashMap<String, Set<String>>()

    fun reload(context: Context) {
        cache.clear()
        cache["social"] = loadAsset(context, ASSET_SOCIAL)
        cache["gaming"] = loadAsset(context, ASSET_GAMING)
        cache["entertainment"] = loadAsset(context, ASSET_ENTERTAINMENT)
    }

    private fun ensureLoaded(context: Context) {
        if (cache.isEmpty()) reload(context)
    }

    private fun loadAsset(context: Context, path: String): Set<String> {
        val out = linkedSetOf<String>()
        try {
            context.assets.open(path).bufferedReader().useLines { lines ->
                lines.forEach { line ->
                    val trimmed = line.substringBefore('#').trim().lowercase()
                    if (trimmed.isNotEmpty()) out.add(trimmed)
                }
            }
        } catch (_: Exception) {
            // missing asset
        }
        return out
    }

    fun categoryDomainCount(context: Context, category: String): Int {
        ensureLoaded(context)
        return cache[category]?.size ?: 0
    }

    fun activeBlockedDomainCount(context: Context): Int {
        ensureLoaded(context)
        var total = 0
        if (DnsFilterPrefs.blockSocial(context)) total += cache["social"]?.size ?: 0
        if (DnsFilterPrefs.blockGaming(context)) total += cache["gaming"]?.size ?: 0
        if (DnsFilterPrefs.blockEntertainment(context)) total += cache["entertainment"]?.size ?: 0
        return total
    }

    fun isBlocked(context: Context, host: String): Boolean {
        ensureLoaded(context)
        val normalized = host.trim().trimEnd('.').lowercase()
        if (normalized.isEmpty()) return false

        val categories = mutableListOf<String>()
        if (DnsFilterPrefs.blockSocial(context)) categories.add("social")
        if (DnsFilterPrefs.blockGaming(context)) categories.add("gaming")
        if (DnsFilterPrefs.blockEntertainment(context)) categories.add("entertainment")

        for (category in categories) {
            val set = cache[category] ?: continue
            for (blocked in set) {
                if (matchesBlockedDomain(normalized, blocked)) {
                    return true
                }
            }
        }
        return false
    }

    private fun matchesBlockedDomain(host: String, blocked: String): Boolean {
        if (blocked.startsWith("*.")) {
            val suffix = blocked.removePrefix("*.").lowercase()
            return host == suffix || host.endsWith(".$suffix")
        }
        return host == blocked || host.endsWith(".$blocked")
    }
}
