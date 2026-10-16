package com.example.frontend

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.pm.ServiceInfo
import android.app.usage.UsageEvents
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import android.media.AudioManager
import android.provider.Settings
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.HashSet
import java.util.Locale
import java.util.TimeZone

private const val ACTION_ENFORCE_NOW = "com.example.frontend.ACTION_ENFORCE_NOW"
private const val ACTION_SCREEN_CAPTURE_GRANTED = "com.example.frontend.ACTION_SCREEN_CAPTURE_GRANTED"
private const val ACTION_REQUEST_UNLOCK_VERIFY = "com.example.frontend.ACTION_REQUEST_UNLOCK_VERIFY"
private const val ACTION_BLOCKED_APPS_CHANGED = "com.example.frontend.ACTION_BLOCKED_APPS_CHANGED"

class BackgroundUsageService : Service() {
    /** null = untested; false = missing on this ROM (e.g. some API 34 builds). */
    @Volatile
    private var foregroundTypeUpdateSupported: Boolean? = null

    /** Latest foreground package resolved during [collectAndSync] (social / capture hints). */
    @Volatile
    internal var lastForegroundPackageHint: String? = null

    private val socialPackages = TrackedSocialApps.socialPackages
    private val videoPackages =
        TrackedSocialApps.socialPackages +
            setOf(
                "com.netflix.mediaclient",
                "com.amazon.avod.thirdpartyclient",
                "com.disney.disneyplus",
                "in.startv.hotstar",
            )
    private val browserPackages = setOf(
        "com.android.chrome",
        "com.microsoft.emmx",
        "org.mozilla.firefox",
        "com.opera.browser",
        "com.brave.browser",
    )

    private val handler = Handler(Looper.getMainLooper())
    private var syncWakeLock: PowerManager.WakeLock? = null
    private val pollIntervalMs = 15_000L
    private val monitoringIntervalMs = 1_000L
    private val enforceIntervalFastMs = 500L
    private lateinit var videoCaptureController: VideoCaptureController
    private lateinit var faceReactionController: FaceReactionController
    private lateinit var scheduledFaceCapture: ScheduledFaceCaptureController
    private lateinit var appMonitoringCoordinator: AppMonitoringCoordinator
    private lateinit var monitoringDb: MonitoringLocalDatabase
    private val unlockFaceVerifier by lazy { UnlockFaceVerifier(this, handler) }
    private var mediaProjectionForegroundElevated = false
    private var cameraForegroundElevated = false

    @Volatile
    private var accessibilityVideoPackage: String? = null
    @Volatile
    private var accessibilityVideoUntilMs: Long = 0L

    /** Remote blocked list from API; TTL refresh to reduce network churn. */
    private var cachedRemoteBlocked: Set<String> = emptySet()
    private var cachedRemoteBlockedLoadedAtMs: Long = 0L
    private var forceBlockedRemoteRefresh = false
    private var lastLocalVideoPurgeMs = 0L

    private val enforceRunnable = object : Runnable {
        override fun run() {
            try {
                if (!hasUsageAccess()) {
                    return
                }
                if (!TrackerPrefs.hasActiveAppBlockingRules(this@BackgroundUsageService)) {
                    return
                }
                val effective = mutableBlockedPackagesForPolicy()
                enforceBlockingAgainstForeground(effective)
            } finally {
                handler.postDelayed(this, enforcementDelayMs())
            }
        }
    }

    private val pollRunnable = object : Runnable {
        override fun run() {
            try {
                collectAndSync()
                MonitoredAppsCache.refreshAsync(this@BackgroundUsageService)
                MonitoringUploadQueue.processPending(this@BackgroundUsageService, maxItems = 5)
                maybePurgeOldLocalVideos()
            } finally {
                handler.postDelayed(this, pollIntervalMs)
            }
        }
    }

    /** 1 Hz: target-app foreground → screen + face monitoring (independent pipelines). */
    private val monitoringRunnable = object : Runnable {
        override fun run() {
            try {
                if (!hasUsageAccess()) {
                    if (::appMonitoringCoordinator.isInitialized) {
                        appMonitoringCoordinator.onForegroundTick(null)
                    }
                    return
                }
                // Foreground monitoring + recordings must run whenever logged in — not only after
                // unlock-face server sync (that gate applies to usage upload in collectAndSync).
                if (!TrackerPrefs.shouldAllowUsageCollection(this@BackgroundUsageService)) {
                    if (::appMonitoringCoordinator.isInitialized) {
                        appMonitoringCoordinator.onForegroundTick(null)
                    }
                    return
                }
                if (TrackerPrefs.shouldAllowUsageCollection(this@BackgroundUsageService)) {
                    UsageLimitEnforcer.onTrackingTick(this@BackgroundUsageService)
                }
                val foregroundPackage = ForegroundPackageResolver.lastPackage
                lastForegroundPackageHint = foregroundPackage
                val screenOn = isScreenInteractive()
                LateNightSleepTracker.tick(
                    this@BackgroundUsageService,
                    screenOn = screenOn,
                    foregroundPackage = foregroundPackage,
                )
                if (::appMonitoringCoordinator.isInitialized) {
                    appMonitoringCoordinator.onForegroundTick(foregroundPackage)
                } else {
                    TrackerPrefs.setBackgroundMonitoringState(
                        this@BackgroundUsageService,
                        monitoredAppName = "",
                        monitoredPackage = foregroundPackage ?: "",
                        serviceRunning = true,
                    )
                }
            } finally {
                if (TrackerPrefs.shouldAllowUsageCollection(this@BackgroundUsageService)) {
                    TrackerPrefs.setBackgroundMonitoringState(
                        this@BackgroundUsageService,
                        monitoredAppName = TrackerPrefs.backgroundMonitoredAppName(this@BackgroundUsageService),
                        monitoredPackage = lastForegroundPackageHint.orEmpty(),
                        serviceRunning = true,
                    )
                }
                handler.postDelayed(this, monitoringIntervalMs)
            }
        }
    }

    /** Fast when parental or local/server blocks matter; slower otherwise. */
    private fun enforcementDelayMs(): Long {
        val now = System.currentTimeMillis()
        val lockActive = TrackerPrefs.socialLockUntilMs(this) > now
        val fast =
            TrackerPrefs.parentalEnforcementEnabled(this) ||
                localBlockedPackages().isNotEmpty() ||
                lockActive ||
                cachedRemoteBlocked.isNotEmpty() ||
                TrackerPrefs.hasActiveAppBlockingRules(this)
        return if (fast) enforceIntervalFastMs else 3500L
    }
    private val blockedAppsReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ACTION_BLOCKED_APPS_CHANGED) return
            forceBlockedRemoteRefresh = true
            handler.post {
                if (!hasUsageAccess()) return@post
                enforceBlockingAgainstForeground(mutableBlockedPackagesForPolicy())
            }
        }
    }

    private var screenOnAtMs: Long = 0L
    private var lastUnlockVerifyAttemptMs: Long = 0L

    /** Monitored social app actually in foreground (ignores launcher / stale hints). */
    internal fun resolveMonitoredSocialForeground(): String? {
        if (!isScreenInteractive()) return null
        return ForegroundAppResolver.resolveRecordingForeground(
            this,
            ForegroundPackageResolver.lastPackage,
            packageName,
        )
    }

    private fun isMonitoredSocialForeground(): Boolean =
        resolveMonitoredSocialForeground() != null

    private fun maybeScheduleUnlockFaceVerify(force: Boolean = false) {
        if (!TrackerPrefs.faceVerified(this)) return
        if (CameraCaptureCoordinator.isFacialExpressionRecording()) return
        if (TrackerPrefs.isUnlockFaceCooldownActive(this)) {
            TrackerPrefs.setUnlockFaceSessionOk(this, true)
            return
        }
        if (TrackerPrefs.unlockFaceSessionOk(this)) return
        if (!isScreenInteractive()) return
        val now = System.currentTimeMillis()
        if (!force && now - lastUnlockVerifyAttemptMs < 45_000L) return
        lastUnlockVerifyAttemptMs = now
        unlockFaceVerifier.scheduleVerifyAfterUnlock()
    }

    private val screenOffReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_SCREEN_OFF) {
                if (TrackerPrefs.faceVerified(this@BackgroundUsageService)) {
                    if (!TrackerPrefs.isUnlockFaceCooldownActive(this@BackgroundUsageService)) {
                        TrackerPrefs.setUnlockFaceSessionOk(this@BackgroundUsageService, false)
                    }
                }
                // [unlockFaceVerifier] is `by lazy`, not `lateinit` — do not use ::isInitialized.
                unlockFaceVerifier.cancelPendingRetries()
                videoCaptureController.onScreenLockedOrOff()
                faceReactionController.onScreenOffOrLocked()
                if (::scheduledFaceCapture.isInitialized) {
                    scheduledFaceCapture.onScreenOffOrLocked()
                }
                ScreenTimeSessionStore.onScreenOff(applicationContext)
                LateNightSleepTracker.onScreenOff(applicationContext)
            }
        }
    }

    private val screenStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action ?: return
            val now = System.currentTimeMillis()
            if (action == Intent.ACTION_SCREEN_ON) {
                screenOnAtMs = now
                ScreenTimeSessionStore.onScreenOn(applicationContext)
                LateNightSleepTracker.onScreenOn(applicationContext)
                ForegroundPackageResolver.refreshAsync { pkg ->
                    handler.post { lastForegroundPackageHint = pkg }
                }
                postFaceVerificationEvent(
                    eventType = "screen_on",
                    unlockTimestampMs = null,
                    screenOnTimestampMs = now,
                    sessionDurationSeconds = 0,
                )
            } else if (action == Intent.ACTION_USER_PRESENT) {
                val sessionDurationSeconds = if (screenOnAtMs > 0L) {
                    ((now - screenOnAtMs) / 1000L).toInt().coerceAtLeast(0)
                } else {
                    0
                }
                postFaceVerificationEvent(
                    eventType = "unlock",
                    unlockTimestampMs = now,
                    screenOnTimestampMs = if (screenOnAtMs > 0L) screenOnAtMs else null,
                    sessionDurationSeconds = sessionDurationSeconds,
                )
                ForegroundPackageResolver.refreshAsync { pkg ->
                    handler.post {
                        lastForegroundPackageHint = pkg
                        maybeScheduleUnlockFaceVerify(force = true)
                    }
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        // Must run before any slow init — Android kills the process if startForeground()
        // is not called within a few seconds of startForegroundService().
        promoteForegroundImmediately()
        ScreenCapturePermissionStore.syncFromDisk(applicationContext)
        CameraCaptureCoordinator.syncFaceCooldownFromPrefs(applicationContext)
        monitoringDb = MonitoringLocalDatabase.getInstance(applicationContext)
        videoCaptureController = VideoCaptureController(applicationContext) { projectionActive ->
            setMediaProjectionForegroundServiceType(projectionActive)
        }
        faceReactionController = FaceReactionController(this, handler)
        scheduledFaceCapture = ScheduledFaceCaptureController(this, handler)
        appMonitoringCoordinator =
            AppMonitoringCoordinator(
                applicationContext,
                handler,
                videoCaptureController,
                scheduledFaceCapture,
                monitoringDb,
            )
        videoCaptureController.attachDatabase(appMonitoringCoordinator.database())
        scheduledFaceCapture.attachDatabase(appMonitoringCoordinator.database())
        if (TrackerPrefs.shouldAllowUsageCollection(this)) {
            scheduledFaceCapture.startScheduler()
        }
        MonitoredAppsCache.refreshAsync(this, force = true)
        ForegroundPackageResolver.start(this)
        if (TrackerPrefs.usageHealthSocialLimitActive(this)) {
            UsageLimitExpiryWorker.schedule(this)
        }
        val fg = if (hasUsageAccess()) ForegroundPackageResolver.lastPackage else null
        appMonitoringCoordinator.restoreSessionIfNeeded(fg)
        ForegroundPackageResolver.refreshAsync { pkg ->
            handler.post {
                if (::appMonitoringCoordinator.isInitialized) {
                    appMonitoringCoordinator.onForegroundTick(pkg)
                }
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                screenStateReceiver,
                IntentFilter().apply {
                    addAction(Intent.ACTION_SCREEN_ON)
                    addAction(Intent.ACTION_USER_PRESENT)
                },
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(
                screenStateReceiver,
                IntentFilter().apply {
                    addAction(Intent.ACTION_SCREEN_ON)
                    addAction(Intent.ACTION_USER_PRESENT)
                },
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                screenOffReceiver,
                IntentFilter(Intent.ACTION_SCREEN_OFF),
                Context.RECEIVER_NOT_EXPORTED,
            )
            registerReceiver(
                blockedAppsReceiver,
                IntentFilter(ACTION_BLOCKED_APPS_CHANGED),
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(
                screenOffReceiver,
                IntentFilter(Intent.ACTION_SCREEN_OFF),
            )
            @Suppress("DEPRECATION")
            registerReceiver(
                blockedAppsReceiver,
                IntentFilter(ACTION_BLOCKED_APPS_CHANGED),
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Each startForegroundService() on API 31+ requires a matching startForeground() here.
        promoteForegroundImmediately()
        if (intent?.action == ACTION_REQUEST_UNLOCK_VERIFY) {
            maybeScheduleUnlockFaceVerify(force = true)
        }
        if (intent?.action == ACTION_VIDEO_APP_FOREGROUND) {
            val pkg = intent.getStringExtra(EXTRA_VIDEO_PACKAGE)
            if (!pkg.isNullOrBlank()) {
                accessibilityVideoPackage = pkg
                accessibilityVideoUntilMs = System.currentTimeMillis() + 90_000L
                collectAndSync()
            }
        }
        if (intent?.action == ACTION_ENFORCE_NOW) {
            forceBlockedRemoteRefresh = true
            handler.post {
                if (TrackerPrefs.hasActiveAppBlockingRules(this)) {
                    enforceBlockingAgainstForeground(mutableBlockedPackagesForPolicy())
                }
            }
            collectAndSync()
        }
        if (intent?.action == ACTION_SCREEN_CAPTURE_GRANTED) {
            ScreenCapturePermissionStore.syncFromDisk(applicationContext)
            MindSyncMonitor.onScreenCaptureGranted(applicationContext)
            if (::videoCaptureController.isInitialized) {
                setMediaProjectionForegroundServiceType(true)
                videoCaptureController.warmUpProjection()
            }
            collectAndSync()
            if (::appMonitoringCoordinator.isInitialized) {
                val fg = if (hasUsageAccess()) ForegroundPackageResolver.lastPackage else null
                appMonitoringCoordinator.onForegroundTick(fg)
            }
        }
        if (TrackerPrefs.shouldAllowUsageCollection(this) && ::scheduledFaceCapture.isInitialized) {
            scheduledFaceCapture.startScheduler()
        }
        handler.removeCallbacks(pollRunnable)
        handler.removeCallbacks(monitoringRunnable)
        handler.removeCallbacks(enforceRunnable)
        handler.post(pollRunnable)
        handler.post(monitoringRunnable)
        handler.post(enforceRunnable)
        maybeScheduleUnlockFaceVerify(force = true)
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (TrackerPrefs.shouldAllowUsageCollection(this)) {
            deliverStart(applicationContext, Intent(this, BackgroundUsageService::class.java))
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        AppIconCache.onTrimMemory(level)
        if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL) {
            MonitoringLog.w("Low memory — trimming monitoring caches")
            AppIconCache.invalidateRollingUsage()
        }
    }

    override fun onDestroy() {
        instance = null
        ForegroundPackageResolver.stop()
        releaseSyncWakeLock()
        handler.removeCallbacks(pollRunnable)
        handler.removeCallbacks(monitoringRunnable)
        handler.removeCallbacks(enforceRunnable)
        videoCaptureController.release()
        if (::appMonitoringCoordinator.isInitialized) {
            appMonitoringCoordinator.release()
        }
        if (::faceReactionController.isInitialized) {
            faceReactionController.release()
        }
        if (::scheduledFaceCapture.isInitialized) {
            scheduledFaceCapture.release()
        }
        TrackerPrefs.setBackgroundMonitoringState(applicationContext, "", "", false)
        runCatching { unregisterReceiver(screenStateReceiver) }
        runCatching { unregisterReceiver(screenOffReceiver) }
        runCatching { unregisterReceiver(blockedAppsReceiver) }
        super.onDestroy()
    }

    private fun isScreenInteractive(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isInteractive
    }

    private fun collectAndSync() {
        if (!hasUsageAccess()) {
            faceReactionController.onVideoConsumptionLikely(
                videoLikely = false,
                packageName = "",
                appDisplayName = "",
                nowMs = System.currentTimeMillis(),
            )
            return
        }
        if (!TrackerPrefs.shouldAllowUsageCollection(this)) {
            faceReactionController.onVideoConsumptionLikely(
                videoLikely = false,
                packageName = "",
                appDisplayName = "",
                nowMs = System.currentTimeMillis(),
            )
            if (::scheduledFaceCapture.isInitialized) {
                scheduledFaceCapture.stopScheduler()
            }
            return
        }

        maybeScheduleUnlockFaceVerify()

        val canRecordUsage = TrackerPrefs.shouldAllowUsageCollection(this)
        val canSyncUsage = TrackerPrefs.shouldSyncUsageStats(this)
        val uid = TrackerPrefs.userId(this)

        // No usage deltas while screen is off (idle / background).
        if (!isScreenInteractive()) {
            faceReactionController.onVideoConsumptionLikely(
                videoLikely = false,
                packageName = "",
                appDisplayName = "",
                nowMs = System.currentTimeMillis(),
            )
            return
        }

        val usageManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val dayStart = startOfDay(now)
        val totals = usageManager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, dayStart, now)
            .filter { it.totalTimeInForeground > 0L }
            .associateBy({ it.packageName }, { it.totalTimeInForeground })

        val lastJson = JSONObject(TrackerPrefs.lastTotalsJson(this))
        val newJson = JSONObject()
        var deltaTotalSeconds = 0
        var deltaSocialSeconds = 0
        var deltaVideoSeconds = 0
        val foregroundPackage = ForegroundPackageResolver.lastPackage
        lastForegroundPackageHint = foregroundPackage
        for ((pkg, totalMs) in totals) {
            newJson.put(pkg, totalMs)
        }
        val activePkg =
            foregroundPackage?.takeIf {
                it.isNotBlank() && it != applicationContext.packageName
            }
        if (activePkg != null && totals.containsKey(activePkg)) {
            val totalMs = totals.getValue(activePkg)
            val oldMs = if (lastJson.has(activePkg)) lastJson.optLong(activePkg, 0L) else 0L
            val deltaMs = totalMs - oldMs
            if (deltaMs > 0L) {
                val appName = resolveAppName(activePkg)
                val seconds = (deltaMs / 1000L).toInt()
                deltaTotalSeconds += seconds
                if (socialPackages.contains(activePkg)) deltaSocialSeconds += seconds
                if (videoPackages.contains(activePkg)) deltaVideoSeconds += seconds
                if (canRecordUsage) {
                    postUsageEvent(
                        packageName = activePkg,
                        appName = appName,
                        usageSeconds = seconds,
                    )
                }
                if (uid.isNotBlank() && canSyncUsage) {
                    UsagePeriodStore.addForegroundMs(this, uid, deltaMs)
                }
            }
        }
        TrackerPrefs.saveLastTotalsJson(this, newJson.toString())
        if (canRecordUsage &&
            (deltaTotalSeconds > 0 || deltaSocialSeconds > 0 || deltaVideoSeconds > 0)
        ) {
            postScreenTimeDelta(
                deltaTotal = deltaTotalSeconds,
                deltaSocial = deltaSocialSeconds,
                deltaVideo = deltaVideoSeconds,
            )
        }
        updateSocialLimitLockIfNeeded(now)
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val nowMs = System.currentTimeMillis()
        val accessibilityVideoActive =
            accessibilityVideoPackage != null && nowMs < accessibilityVideoUntilMs
        val videoPkg =
            if (accessibilityVideoActive) {
                accessibilityVideoPackage
            } else {
                foregroundPackage
            }
        val videoConsumptionLikely =
            accessibilityVideoActive ||
                isForegroundVideoConsumption(foregroundPackage, audioManager)
        val appLabel = resolveAppName(foregroundPackage ?: "")
        faceReactionController.onVideoConsumptionLikely(
            videoLikely = videoConsumptionLikely,
            packageName = videoPkg ?: foregroundPackage ?: "",
            appDisplayName = resolveAppName(videoPkg ?: foregroundPackage ?: ""),
            nowMs = nowMs,
        )
    }

    private fun acquireSyncWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (syncWakeLock?.isHeld == true) return
            @Suppress("DEPRECATION")
            syncWakeLock =
                pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MindSync:usageSync").apply {
                    setReferenceCounted(false)
                    acquire(45_000L)
                }
        } catch (e: Exception) {
            Log.w(LOG_TAG, "wakeLock acquire failed: ${e.message}")
        }
    }

    private fun releaseSyncWakeLock() {
        try {
            syncWakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        syncWakeLock = null
    }

    private fun postScreenTimeDelta(deltaTotal: Int, deltaSocial: Int, deltaVideo: Int) {
        val baseUrl = TrackerPrefs.baseUrl(this)
        val token = TrackerPrefs.token(this)
        if (baseUrl.isBlank() || token.isBlank()) return

        val payload = JSONObject()
            .put("mode", "delta")
            .put("delta_total", deltaTotal)
            .put("delta_social", deltaSocial)
            .put("delta_video", deltaVideo)
            .toString()

        acquireSyncWakeLock()
        try {
            val url = URL("${baseUrl.trimEnd('/')}/api/screen-time/update/")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 5000
                readTimeout = 7000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Authorization", "Bearer $token")
            }
            conn.outputStream.use { it.write(payload.toByteArray(Charsets.UTF_8)) }
            conn.inputStream.close()
            conn.disconnect()
        } catch (_: Exception) {
            // Silent retry on next tick.
        } finally {
            releaseSyncWakeLock()
        }
    }


    private fun resolvePlatformName(packageName: String): String {
        val p = packageName.lowercase(Locale.US)
        return when {
            p.contains("youtube") -> "YouTube"
            p.contains("instagram") -> "Instagram"
            p.contains("musically") || p.contains("trill") || p.contains("tiktok") -> "TikTok"
            p.contains("reddit") -> "Reddit"
            p.contains("facebook") -> "Facebook"
            p.contains("netflix") -> "Netflix"
            p.contains("disney") -> "Disney+"
            p.contains("hotstar") -> "Hotstar"
            p.contains("amazon.avod") || p.contains("primevideo") -> "Prime Video"
            browserPackages.contains(packageName) -> "Browser"
            p.contains("snapchat") -> "Snapchat"
            p.contains("whatsapp") -> "WhatsApp"
            p.contains("twitter") || p == "com.x.android" -> "X"
            else -> "Other"
        }
    }

    private fun maybePurgeOldLocalVideos() {
        val now = System.currentTimeMillis()
        if (now - lastLocalVideoPurgeMs < 60 * 60 * 1000L) return
        lastLocalVideoPurgeMs = now
        MonitoringStorage.purgeVideosOlderThan(
            applicationContext,
            MonitoringStorage.DEFAULT_RETENTION_MS,
        )
    }

    /** Video consumption heuristic (no MediaProjection requirement). */
    private fun isForegroundVideoConsumption(
        packageName: String?,
        audioManager: AudioManager,
    ): Boolean {
        if (packageName.isNullOrBlank()) return false
        val p = packageName.lowercase(Locale.US)
        if (p.startsWith("com.android.systemui")) return false
        if (packageName == applicationContext.packageName) return false
        if (browserPackages.contains(packageName)) {
            return audioManager.isMusicActive
        }
        if (videoPackages.contains(packageName)) {
            return true
        }
        return false
    }

    /**
     * Screen capture only when MediaProjection is granted **and** [isForegroundVideoConsumption].
     */
    private fun shouldRecordForegroundPlayback(
        packageName: String?,
        audioManager: AudioManager,
    ): Boolean {
        if (!ScreenCapturePermissionStore.hasPermission(applicationContext)) return false
        return isForegroundVideoConsumption(packageName, audioManager)
    }

    /**
     * API 34+: elevate FGS types when camera / MediaProjection runs.
     * Returns false if the platform method is absent (uncaught reflection used to crash here).
     */
    private fun invokeUpdateForegroundServiceType(types: Int): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        if (foregroundTypeUpdateSupported == false) return false
        return try {
            Service::class.java
                .getMethod("updateForegroundServiceType", Int::class.javaPrimitiveType)
                .invoke(this, types)
            foregroundTypeUpdateSupported = true
            true
        } catch (e: NoSuchMethodException) {
            foregroundTypeUpdateSupported = false
            Log.w(
                LOG_TAG,
                "updateForegroundServiceType missing on API ${Build.VERSION.SDK_INT}; " +
                    "will fall back to startForeground",
            )
            false
        } catch (e: SecurityException) {
            throw e
        } catch (e: java.lang.reflect.InvocationTargetException) {
            val target = e.targetException
            if (target is SecurityException) throw target
            foregroundTypeUpdateSupported = false
            Log.w(LOG_TAG, "updateForegroundServiceType failed", target ?: e)
            false
        } catch (e: Throwable) {
            foregroundTypeUpdateSupported = false
            Log.w(LOG_TAG, "updateForegroundServiceType failed", e)
            false
        }
    }

    private fun combinedForegroundServiceTypes(): Int {
        var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        if (mediaProjectionForegroundElevated) {
            types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
        }
        if (cameraForegroundElevated) {
            types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
        }
        return types
    }

    private var lastForegroundNotificationText: String? = null

    private fun foregroundNotificationText(): String =
        when {
            cameraForegroundElevated && mediaProjectionForegroundElevated ->
                "MindSync · screen + face analysis"
            cameraForegroundElevated ->
                "MindSync · face reactions (20s)"
            mediaProjectionForegroundElevated ->
                "Analyzing on-screen video (30s segments)"
            else ->
                "Screen time & wellness tracking is active"
        }

    private fun notifyTrackerForegroundState() {
        val text = foregroundNotificationText()
        if (text == lastForegroundNotificationText) return
        lastForegroundNotificationText = text
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(7301, buildNotification(text = text))
    }

    private fun syncForegroundServiceTypes() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            notifyTrackerForegroundState()
            return
        }
        val types = combinedForegroundServiceTypes()
        val text = foregroundNotificationText()
        lastForegroundNotificationText = text
        val notification = buildNotification(text = text)
        if (!invokeUpdateForegroundServiceType(types)) {
            try {
                startForeground(7301, notification, types)
                foregroundTypeUpdateSupported = true
            } catch (e: SecurityException) {
                throw e
            } catch (e: Throwable) {
                Log.w(LOG_TAG, "startForeground FGS type sync failed: ${e.message}")
            }
        }
        notifyTrackerForegroundState()
    }

    private fun setMediaProjectionForegroundServiceType(projectionCaptureActive: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        if (projectionCaptureActive == mediaProjectionForegroundElevated) return
        mediaProjectionForegroundElevated = projectionCaptureActive
        try {
            syncForegroundServiceTypes()
        } catch (_: SecurityException) {
            mediaProjectionForegroundElevated = false
            videoCaptureController.onForegroundTypeDenied()
            try {
                syncForegroundServiceTypes()
            } catch (_: SecurityException) {
            }
        }
    }

    internal fun setCameraForegroundElevated(active: Boolean) {
        if (active == cameraForegroundElevated) return
        cameraForegroundElevated = active
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            handler.removeCallbacks(syncForegroundTypesRunnable)
            handler.postDelayed(syncForegroundTypesRunnable, 150L)
        } else {
            notifyTrackerForegroundState()
        }
    }

    private val syncForegroundTypesRunnable = Runnable {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return@Runnable
        try {
            syncForegroundServiceTypes()
        } catch (_: SecurityException) {
            cameraForegroundElevated = false
            faceReactionController.onCameraForegroundDenied()
            try {
                syncForegroundServiceTypes()
            } catch (_: SecurityException) {
            }
        }
    }

    /** Backup limit check on the 15s usage sync tick (primary check is 1 Hz in monitoring loop). */
    private fun updateSocialLimitLockIfNeeded(@Suppress("UNUSED_PARAMETER") now: Long) {
        UsageLimitEnforcer.onTrackingTick(this)
    }

    /** Parental blocks — hot path; avoid heavy usage queries here. */
    private fun mutableBlockedPackagesForPolicy(): MutableSet<String> {
        return HashSet(BlockEnforcementHelper.packagesToBlock(this))
    }

    private fun enforceBlockingAgainstForeground(@Suppress("UNUSED_PARAMETER") effectiveBlocked: Set<String>) {
        if (!TrackerPrefs.hasActiveAppBlockingRules(this)) return
        val currentForeground = ForegroundPackageResolver.lastPackage
        BlockEnforcementHelper.enforceIfBlocked(this, currentForeground)
        if (currentForeground.isNullOrBlank()) return
        if (!BlockEnforcementHelper.isPackageBlocked(this, currentForeground)) return
        tryStartBlockOverlay(currentForeground)
    }

    private fun tryStartBlockOverlay(blockedPackage: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            return
        }
        try {
            val i =
                Intent(this, BlockedAppOverlayActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    putExtra(BlockedAppOverlayActivity.EXTRA_BLOCKED_PACKAGE, blockedPackage)
                }
            startActivity(i)
        } catch (_: Exception) {
        }
    }

    private fun burstGoHome() {
        goHome()
        for (i in 1..6) {
            handler.postDelayed({ goHome() }, 80L * i)
        }
    }

    private fun remoteBlockedPackagesCached(): Set<String> {
        val baseUrl = TrackerPrefs.baseUrl(this)
        val token = TrackerPrefs.token(this)
        if (baseUrl.isBlank() || token.isBlank()) return emptySet()

        val now = System.currentTimeMillis()
        val needsFrequentSync =
            TrackerPrefs.parentalEnforcementEnabled(this) ||
                localBlockedPackages().isNotEmpty()
        val ttlMs = if (needsFrequentSync) 12_000L else 120_000L

        if (!forceBlockedRemoteRefresh && cachedRemoteBlockedLoadedAtMs > 0L &&
            (now - cachedRemoteBlockedLoadedAtMs) < ttlMs
        ) {
            return cachedRemoteBlocked
        }
        forceBlockedRemoteRefresh = false

        val fetched = fetchRemoteBlockedFromNetwork("${baseUrl.trimEnd('/')}", token)
        cachedRemoteBlocked = fetched
        cachedRemoteBlockedLoadedAtMs = now
        return fetched
    }

    private fun fetchRemoteBlockedFromNetwork(baseUrlTrimmed: String, token: String): Set<String> {
        return try {
            val url = URL("$baseUrlTrimmed/api/auth/child/blocked-packages/")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 5000
                readTimeout = 7000
                setRequestProperty("Authorization", "Bearer $token")
            }
            val raw = conn.inputStream.bufferedReader().use { it.readText() }
            conn.disconnect()
            val json = JSONObject(raw)
            val arr = json.optJSONArray("blocked_packages")
            val set = HashSet<String>()
            if (arr != null) {
                for (i in 0 until arr.length()) {
                    val pkg = arr.optString(i, "")
                    if (pkg.isNotBlank()) set.add(pkg)
                }
            }
            set
        } catch (_: Exception) {
            cachedRemoteBlocked
        }
    }

    private fun readTodaySocialUsageMs(): Long {
        val usageManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val dayStart = startOfDay(now)
        val stats = usageManager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, dayStart, now)
        return stats
            .filter { socialPackages.contains(it.packageName) }
            .sumOf { it.totalTimeInForeground }
    }

    private fun localBlockedPackages(): Set<String> {
        return try {
            val raw = TrackerPrefs.localBlockedPackagesJson(this)
            val obj = JSONObject(raw)
            val out = HashSet<String>()
            val keys = obj.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                if (obj.optBoolean(k, false)) out.add(k)
            }
            out
        } catch (_: Exception) {
            emptySet()
        }
    }


    private fun goHome() {
        if (MindSyncAccessibilityBridge.sendHome()) return
        try {
            val intent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
        } catch (_: Exception) {
        }
    }

    private fun postUsageEvent(packageName: String, appName: String, usageSeconds: Int) {
        if (usageSeconds <= 0) return
        val baseUrl = TrackerPrefs.baseUrl(this)
        val token = TrackerPrefs.token(this)
        if (baseUrl.isBlank() || token.isBlank()) return

        val now = Date()
        val isoDate = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = TimeZone.getDefault()
        }.format(now)
        val isoDateTime = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(now)

        val payload = JSONObject()
            .put("app_name", appName)
            .put("package_name", packageName)
            .put("usage_time", usageSeconds)
            .put("date", isoDate)
            .put("start_time", isoDateTime)
            .put("end_time", isoDateTime)
            .toString()

        try {
            val url = URL("${baseUrl.trimEnd('/')}/api/auth/track-usage/")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 5000
                readTimeout = 7000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Authorization", "Bearer $token")
            }
            conn.outputStream.use { it.write(payload.toByteArray(Charsets.UTF_8)) }
            conn.inputStream.close()
            conn.disconnect()
        } catch (_: Exception) {
            // Keep service resilient; transient failures will retry next ticks.
        }
    }

    private fun postFaceVerificationEvent(
        eventType: String,
        unlockTimestampMs: Long?,
        screenOnTimestampMs: Long?,
        sessionDurationSeconds: Int,
    ) {
        val baseUrl = TrackerPrefs.baseUrl(this)
        val token = TrackerPrefs.token(this)
        if (baseUrl.isBlank() || token.isBlank()) return

        val usageManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val dayStart = startOfDay(now)
        val todayStats = usageManager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, dayStart, now)
        val totalSeconds = (todayStats.sumOf { it.totalTimeInForeground } / 1000L).toInt()
        val socialSeconds = (todayStats.filter { socialPackages.contains(it.packageName) }
            .sumOf { it.totalTimeInForeground } / 1000L).toInt()
        val videoSeconds = (todayStats.filter { videoPackages.contains(it.packageName) }
            .sumOf { it.totalTimeInForeground } / 1000L).toInt()

        val appUsageStats = JSONObject()
            .put("day_total_seconds", totalSeconds)
            .put("day_social_seconds", socialSeconds)
            .put("day_video_seconds", videoSeconds)

        val payload = JSONObject()
            .put("event_type", eventType)
            .put("unlock_timestamp", unlockTimestampMs?.let { toIsoUtc(it) })
            .put("screen_on_timestamp", screenOnTimestampMs?.let { toIsoUtc(it) })
            .put("session_duration_seconds", sessionDurationSeconds)
            .put("verified_face_match_percent", TrackerPrefs.faceMatchPercent(this))
            .put("app_usage_stats", appUsageStats)
            .toString()

        try {
            val url = URL("${baseUrl.trimEnd('/')}/api/face-verification/events/")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 5000
                readTimeout = 7000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Authorization", "Bearer $token")
            }
            conn.outputStream.use { it.write(payload.toByteArray(Charsets.UTF_8)) }
            conn.inputStream.close()
            conn.disconnect()
        } catch (_: Exception) {
            // Keep tracker resilient.
        }
    }

    private fun toIsoUtc(timestampMs: Long): String {
        return SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date(timestampMs))
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as android.app.AppOpsManager
        val mode = appOps.checkOpNoThrow(
            "android:get_usage_stats",
            android.os.Process.myUid(),
            packageName,
        )
        return mode == android.app.AppOpsManager.MODE_ALLOWED
    }

    private fun resolveAppName(packageName: String): String {
        return AppDisplayName.resolve(this, packageName)
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

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel =
                NotificationChannel(
                    TRACKER_CHANNEL_ID,
                    "MindSync Background Tracker",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Silent status while screen and face tracking is active"
                    setSound(null, null)
                    enableVibration(false)
                    setShowBadge(false)
                }
            manager.createNotificationChannel(channel)
            val alerts =
                NotificationChannel(
                    ALERTS_CHANNEL_ID,
                    "MindSync alerts",
                    NotificationManager.IMPORTANCE_HIGH,
                )
            manager.createNotificationChannel(alerts)
        }
    }

    /** Face matched (≥80%) — start counting immediately for this user session. */
    internal fun onUnlockFaceVerifiedForTracking() {
        handler.post { collectAndSync() }
    }

    /** Notifications removed — unlock verification is silent; failures retry in the background. */
    internal fun showUnlockFaceReverifyNotification(message: String) {
        Log.d(LOG_TAG, "Unlock verify (silent): $message")
    }

    /** Satisfies the FGS deadline before heavy camera / usage init. */
    private fun promoteForegroundImmediately() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                7301,
                buildNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(7301, buildNotification())
        }
    }

    private fun buildNotification(
        title: String = "MindSync",
        text: String = "Screen time & wellness tracking is active",
    ): Notification {
        return NotificationCompat.Builder(this, TRACKER_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    setForegroundServiceBehavior(
                        NotificationCompat.FOREGROUND_SERVICE_DEFERRED,
                    )
                }
            }
            .build()
    }

    companion object {
        private const val LOG_TAG = "BackgroundUsageService"
        internal const val TRACKER_CHANNEL_ID = "mindsync_tracker"
        internal const val ALERTS_CHANNEL_ID = "mindsync_alerts"
        const val ACTION_VIDEO_APP_FOREGROUND = "com.example.frontend.ACTION_VIDEO_APP_FOREGROUND"
        const val EXTRA_VIDEO_PACKAGE = "video_package"

        @Volatile
        private var instance: BackgroundUsageService? = null

        /** True while this process has a live [BackgroundUsageService]. */
        fun isRunning(): Boolean = instance != null

        /**
         * If the service is already foreground, use [Context.startService] so we do not
         * trigger another startForegroundService() deadline (crashes on API 31+).
         */
        private fun deliverStart(context: Context, intent: Intent) {
            try {
                if (instance != null) {
                    context.startService(intent)
                    return
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: IllegalStateException) {
                Log.w(LOG_TAG, "deliverStart failed: ${e.message}")
            } catch (e: Exception) {
                if (e.javaClass.simpleName == "ForegroundServiceStartNotAllowedException") {
                    Log.w(LOG_TAG, "FGS not allowed in background: ${e.message}")
                } else {
                    throw e
                }
            }
        }

        fun start(context: Context) {
            deliverStart(context, Intent(context, BackgroundUsageService::class.java))
        }

        /** Used by [VideoPlaybackDetectorService] when a tracked app enters the foreground. */
        fun deliverStartFromAccessibility(context: Context, intent: Intent) {
            deliverStart(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, BackgroundUsageService::class.java))
        }

        fun requestImmediateEnforcement(context: Context) {
            val intent = Intent(context, BackgroundUsageService::class.java).apply {
                action = ACTION_ENFORCE_NOW
            }
            deliverStart(context, intent)
        }

        /** Pre-elevate MediaProjection FGS type after the user grants screen capture. */
        fun notifyScreenCaptureGranted(context: Context) {
            val intent = Intent(context, BackgroundUsageService::class.java).apply {
                action = ACTION_SCREEN_CAPTURE_GRANTED
            }
            deliverStart(context, intent)
        }

        /**
         * Re-run unlock face capture when the session is not verified.
         * No-op if the tracker service is not running (configureTracker / start() will schedule verify).
         */
        fun requestUnlockFaceVerify(context: Context) {
            if (!TrackerPrefs.faceVerified(context)) return
            if (TrackerPrefs.isUnlockFaceCooldownActive(context)) return
            if (TrackerPrefs.unlockFaceSessionOk(context)) return
            if (instance == null) {
                if (TrackerPrefs.shouldAllowUsageCollection(context)) {
                    start(context)
                }
                return
            }
            val intent = Intent(context, BackgroundUsageService::class.java).apply {
                action = ACTION_REQUEST_UNLOCK_VERIFY
            }
            deliverStart(context, intent)
        }

        /** After SharedPreferences block list changes, wake the foreground service enforcement loop. */
        fun notifyBlockedAppsChanged(context: Context) {
            val i =
                Intent("com.example.frontend.ACTION_BLOCKED_APPS_CHANGED")
                    .setPackage(context.packageName)
            context.sendBroadcast(i)
        }
    }
}
