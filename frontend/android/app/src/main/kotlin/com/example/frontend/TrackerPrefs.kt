package com.example.frontend

import android.content.Context

object TrackerPrefs {
    private const val PREFS = "mindsync_tracker_prefs"
    private const val KEY_BASE_URL = "base_url"
    private const val KEY_TOKEN = "token"
    private const val KEY_USER_ID = "user_id"
    private const val KEY_FACE_VERIFIED = "face_verified"
    private const val KEY_LAST_TOTALS = "last_totals_json"
    private const val KEY_SOCIAL_LIMIT_MINUTES = "social_limit_minutes"
    private const val KEY_GAMING_LIMIT_MINUTES = "gaming_limit_minutes"
    private const val KEY_ENTERTAINMENT_LIMIT_MINUTES = "entertainment_limit_minutes"
    private const val KEY_SOCIAL_LOCK_UNTIL_MS = "social_lock_until_ms"
    private const val KEY_VIDEO_ACCUM_SECONDS = "video_accum_seconds"
    private const val KEY_RECORDING_ACTIVE = "recording_active"
    private const val KEY_LAST_VIDEO_PLATFORM = "last_video_platform"
    private const val KEY_LAST_VIDEO_PACKAGE = "last_video_package"
    private const val KEY_LAST_VIDEO_UPLOAD_ERROR = "last_video_upload_error"
    private const val KEY_FACE_MATCH_PERCENT = "face_match_percent"
    private const val KEY_PARENTAL_ENFORCEMENT_ENABLED = "parental_enforcement_enabled"
    private const val KEY_LOCAL_BLOCKED_PACKAGES = "local_blocked_packages_json"
    private const val KEY_HOME_BLOCKED_PACKAGES_JSON = "home_blocked_packages_json"
    private const val KEY_FACE_REACTION_COOLDOWN_UNTIL_MS = "face_reaction_cooldown_until_ms"
    private const val KEY_FACE_REACTION_RECORDING = "face_reaction_recording_active"
    private const val KEY_FACE_REACTION_LAST_ERROR = "face_reaction_last_error"
    private const val KEY_LAST_SCHEDULED_FACE_CAPTURE_MS = "last_scheduled_face_capture_ms"
    private const val KEY_MONITORING_SOCIAL_SESSION_PKG = "monitoring_social_session_pkg"
    private const val KEY_UNLOCK_FACE_SESSION_OK = "unlock_face_session_ok"
    private const val KEY_UNLOCK_FACE_LAST_ERROR = "unlock_face_last_error"
    private const val KEY_UNLOCK_FACE_LAST_SUCCESS_MS = "unlock_face_last_success_ms"
    private const val KEY_FACE_MATCH_PAUSE_UNTIL_MS = "face_match_pause_until_ms"
    private const val KEY_BG_MONITORED_APP = "bg_monitored_app_name"
    private const val KEY_BG_MONITORED_PKG = "bg_monitored_package"
    private const val KEY_BG_LAST_TICK_MS = "bg_monitoring_last_tick_ms"
    private const val KEY_BG_SERVICE_RUNNING = "bg_service_running"
    private const val KEY_ACTIVE_USER_ID = "active_user_id"
    private const val KEY_SCREEN_CAPTURE_ONBOARDING_DONE = "screen_capture_onboarding_done"
    private const val KEY_USAGE_HEALTH_SOCIAL_LIMIT_MINUTES = "usage_health_social_limit_minutes"
    private const val KEY_USAGE_HEALTH_SOCIAL_LIMIT_SET_AT_MS = "usage_health_social_limit_set_at_ms"
    private const val KEY_USAGE_HEALTH_SHOW_EXPIRED = "usage_health_show_expired"
    const val USAGE_HEALTH_LIMIT_EXPIRY_MS = 12L * 60L * 60L * 1000L
    private const val PREFS_SCREEN_SESSION = "mindsync_screen_session"

    fun writeConfig(
        context: Context,
        baseUrl: String,
        token: String,
        userId: String,
        faceVerified: Boolean,
        faceMatchPercent: Double,
        screenCaptureOnboardingDone: Boolean = false,
    ) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_BASE_URL, NetworkConfig.effectiveBaseUrl(baseUrl))
            .putString(KEY_TOKEN, token)
            .putString(KEY_USER_ID, userId)
            .putBoolean(KEY_FACE_VERIFIED, faceVerified)
            .putFloat(
                KEY_FACE_MATCH_PERCENT,
                if (faceMatchPercent > 0.0) faceMatchPercent.toFloat() else 50f,
            )
            .putBoolean(KEY_SCREEN_CAPTURE_ONBOARDING_DONE, screenCaptureOnboardingDone)
            .putBoolean(KEY_UNLOCK_FACE_SESSION_OK, !faceVerified)
            .putString(KEY_UNLOCK_FACE_LAST_ERROR, "")
            .apply()
    }

    fun screenCaptureOnboardingDone(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_SCREEN_CAPTURE_ONBOARDING_DONE, false) ||
            ScreenCapturePermissionStore.hasPermission(context)

    fun markScreenCaptureOnboardingDone(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_SCREEN_CAPTURE_ONBOARDING_DONE, true)
            .apply()
    }

    fun baseUrl(context: Context): String {
        val stored =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_BASE_URL, "")
                ?: ""
        return NetworkConfig.effectiveBaseUrl(stored)
    }

    fun token(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_TOKEN, "") ?: ""

    fun userId(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_USER_ID, "") ?: ""

    fun faceVerified(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_FACE_VERIFIED, false)

    fun shouldTrack(context: Context): Boolean =
        faceVerified(context) && token(context).isNotBlank() && userId(context).isNotBlank()

    fun lastTotalsJson(context: Context): String {
        val uid = userId(context)
        val key = if (uid.isBlank()) KEY_LAST_TOTALS else "${KEY_LAST_TOTALS}_$uid"
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(key, "{}") ?: "{}"
    }

    fun saveLastTotalsJson(context: Context, json: String) {
        val uid = userId(context)
        val key = if (uid.isBlank()) KEY_LAST_TOTALS else "${KEY_LAST_TOTALS}_$uid"
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(key, json)
            .apply()
    }

    fun setLimits(
        context: Context,
        socialMinutes: Int,
        gamingMinutes: Int,
        entertainmentMinutes: Int,
    ) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_SOCIAL_LIMIT_MINUTES, socialMinutes)
            .putInt(KEY_GAMING_LIMIT_MINUTES, gamingMinutes)
            .putInt(KEY_ENTERTAINMENT_LIMIT_MINUTES, entertainmentMinutes)
            .apply()
    }

    fun socialLimitMinutes(context: Context): Int =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getInt(KEY_SOCIAL_LIMIT_MINUTES, 90)

    fun usageHealthSocialLimitMinutes(context: Context): Int =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getInt(KEY_USAGE_HEALTH_SOCIAL_LIMIT_MINUTES, 0)

    fun usageHealthSocialLimitSetAtMs(context: Context): Long =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getLong(KEY_USAGE_HEALTH_SOCIAL_LIMIT_SET_AT_MS, 0L)

    fun setUsageHealthSocialLimit(context: Context, limitMinutes: Int, setAtMs: Long) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_USAGE_HEALTH_SOCIAL_LIMIT_MINUTES, maxOf(0, limitMinutes))
            .putLong(KEY_USAGE_HEALTH_SOCIAL_LIMIT_SET_AT_MS, maxOf(0L, setAtMs))
            .apply()
    }

    fun clearUsageHealthSocialLimit(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_USAGE_HEALTH_SOCIAL_LIMIT_MINUTES)
            .remove(KEY_USAGE_HEALTH_SOCIAL_LIMIT_SET_AT_MS)
            .apply()
        clearSocialLimitLock(context)
    }

    fun usageHealthSocialLimitActive(context: Context, nowMs: Long = System.currentTimeMillis()): Boolean {
        val limit = usageHealthSocialLimitMinutes(context)
        val setAt = usageHealthSocialLimitSetAtMs(context)
        if (limit <= 0 || setAt <= 0L) return false
        return nowMs < setAt + USAGE_HEALTH_LIMIT_EXPIRY_MS
    }

    fun clearUsageHealthSocialLimitIfExpired(context: Context) {
        val setAt = usageHealthSocialLimitSetAtMs(context)
        if (setAt <= 0L) return
        if (!usageHealthSocialLimitActive(context)) {
            clearUsageHealthSocialLimit(context)
        }
    }

    /** Usage Health temporary limit overrides Content Time social limit when active. */
    fun effectiveSocialLimitMinutes(context: Context): Int {
        if (usageHealthSocialLimitActive(context)) {
            return usageHealthSocialLimitMinutes(context)
        }
        return socialLimitMinutes(context)
    }

    fun gamingLimitMinutes(context: Context): Int =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getInt(KEY_GAMING_LIMIT_MINUTES, 60)

    fun entertainmentLimitMinutes(context: Context): Int =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getInt(KEY_ENTERTAINMENT_LIMIT_MINUTES, 120)

    fun socialLockUntilMs(context: Context): Long =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong(KEY_SOCIAL_LOCK_UNTIL_MS, 0L)

    fun setSocialLockUntilMs(context: Context, value: Long) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_SOCIAL_LOCK_UNTIL_MS, value)
            .apply()
    }

    fun videoAccumSeconds(context: Context): Int =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getInt(KEY_VIDEO_ACCUM_SECONDS, 0)

    fun setVideoAccumSeconds(context: Context, value: Int) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_VIDEO_ACCUM_SECONDS, maxOf(0, value))
            .apply()
    }

    fun setRecordingState(context: Context, active: Boolean, platform: String, packageName: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_RECORDING_ACTIVE, active)
            .putString(KEY_LAST_VIDEO_PLATFORM, platform)
            .putString(KEY_LAST_VIDEO_PACKAGE, packageName)
            .apply()
    }

    fun recordingActive(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_RECORDING_ACTIVE, false)

    /** Written by [BackgroundUsageService] — UI reads this without depending on Flutter lifecycle. */
    fun setBackgroundMonitoringState(
        context: Context,
        monitoredAppName: String,
        monitoredPackage: String,
        serviceRunning: Boolean,
    ) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_BG_MONITORED_APP, monitoredAppName)
            .putString(KEY_BG_MONITORED_PKG, monitoredPackage)
            .putLong(KEY_BG_LAST_TICK_MS, System.currentTimeMillis())
            .putBoolean(KEY_BG_SERVICE_RUNNING, serviceRunning)
            .apply()
    }

    fun backgroundMonitoredAppName(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_BG_MONITORED_APP, "") ?: ""

    fun backgroundMonitoredPackage(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_BG_MONITORED_PKG, "") ?: ""

    fun backgroundMonitoringLastTickMs(context: Context): Long =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getLong(KEY_BG_LAST_TICK_MS, 0L)

    fun backgroundServiceRunningFlag(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_BG_SERVICE_RUNNING, false)

    fun lastVideoPlatform(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_LAST_VIDEO_PLATFORM, "") ?: ""

    fun lastVideoPackage(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_LAST_VIDEO_PACKAGE, "") ?: ""

    fun saveLastVideoUploadError(context: Context, value: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_LAST_VIDEO_UPLOAD_ERROR, value)
            .apply()
    }

    fun lastVideoUploadError(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_LAST_VIDEO_UPLOAD_ERROR, "") ?: ""

    fun setHomeBlockedPackages(context: Context, packages: Collection<String>) {
        val arr = org.json.JSONArray()
        packages.filter { it.isNotBlank() }.distinct().sorted().forEach { arr.put(it) }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_HOME_BLOCKED_PACKAGES_JSON, arr.toString())
            .apply()
    }

    fun homeBlockedPackages(context: Context): Set<String> {
        val raw =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY_HOME_BLOCKED_PACKAGES_JSON, "[]") ?: "[]"
        return try {
            val arr = org.json.JSONArray(raw)
            val out = HashSet<String>()
            for (i in 0 until arr.length()) {
                val s = arr.optString(i, "")
                if (s.isNotBlank()) out.add(s)
            }
            out
        } catch (_: Exception) {
            emptySet()
        }
    }

    fun faceMatchPercent(context: Context): Double =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getFloat(KEY_FACE_MATCH_PERCENT, 0f)
            .toDouble()

    fun setParentalEnforcementEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_PARENTAL_ENFORCEMENT_ENABLED, enabled)
            .commit()
    }

    fun parentalEnforcementEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_PARENTAL_ENFORCEMENT_ENABLED, false)

    /** Logged-in session present — run usage polling (face verify may still be pending). */
    fun shouldAllowUsageCollection(context: Context): Boolean {
        return token(context).isNotBlank() && userId(context).isNotBlank()
    }

    fun shouldRunTrackerOrParental(context: Context): Boolean =
        shouldAllowUsageCollection(context)

    /**
     * True only when MindSync parental blocking is actively enabled.
     *
     * Blocked package lists may be persisted/restored on login; we should not start enforcement
     * until the user turns blocking ON (via setParentalPolicy / setBlockedAppNow).
     */
    fun hasActiveAppBlockingRules(context: Context): Boolean {
        if (!parentalEnforcementEnabled(context)) return false
        if (effectiveBlockedPackages(context).isNotEmpty()) return true
        if (isSocialLimitLockActive(context)) return true
        return false
    }

    fun isSocialLimitLockActive(context: Context): Boolean {
        val until = socialLockUntilMs(context)
        return until > System.currentTimeMillis()
    }

    fun setSocialLimitLock(context: Context) {
        val setAt = usageHealthSocialLimitSetAtMs(context)
        val until =
            if (setAt > 0L) {
                setAt + USAGE_HEALTH_LIMIT_EXPIRY_MS
            } else {
                System.currentTimeMillis() + USAGE_HEALTH_LIMIT_EXPIRY_MS
            }
        setSocialLockUntilMs(context, until)
    }

    fun clearSocialLimitLock(context: Context) {
        setSocialLockUntilMs(context, 0L)
    }

    fun markUsageHealthLimitExpired(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_USAGE_HEALTH_SHOW_EXPIRED, true)
            .apply()
    }

    fun usageHealthLimitExpired(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_USAGE_HEALTH_SHOW_EXPIRED, false)

    private fun hasAnyLocalBlock(context: Context): Boolean {
        return try {
            val obj = org.json.JSONObject(localBlockedPackagesJson(context))
            val keys = obj.keys()
            while (keys.hasNext()) {
                if (obj.optBoolean(keys.next(), false)) return true
            }
            false
        } catch (_: Exception) {
            false
        }
    }

    fun shouldSyncUsageStats(context: Context): Boolean {
        val t = token(context).isNotBlank()
        val uid = userId(context).isNotBlank()
        if (!t || !uid) return false
        if (faceVerified(context) && !unlockFaceSessionOk(context)) return false
        return true
    }

    /** After device unlock, native capture must match profile before usage / screen capture sync runs. */
    fun unlockFaceSessionOk(context: Context): Boolean {
        if (!faceVerified(context)) return true
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_UNLOCK_FACE_SESSION_OK, false)
    }

    fun setUnlockFaceSessionOk(context: Context, ok: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_UNLOCK_FACE_SESSION_OK, ok)
            .apply()
    }

    fun saveUnlockFaceLastError(context: Context, value: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_UNLOCK_FACE_LAST_ERROR, value)
            .apply()
    }

    fun unlockFaceLastError(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_UNLOCK_FACE_LAST_ERROR, "") ?: ""

    fun unlockFaceLastSuccessMs(context: Context): Long =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getLong(KEY_UNLOCK_FACE_LAST_SUCCESS_MS, 0L)

    fun setUnlockFaceLastSuccessMs(context: Context, ms: Long) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_UNLOCK_FACE_LAST_SUCCESS_MS, ms)
            .apply()
    }

    const val FACE_MATCH_PAUSE_MS = 300_000L
    const val FACE_MATCH_RETRY_MS = 60_000L

    fun faceMatchPauseUntilMs(context: Context): Long =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getLong(KEY_FACE_MATCH_PAUSE_UNTIL_MS, 0L)

    fun setFaceMatchPauseUntilMs(context: Context, untilMs: Long) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_FACE_MATCH_PAUSE_UNTIL_MS, untilMs)
            .apply()
    }

    /** True while face verify + mood image/video captures are paused (5 min after match). */
    fun isFaceMatchPauseActive(context: Context): Boolean {
        val until = faceMatchPauseUntilMs(context)
        return until > 0L && System.currentTimeMillis() < until
    }

    fun faceMatchPauseRemainingMs(context: Context): Long {
        val until = faceMatchPauseUntilMs(context)
        if (until <= 0L) return 0L
        return (until - System.currentTimeMillis()).coerceAtLeast(0L)
    }

    /** Call after successful unlock face match — pauses verify + mood only (not expression video). */
    fun applyFaceMatchPause(context: Context) {
        val now = System.currentTimeMillis()
        val until = now + FACE_MATCH_PAUSE_MS
        setFaceMatchPauseUntilMs(context, until)
        setUnlockFaceLastSuccessMs(context, now)
    }

    fun clearFaceMatchPause(context: Context) {
        setFaceMatchPauseUntilMs(context, 0L)
    }

    /** After the 5-minute pause ends, allow one fresh unlock verify. */
    fun shouldResetSessionAfterPause(context: Context): Boolean {
        val until = faceMatchPauseUntilMs(context)
        if (until <= 0L) return false
        return System.currentTimeMillis() >= until && unlockFaceSessionOk(context)
    }

    /** True for 5 minutes after a successful unlock face match. */
    fun isUnlockFaceCooldownActive(context: Context): Boolean {
        if (!faceVerified(context)) return false
        return isFaceMatchPauseActive(context)
    }

    fun localBlockedPackagesJson(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_LOCAL_BLOCKED_PACKAGES, "{}") ?: "{}"

    fun setLocalBlockedState(context: Context, packageName: String, blocked: Boolean) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val current = org.json.JSONObject(localBlockedPackagesJson(context))
        val targets = BlockedPackageMatcher.expandPackages(listOf(packageName))
        for (target in targets) {
            current.put(target, blocked)
        }
        prefs.edit().putString(KEY_LOCAL_BLOCKED_PACKAGES, current.toString()).commit()
        syncHomeBlockedFromLocal(context)
    }

    /** Union of [homeBlockedPackages] and locally toggled blocks (parent UI + enforcement). */
    fun effectiveBlockedPackages(context: Context): Set<String> {
        val out = HashSet<String>()
        out.addAll(homeBlockedPackages(context))
        try {
            val obj = org.json.JSONObject(localBlockedPackagesJson(context))
            val keys = obj.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                if (obj.optBoolean(k, false)) out.add(k)
            }
        } catch (_: Exception) {
        }
        return BlockedPackageMatcher.expandPackages(out)
    }

    /** Keep the HOME-blocker list aligned with parental local toggles. */
    fun syncHomeBlockedFromLocal(context: Context) {
        val blocked = HashSet<String>()
        blocked.addAll(homeBlockedPackages(context))
        try {
            val obj = org.json.JSONObject(localBlockedPackagesJson(context))
            val keys = obj.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                if (obj.optBoolean(k, false)) blocked.add(k)
            }
        } catch (_: Exception) {
        }
        setHomeBlockedPackages(context, blocked)
    }

    fun faceReactionCooldownUntilMs(context: Context): Long =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getLong(KEY_FACE_REACTION_COOLDOWN_UNTIL_MS, 0L)

    fun setFaceReactionCooldownUntilMs(context: Context, untilMs: Long) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_FACE_REACTION_COOLDOWN_UNTIL_MS, untilMs)
            .apply()
    }

    fun clearFaceReactionCooldown(context: Context) {
        setFaceReactionCooldownUntilMs(context, 0L)
    }

    fun setFaceReactionRecording(context: Context, active: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_FACE_REACTION_RECORDING, active)
            .apply()
    }

    fun faceReactionRecording(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_FACE_REACTION_RECORDING, false)

    fun saveFaceReactionLastError(context: Context, value: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_FACE_REACTION_LAST_ERROR, value)
            .apply()
    }

    fun faceReactionLastError(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_FACE_REACTION_LAST_ERROR, "") ?: ""

    fun lastScheduledFaceCaptureMs(context: Context): Long =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getLong(KEY_LAST_SCHEDULED_FACE_CAPTURE_MS, 0L)

    fun setLastScheduledFaceCaptureMs(context: Context, value: Long) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_LAST_SCHEDULED_FACE_CAPTURE_MS, maxOf(0L, value))
            .apply()
    }

    fun monitoringSocialSessionPackage(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_MONITORING_SOCIAL_SESSION_PKG, "") ?: ""

    fun setMonitoringSocialSessionPackage(context: Context, packageName: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_MONITORING_SOCIAL_SESSION_PKG, packageName)
            .apply()
    }

    fun clearMonitoringSocialSession(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_MONITORING_SOCIAL_SESSION_PKG)
            .apply()
    }

    /** Fresh login: session timer at 0 and usage delta baseline reset. */
    fun startUserSession(context: Context, userId: String) {
        if (userId.isBlank()) return
        val sessionPrefs = context.getSharedPreferences(PREFS_SCREEN_SESSION, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        sessionPrefs.edit()
            .putString(KEY_ACTIVE_USER_ID, userId)
            .putLong(sessionStartKey(userId), now)
            .putLong(accumulatedKey(userId), 0L)
            .apply()
        saveLastTotalsJson(context, "{}")
        UsagePeriodStore.onSessionStart(context, userId)
    }

    /** New account: zero local period caches (server rows start at 0 on first sync). */
    fun resetNewUserUsageBaselines(context: Context, userId: String) {
        if (userId.isBlank()) return
        saveLastTotalsJson(context, "{}")
        UsagePeriodStore.resetUser(context, userId)
        ScreenTimeLocalDatabase.getInstance(context).resetUser(userId)
    }

    fun endUserSession(context: Context, userId: String) {
        if (userId.isBlank()) return
        val sessionPrefs = context.getSharedPreferences(PREFS_SCREEN_SESSION, Context.MODE_PRIVATE)
        val start = sessionPrefs.getLong(sessionStartKey(userId), 0L)
        var accumulated = sessionPrefs.getLong(accumulatedKey(userId), 0L)
        if (start > 0L) {
            accumulated += System.currentTimeMillis() - start
        }
        sessionPrefs.edit()
            .putLong(accumulatedKey(userId), accumulated)
            .remove(sessionStartKey(userId))
            .apply()
        val active = sessionPrefs.getString(KEY_ACTIVE_USER_ID, null)
        if (active == userId) {
            sessionPrefs.edit().remove(KEY_ACTIVE_USER_ID).apply()
        }
    }

    fun getSessionScreenTimeMs(context: Context, userId: String): Long {
        if (userId.isBlank()) return 0L
        val sessionPrefs = context.getSharedPreferences(PREFS_SCREEN_SESSION, Context.MODE_PRIVATE)
        var accumulated = sessionPrefs.getLong(accumulatedKey(userId), 0L)
        val active = sessionPrefs.getString(KEY_ACTIVE_USER_ID, null)
        if (active == userId) {
            val start = sessionPrefs.getLong(sessionStartKey(userId), 0L)
            if (start > 0L) {
                accumulated += System.currentTimeMillis() - start
            }
        }
        return accumulated.coerceAtLeast(0L)
    }

    fun activeUserId(context: Context): String? =
        context.getSharedPreferences(PREFS_SCREEN_SESSION, Context.MODE_PRIVATE)
            .getString(KEY_ACTIVE_USER_ID, null)

    private fun sessionStartKey(userId: String) = "session_start_$userId"

    private fun accumulatedKey(userId: String) = "accumulated_ms_$userId"
}
