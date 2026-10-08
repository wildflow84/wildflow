package com.wildflow.ourday

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.net.Uri
import androidx.work.Worker
import androidx.work.WorkerParameters
import es.antonborri.home_widget.HomeWidgetBackgroundIntent

/**
 * 30분마다 불려서, 홈 화면에 위젯이 있으면 Flutter 백그라운드 콜백(ourday://refresh)을 깨워
 * 위젯 데이터(상대가 추가한 일정, 다른 기기 변경, 날짜 변경)를 앱을 안 열어도 새로 채운다. 위젯이 없으면 바로 끝난다.
 */
class RefreshWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        try {
            val mgr = AppWidgetManager.getInstance(applicationContext)
            val ids = mgr.getAppWidgetIds(ComponentName(applicationContext, OurDayWidget::class.java))
            if (ids.isEmpty()) return Result.success()
            HomeWidgetBackgroundIntent.getBroadcast(applicationContext, Uri.parse("ourday://refresh")).send()
        } catch (e: Exception) {
            // 보내지 못해도 다음 주기에 다시 한다
        }
        return Result.success()
    }
}
