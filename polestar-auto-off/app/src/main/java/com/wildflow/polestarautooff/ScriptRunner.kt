package com.wildflow.polestarautooff

import android.accessibilityservice.AccessibilityService
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.view.accessibility.AccessibilityNodeInfo

/** Walks the script one step at a time, polling the screen until each step can be applied or times out. */
class ScriptRunner(
    private val svc: AutoOffService,
    private val script: Script,
    private val onFinish: (Boolean) -> Unit,
) {
    private enum class R { DONE, RETRY }

    private val handler = Handler(Looper.getMainLooper())
    private var idx = 0
    private var stepStart = 0L
    private var scrolls = 0
    private var lastClick = 0L
    private var finished = false

    fun start() = beginStep()

    private fun log(msg: String) = Logger.log(svc, msg)

    private fun beginStep() {
        stepStart = SystemClock.uptimeMillis()
        scrolls = 0
        lastClick = 0L
        tick()
    }

    private fun next(delayMs: Long) {
        idx++
        handler.postDelayed({ beginStep() }, delayMs)
    }

    private fun tick() {
        if (finished) return
        if (idx >= script.steps.size) return finish(true)
        val step = script.steps[idx]
        if (step.op == "wait") {
            log("step ${idx + 1}: wait ${step.ms}ms")
            return next(step.ms)
        }
        when (exec(step)) {
            R.DONE -> next(script.stepDelayMs)
            R.RETRY -> {
                if (SystemClock.uptimeMillis() - stepStart <= script.stepTimeoutMs) {
                    handler.postDelayed({ tick() }, 500)
                } else if (step.optional) {
                    log("step ${idx + 1} (${step.op}) skipped: not found")
                    next(0)
                } else {
                    log("step ${idx + 1} (${step.op} ${step.any}) timed out; screen was:\n" +
                        Nodes.dump(Nodes.roots(svc)).take(15_000))
                    finish(false)
                }
            }
        }
    }

    private fun exec(step: Step): R = when (step.op) {
        "open_settings" -> launch(Intent(Settings.ACTION_SETTINGS))
        "launch" -> {
            val i = step.pkg?.let { svc.packageManager.getLaunchIntentForPackage(it) }
            if (i == null) {
                log("launch: no launch intent for ${step.pkg}")
                R.RETRY
            } else {
                launch(i)
            }
        }
        "back" -> { svc.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK); R.DONE }
        "home" -> { svc.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME); R.DONE }
        "click" -> doClick(step)
        "set_off" -> doSetOff(step)
        else -> { log("unknown op '${step.op}', ignored"); R.DONE }
    }

    private fun launch(intent: Intent): R = try {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        svc.startActivity(intent)
        log("step ${idx + 1}: launched ${intent.action ?: intent.`package`}")
        R.DONE
    } catch (e: ActivityNotFoundException) {
        log("launch failed: $e")
        R.RETRY
    }

    private fun scrollAndRetry(roots: List<AccessibilityNodeInfo>): R {
        if (scrolls < 10) {
            Nodes.scroll(roots, forward = scrolls < 6)
            scrolls++
        }
        return R.RETRY
    }

    private fun doClick(step: Step): R {
        val roots = Nodes.roots(svc)
        val node = Nodes.find(roots, step.any) ?: return scrollAndRetry(roots)
        if (!Nodes.click(node)) return R.RETRY
        log("step ${idx + 1}: clicked '${node.text ?: node.contentDescription}'")
        return R.DONE
    }

    private fun doSetOff(step: Step): R {
        val roots = Nodes.roots(svc)
        val label = Nodes.find(roots, step.any) ?: return scrollAndRetry(roots)
        val name = label.text ?: label.contentDescription
        val toggle = Nodes.findToggle(label)
        if (toggle == null) {
            log("no single switch next to '$name'")
            return R.RETRY
        }
        if (!toggle.isChecked) {
            log("step ${idx + 1}: '$name' is off")
            return R.DONE
        }
        // The screen is re-read every tick; only click again if the first click had time to take effect and didn't.
        val now = SystemClock.uptimeMillis()
        if (now - lastClick > 2000) {
            val ok = Nodes.click(toggle)
            lastClick = now
            log("step ${idx + 1}: '$name' is on, clicked switch (ok=$ok)")
        }
        return R.RETRY
    }

    private fun finish(ok: Boolean) {
        finished = true
        handler.removeCallbacksAndMessages(null)
        onFinish(ok)
    }
}
