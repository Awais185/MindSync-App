package com.example.frontend

import android.app.Activity
import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import androidx.activity.result.ActivityResult
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.Lifecycle
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import kotlin.math.max
import kotlin.math.min

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "mindsync/screen_time"
    private var pendingScreenCaptureResult: MethodChannel.Result? = null
    private var pendingDnsVpnResult: MethodChannel.Result? = null
    private var launchScreenCaptureOnResume = false
    private val ioExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()
    private lateinit var screenCaptureLauncher: ActivityResultLauncher<Intent>
    private lateinit var dnsVpnPrepareLauncher: ActivityResultLauncher<Intent>

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        ScreenCapturePermissionStore.syncFromDisk(applicationContext)
        dnsVpnPrepareLauncher =
            registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
                DnsFilterController.onVpnPermissionResult(this, result.resultCode)
                pendingDnsVpnResult?.success(result.resultCode == Activity.RESULT_OK)
                pendingDnsVpnResult = null
            }
        screenCaptureLauncher =
            registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result: ActivityResult ->
                val allowed = result.resultCode == Activity.RESULT_OK && result.data != null
                if (allowed) {
                    ScreenCapturePermissionStore.save(applicationContext, result.resultCode, result.data)
                    BackgroundUsageService.notifyScreenCaptureGranted(applicationContext)
                }
                pendingScreenCaptureResult?.success(allowed)
                pendingScreenCaptureResult = null
            }
    }

    override fun onPause() {
        super.onPause()
        if (TrackerPrefs.shouldAllowUsageCollection(applicationContext)) {
            BackgroundUsageService.start(applicationContext)
        }
    }

    override fun onStop() {
        super.onStop()
        if (TrackerPrefs.shouldAllowUsageCollection(applicationContext)) {
            BackgroundUsageService.start(applicationContext)
        }
    }

    override fun onResume() {
        super.onResume()
        if (TrackerPrefs.shouldAllowUsageCollection(applicationContext)) {
            BackgroundUsageService.start(applicationContext)
        }
        ScreenCapturePermissionStore.syncFromDisk(applicationContext)
        if (ScreenCapturePermissionStore.hasPermission(applicationContext)) {
            BackgroundUsageService.notifyScreenCaptureGranted(applicationContext)
        }
        if (launchScreenCaptureOnResume && pendingScreenCaptureResult != null) {
            launchScreenCaptureOnResume = false
            runOnUiThread { launchScreenCaptureConsent() }
        }
        if (BackgroundUsageService.isRunning() &&
            TrackerPrefs.faceVerified(applicationContext) &&
            TrackerPrefs.token(applicationContext).isNotBlank() &&
            !TrackerPrefs.unlockFaceSessionOk(applicationContext)
        ) {
            BackgroundUsageService.requestUnlockFaceVerify(applicationContext)
        }
    }

    private fun requestScreenCaptureFromChannel(result: MethodChannel.Result) {
        ScreenCapturePermissionStore.syncFromDisk(applicationContext)
        if (ScreenCapturePermissionStore.hasPermission(applicationContext)) {
            result.success(true)
            return
        }
        if (pendingScreenCaptureResult != null) {
            result.error(
                "capture_pending",
                "A screen capture permission request is already active.",
                null,
            )
            return
        }
        pendingScreenCaptureResult = result
        if (lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
            runOnUiThread { launchScreenCaptureConsent() }
        } else {
            launchScreenCaptureOnResume = true
        }
    }

    private fun launchScreenCaptureConsentActivity(result: MethodChannel.Result) {
        ScreenCapturePermissionStore.syncFromDisk(applicationContext)
        if (ScreenCapturePermissionStore.hasPermission(applicationContext)) {
            result.success(true)
            return
        }
        try {
            ScreenCaptureRestoreActivity.requestExplicitly(
                applicationContext,
                requireLoggedInSession = false,
            )
            result.success(false)
        } catch (e: Exception) {
            result.error("capture_failed", e.message ?: "launch_failed", null)
        }
    }

    private fun launchScreenCaptureConsent() {
        val pending = pendingScreenCaptureResult ?: return
        try {
            val projectionManager =
                getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val captureIntent =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    projectionManager.createScreenCaptureIntent(
                        MediaProjectionConfig.createConfigForDefaultDisplay(),
                    )
                } else {
                    projectionManager.createScreenCaptureIntent()
                }
            screenCaptureLauncher.launch(captureIntent)
        } catch (e: Exception) {
            pending.error("capture_failed", e.message ?: "launch_failed", null)
            pendingScreenCaptureResult = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasUsageAccess" -> result.success(hasUsageAccess())
                    "openUsageAccessSettings" -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(true)
                    }
                    "hasScreenCapturePermission" -> {
                        ScreenCapturePermissionStore.syncFromDisk(applicationContext)
                        result.success(ScreenCapturePermissionStore.hasPermission(applicationContext))
                    }
                    "syncScreenCaptureGrant" -> {
                        ScreenCapturePermissionStore.syncFromDisk(applicationContext)
                        val ok = ScreenCapturePermissionStore.hasPermission(applicationContext)
                        if (ok) {
                            BackgroundUsageService.notifyScreenCaptureGranted(applicationContext)
                        }
                        result.success(ok)
                    }
                    "notifyScreenCaptureGranted" -> {
                        ScreenCapturePermissionStore.syncFromDisk(applicationContext)
                        if (ScreenCapturePermissionStore.hasPermission(applicationContext)) {
                            BackgroundUsageService.notifyScreenCaptureGranted(applicationContext)
                        }
                        result.success(true)
                    }
                    "openScreenCaptureSettings" -> {
                        launchScreenCaptureConsentActivity(result)
                    }
                    "launchScreenCaptureConsentActivity" -> {
                        launchScreenCaptureConsentActivity(result)
                    }
                    "openAppInfoSettings" -> {
                        ScreenCaptureSettingsHelper.openMindSyncAppInfo(applicationContext)
                        result.success(true)
                    }
                    "requestScreenCapturePermission" -> {
                        launchScreenCaptureConsentActivity(result)
                    }
                    "updateTrackerBaseUrl" -> {
                        val args = call.arguments as? Map<*, *>
                        val base = (args?.get("baseUrl") as? String).orEmpty()
                        if (base.isNotBlank()) {
                            TrackerPrefs.updateBaseUrl(applicationContext, base)
                        }
                        result.success(true)
                    }
                    "configureTracker" -> {
                        val args = call.arguments as? Map<*, *>
                        if (args != null) {
                            val token = (args["token"] as? String).orEmpty()
                            if (token.isBlank()) {
                                TrackerPrefs.setParentalEnforcementEnabled(applicationContext, false)
                                AppBlockerService.stop(applicationContext)
                                val baseOnly = (args["baseUrl"] as? String).orEmpty()
                                TrackerPrefs.writeConfig(
                                    context = applicationContext,
                                    baseUrl = baseOnly,
                                    token = "",
                                    userId = "",
                                    faceVerified = false,
                                    faceMatchPercent = 0.0,
                                    screenCaptureOnboardingDone =
                                        (args["screenCaptureOnboardingDone"] as? Boolean) ?: false,
                                )
                                BackgroundUsageService.stop(applicationContext)
                                result.success(true)
                                return@setMethodCallHandler
                            }
                            ScreenCapturePermissionStore.syncFromDisk(applicationContext)
                            TrackerPrefs.writeConfig(
                                context = applicationContext,
                                baseUrl = (args["baseUrl"] as? String).orEmpty(),
                                token = token,
                                userId = (args["userId"] as? String).orEmpty(),
                                faceVerified = (args["faceVerified"] as? Boolean) ?: false,
                                faceMatchPercent = ((args["faceMatchPercent"] as? Number)?.toDouble() ?: 0.0),
                                screenCaptureOnboardingDone =
                                    (args["screenCaptureOnboardingDone"] as? Boolean) ?: false,
                            )
                            if (TrackerPrefs.shouldAllowUsageCollection(applicationContext)) {
                                BackgroundUsageService.start(applicationContext)
                            } else {
                                BackgroundUsageService.stop(applicationContext)
                            }
                            if (TrackerPrefs.faceVerified(applicationContext) &&
                                !TrackerPrefs.unlockFaceSessionOk(applicationContext)
                            ) {
                                BackgroundUsageService.requestUnlockFaceVerify(applicationContext)
                            }
                            if (token.isNotBlank() &&
                                TrackerPrefs.hasActiveAppBlockingRules(applicationContext) &&
                                TrackerPrefs.effectiveBlockedPackages(applicationContext).isNotEmpty() &&
                                hasUsageAccess()
                            ) {
                                AppBlockerService.start(applicationContext)
                            }
                            if (token.isNotBlank() &&
                                ScreenCapturePermissionStore.hasPermission(applicationContext)
                            ) {
                                BackgroundUsageService.notifyScreenCaptureGranted(applicationContext)
                            }
                        }
                        result.success(true)
                    }
                    "pingTracker" -> {
                        if (TrackerPrefs.shouldAllowUsageCollection(applicationContext)) {
                            BackgroundUsageService.start(applicationContext)
                        }
                        result.success(true)
                    }
                    "requestUnlockFaceVerify" -> {
                        BackgroundUsageService.requestUnlockFaceVerify(applicationContext)
                        result.success(true)
                    }
                    "applyFaceMatchPause" -> {
                        TrackerPrefs.applyFaceMatchPause(applicationContext)
                        result.success(true)
                    }
                    "setParentalPolicy" -> {
                        val args = call.arguments as? Map<*, *>
                        if (args != null) {
                            TrackerPrefs.setLimits(
                                context = applicationContext,
                                socialMinutes = ((args["socialLimitMinutes"] as? Number)?.toInt() ?: 90),
                                gamingMinutes = ((args["gamingLimitMinutes"] as? Number)?.toInt() ?: 60),
                                entertainmentMinutes = ((args["entertainmentLimitMinutes"] as? Number)?.toInt() ?: 120),
                            )
                            val enableEnforcement = (args["enableEnforcement"] as? Boolean) ?: false
                            if (enableEnforcement) {
                                TrackerPrefs.setParentalEnforcementEnabled(applicationContext, true)
                                if (hasUsageAccess()) {
                                    BackgroundUsageService.start(applicationContext)
                                    BackgroundUsageService.requestImmediateEnforcement(applicationContext)
                                }
                            }
                        }
                        result.success(true)
                    }
                    "setUsageHealthSocialLimit" -> {
                        val args = call.arguments as? Map<*, *>
                        if (args != null) {
                            val limitMinutes = ((args["limitMinutes"] as? Number)?.toInt() ?: 0)
                            val setAtMs = ((args["setAtMs"] as? Number)?.toLong() ?: 0L)
                            if (limitMinutes > 0 && setAtMs > 0L) {
                                TrackerPrefs.setUsageHealthSocialLimit(
                                    applicationContext,
                                    limitMinutes,
                                    setAtMs,
                                )
                                TrackerPrefs.setParentalEnforcementEnabled(applicationContext, true)
                                UsageLimitEnforcer.onLimitSaved(applicationContext, setAtMs)
                                if (hasUsageAccess()) {
                                    BackgroundUsageService.start(applicationContext)
                                    BackgroundUsageService.requestImmediateEnforcement(applicationContext)
                                }
                            } else {
                                TrackerPrefs.clearUsageHealthSocialLimit(applicationContext)
                                UsageLimitEnforcer.onLimitCleared(applicationContext)
                            }
                        }
                        result.success(true)
                    }
                    "getUsageHealthSocialLimit" -> {
                        TrackerPrefs.clearUsageHealthSocialLimitIfExpired(applicationContext)
                        val setAt = TrackerPrefs.usageHealthSocialLimitSetAtMs(applicationContext)
                        val limit = TrackerPrefs.usageHealthSocialLimitMinutes(applicationContext)
                        val active = TrackerPrefs.usageHealthSocialLimitActive(applicationContext)
                        result.success(
                            mapOf(
                                "limitMinutes" to if (active) limit else 0,
                                "setAtMs" to if (active) setAt else 0L,
                                "expired" to (setAt > 0L && !active),
                                "expiresAtMs" to if (active) setAt + TrackerPrefs.USAGE_HEALTH_LIMIT_EXPIRY_MS else 0L,
                            ),
                        )
                    }
                    "setBlockedAppNow" -> {
                        val args = call.arguments as? Map<*, *>
                        if (args != null) {
                            val packageName = (args["packageName"] as? String).orEmpty()
                            val blocked = (args["blocked"] as? Boolean) ?: false
                            if (packageName.isNotBlank()) {
                                TrackerPrefs.setLocalBlockedState(
                                    context = applicationContext,
                                    packageName = packageName,
                                    blocked = blocked,
                                )
                                val effective = TrackerPrefs.effectiveBlockedPackages(applicationContext)
                                if (effective.isNotEmpty()) {
                                    TrackerPrefs.setParentalEnforcementEnabled(applicationContext, true)
                                } else {
                                    TrackerPrefs.setParentalEnforcementEnabled(applicationContext, false)
                                }
                                if (TrackerPrefs.shouldAllowUsageCollection(applicationContext)) {
                                    BackgroundUsageService.start(applicationContext)
                                }
                                if (TrackerPrefs.hasActiveAppBlockingRules(applicationContext)) {
                                    BackgroundUsageService.requestImmediateEnforcement(applicationContext)
                                    BackgroundUsageService.notifyBlockedAppsChanged(applicationContext)
                                }
                                if (TrackerPrefs.hasActiveAppBlockingRules(applicationContext) &&
                                    effective.isNotEmpty()
                                ) {
                                    AppBlockerService.start(applicationContext)
                                } else {
                                    AppBlockerService.stop(applicationContext)
                                }
                            }
                        }
                        result.success(true)
                    }
                    "getUsageSnapshot" -> {
                        if (!hasUsageAccess()) {
                            result.success(
                                mapOf(
                                    "daySeconds" to 0,
                                    "weekSeconds" to 0,
                                    "monthSeconds" to 0,
                                    "topApps" to emptyList<Map<String, Any>>(),
                                    "hasUsageAccess" to false,
                                    "lateNightWeekSeconds" to 0,
                                    "lateNightOpensWeek" to 0,
                                    "lateNightByDaySeconds" to List(7) { 0 },
                                    "lateNightTopApps" to emptyList<Map<String, Any>>(),
                                ),
                            )
                            return@setMethodCallHandler
                        }
                        result.success(buildUsageSnapshot())
                    }
                    "getScreenTimeUsageArchive" -> {
                        val uid = TrackerPrefs.userId(applicationContext).trim()
                        if (uid.isBlank()) {
                            result.success(
                                mapOf(
                                    "dailyArchive" to emptyList<Map<String, Any>>(),
                                    "weekMergedAppSeconds" to emptyMap<String, Int>(),
                                    "todayLiveApps" to emptyList<Map<String, Any>>(),
                                    "todayTotalSeconds" to 0,
                                ),
                            )
                            return@setMethodCallHandler
                        }
                        val db = ScreenTimeLocalDatabase.getInstance(applicationContext)
                        db.checkMidnightReset(uid)
                        val archive = db.getDailyHistory(uid, 31)
                        val fmt =
                            SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
                                timeZone = TimeZone.getDefault()
                            }
                        val weekStartCal = Calendar.getInstance()
                        weekStartCal.add(Calendar.DAY_OF_YEAR, -6)
                        val weekStart = fmt.format(weekStartCal.time)
                        val yesterdayCal = Calendar.getInstance()
                        yesterdayCal.add(Calendar.DAY_OF_YEAR, -1)
                        val weekEndArchived = fmt.format(yesterdayCal.time)
                        val merged =
                            HashMap(
                                db.sumAppSecondsFromDailyArchive(
                                    uid,
                                    weekStart,
                                    weekEndArchived,
                                ),
                            )
                        val todayApps = db.getTopAppsToday(uid, 40)
                        for (row in todayApps) {
                            val name = (row["appName"] as? String).orEmpty()
                            val sec = (row["durationSeconds"] as? Int) ?: 0
                            if (name.isNotBlank() && sec > 0) {
                                merged.merge(name, sec, Int::plus)
                            }
                        }
                        val sleepArchive = LateNightSleepTracker.getSleepNightArchive(applicationContext, uid, 31)
                        val sleepSnapshot = LateNightSleepTracker.buildSnapshot(applicationContext, uid)
                        result.success(
                            mapOf(
                                "dailyArchive" to archive,
                                "weekMergedAppSeconds" to merged,
                                "todayLiveApps" to todayApps,
                                "todayTotalSeconds" to db.getTodayTotalSeconds(uid),
                                "sleepNightArchive" to sleepArchive,
                                "sleepTonightMinutes" to (sleepSnapshot["sleepTonightMinutes"] as? Int ?: 0),
                                "lateNightTonightMinutes" to (sleepSnapshot["lateNightTonightMinutes"] as? Int ?: 0),
                                "lateNightCategoriesTonight" to (sleepSnapshot["lateNightCategoriesTonight"] as? Map<*, *> ?: emptyMap<String, Int>()),
                                "lateNightByDayMinutes" to (sleepSnapshot["lateNightByDayMinutes"] as? List<*> ?: List(7) { 0 }),
                                "sleepByDayMinutes" to (sleepSnapshot["sleepByDayMinutes"] as? List<*> ?: List(7) { 0 }),
                                "lateNightCategoriesWeek" to (sleepSnapshot["lateNightCategoriesWeek"] as? Map<*, *> ?: emptyMap<String, Int>()),
                            ),
                        )
                    }
                    "getTodayScreenTimeMs" -> {
                        if (!hasUsageAccess()) {
                            result.success(0L)
                            return@setMethodCallHandler
                        }
                        val now = System.currentTimeMillis()
                        val dayStart = startOfDay(now)
                        val sec = totalUsageSeconds(dayStart, now).toLong().coerceAtLeast(0L)
                        result.success(sec * 1000L)
                    }
                    "hasOverlayPermission" -> {
                        val ok =
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                Settings.canDrawOverlays(applicationContext)
                            } else {
                                true
                            }
                        result.success(ok)
                    }
                    "openManageOverlaySettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val uri = android.net.Uri.parse("package:${applicationContext.packageName}")
                            val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, uri)
                            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        }
                        result.success(true)
                    }
                    "getRollingAppUsage" -> {
                        if (!hasUsageAccess()) {
                            result.success(emptyList<Map<String, Any>>())
                            return@setMethodCallHandler
                        }
                        result.success(buildRollingAppUsage())
                    }
                    "hasAccessibilityService" -> {
                        result.success(AccessibilityHelper.isVideoDetectorEnabled(applicationContext))
                    }
                    "openAccessibilitySettings" -> {
                        AccessibilityHelper.openAccessibilitySettings(applicationContext)
                        result.success(true)
                    }
                    "startTrackingSession" -> {
                        val userId = (call.arguments as? String).orEmpty()
                        if (userId.isBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        ioExecutor.execute {
                            val verified =
                                if (!TrackerPrefs.faceVerified(applicationContext)) {
                                    true
                                } else {
                                    ActivityFaceVerifier.verify(this@MainActivity)
                                }
                            runOnUiThread {
                                if (!verified) {
                                    result.success(false)
                                    return@runOnUiThread
                                }
                                ScreenTimeSessionStore.startSession(applicationContext, userId)
                                ForegroundScreenTimeTracker.onUserSessionStarted(applicationContext, userId)
                                TrackerPrefs.startUserSession(applicationContext, userId)
                                result.success(true)
                            }
                        }
                    }
                    "resetUsageBaselines" -> {
                        val userId = (call.arguments as? String).orEmpty()
                        if (userId.isNotBlank()) {
                            TrackerPrefs.resetNewUserUsageBaselines(applicationContext, userId)
                        }
                        result.success(true)
                    }
                    "endTrackingSession" -> {
                        val userId = (call.arguments as? String).orEmpty()
                        if (userId.isNotBlank()) {
                            ScreenTimeSessionStore.endSession(applicationContext, userId)
                            ForegroundScreenTimeTracker.onUserSessionEnded(applicationContext)
                            TrackerPrefs.endUserSession(applicationContext, userId)
                        }
                        result.success(true)
                    }
                    "getSessionScreenTimeMs" -> {
                        val userId = (call.arguments as? String).orEmpty()
                        val ms =
                            if (userId.isBlank()) {
                                0L
                            } else {
                                val secs =
                                    ForegroundScreenTimeTracker.buildSnapshot(
                                        applicationContext,
                                        userId,
                                    )["daySeconds"] as? Int ?: 0
                                secs.toLong() * 1000L
                            }
                        result.success(ms)
                    }
                    "screenTimeCheckMidnightReset" -> {
                        val userId = (call.arguments as? String).orEmpty()
                        val payload =
                            if (userId.isBlank()) {
                                emptyMap<String, Any?>()
                            } else {
                                val primary =
                                    ForegroundScreenTimeTracker.checkMidnightReset(
                                        applicationContext,
                                        userId,
                                    )
                                if (primary.isNotEmpty()) {
                                    primary
                                } else {
                                    ScreenTimeSessionStore.checkMidnightReset(
                                        applicationContext,
                                        userId,
                                    )
                                }
                            }
                        result.success(payload)
                    }
                    "appBlockerSetBlockedApps" -> {
                        val raw = call.argument<List<*>>("packages")
                        val pkgs =
                            raw?.mapNotNull { it as? String }?.filter { it.isNotBlank() }
                                ?: emptyList()
                        TrackerPrefs.setHomeBlockedPackages(applicationContext, pkgs.toSet())
                        if (pkgs.isEmpty()) {
                            AppBlockerService.stop(applicationContext)
                        } else {
                            // Restoring blocked lists on login must not enable blocking by itself.
                            if (TrackerPrefs.hasActiveAppBlockingRules(applicationContext)) {
                                AppBlockerService.start(applicationContext)
                            } else {
                                AppBlockerService.stop(applicationContext)
                            }
                            if (hasUsageAccess()) {
                                if (TrackerPrefs.hasActiveAppBlockingRules(applicationContext)) {
                                    BackgroundUsageService.start(applicationContext)
                                    BackgroundUsageService.requestImmediateEnforcement(applicationContext)
                                }
                            }
                        }
                        result.success(true)
                    }
                    "getTrackerStatus" -> {
                        result.success(buildTrackerStatusMap())
                    }
                    "getMonitoringState" -> {
                        result.success(buildMonitoringStateMap())
                    }
                    "getInstalledApps" -> {
                        ioExecutor.execute {
                            val pm = packageManager
                            val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
                            val out = mutableListOf<Map<String, String>>()
                            for (app in apps) {
                                // Skip system apps
                                if ((app.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0 && (app.flags and android.content.pm.ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0) {
                                    continue
                                }
                                val pkg = app.packageName
                                val label = app.loadLabel(pm).toString()
                                out.add(mapOf("package_name" to pkg, "app_label" to label))
                            }
                            runOnUiThread {
                                result.success(out)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mindsync/dns_filter")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "dnsFilterGetStatus" -> {
                        result.success(DnsFilterPrefs.statusMap(applicationContext))
                    }
                    "dnsFilterApplyConfig" -> {
                        val args = call.arguments as? Map<*, *>
                        if (args == null) {
                            result.error("invalid_args", "Missing config", null)
                            return@setMethodCallHandler
                        }
                        DnsFilterController.applyConfig(
                            context = applicationContext,
                            blockSocial = (args["blockSocial"] as? Boolean) ?: false,
                            blockGaming = (args["blockGaming"] as? Boolean) ?: false,
                            blockEntertainment = (args["blockEntertainment"] as? Boolean) ?: false,
                            safeSearch = (args["safeSearch"] as? Boolean) ?: false,
                            blockAdult = (args["blockAdult"] as? Boolean) ?: false,
                        )
                        result.success(DnsFilterPrefs.statusMap(applicationContext))
                    }
                    "dnsFilterPrepareVpn" -> {
                        if (pendingDnsVpnResult != null) {
                            result.error("vpn_pending", "VPN permission request already active", null)
                            return@setMethodCallHandler
                        }
                        val prepare = DnsFilterController.prepareIntent(this)
                        if (prepare == null) {
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        pendingDnsVpnResult = result
                        dnsVpnPrepareLauncher.launch(prepare)
                    }
                    "dnsFilterHasVpnPermission" -> {
                        result.success(DnsFilterController.hasVpnPermission(applicationContext))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun buildTrackerStatusMap(): Map<String, Any> {
        val loggedIn = TrackerPrefs.shouldAllowUsageCollection(applicationContext)
        val usageGranted = hasUsageAccess()
        val serviceRunning =
            BackgroundUsageService.isRunning() ||
                TrackerPrefs.backgroundServiceRunningFlag(applicationContext)
        return mapOf(
            "recordingActive" to TrackerPrefs.recordingActive(applicationContext),
            "lastVideoPlatform" to TrackerPrefs.lastVideoPlatform(applicationContext),
            "lastVideoPackage" to TrackerPrefs.lastVideoPackage(applicationContext),
            "lastVideoUploadError" to TrackerPrefs.lastVideoUploadError(applicationContext),
            "screenCaptureGranted" to ScreenCapturePermissionStore.hasPermission(applicationContext),
            "accessibilityVideoDetectorEnabled" to AccessibilityHelper.isVideoDetectorEnabled(applicationContext),
            "trackingConfigured" to (loggedIn && usageGranted),
            "serviceRunning" to serviceRunning,
            "hasUsageAccess" to usageGranted,
            "monitoredAppName" to TrackerPrefs.backgroundMonitoredAppName(applicationContext),
            "monitoredPackage" to TrackerPrefs.backgroundMonitoredPackage(applicationContext),
            "faceReactionRecording" to TrackerPrefs.faceReactionRecording(applicationContext),
            "faceReactionCooldownUntilMs" to TrackerPrefs.faceReactionCooldownUntilMs(applicationContext),
            "faceReactionLastError" to TrackerPrefs.faceReactionLastError(applicationContext),
            "unlockFaceSessionOk" to TrackerPrefs.unlockFaceSessionOk(applicationContext),
            "unlockFaceLastError" to TrackerPrefs.unlockFaceLastError(applicationContext),
            "faceVerified" to TrackerPrefs.faceVerified(applicationContext),
        )
    }

    private fun buildMonitoringStateMap(): Map<String, Any> {
        val loggedIn = TrackerPrefs.shouldAllowUsageCollection(applicationContext)
        val usageGranted = hasUsageAccess()
        val serviceRunning =
            BackgroundUsageService.isRunning() ||
                TrackerPrefs.backgroundServiceRunningFlag(applicationContext)
        val monitoredApp = TrackerPrefs.backgroundMonitoredAppName(applicationContext)
        val lastTick = TrackerPrefs.backgroundMonitoringLastTickMs(applicationContext)
        val tickFresh = lastTick > 0L && System.currentTimeMillis() - lastTick < 15_000L
        return mapOf(
            "serviceRunning" to serviceRunning,
            "trackingConfigured" to (loggedIn && usageGranted),
            "loggedIn" to loggedIn,
            "hasUsageAccess" to usageGranted,
            "monitoredAppName" to monitoredApp,
            "monitoredPackage" to TrackerPrefs.backgroundMonitoredPackage(applicationContext),
            "recordingActive" to TrackerPrefs.recordingActive(applicationContext),
            "lastTickMs" to lastTick,
            "monitoringActive" to (serviceRunning && loggedIn && usageGranted && tickFresh),
        )
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            "android:get_usage_stats",
            Process.myUid(),
            packageName,
        )
        if (mode == AppOpsManager.MODE_ALLOWED) return true
        if (mode == AppOpsManager.MODE_DEFAULT) {
            return checkCallingOrSelfPermission(android.Manifest.permission.PACKAGE_USAGE_STATS) ==
                PackageManager.PERMISSION_GRANTED
        }
        return false
    }

    private fun buildUsageSnapshot(): Map<String, Any> {
        val now = System.currentTimeMillis()
        val userId = TrackerPrefs.userId(applicationContext).trim()
        val fgPkg = getCurrentForegroundPackageForSnapshot()
        val fgName = fgPkg?.let { resolvePackageLabel(it) } ?: ""

        val lateNight = computeLateNightRollup7d(now)
        val sleepNight =
            if (userId.isNotBlank()) {
                LateNightSleepTracker.buildSnapshot(applicationContext, userId)
            } else {
                emptyMap()
            }

        val tracked =
            if (userId.isNotBlank()) {
                ForegroundScreenTimeTracker.buildSnapshot(applicationContext, userId)
            } else {
                emptyMap()
            }
        val daySeconds = (tracked["daySeconds"] as? Int) ?: 0
        val weekSeconds = (tracked["weekSeconds"] as? Int) ?: 0
        val monthSeconds = (tracked["monthSeconds"] as? Int) ?: 0
        @Suppress("UNCHECKED_CAST")
        val topAppsTracked = (tracked["topApps"] as? List<Map<String, Any>>) ?: emptyList()
        @Suppress("UNCHECKED_CAST")
        val weekBars = (tracked["weekBarSeconds"] as? List<Int>) ?: List(7) { 0 }

        val fgSeconds =
            if (userId.isNotBlank() && !fgPkg.isNullOrBlank()) {
                ForegroundScreenTimeTracker.foregroundTodaySeconds(applicationContext, userId, fgPkg)
            } else {
                0
            }

        val topAppsOut =
            if (topAppsTracked.isNotEmpty()) {
                topAppsTracked
            } else {
                val dayStart = startOfDay(now)
                topApps(dayStart, now)
            }

        return mapOf(
            "daySeconds" to daySeconds,
            "weekSeconds" to weekSeconds,
            "monthSeconds" to monthSeconds,
            "topApps" to topAppsOut,
            "foregroundPackage" to (fgPkg ?: ""),
            "foregroundAppName" to fgName,
            "foregroundTodaySeconds" to fgSeconds,
            "foregroundIconPngBase64" to (if (fgPkg.isNullOrBlank()) "" else iconPngBase64(fgPkg)),
            "hasUsageAccess" to true,
            "weekBarSeconds" to weekBars,
            "lateNightWeekSeconds" to lateNight.totalSeconds,
            "lateNightOpensWeek" to lateNight.opens,
            "lateNightByDaySeconds" to lateNight.byDaySeconds,
            "lateNightTopApps" to lateNight.topApps,
            "sleepTonightMinutes" to (sleepNight["sleepTonightMinutes"] as? Int ?: 0),
            "lateNightTonightMinutes" to (sleepNight["lateNightTonightMinutes"] as? Int ?: 0),
            "lateNightCategoriesTonight" to (sleepNight["lateNightCategoriesTonight"] as? Map<*, *> ?: emptyMap<String, Int>()),
            "sleepWeekMinutes" to (sleepNight["sleepWeekMinutes"] as? Int ?: 0),
            "lateNightWeekMinutes" to (sleepNight["lateNightWeekMinutes"] as? Int ?: 0),
            "lateNightByDayMinutes" to (sleepNight["lateNightByDayMinutes"] as? List<*> ?: List(7) { 0 }),
            "sleepByDayMinutes" to (sleepNight["sleepByDayMinutes"] as? List<*> ?: List(7) { 0 }),
            "lateNightCategoriesWeek" to (sleepNight["lateNightCategoriesWeek"] as? Map<*, *> ?: emptyMap<String, Int>()),
        )
    }

    private data class LateNightRollup(
        val totalSeconds: Int,
        val opens: Int,
        val byDaySeconds: List<Int>,
        val topApps: List<Map<String, Any>>,
    )

    private fun computeLateNightRollup7d(nowMs: Long): LateNightRollup {
        val cal = Calendar.getInstance()
        cal.timeInMillis = nowMs
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        val oldestMidnight = cal.apply { add(Calendar.DAY_OF_YEAR, -6) }.timeInMillis
        val dayMs = 24L * 3600 * 1000

        val nightWindows = Array(7) { idx ->
            val dayStart = oldestMidnight + idx * dayMs
            val wStart = dayStart + 22L * 3600 * 1000
            val wEndRaw = dayStart + 29L * 3600 * 1000
            longArrayOf(wStart, min(wEndRaw, nowMs))
        }

        val byDay = IntArray(7)
        val pkgMs = HashMap<String, Long>()
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = manager.queryEvents(oldestMidnight, nowMs) ?: return LateNightRollup(0, 0, List(7) { 0 }, emptyList())

        var opens = 0
        var activePkg: String? = null
        var activeStart = 0L

        fun tsInAnyNightWindow(ts: Long): Boolean {
            for (w in nightWindows) {
                if (ts >= w[0] && ts < w[1]) return true
            }
            return false
        }

        fun addOverlap(pkg: String, s: Long, e: Long) {
            if (e <= s || pkg.isBlank()) return
            for (idx in 0 until 7) {
                val w = nightWindows[idx]
                val wStart = w[0]
                val wEnd = w[1]
                if (wEnd <= wStart) continue
                val os = max(s, wStart)
                val oe = min(e, wEnd)
                if (oe > os) {
                    val dur = oe - os
                    byDay[idx] += (dur / 1000L).toInt()
                    pkgMs.merge(pkg, dur) { a, b -> a + b }
                }
            }
        }

        fun closeSession(endTs: Long) {
            val pkg = activePkg ?: return
            addOverlap(pkg, activeStart, endTs)
            activePkg = null
        }

        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val t = event.timeStamp
            val pkg = event.packageName ?: continue
            when (event.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND, UsageEvents.Event.ACTIVITY_RESUMED -> {
                    val switched = activePkg != null && activePkg != pkg
                    val freshOpen = activePkg == null
                    if (tsInAnyNightWindow(t) && (freshOpen || switched)) {
                        opens++
                    }
                    if (activePkg != null && activePkg != pkg) {
                        closeSession(t)
                    }
                    activePkg = pkg
                    activeStart = t
                }
                UsageEvents.Event.MOVE_TO_BACKGROUND, UsageEvents.Event.ACTIVITY_PAUSED -> {
                    if (activePkg != null && activePkg == pkg) {
                        closeSession(t)
                    }
                }
            }
        }
        if (activePkg != null) {
            closeSession(nowMs)
        }

        val top = pkgMs.entries
            .sortedByDescending { it.value }
            .take(6)
            .map { e ->
                val label = AppDisplayName.resolve(applicationContext, e.key)
                mapOf(
                    "packageName" to e.key,
                    "appName" to label,
                    "durationSeconds" to (e.value / 1000L).toInt(),
                    "iconPngBase64" to iconPngBase64(e.key),
                )
            }

        return LateNightRollup(
            totalSeconds = byDay.sum(),
            opens = opens,
            byDaySeconds = byDay.toList(),
            topApps = top,
        )
    }

    private fun getCurrentForegroundPackageForSnapshot(): String? {
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val t = System.currentTimeMillis()
        val fromEvents = foregroundPackageFromUsageEvents(manager, t - 120_000, t)
        if (!fromEvents.isNullOrBlank()) return fromEvents
        val stats = manager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, t - 120_000, t)
        if (stats.isNullOrEmpty()) return null
        return stats.maxByOrNull { it.lastTimeUsed }?.packageName
    }

    private fun foregroundPackageFromUsageEvents(
        manager: UsageStatsManager,
        beginMs: Long,
        endMs: Long,
    ): String? {
        val events = manager.queryEvents(beginMs, endMs) ?: return null
        var lastPkg: String? = null
        var lastTs = -1L
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val isForeground = when (event.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND -> true
                UsageEvents.Event.ACTIVITY_RESUMED -> true
                else -> false
            }
            if (isForeground && event.timeStamp >= lastTs) {
                lastTs = event.timeStamp
                lastPkg = event.packageName
            }
        }
        return lastPkg
    }

    private fun resolvePackageLabel(packageName: String): String {
        return AppDisplayName.resolve(applicationContext, packageName)
    }

    private fun iconPngBase64(packageName: String): String =
        AppIconCache.iconPngBase64(applicationContext, packageName)

    private fun foregroundTodaySeconds(dayStart: Long, nowMs: Long, pkg: String): Int {
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val agg = manager.queryAndAggregateUsageStats(dayStart, nowMs)
            val s = agg[pkg] ?: return 0
            return (s.totalTimeInForeground / 1000L).toInt().coerceAtLeast(0)
        }
        val stats = manager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, dayStart, nowMs)
            .filter { it.packageName == pkg }
        val millis = stats.sumOf { it.totalTimeInForeground }
        return (millis / 1000L).toInt().coerceAtLeast(0)
    }

    private fun totalUsageSeconds(start: Long, end: Long): Int {
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val aggregated = manager.queryAndAggregateUsageStats(start, end)
            val totalMillis = aggregated.values.sumOf { it.totalTimeInForeground }
            return (totalMillis / 1000L).toInt().coerceAtLeast(0)
        }
        @Suppress("DEPRECATION")
        val legacy = manager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            start,
            end,
        ).orEmpty()
        val totalMillis = legacy
            .groupBy { it.packageName }
            .mapValues { (_, list) ->
                list.maxOfOrNull { it.totalTimeInForeground } ?: 0L
            }
            .values
            .sum()
        return (totalMillis / 1000L).toInt().coerceAtLeast(0)
    }

    /**
     * Apps with meaningful foreground time today (midnight → now) for the home list.
     */
    private fun buildRollingAppUsage(): List<Map<String, Any>> {
        AppIconCache.getRollingUsageIfFresh()?.let { return it }
        val built = buildRollingAppUsageUncached()
        AppIconCache.putRollingUsage(built)
        return built
    }

    private fun buildRollingAppUsageUncached(): List<Map<String, Any>> {
        val now = System.currentTimeMillis()
        val begin = startOfDay(now)
        val ourPkg = applicationContext.packageName
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val out = ArrayList<MutableMap<String, Any>>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val agg = manager.queryAndAggregateUsageStats(begin, now)
            for ((pkg, stats) in agg) {
                if (pkg.isBlank() || pkg == ourPkg) continue
                val ms = stats.totalTimeInForeground
                if (ms <= 0L) continue
                val label = AppDisplayName.resolve(applicationContext, pkg)
                out.add(
                    mutableMapOf(
                        "packageName" to pkg,
                        "appName" to label,
                        "totalTimeInForegroundMs" to ms,
                        "iconPngBase64" to AppIconCache.iconPngBase64(applicationContext, pkg),
                    ),
                )
            }
        } else {
            @Suppress("DEPRECATION")
            val legacy = manager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, begin, now)
                .groupBy { it.packageName }
                .mapValues { e -> e.value.sumOf { it.totalTimeInForeground } }
            for ((pkg, ms) in legacy) {
                if (pkg.isBlank() || pkg == ourPkg || ms <= 0L) continue
                val label = AppDisplayName.resolve(applicationContext, pkg)
                out.add(
                    mutableMapOf(
                        "packageName" to pkg,
                        "appName" to label,
                        "totalTimeInForegroundMs" to ms,
                        "iconPngBase64" to AppIconCache.iconPngBase64(applicationContext, pkg),
                    ),
                )
            }
        }
        out.sortByDescending { (it["totalTimeInForegroundMs"] as Number).toLong() }
        return out.take(48)
    }

    private fun topApps(start: Long, end: Long): List<Map<String, Any>> {
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val aggregated = manager.queryAndAggregateUsageStats(start, end)
            return aggregated.entries
                .filter { it.value.totalTimeInForeground > 0L }
                .sortedByDescending { it.value.totalTimeInForeground }
                .take(10)
                .map { item ->
                    val packageName = item.key
                    val appName = AppDisplayName.resolve(applicationContext, packageName)
                    mapOf(
                        "packageName" to packageName,
                        "appName" to appName,
                        "durationSeconds" to (item.value.totalTimeInForeground / 1000L).toInt(),
                        "iconPngBase64" to AppIconCache.iconPngBase64(applicationContext, packageName),
                    )
                }
        }
        @Suppress("DEPRECATION")
        val stats = manager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, start, end)
            .groupBy { it.packageName }
            .mapValues { entry -> entry.value.sumOf(UsageStats::getTotalTimeInForeground) }
            .filterValues { it > 0L }
            .entries
            .sortedByDescending { it.value }
            .take(10)

        return stats.map { item ->
            val packageName = item.key
            val appName = AppDisplayName.resolve(applicationContext, packageName)
            mapOf(
                "packageName" to packageName,
                "appName" to appName,
                "durationSeconds" to (item.value / 1000L).toInt(),
                "iconPngBase64" to iconPngBase64(packageName),
            )
        }
    }

    private fun startOfDay(timeMs: Long): Long {
        val cal = Calendar.getInstance()
        cal.timeInMillis = timeMs
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    private fun startOfWeek(timeMs: Long): Long {
        val cal = Calendar.getInstance(Locale.getDefault())
        cal.timeInMillis = timeMs
        val firstDay = cal.firstDayOfWeek
        while (cal.get(Calendar.DAY_OF_WEEK) != firstDay) {
            cal.add(Calendar.DAY_OF_YEAR, -1)
        }
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    private fun startOfMonth(timeMs: Long): Long {
        val cal = Calendar.getInstance()
        cal.timeInMillis = timeMs
        cal.set(Calendar.DAY_OF_MONTH, 1)
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }
}
