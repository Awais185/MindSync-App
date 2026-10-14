package com.example.frontend

/** 5-minute / 20-second face clips while any trackable app is foreground. */
internal object MindSyncFaceScheduleTargets {
    fun matches(context: android.content.Context, packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) return false
        if (packageName == context.packageName) return false
        return !ForegroundAppResolver.isIgnorableForeground(packageName)
    }
}
