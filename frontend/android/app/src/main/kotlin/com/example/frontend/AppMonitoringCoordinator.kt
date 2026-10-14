package com.example.frontend

import android.content.Context
import android.os.Handler

/**
 * 1 Hz foreground monitor:
 * - Face capture (20s + 5 min repeat) for any trackable foreground app
 * - Screen recording chunks via [MindSyncMonitor] / [screenrecording.ScreenRecordingService]
 */
class AppMonitoringCoordinator(
    private val context: Context,
    private val handler: Handler,
    @Suppress("UNUSED_PARAMETER")
    private val videoCapture: VideoCaptureController,
    private val faceCapture: ScheduledFaceCaptureController,
    private val db: MonitoringLocalDatabase,
) {
    private var activeForegroundPackage: String? = null
    private var activeForegroundAppName: String = ""
    private var activeSocialPackage: String? = null
    private var activeSocialAppName: String = ""
    private var lastScreenPermWarnMs: Long = 0L
    private var lastScreenCaptureRequestMs: Long = 0L
    private var screenPermHintShown: Boolean = false

    companion object {
        private const val PREFS = "mindsync_app_monitoring"
        private const val KEY_SCREEN_HINT = "screen_capture_hint_shown"
    }

    private fun prefs() = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Called every ~1s with the current foreground package (may be null / launcher). */
    fun onForegroundTick(foregroundPackage: String?) {
        val selfPkg = context.packageName
        val rawFg = foregroundPackage?.trim().orEmpty()
        val trackableFg =
            ForegroundAppResolver.resolveTrackableForeground(rawFg, selfPkg)
        val socialPkg =
            ForegroundAppResolver.resolveSocialForeground(context, rawFg, selfPkg)

        ForegroundScreenTimeTracker.onForegroundTick(context, trackableFg)

        if (rawFg.isBlank() || rawFg == selfPkg || ForegroundAppResolver.isIgnorableForeground(rawFg)) {
            MonitoringLog.i("FG: (launcher / system / none)")
        } else {
            val label = AppDisplayName.resolve(context, rawFg)
            MonitoringLog.i("FG: $label ($rawFg)")
        }

        val displayPkg = trackableFg ?: socialPkg
        val displayName = displayPkg?.let { AppDisplayName.resolve(context, it) } ?: ""
        TrackerPrefs.setBackgroundMonitoringState(
            context = context,
            monitoredAppName = displayName,
            monitoredPackage = displayPkg.orEmpty(),
            serviceRunning = true,
        )

        handleFaceCapture(trackableFg)
        handleSocialScreenCapture(socialPkg, rawFg)
    }

    private fun handleFaceCapture(trackablePkg: String?) {
        if (trackablePkg != null) {
            val appName = AppDisplayName.resolve(context, trackablePkg)
            MonitoringLog.i("FACE TARGET: [$appName]")
            val isNewSession = activeForegroundPackage != trackablePkg
            faceCapture.onForegroundTargetActive(
                packageName = trackablePkg,
                appName = appName,
                isNewSession = isNewSession,
            )
            activeForegroundPackage = trackablePkg
            activeForegroundAppName = appName
            return
        }

        if (activeForegroundPackage != null) {
            MonitoringLog.i("Face recording stopped — left foreground app")
            faceCapture.onForegroundSessionEnded()
            TrackerPrefs.clearMonitoringSocialSession(context)
            activeForegroundPackage = null
            activeForegroundAppName = ""
        }
    }

    private fun handleSocialScreenCapture(socialPkg: String?, rawFg: String) {
        if (socialPkg != null) {
            val appName = AppDisplayName.resolve(context, socialPkg)
            MonitoringLog.i("SOCIAL TARGET: [$appName]")
            ScreenCapturePermissionStore.syncFromDisk(context)
            val hasScreenPerm = ScreenCapturePermissionStore.hasPermission(context)
            val canRecordScreen =
                TrackerPrefs.shouldAllowUsageCollection(context) &&
                    hasScreenPerm &&
                    MonitoringPolicy.screenRecordingAllowed(context)
            if (!hasScreenPerm && TrackerPrefs.shouldAllowUsageCollection(context)) {
                val now = System.currentTimeMillis()
                if (!screenPermHintShown && !prefs().getBoolean(KEY_SCREEN_HINT, false)) {
                    screenPermHintShown = true
                    prefs().edit().putBoolean(KEY_SCREEN_HINT, true).apply()
                    if (ScreenCapturePermissionStore.userGrantedOnce(context)) {
                        MonitoringLog.w(
                            "Screen capture consent expired — open MindSync once to renew (one-time)",
                        )
                    } else {
                        MonitoringLog.w(
                            "Screen capture not granted — allow once in MindSync onboarding",
                        )
                        maybeRequestScreenCaptureForSocialTarget()
                    }
                } else if (
                    ScreenCapturePermissionStore.userGrantedOnce(context) &&
                    now - lastScreenPermWarnMs > 30 * 60_000L
                ) {
                    lastScreenPermWarnMs = now
                    MonitoringLog.w(
                        "Screen capture inactive — open MindSync to renew consent",
                    )
                }
            }

            if (canRecordScreen) {
                MindSyncMonitor.startRecording(context, socialPkg, appName)
            }

            val isNewSocialSession = activeSocialPackage != socialPkg
            if (isNewSocialSession) {
                db.closeOpenAppSession()
                db.openAppSession(appName)
                MonitoringSession.onSocialAppStarted(context, socialPkg)
            }
            activeSocialPackage = socialPkg
            activeSocialAppName = appName
            return
        }

        if (activeSocialPackage != null) {
            ForegroundAppResolver.clearSocialSticky()
            db.closeOpenAppSession()
            MonitoringLog.i("Screen recording stopped — left social app")
            MindSyncMonitor.stopRecording(context)
            MonitoringSession.onSocialAppEnded(context)
            if (TrackerPrefs.faceVerified(context) &&
                !TrackerPrefs.unlockFaceSessionOk(context) &&
                !TrackedSocialApps.isSocialPackage(context, rawFg)
            ) {
                BackgroundUsageService.requestUnlockFaceVerify(context)
            }
            activeSocialPackage = null
            activeSocialAppName = ""
        }
    }

    /** First-time grant only — never auto-prompt from background after onboarding. */
    private fun maybeRequestScreenCaptureForSocialTarget() {
        if (ScreenCapturePermissionStore.hasPermission(context)) return
        if (ScreenCapturePermissionStore.userGrantedOnce(context)) return
        if (!TrackerPrefs.shouldAllowUsageCollection(context)) return
        val now = System.currentTimeMillis()
        if (now - lastScreenCaptureRequestMs < 300_000L) return
        lastScreenCaptureRequestMs = now
        MonitoringLog.i("Requesting screen capture for active social monitoring session")
        ScreenCaptureRestoreActivity.requestExplicitly(context)
    }

    fun database(): MonitoringLocalDatabase = db

    fun release() {
        db.closeOpenAppSession()
        activeForegroundPackage = null
        activeSocialPackage = null
        MindSyncMonitor.stopRecording(context)
        faceCapture.onForegroundSessionEnded()
    }

    /** After service restart: avoid duplicate face capture for the same session. */
    fun restoreSessionIfNeeded(foregroundPackage: String?) {
        db.recoverOpenAppSessionOnRestart()
        val selfPkg = context.packageName
        val trackable =
            ForegroundAppResolver.resolveTrackableForeground(foregroundPackage, selfPkg)
        val social =
            ForegroundAppResolver.resolveSocialForeground(context, foregroundPackage, selfPkg)

        if (trackable != null) {
            val saved = TrackerPrefs.monitoringSocialSessionPackage(context)
            if (saved == trackable) {
                activeForegroundPackage = trackable
                activeForegroundAppName = AppDisplayName.resolve(context, trackable)
                faceCapture.onForegroundTargetActive(
                    packageName = trackable,
                    appName = activeForegroundAppName,
                    isNewSession = true,
                )
            } else {
                TrackerPrefs.clearMonitoringSocialSession(context)
            }
        }

        if (social != null) {
            activeSocialPackage = social
            activeSocialAppName = AppDisplayName.resolve(context, social)
            ScreenCapturePermissionStore.syncFromDisk(context)
            val hasScreenPerm = ScreenCapturePermissionStore.hasPermission(context)
            val canRecord =
                TrackerPrefs.shouldAllowUsageCollection(context) &&
                    hasScreenPerm &&
                    MonitoringPolicy.screenRecordingAllowed(context)
            if (canRecord) {
                MindSyncMonitor.startRecording(context, social, activeSocialAppName)
            }
        }
    }
}
