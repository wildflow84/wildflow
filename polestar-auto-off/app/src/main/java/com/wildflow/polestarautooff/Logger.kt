package com.wildflow.polestarautooff

import android.content.Context
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object Logger {
    private const val TAG = "PolestarAutoOff"
    private const val MAX_BYTES = 200_000

    @Synchronized
    fun log(ctx: Context, msg: String) {
        Log.i(TAG, msg)
        try {
            val f = File(ctx.filesDir, "log.txt")
            if (f.length() > MAX_BYTES) f.writeText(f.readText().takeLast(MAX_BYTES / 2))
            val ts = SimpleDateFormat("MM-dd HH:mm:ss", Locale.US).format(Date())
            f.appendText("$ts $msg\n")
        } catch (_: Exception) {
        }
    }

    fun read(ctx: Context): String = try {
        File(ctx.filesDir, "log.txt").readText().takeLast(20_000)
    } catch (_: Exception) {
        ""
    }

    fun clear(ctx: Context) {
        File(ctx.filesDir, "log.txt").delete()
    }
}
