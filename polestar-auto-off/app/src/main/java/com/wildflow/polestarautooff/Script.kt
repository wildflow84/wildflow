package com.wildflow.polestarautooff

import android.content.Context
import org.json.JSONObject
import java.io.File

data class Step(
    val op: String,
    val any: List<String> = emptyList(),
    val confirm: List<String> = emptyList(),
    val optional: Boolean = false,
    val ms: Long = 0,
    val pkg: String? = null,
    // Coordinates: values <= 1.0 are fractions of the screen, anything larger is pixels.
    val x: Double? = null,
    val y: Double? = null,
    val x2: Double? = null,
    val y2: Double? = null,
    val confirmX: Double? = null,
    val confirmY: Double? = null,
    val blind: Boolean = false,
)

data class Script(
    val cooldownSec: Long,
    val maxAttempts: Int,
    val stepTimeoutMs: Long,
    val stepDelayMs: Long,
    val steps: List<Step>,
) {
    companion object {
        /** An script.json in the app's external files dir overrides the bundled one (no rebuild needed to retune labels). */
        fun load(ctx: Context): Script {
            val override = File(ctx.getExternalFilesDir(null), "script.json")
            val text = if (override.isFile) {
                override.readText()
            } else {
                ctx.assets.open("script.json").bufferedReader().use { it.readText() }
            }
            return parse(text)
        }

        fun parse(text: String): Script {
            val o = JSONObject(text)
            val arr = o.getJSONArray("steps")
            val steps = (0 until arr.length()).map { i ->
                val s = arr.getJSONObject(i)
                fun strings(key: String): List<String> {
                    val a = s.optJSONArray(key) ?: return emptyList()
                    return (0 until a.length()).map { a.getString(it) }
                }
                Step(
                    op = s.getString("op"),
                    any = strings("any"),
                    confirm = strings("confirm"),
                    optional = s.optBoolean("optional"),
                    ms = s.optLong("ms"),
                    pkg = s.optString("pkg").ifEmpty { null },
                    x = if (s.has("x")) s.getDouble("x") else null,
                    y = if (s.has("y")) s.getDouble("y") else null,
                    x2 = if (s.has("x2")) s.getDouble("x2") else null,
                    y2 = if (s.has("y2")) s.getDouble("y2") else null,
                    confirmX = if (s.has("confirmX")) s.getDouble("confirmX") else null,
                    confirmY = if (s.has("confirmY")) s.getDouble("confirmY") else null,
                    blind = s.optBoolean("blind"),
                )
            }
            return Script(
                cooldownSec = o.optLong("cooldownSec", 120),
                maxAttempts = o.optInt("maxAttempts", 3),
                stepTimeoutMs = o.optLong("stepTimeoutMs", 8000),
                stepDelayMs = o.optLong("stepDelayMs", 1000),
                steps = steps,
            )
        }
    }
}
