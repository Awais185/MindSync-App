package com.example.frontend

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService

object DnsFilterController {
    const val VPN_PREPARE_REQUEST = 9103

    fun prepareIntent(context: Context): Intent? =
        VpnService.prepare(context.applicationContext)

    fun hasVpnPermission(context: Context): Boolean =
        prepareIntent(context) == null

    fun applyConfig(
        context: Context,
        blockSocial: Boolean,
        blockGaming: Boolean,
        blockEntertainment: Boolean,
        safeSearch: Boolean,
        blockAdult: Boolean,
    ) {
        val app = context.applicationContext
        DnsFilterPrefs.saveConfig(
            app,
            blockSocial = blockSocial,
            blockGaming = blockGaming,
            blockEntertainment = blockEntertainment,
            safeSearch = safeSearch,
            blockAdult = blockAdult,
        )
        if (!DnsFilterPrefs.needsVpn(app)) {
            DnsFilterVpnService.stop(app)
            return
        }
        if (!hasVpnPermission(app)) {
            DnsFilterPrefs.setVpnActive(app, false)
            return
        }
        DnsFilterVpnService.start(app)
    }

    fun onVpnPermissionResult(context: Context, resultCode: Int) {
        val app = context.applicationContext
        if (resultCode != Activity.RESULT_OK) {
            DnsFilterPrefs.setVpnActive(app, false)
            return
        }
        if (DnsFilterPrefs.needsVpn(app)) {
            DnsFilterVpnService.start(app)
        }
    }

    fun restoreIfNeeded(context: Context) {
        val app = context.applicationContext
        if (DnsFilterPrefs.needsVpn(app) && hasVpnPermission(app)) {
            DnsFilterVpnService.start(app)
        }
    }
}
