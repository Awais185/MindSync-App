package com.example.frontend

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView

/**
 * Full-screen block screen shown when a blocked package is in the foreground.
 * Requires "Display over other apps" so the service can start this Activity from the background.
 */
class BlockedAppOverlayActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        @Suppress("DEPRECATION")
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
        )
        setContentView(R.layout.activity_blocked_overlay)

        val pkg = intent.getStringExtra(EXTRA_BLOCKED_PACKAGE).orEmpty()
        findViewById<TextView>(R.id.blocked_subtitle).text =
            if (pkg.isNotBlank()) {
                "“$pkg” is restricted by MindSync parental controls."
            } else {
                "This app is restricted by MindSync parental controls."
            }

        findViewById<Button>(R.id.blocked_open_mindsync).setOnClickListener {
            val launch = packageManager.getLaunchIntentForPackage(packageName)
            if (launch != null) {
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                startActivity(launch)
            }
            finish()
        }
    }

    companion object {
        const val EXTRA_BLOCKED_PACKAGE = "blocked_package"
    }
}
