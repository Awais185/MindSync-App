package com.example.frontend

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.util.Log

/**
 * Battery / power-saver gates for background capture and heavy sync.
 */
object MonitoringPolicy {
    private const val TAG = "app_tracking_service"
    private const val MIN_BATTERY_PERCENT = 20

    /**
     * Screen capture (MediaProjection) — no camera; allow during mild device heat.
     * Xiaomi devices often report THERMAL_STATUS_SEVERE during normal TikTok use.
     */
    fun screenRecordingAllowed(context: Context): Boolean {
        if (!isScreenInteractive(context)) {
            return false
        }
        if (isPowerSaveMode(context)) {
            Log.i(TAG, "Screen recording paused: power saver active")
            return false
        }
        val level = batteryPercent(context)
        if (level in 0 until MIN_BATTERY_PERCENT) {
            Log.i(TAG, "Screen recording paused: battery at $level%")
            return false
        }
        return true
    }

    /**
     * Front-camera clips (unlock verify, facial expression, mood video).
     * Same battery / power gates as screen capture; no extra thermal throttle.
     */
    fun cameraCaptureAllowed(context: Context): Boolean = screenRecordingAllowed(context)

    /** Front-camera / OpenFace workloads — stricter thermal gate than screen capture. */
    fun heavyCaptureAllowed(context: Context): Boolean {
        if (!screenRecordingAllowed(context)) {
            return false
        }
        if (isDeviceOverheating(context, minLevel = PowerManager.THERMAL_STATUS_CRITICAL)) {
            Log.i(TAG, "Heavy capture paused: device thermal throttling")
            return false
        }
        return true
    }

    fun isScreenInteractive(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isInteractive
    }

    private fun isPowerSaveMode(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isPowerSaveMode
    }

    private fun batteryPercent(context: Context): Int {
        val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        val batteryStatus = context.registerReceiver(null, filter) ?: return 100
        val level = batteryStatus.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = batteryStatus.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        if (level < 0 || scale <= 0) return 100
        return ((level * 100f) / scale).toInt().coerceIn(0, 100)
    }

    private fun isDeviceOverheating(
        context: Context,
        minLevel: Int = PowerManager.THERMAL_STATUS_CRITICAL,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return try {
            pm.currentThermalStatus >= minLevel
        } catch (_: Exception) {
            false
        }
    }
}
