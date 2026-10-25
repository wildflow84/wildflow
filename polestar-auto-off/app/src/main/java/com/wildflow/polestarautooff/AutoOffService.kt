package com.wildflow.polestarautooff

import android.accessibilityservice.AccessibilityService
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent

class AutoOffService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private var runner: ScriptRunner? = null

    // Head units usually wake the screen on ignition, which is when the car resets these options.
    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            handler.postDelayed({ trigger("screen:${intent.action}", force = false) }, 3000)
        }
    }

    override fun onServiceConnected() {
        instance = this
        val filter = IntentFilter(Intent.ACTION_SCREEN_ON).apply { addAction(Intent.ACTION_USER_PRESENT) }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(screenReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(screenReceiver, filter)
        }
        Logger.log(this, "service connected")
        handler.postDelayed({ trigger("service-connected", force = false) }, 5000)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onInterrupt() = Unit

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        handler.removeCallbacksAndMessages(null)
        try {
            unregisterReceiver(screenReceiver)
        } catch (_: IllegalArgumentException) {
        }
        return super.onUnbind(intent)
    }

    fun trigger(reason: String, force: Boolean, attempt: Int = 1) {
        val script = try {
            Script.load(this)
        } catch (e: Exception) {
            Logger.log(this, "script.json error: $e")
            return
        }
        if (runner != null) {
            Logger.log(this, "trigger($reason) ignored: already running")
            return
        }
        val prefs = getSharedPreferences("state", MODE_PRIVATE)
        val ageSec = (System.currentTimeMillis() - prefs.getLong("lastOk", 0)) / 1000
        if (!force && ageSec < script.cooldownSec) {
            Logger.log(this, "trigger($reason) skipped: last success ${ageSec}s ago")
            return
        }
        Logger.log(this, "run ($reason) attempt $attempt/${script.maxAttempts}")
        runner = ScriptRunner(this, script) { ok ->
            runner = null
            if (ok) {
                prefs.edit().putLong("lastOk", System.currentTimeMillis()).apply()
                Logger.log(this, "done")
            } else if (attempt < script.maxAttempts) {
                handler.postDelayed({ trigger("retry", force, attempt + 1) }, 15_000)
            } else {
                Logger.log(this, "gave up after $attempt attempts")
            }
        }.also { it.start() }
    }

    fun dumpScreen() {
        Logger.log(this, "DUMP\n" + Nodes.dump(Nodes.roots(this)))
    }

    companion object {
        @Volatile
        var instance: AutoOffService? = null
    }
}
