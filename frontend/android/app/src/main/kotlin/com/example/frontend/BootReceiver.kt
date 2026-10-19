package com.example.frontend

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restores foreground trackers after reboot when configs warrant it.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        val app = context.applicationContext
        if (TrackerPrefs.shouldAllowUsageCollection(app)) {
            BackgroundUsageService.start(app)
        }
        if (TrackerPrefs.hasActiveAppBlockingRules(app) &&
            TrackerPrefs.effectiveBlockedPackages(app).isNotEmpty()
        ) {
            AppBlockerService.start(app)
        }
        DnsFilterController.restoreIfNeeded(app)
        BedtimeScheduleHelper.restoreFromPrefs(app)
    }
}
