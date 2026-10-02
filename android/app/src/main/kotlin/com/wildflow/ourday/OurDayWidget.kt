package com.wildflow.ourday

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import android.content.SharedPreferences

class OurDayWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.ourday_widget).apply {
                setTextViewText(R.id.widget_title, widgetData.getString("title", "OurDay"))
                setTextViewText(R.id.widget_body, widgetData.getString("body", "앱을 열어서 로그인해줘"))
                val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                val pi = PendingIntent.getActivity(
                    context, 0, launch ?: Intent(),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.widget_root, pi)
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
