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
    }
}
