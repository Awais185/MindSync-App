package com.example.frontend

import android.content.Context
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/** Fires 12 hours after the usage limit was saved to expire enforcement. */
class UsageLimitExpiryWorker(
    context: Context,
    params: WorkerParameters,
) : Worker(context, params) {
    override fun doWork(): Result {
        UsageLimitEnforcer.onLimitExpired(applicationContext)
        return Result.success()
    }

    companion object {
        private const val UNIQUE_WORK = "mindsync_usage_health_limit_expiry"

        fun schedule(context: Context, setAtMs: Long = TrackerPrefs.usageHealthSocialLimitSetAtMs(context)) {
            if (setAtMs <= 0L) return
            val delayMs =
                (setAtMs + TrackerPrefs.USAGE_HEALTH_LIMIT_EXPIRY_MS - System.currentTimeMillis())
                    .coerceAtLeast(1_000L)
            val request =
                OneTimeWorkRequestBuilder<UsageLimitExpiryWorker>()
                    .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
                    .build()
            WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
                UNIQUE_WORK,
                ExistingWorkPolicy.REPLACE,
                request,
            )
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context.applicationContext).cancelUniqueWork(UNIQUE_WORK)
        }
    }
}
