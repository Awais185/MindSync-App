package com.example.frontend

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/**
 * Fetches monitored social packages from GET /api/auth/monitoring/target-apps/
 * and caches them locally (TTL 6h). Falls back to [TrackedSocialApps.defaultPackages].
 */
object MonitoredAppsCache {
    private const val PREFS = "mindsync_monitored_apps"
    private const val KEY_PACKAGES_JSON = "packages_json"
    private const val KEY_LOADED_AT_MS = "loaded_at_ms"
    private const val TTL_MS = 6 * 60 * 60 * 1000L

    private val refreshExecutor = Executors.newSingleThreadExecutor()
    private val lastRefreshAttemptMs = AtomicLong(0L)

    fun getPackages(context: Context): Set<String> {
        val cached = readCached(context)
        // Always union defaults so core social apps record even if the server list is narrow.
        return if (cached.isEmpty()) {
            TrackedSocialApps.defaultPackages
        } else {
            cached + TrackedSocialApps.defaultPackages
        }
    }

    fun isMonitored(context: Context, packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) return false
        return getPackages(context).contains(packageName)
    }

    fun refreshAsync(context: Context, force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - lastRefreshAttemptMs.get() < 30_000L) return
        lastRefreshAttemptMs.set(now)
        val appCtx = context.applicationContext
        refreshExecutor.execute {
            try {
                fetchAndStore(appCtx)
            } catch (e: Exception) {
                MonitoringLog.w("Monitored apps sync failed: ${e.message}")
            }
        }
    }

    private fun readCached(context: Context): Set<String> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val loadedAt = prefs.getLong(KEY_LOADED_AT_MS, 0L)
        if (loadedAt <= 0L || System.currentTimeMillis() - loadedAt > TTL_MS) {
            return emptySet()
        }
        val raw = prefs.getString(KEY_PACKAGES_JSON, "") ?: ""
        if (raw.isBlank()) return emptySet()
        return parsePackagesJson(raw)
    }

    private fun fetchAndStore(context: Context) {
        val baseUrl = TrackerPrefs.baseUrl(context)
        val token = TrackerPrefs.token(context)
        if (baseUrl.isBlank() || token.isBlank()) return

        val url = URL("${baseUrl.trimEnd('/')}/api/auth/monitoring/target-apps/")
        val conn =
            (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 12_000
                readTimeout = 20_000
                setRequestProperty("Authorization", "Bearer $token")
            }
        val code = conn.responseCode
        val body =
            if (code in 200..299) {
                conn.inputStream.bufferedReader().use { it.readText() }
            } else {
                conn.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
            }
        conn.disconnect()
        if (code !in 200..299) {
            MonitoringLog.w("Monitored apps HTTP $code")
            return
        }
        val root = runCatching { JSONObject(body) }.getOrNull() ?: return
        val packages = mutableSetOf<String>()
        val apps = root.optJSONArray("apps")
        if (apps != null) {
            for (i in 0 until apps.length()) {
                val row = apps.optJSONObject(i) ?: continue
                val pkg = row.optString("package_name").trim()
                if (pkg.isNotEmpty()) packages.add(pkg)
            }
        }
        val flat = root.optJSONArray("packages")
        if (flat != null) {
            for (i in 0 until flat.length()) {
                val pkg = flat.optString(i).trim()
                if (pkg.isNotEmpty()) packages.add(pkg)
            }
        }
        if (packages.isEmpty()) return
        val arr = JSONArray()
        packages.forEach { arr.put(it) }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PACKAGES_JSON, arr.toString())
            .putLong(KEY_LOADED_AT_MS, System.currentTimeMillis())
            .apply()
        MonitoringLog.i("Monitored apps synced (${packages.size} packages)")
    }

    private fun parsePackagesJson(raw: String): Set<String> {
        val out = mutableSetOf<String>()
        val arr = runCatching { JSONArray(raw) }.getOrNull() ?: return out
        for (i in 0 until arr.length()) {
            val pkg = arr.optString(i).trim()
            if (pkg.isNotEmpty()) out.add(pkg)
        }
        return out
    }
}
