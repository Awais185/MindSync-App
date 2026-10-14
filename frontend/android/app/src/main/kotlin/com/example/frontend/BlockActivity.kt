package com.example.frontend

import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity

class BlockActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_block)

        val blockTitle = findViewById<TextView>(R.id.blockTitle)
        val blockMessage = findViewById<TextView>(R.id.blockMessage)
        val btnGoHome = findViewById<Button>(R.id.btnGoHome)

        val reason = intent.getStringExtra(EXTRA_REASON)
        if (reason == REASON_SOCIAL_LIMIT) {
            blockTitle.text = "Social Limit Reached"
            blockMessage.text = "Your daily social media limit has been reached. Apps will unlock when the limit resets."
        }

        btnGoHome.setOnClickListener {
            val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(homeIntent)
            finish()
        }

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                // Do nothing, enforce blocking
                val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(homeIntent)
                finish()
            }
        })
    }

    companion object {
        const val EXTRA_REASON = "extra_reason"
        const val REASON_SOCIAL_LIMIT = "reason_social_limit"
        const val REASON_PARENT_BLOCKED = "reason_parent_blocked"
    }
}
