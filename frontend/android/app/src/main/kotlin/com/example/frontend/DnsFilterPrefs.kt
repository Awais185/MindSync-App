package com.example.frontend

import android.content.Context
import org.json.JSONArray

/**
 * Persisted DNS filter / parental content-restriction settings.
 */
object DnsFilterPrefs {
    private const val PREFS = "mindsync.dns_filter"
    private const val KEY_SOCIAL = "block_social"
    private const val KEY_GAMING = "block_gaming"
    private const val KEY_ENTERTAINMENT = "block_entertainment"
    private const val KEY_SAFE_SEARCH = "safe_search"
    private const val KEY_ADULT = "block_adult"
    private const val KEY_VPN_ACTIVE = "vpn_active"

    const val VPN_ADDRESS = "10.1.10.1"
    /** Standard Cloudflare — used when both Safe Search and Adult Block are OFF. */
    const val UPSTREAM_DNS_STANDARD = "1.1.1.1"
    const val UPSTREAM_DNS_STANDARD_ALT = "1.0.0.1"
    /** AdGuard Family DNS — Safe Search + adult filtering when either toggle is ON. */
    const val UPSTREAM_DNS_FAMILY = "94.140.14.15"
    const val UPSTREAM_DNS_FAMILY_ALT = "94.140.15.16"

    fun blockSocial(context: Context): Boolean =
        prefs(context).getBoolean(KEY_SOCIAL, false)

    fun blockGaming(context: Context): Boolean =
        prefs(context).getBoolean(KEY_GAMING, false)

    fun blockEntertainment(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ENTERTAINMENT, false)

    fun safeSearch(context: Context): Boolean =
        prefs(context).getBoolean(KEY_SAFE_SEARCH, false)

    fun blockAdult(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ADULT, false)

    fun setVpnActive(context: Context, active: Boolean) {
        prefs(context).edit().putBoolean(KEY_VPN_ACTIVE, active).apply()
    }

    fun vpnActive(context: Context): Boolean =
        prefs(context).getBoolean(KEY_VPN_ACTIVE, false)

    fun saveConfig(
        context: Context,
        blockSocial: Boolean,
        blockGaming: Boolean,
        blockEntertainment: Boolean,
        safeSearch: Boolean,
        blockAdult: Boolean,
    ) {
        prefs(context).edit()
            .putBoolean(KEY_SOCIAL, blockSocial)
            .putBoolean(KEY_GAMING, blockGaming)
            .putBoolean(KEY_ENTERTAINMENT, blockEntertainment)
            .putBoolean(KEY_SAFE_SEARCH, safeSearch)
            .putBoolean(KEY_ADULT, blockAdult)
            .apply()
    }

    fun needsVpn(context: Context): Boolean =
        blockSocial(context) ||
            blockGaming(context) ||
            blockEntertainment(context) ||
            safeSearch(context) ||
            blockAdult(context)

    /** AdGuard Family when either Safe Search or Adult Block is ON; else Cloudflare. */
    fun contentFilteringActive(context: Context): Boolean =
        safeSearch(context) || blockAdult(context)

    fun upstreamDns(context: Context): String =
        if (contentFilteringActive(context)) UPSTREAM_DNS_FAMILY else UPSTREAM_DNS_STANDARD

    fun upstreamDnsSecondary(context: Context): String =
        if (contentFilteringActive(context)) UPSTREAM_DNS_FAMILY_ALT else UPSTREAM_DNS_STANDARD_ALT

    fun filterStatusLabel(context: Context): String =
        if (contentFilteringActive(context)) {
            "Protected by AdGuard Family DNS"
        } else if (needsVpn(context)) {
            "Category DNS blocking active"
        } else {
            "No filtering active"
        }

    fun statusMap(context: Context): Map<String, Any?> {
        val social = blockSocial(context)
        val gaming = blockGaming(context)
        val entertainment = blockEntertainment(context)
        val safe = safeSearch(context)
        val adult = blockAdult(context)
        val active = vpnActive(context)
        val filtering = contentFilteringActive(context)
        val blockedCount = DnsBlocklist.activeBlockedDomainCount(context)
        return mapOf(
            "vpnActive" to active,
            "vpnPermissionGranted" to true,
            "blockSocial" to social,
            "blockGaming" to gaming,
            "blockEntertainment" to entertainment,
            "safeSearch" to safe,
            "blockAdult" to adult,
            "blockedDomainCount" to blockedCount,
            "upstreamDns" to if (active) upstreamDns(context) else "System default",
            "filterStatusLabel" to filterStatusLabel(context),
            "safeSearchStatus" to safeSearchStatusText(safe, filtering, active),
            "adultBlockStatus" to adultBlockStatusText(adult, filtering, active),
            "socialStatus" to categoryStatusText(context, social, active, "social"),
            "gamingStatus" to categoryStatusText(context, gaming, active, "gaming"),
            "entertainmentStatus" to categoryStatusText(context, entertainment, active, "entertainment"),
            "platform" to "android",
        )
    }

    private fun safeSearchStatusText(on: Boolean, filtering: Boolean, vpn: Boolean): String = when {
        !on -> "Off"
        !vpn -> "Pending VPN"
        filtering -> "Protected by AdGuard Family DNS"
        else -> "Off"
    }

    private fun adultBlockStatusText(on: Boolean, filtering: Boolean, vpn: Boolean): String = when {
        !on -> "Off"
        !vpn -> "Pending VPN"
        filtering -> "Protected by AdGuard Family DNS"
        else -> "Off"
    }

    private fun categoryStatusText(
        context: Context,
        on: Boolean,
        vpn: Boolean,
        category: String,
    ): String = when {
        !on -> "DNS: Off"
        !vpn -> "DNS: Pending VPN"
        else -> {
            val n = DnsBlocklist.categoryDomainCount(context, category)
            "DNS: Blocking $n domains"
        }
    }

    fun enabledCategoriesJson(context: Context): JSONArray {
        val arr = JSONArray()
        if (blockSocial(context)) arr.put("social")
        if (blockGaming(context)) arr.put("gaming")
        if (blockEntertainment(context)) arr.put("entertainment")
        return arr
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
