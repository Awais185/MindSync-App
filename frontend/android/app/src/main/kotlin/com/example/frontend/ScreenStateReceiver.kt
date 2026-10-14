package com.example.frontend

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ScreenStateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        when (action) {
            Intent.ACTION_SCREEN_ON -> {
                if (TrackerPrefs.shouldAllowUsageCollection(context)) {
                    BackgroundUsageService.start(context)
                }
            }
        }
    }
}
