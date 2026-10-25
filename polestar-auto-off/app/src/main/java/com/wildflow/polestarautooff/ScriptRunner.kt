package com.wildflow.polestarautooff

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Path
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
    private var confirmTapped = false
    private var finished = false

    fun start() = beginStep()

    private fun log(msg: String) = Logger.log(svc, msg)

    private fun beginStep() {
        stepStart = SystemClock.uptimeMillis()
        scrolls = 0
        lastClick = 0L
        confirmTapped = false
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
        "tap" -> doTap(step)
        "swipe" -> doSwipe(step)
        "tap_if_on" -> doTapIfOn(step)
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
        // Turning a safety option off may raise a confirmation dialog. Some UIs flip the switch before the
        // dialog is answered, so look for the dialog button before trusting the switch state.
        if (lastClick != 0L && step.confirm.isNotEmpty()) {
            val button = Nodes.find(roots, step.confirm, exactOnly = true)
            if (button != null && Nodes.click(button)) {
                log("step ${idx + 1}: confirmed '${button.text ?: button.contentDescription}'")
                return R.RETRY
            }
        }
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
        // With a confirmation dialog in play the switch stays on until it is answered, so wait longer.
        val now = SystemClock.uptimeMillis()
        val retryAfterMs = if (step.confirm.isEmpty()) 2000 else 6000
        if (now - lastClick > retryAfterMs) {
            val ok = Nodes.click(toggle)
            lastClick = now
            log("step ${idx + 1}: '$name' is on, clicked switch (ok=$ok)")
        }
        return R.RETRY
    }

    private fun px(v: Double?, full: Int): Float = (v ?: 0.0).let { if (it <= 1.0) it * full else it }.toFloat()

    private fun gesture(x: Float, y: Float, x2: Float?, y2: Float?, ms: Long): Boolean {
        val path = Path().apply {
            moveTo(x, y)
            if (x2 != null && y2 != null) lineTo(x2, y2)
        }
        val duration = if (ms > 0) ms else if (x2 != null) 300L else 50L
        val stroke = GestureDescription.StrokeDescription(path, 0, duration)
        return svc.dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    private fun tapAt(x: Double?, y: Double?, ms: Long = 0): Boolean {
        val dm = svc.resources.displayMetrics
        return gesture(px(x, dm.widthPixels), px(y, dm.heightPixels), null, null, ms)
    }

    private fun doTap(step: Step): R {
        if (step.x == null || step.y == null) {
            log("step ${idx + 1}: tap needs x and y")
            return R.RETRY
        }
        val ok = tapAt(step.x, step.y, step.ms)
        log("step ${idx + 1}: tap (${step.x}, ${step.y}) ok=$ok")
        return if (ok) R.DONE else R.RETRY
    }

    private fun doSwipe(step: Step): R {
        if (step.x == null || step.y == null || step.x2 == null || step.y2 == null) {
            log("step ${idx + 1}: swipe needs x, y, x2, y2")
            return R.RETRY
        }
        val dm = svc.resources.displayMetrics
        val ok = gesture(
            px(step.x, dm.widthPixels), px(step.y, dm.heightPixels),
            px(step.x2, dm.widthPixels), px(step.y2, dm.heightPixels), step.ms,
        )
        log("step ${idx + 1}: swipe ok=$ok")
        return if (ok) R.DONE else R.RETRY
    }

    /**
     * Tap a point only when the switch under it reads as on. If the point has no readable switch, skip
     * (a blind tap could turn the option on) unless the step says "blind": true.
     */
    private fun doTapIfOn(step: Step): R {
        if (step.x == null || step.y == null) {
            log("step ${idx + 1}: tap_if_on needs x and y")
            return R.RETRY
        }
        val roots = Nodes.roots(svc)
        val dm = svc.resources.displayMetrics
        val toggle = Nodes.toggleAt(
            roots, px(step.x, dm.widthPixels).toInt(), px(step.y, dm.heightPixels).toInt(),
        )
        val now = SystemClock.uptimeMillis()

        if (lastClick == 0L) {
            if (toggle != null && !toggle.isChecked) {
                log("step ${idx + 1}: switch at (${step.x}, ${step.y}) is off")
                return R.DONE
            }
            if (toggle == null && !step.blind) {
                log("step ${idx + 1}: no readable switch at (${step.x}, ${step.y}); skipped (set \"blind\": true to tap anyway)")
                return R.DONE
            }
            val ok = tapAt(step.x, step.y)
            lastClick = now
            log("step ${idx + 1}: tap (${step.x}, ${step.y}) ok=$ok readable=${toggle != null}")
            return R.RETRY
        }

        // Already tapped: answer a confirmation dialog, then verify.
        if (step.confirm.isNotEmpty()) {
            val button = Nodes.find(roots, step.confirm, exactOnly = true)
            if (button != null && Nodes.click(button)) {
                log("step ${idx + 1}: confirmed '${button.text ?: button.contentDescription}'")
                return R.RETRY
            }
        }
        if (now - lastClick < 1500) return R.RETRY
        if (step.confirmX != null && step.confirmY != null && !confirmTapped) {
            confirmTapped = true
            val ok = tapAt(step.confirmX, step.confirmY)
            log("step ${idx + 1}: confirm tap (${step.confirmX}, ${step.confirmY}) ok=$ok")
            return R.RETRY
        }
        if (toggle == null) return R.DONE // blind: nothing to verify against
        if (!toggle.isChecked) {
            log("step ${idx + 1}: switch at (${step.x}, ${step.y}) is now off")
            return R.DONE
        }
        if (now - lastClick > 6000) {
            lastClick = now
            confirmTapped = false
            tapAt(step.x, step.y)
            log("step ${idx + 1}: still on, tapped again")
        }
        return R.RETRY
    }

    private fun finish(ok: Boolean) {
        finished = true
        handler.removeCallbacksAndMessages(null)
        onFinish(ok)
    }
}
