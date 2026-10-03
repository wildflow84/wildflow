package com.wildflow.ourday

import android.app.Activity
import android.os.Bundle
import es.antonborri.home_widget.HomeWidgetBackgroundIntent

/**
 * 위젯 목록의 클릭을 받는 화면 없는 중간 다리.
 *  - 체크박스를 눌렀으면(ourday://done?…) 앱을 열지 않고 Flutter 백그라운드 콜백으로 완료 처리
 *  - 그 밖의 곳을 눌렀으면 앱을 연다
 */
class WidgetActionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uri = intent?.data
        if (uri != null && uri.scheme == "ourday" && uri.host == "done") {
            try {
                HomeWidgetBackgroundIntent.getBroadcast(this, uri).send()
            } catch (e: Exception) {
                // 보내지 못해도 조용히 닫는다
            }
        } else {
            val launch = packageManager.getLaunchIntentForPackage(packageName)
            if (launch != null) startActivity(launch)
        }
        finish()
    }
}
