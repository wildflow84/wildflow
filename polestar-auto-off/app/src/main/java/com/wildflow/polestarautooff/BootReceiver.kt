package com.wildflow.polestarautooff

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings

/** Re-enables the accessibility service after boot or an app update, if WRITE_SECURE_SETTINGS was granted over adb. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val ok = Access.ensureEnabled(context)
        Logger.log(context, "${intent.action}: accessibility service enabled=$ok")
    }
}

object Access {
    private const val KEY = "enabled_accessibility_services"

    fun ensureEnabled(ctx: Context): Boolean = try {
        val cn = ComponentName(ctx, AutoOffService::class.java)
        val cr = ctx.contentResolver
        val current = Settings.Secure.getString(cr, KEY).orEmpty()
        val entries = current.split(':').filter { it.isNotEmpty() }
        if (entries.none { it == cn.flattenToString() || it == cn.flattenToShortString() }) {
            Settings.Secure.putString(cr, KEY, (entries + cn.flattenToString()).joinToString(":"))
        }
        Settings.Secure.putInt(cr, Settings.Secure.ACCESSIBILITY_ENABLED, 1)
        true
    } catch (e: SecurityException) {
        false
    }
}
