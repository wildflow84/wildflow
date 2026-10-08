package com.wildflow.ourday

import android.os.Bundle
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import io.flutter.embedding.android.FlutterActivity
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 앱을 한 번 열면 15분마다 위치 갱신 작업을 예약해 둔다 (출발 알림 일정이 없으면 바로 끝남)
        val request = PeriodicWorkRequestBuilder<LocateWorker>(15, TimeUnit.MINUTES).build()
        WorkManager.getInstance(applicationContext)
            .enqueueUniquePeriodicWork("ourday-locate", ExistingPeriodicWorkPolicy.KEEP, request)
        // 위젯 데이터를 30분마다 앱을 안 열어도 새로 채운다 (홈 화면에 위젯이 없으면 바로 끝남)
        val refresh = PeriodicWorkRequestBuilder<RefreshWorker>(30, TimeUnit.MINUTES).build()
        WorkManager.getInstance(applicationContext)
            .enqueueUniquePeriodicWork("ourday-widget-refresh", ExistingPeriodicWorkPolicy.KEEP, refresh)
    }
}
