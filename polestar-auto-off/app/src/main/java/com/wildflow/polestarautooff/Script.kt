package com.wildflow.polestarautooff

import android.content.Context
import org.json.JSONObject
import java.io.File

data class Step(
    val op: String,
    val any: List<String> = emptyList(),
    val optional: Boolean = false,
    val ms: Long = 0,
    val pkg: String? = null,
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
                val a = s.optJSONArray("any")
                Step(
                    op = s.getString("op"),
                    any = if (a == null) emptyList() else (0 until a.length()).map { a.getString(it) },
                    optional = s.optBoolean("optional"),
                    ms = s.optLong("ms"),
                    pkg = s.optString("pkg").ifEmpty { null },
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
