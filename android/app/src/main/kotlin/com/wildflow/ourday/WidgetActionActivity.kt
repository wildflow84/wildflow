package com.wildflow.ourday

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import org.json.JSONArray

/**
 * 위젯 목록의 클릭을 받는 화면 없는 중간 다리.
 *  - 체크박스(ourday://done?…): 위젯부터 바로 바꾸고(즉시 반영), 앱을 열지 않고 Flutter 백그라운드로 실제 완료 처리
 *  - 항목 줄(ourday://edit?…): 앱을 열어서 그 항목의 편집 화면으로 바로 이동
 *  - 그 밖: 앱 열기
 */
class WidgetActionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uri = intent?.data
        if (uri != null && uri.scheme == "ourday" && uri.host == "done") {
            flipInWidget(uri)
            try {
                HomeWidgetBackgroundIntent.getBroadcast(this, uri).send()
            } catch (e: Exception) {
                // 보내지 못해도 조용히 닫는다
            }
        } else if (uri != null && uri.scheme == "ourday" && uri.host == "edit") {
            // home_widget이 앱으로 넘겨 주는 방식(LAUNCH 액션 + 데이터)으로 열면 Flutter가 uri를 받는다
            val open = Intent(this, MainActivity::class.java)
            open.action = "es.antonborri.home_widget.action.LAUNCH"
            open.data = uri
            open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            startActivity(open)
        } else {
            val launch = packageManager.getLaunchIntentForPackage(packageName)
            if (launch != null) startActivity(launch)
        }
        finish()
    }

    /** 위젯 목록 데이터에서 눌린 항목의 완료 표시만 바로 뒤집고 위젯을 다시 그리게 한다 (서버 저장은 뒤따라 Flutter가 한다) */
    private fun flipInWidget(uri: Uri) {
        try {
            val id = uri.getQueryParameter("id") ?: return
            val date = uri.getQueryParameter("date") ?: return
            val prefs = getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            val days = JSONArray(prefs.getString("agendaJson", "[]") ?: "[]")
            for (d in 0 until days.length()) {
                val items = days.getJSONObject(d).getJSONArray("items")
                for (i in 0 until items.length()) {
                    val it = items.getJSONObject(i)
                    if (it.optString("id") == id && it.optString("dk") == date) {
                        it.put("done", !it.optBoolean("done"))
                    }
                }
            }
            prefs.edit().putString("agendaJson", days.toString()).commit()
            val mgr = AppWidgetManager.getInstance(this)
            val ids = mgr.getAppWidgetIds(ComponentName(this, OurDayWidget::class.java))
            mgr.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
            // 위젯 화면이 첫 알림을 놓치는 경우를 대비해 한 번 더
            val appCtx = applicationContext
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    val m = AppWidgetManager.getInstance(appCtx)
                    m.notifyAppWidgetViewDataChanged(m.getAppWidgetIds(ComponentName(appCtx, OurDayWidget::class.java)), R.id.widget_list)
                } catch (e: Exception) {
                }
            }, 700)
        } catch (e: Exception) {
            // 바로 반영에 실패해도 실제 완료 처리는 계속된다
        }
    }
}
