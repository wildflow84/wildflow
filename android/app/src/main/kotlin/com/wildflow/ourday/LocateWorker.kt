package com.wildflow.ourday

import android.content.Context
import android.net.Uri
import androidx.work.Worker
import androidx.work.WorkerParameters
import es.antonborri.home_widget.HomeWidgetBackgroundIntent

/**
 * 15분마다 불려서, 앞으로 24시간 안에 "출발 알림" 일정이 있을 때만 Flutter 백그라운드 콜백(ourday://locate)을 깨워
 * 내 위치를 서버에 남기게 한다. 일정이 없으면 바로 끝나서 배터리를 거의 안 쓴다.
 */
class LocateWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("departWatch", false)) return Result.success()
        try {
            HomeWidgetBackgroundIntent.getBroadcast(applicationContext, Uri.parse("ourday://locate")).send()
        } catch (e: Exception) {
            // 보내지 못해도 다음 주기에 다시 한다
        }
        return Result.success()
    }
}
