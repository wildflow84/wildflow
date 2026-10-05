package com.wildflow.ourday

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.ComponentName
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

class OurDayWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val cfg = WidgetPrefs(context)
        val idle = cfg.idleMs() > WidgetPrefs.IDLE_RESET_MS
        appWidgetIds.forEach { id ->
            // 한동안 안 썼으면 달력을 이번 달로 되돌린다 (목록은 build 안에서 오늘 위치로 스크롤)
            if (idle) cfg.setMonthOffset(id, 0)
            appWidgetManager.updateAppWidget(id, build(context, id, widgetData))
            if (WidgetPrefs(context).style(id) != "calendar") {
                appWidgetManager.notifyAppWidgetViewDataChanged(id, R.id.widget_list)
            }
        }
        scheduleMidnight(context)
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        scheduleMidnight(context)
    }

    override fun onDisabled(context: Context) {
        cancelMidnight(context)
        super.onDisabled(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action == ACTION_MIDNIGHT) {
            // 자정이 지났다: 지난 날을 빼고 "오늘"을 새로 잡아 다시 그린다
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, OurDayWidget::class.java))
            val data = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            ids.forEach { id -> mgr.updateAppWidget(id, build(context, id, data)) }
            mgr.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
            scheduleMidnight(context)
            return
        }
        if (action == ACTION_PREV || action == ACTION_NEXT || action == ACTION_TODAY) {
            val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            if (id != AppWidgetManager.INVALID_APPWIDGET_ID) {
                val cfg = WidgetPrefs(context)
                cfg.markUsed()
                val next = when (action) {
                    ACTION_PREV -> cfg.monthOffset(id) - 1
                    ACTION_NEXT -> cfg.monthOffset(id) + 1
                    else -> 0
                }
                cfg.setMonthOffset(id, next)
                val data = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
                AppWidgetManager.getInstance(context).updateAppWidget(id, build(context, id, data))
            }
            return
        }
        super.onReceive(context, intent)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val prefs = WidgetPrefs(context)
        appWidgetIds.forEach { prefs.remove(it) }
        super.onDeleted(context, appWidgetIds)
    }

    companion object {
        private const val ACTION_PREV = "com.wildflow.ourday.WIDGET_PREV"
        private const val ACTION_NEXT = "com.wildflow.ourday.WIDGET_NEXT"
        private const val ACTION_TODAY = "com.wildflow.ourday.WIDGET_TODAY"
        private const val ACTION_MIDNIGHT = "com.wildflow.ourday.WIDGET_MIDNIGHT"

        private fun midnightIntent(context: Context): PendingIntent {
            val i = Intent(context, OurDayWidget::class.java)
            i.action = ACTION_MIDNIGHT
            return PendingIntent.getBroadcast(context, 77, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        /** 다음 자정 직후에 위젯을 다시 그리도록 알람을 건다 (정확한 알람 권한 없이, 몇 분 늦을 수 있음) */
        fun scheduleMidnight(context: Context) {
            try {
                val c = Calendar.getInstance()
                c.add(Calendar.DAY_OF_YEAR, 1)
                c.set(Calendar.HOUR_OF_DAY, 0)
                c.set(Calendar.MINUTE, 0)
                c.set(Calendar.SECOND, 5)
                c.set(Calendar.MILLISECOND, 0)
                val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                am.set(AlarmManager.RTC, c.timeInMillis, midnightIntent(context))
            } catch (e: Exception) {
                // 알람을 못 걸어도 30분마다 도는 기본 갱신이 있다
            }
        }

        fun cancelMidnight(context: Context) {
            try {
                (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(midnightIntent(context))
            } catch (e: Exception) {
            }
        }

        private fun actionIntent(context: Context, id: Int, action: String, code: Int): PendingIntent {
            val i = Intent(context, OurDayWidget::class.java)
            i.action = action
            i.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            return PendingIntent.getBroadcast(
                context, id * 10 + code, i,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private val CELL_TEXT = intArrayOf(
            R.id.cell_00_t, R.id.cell_01_t, R.id.cell_02_t, R.id.cell_03_t, R.id.cell_04_t, R.id.cell_05_t, R.id.cell_06_t,
            R.id.cell_10_t, R.id.cell_11_t, R.id.cell_12_t, R.id.cell_13_t, R.id.cell_14_t, R.id.cell_15_t, R.id.cell_16_t,
            R.id.cell_20_t, R.id.cell_21_t, R.id.cell_22_t, R.id.cell_23_t, R.id.cell_24_t, R.id.cell_25_t, R.id.cell_26_t,
            R.id.cell_30_t, R.id.cell_31_t, R.id.cell_32_t, R.id.cell_33_t, R.id.cell_34_t, R.id.cell_35_t, R.id.cell_36_t,
            R.id.cell_40_t, R.id.cell_41_t, R.id.cell_42_t, R.id.cell_43_t, R.id.cell_44_t, R.id.cell_45_t, R.id.cell_46_t,
            R.id.cell_50_t, R.id.cell_51_t, R.id.cell_52_t, R.id.cell_53_t, R.id.cell_54_t, R.id.cell_55_t, R.id.cell_56_t
        )
        private val CELL_MARK = intArrayOf(
            R.id.cell_00_m, R.id.cell_01_m, R.id.cell_02_m, R.id.cell_03_m, R.id.cell_04_m, R.id.cell_05_m, R.id.cell_06_m,
            R.id.cell_10_m, R.id.cell_11_m, R.id.cell_12_m, R.id.cell_13_m, R.id.cell_14_m, R.id.cell_15_m, R.id.cell_16_m,
            R.id.cell_20_m, R.id.cell_21_m, R.id.cell_22_m, R.id.cell_23_m, R.id.cell_24_m, R.id.cell_25_m, R.id.cell_26_m,
            R.id.cell_30_m, R.id.cell_31_m, R.id.cell_32_m, R.id.cell_33_m, R.id.cell_34_m, R.id.cell_35_m, R.id.cell_36_m,
            R.id.cell_40_m, R.id.cell_41_m, R.id.cell_42_m, R.id.cell_43_m, R.id.cell_44_m, R.id.cell_45_m, R.id.cell_46_m,
            R.id.cell_50_m, R.id.cell_51_m, R.id.cell_52_m, R.id.cell_53_m, R.id.cell_54_m, R.id.cell_55_m, R.id.cell_56_m
        )
        private val CELL_ROOT = intArrayOf(
            R.id.cell_00_r, R.id.cell_01_r, R.id.cell_02_r, R.id.cell_03_r, R.id.cell_04_r, R.id.cell_05_r, R.id.cell_06_r,
            R.id.cell_10_r, R.id.cell_11_r, R.id.cell_12_r, R.id.cell_13_r, R.id.cell_14_r, R.id.cell_15_r, R.id.cell_16_r,
            R.id.cell_20_r, R.id.cell_21_r, R.id.cell_22_r, R.id.cell_23_r, R.id.cell_24_r, R.id.cell_25_r, R.id.cell_26_r,
            R.id.cell_30_r, R.id.cell_31_r, R.id.cell_32_r, R.id.cell_33_r, R.id.cell_34_r, R.id.cell_35_r, R.id.cell_36_r,
            R.id.cell_40_r, R.id.cell_41_r, R.id.cell_42_r, R.id.cell_43_r, R.id.cell_44_r, R.id.cell_45_r, R.id.cell_46_r,
            R.id.cell_50_r, R.id.cell_51_r, R.id.cell_52_r, R.id.cell_53_r, R.id.cell_54_r, R.id.cell_55_r, R.id.cell_56_r
        )
        private val CELL_E1 = intArrayOf(
            R.id.cell_00_e1, R.id.cell_01_e1, R.id.cell_02_e1, R.id.cell_03_e1, R.id.cell_04_e1, R.id.cell_05_e1, R.id.cell_06_e1,
            R.id.cell_10_e1, R.id.cell_11_e1, R.id.cell_12_e1, R.id.cell_13_e1, R.id.cell_14_e1, R.id.cell_15_e1, R.id.cell_16_e1,
            R.id.cell_20_e1, R.id.cell_21_e1, R.id.cell_22_e1, R.id.cell_23_e1, R.id.cell_24_e1, R.id.cell_25_e1, R.id.cell_26_e1,
            R.id.cell_30_e1, R.id.cell_31_e1, R.id.cell_32_e1, R.id.cell_33_e1, R.id.cell_34_e1, R.id.cell_35_e1, R.id.cell_36_e1,
            R.id.cell_40_e1, R.id.cell_41_e1, R.id.cell_42_e1, R.id.cell_43_e1, R.id.cell_44_e1, R.id.cell_45_e1, R.id.cell_46_e1,
            R.id.cell_50_e1, R.id.cell_51_e1, R.id.cell_52_e1, R.id.cell_53_e1, R.id.cell_54_e1, R.id.cell_55_e1, R.id.cell_56_e1
        )
        private val CELL_E2 = intArrayOf(
            R.id.cell_00_e2, R.id.cell_01_e2, R.id.cell_02_e2, R.id.cell_03_e2, R.id.cell_04_e2, R.id.cell_05_e2, R.id.cell_06_e2,
            R.id.cell_10_e2, R.id.cell_11_e2, R.id.cell_12_e2, R.id.cell_13_e2, R.id.cell_14_e2, R.id.cell_15_e2, R.id.cell_16_e2,
            R.id.cell_20_e2, R.id.cell_21_e2, R.id.cell_22_e2, R.id.cell_23_e2, R.id.cell_24_e2, R.id.cell_25_e2, R.id.cell_26_e2,
            R.id.cell_30_e2, R.id.cell_31_e2, R.id.cell_32_e2, R.id.cell_33_e2, R.id.cell_34_e2, R.id.cell_35_e2, R.id.cell_36_e2,
            R.id.cell_40_e2, R.id.cell_41_e2, R.id.cell_42_e2, R.id.cell_43_e2, R.id.cell_44_e2, R.id.cell_45_e2, R.id.cell_46_e2,
            R.id.cell_50_e2, R.id.cell_51_e2, R.id.cell_52_e2, R.id.cell_53_e2, R.id.cell_54_e2, R.id.cell_55_e2, R.id.cell_56_e2
        )

        /** 위젯 하나를 설정(모양, 투명도, 색)대로 그린다 */
        fun build(context: Context, id: Int, data: SharedPreferences): RemoteViews {
            val cfg = WidgetPrefs(context)
            val theme = WidgetTheme.all[cfg.color(id)]
            val calendar = cfg.style(id) == "calendar"
            val views = RemoteViews(
                context.packageName,
                if (calendar) R.layout.ourday_widget_cal else R.layout.ourday_widget
            )
            // 배경: 색 + 투명도
            views.setInt(R.id.widget_bg, "setColorFilter", theme.bg)
            views.setInt(R.id.widget_bg, "setImageAlpha", cfg.opacity(id) * 255 / 100)

            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                flags or PendingIntent.FLAG_MUTABLE
            } else {
                flags
            }
            val pi = PendingIntent.getActivity(context, 0, launch ?: Intent(), flags)

            if (calendar) {
                fillCalendar(context, id, views, theme, data, pi)
                views.setOnClickPendingIntent(R.id.widget_root, pi)
                views.setOnClickPendingIntent(R.id.cal_prev, actionIntent(context, id, ACTION_PREV, 1))
                views.setOnClickPendingIntent(R.id.cal_next, actionIntent(context, id, ACTION_NEXT, 2))
                views.setOnClickPendingIntent(R.id.cal_title, actionIntent(context, id, ACTION_TODAY, 3))
                views.setTextColor(R.id.cal_add, theme.accent)
                views.setOnClickPendingIntent(R.id.cal_add, appActionIntent(context, "ourday://add", 0))
            } else {
                // 목록 클릭은 화면 없는 중간 다리(WidgetActionActivity)가 받아서, 체크박스면 앱을 열지 않고 완료 처리한다
                val bridge = Intent(context, WidgetActionActivity::class.java)
                val bridgePi = PendingIntent.getActivity(context, 1, bridge, flags)
                fillList(context, id, views, theme, bridgePi)
            }
            return views
        }

        private fun fillList(context: Context, id: Int, views: RemoteViews, theme: WidgetTheme, pi: PendingIntent) {
            val intent = Intent(context, WidgetListService::class.java)
            intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            intent.data = Uri.parse(intent.toUri(Intent.URI_INTENT_SCHEME))
            views.setRemoteAdapter(R.id.widget_list, intent)
            views.setEmptyView(R.id.widget_list, R.id.widget_empty)
            views.setPendingIntentTemplate(R.id.widget_list, pi)
            // 목록에는 지난 날짜가 길게 들어 있다. 날짜가 바뀐 뒤 처음이거나, 한동안 위젯을 안 썼으면 오늘 위치로 스크롤하고,
            // 쓰는 중(최근에 눌렀다)에는 올려 둔 위치를 건드리지 않는다.
            try {
                val sp = context.getSharedPreferences("OurDayWidgetScroll", Context.MODE_PRIVATE)
                val agenda = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
                    .getString("agendaJson", "[]") ?: "[]"
                val idx = WidgetDates.todayRowIndex(agenda)
                val stamp = WidgetDates.key() + ":" + idx
                val idle = WidgetPrefs(context).idleMs() > WidgetPrefs.IDLE_RESET_MS
                if (idle || sp.getString("day$id", "") != stamp) {
                    views.setScrollPosition(R.id.widget_list, idx)
                    sp.edit().putString("day$id", stamp).apply()
                }
            } catch (e: Exception) {
            }
            views.setTextColor(R.id.widget_empty, theme.sub)
            views.setOnClickPendingIntent(R.id.widget_empty, pi)
            // 새 일정/할 일 추가: 앱이 열리면서 등록 화면이 바로 뜬다
            views.setInt(R.id.widget_fab_bg, "setColorFilter", theme.accent)
            views.setInt(R.id.widget_fab_bg, "setImageAlpha", 255)
            views.setTextColor(R.id.widget_fab_t, theme.onAccent)
            views.setOnClickPendingIntent(R.id.widget_fab, appActionIntent(context, "ourday://add", 0))
        }

        /** 위젯 안 버튼이 앱의 특정 화면(ourday://add, ourday://day?date=…)을 열도록 하는 인텐트 */
        private fun appActionIntent(context: Context, uri: String, code: Int): PendingIntent {
            val i = Intent(context, WidgetActionActivity::class.java)
            i.data = Uri.parse(uri)
            return PendingIntent.getActivity(
                context, code, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        /** 칸 안의 일정 칩 두 줄: 개수가 3개 이상이면 둘째 줄은 "+N" */
        private fun fillChips(views: RemoteViews, id1: Int, id2: Int, cell: org.json.JSONObject?, theme: WidgetTheme) {
            val list = cell?.optJSONArray("e")
            val n = cell?.optInt("n", 0) ?: 0
            if (list == null || list.length() == 0) {
                views.setViewVisibility(id1, View.GONE)
                views.setViewVisibility(id2, View.GONE)
                return
            }
            fun chip(id: Int, text: String, color: Int) {
                views.setViewVisibility(id, View.VISIBLE)
                views.setTextViewText(id, text)
                views.setInt(id, "setBackgroundColor", color)
                views.setTextColor(id, if (isLight(color)) 0xFF222222.toInt() else 0xFFFFFFFF.toInt())
            }
            val first = list.getJSONObject(0)
            chip(id1, first.optString("t"), first.optLong("c", 0xFF4A7BD9L).toInt())
            if (n > 2) {
                views.setViewVisibility(id2, View.VISIBLE)
                views.setTextViewText(id2, "+" + (n - 1))
                views.setInt(id2, "setBackgroundColor", 0x00000000)
                views.setTextColor(id2, theme.sub)
            } else if (list.length() > 1) {
                val second = list.getJSONObject(1)
                chip(id2, second.optString("t"), second.optLong("c", 0xFF4A7BD9L).toInt())
            } else {
                views.setViewVisibility(id2, View.GONE)
            }
        }

        private fun isLight(color: Int): Boolean {
            val r = (color shr 16) and 0xFF
            val g = (color shr 8) and 0xFF
            val b = color and 0xFF
            return (0.299 * r + 0.587 * g + 0.114 * b) > 170
        }

        private fun fillCalendar(context: Context, id: Int, views: RemoteViews, theme: WidgetTheme, data: SharedPreferences, openApp: PendingIntent) {
            val events = (data.getString("eventDays", "") ?: "").split(",").filter { it.isNotEmpty() }.toHashSet()
            val offset0 = WidgetPrefs(context).monthOffset(id)
            val now = Calendar.getInstance()
            val realYear = now.get(Calendar.YEAR)
            val realMonth = now.get(Calendar.MONTH)
            val shown = Calendar.getInstance()
            shown.set(Calendar.DAY_OF_MONTH, 1)
            shown.add(Calendar.MONTH, offset0)
            val year = shown.get(Calendar.YEAR)
            val month = shown.get(Calendar.MONTH)
            // 오늘 표시는 이번 달을 볼 때만
            val today = if (year == realYear && month == realMonth) now.get(Calendar.DAY_OF_MONTH) else -1

            val first = Calendar.getInstance()
            first.set(year, month, 1)
            val offset = first.get(Calendar.DAY_OF_WEEK) - 1 // 일요일=0
            val daysInMonth = first.getActualMaximum(Calendar.DAY_OF_MONTH)

            views.setTextViewText(R.id.cal_title, "${year}년 ${month + 1}월")
            views.setTextColor(R.id.cal_title, theme.text)
            views.setTextColor(R.id.cal_prev, theme.accent)
            views.setTextColor(R.id.cal_next, theme.accent)
            val dowIds = intArrayOf(R.id.dow_0, R.id.dow_1, R.id.dow_2, R.id.dow_3, R.id.dow_4, R.id.dow_5, R.id.dow_6)
            dowIds.forEach { views.setTextColor(it, theme.sub) }

            // 칸마다 그날의 일정 제목(앞의 2개)을 색 칩으로 보여 준다. 앱이 calCells에 {yyyyMMdd: {n, e:[{t,c}]}}로 넣어 준다.
            val cells = try {
                org.json.JSONObject(data.getString("calCells", "{}") ?: "{}")
            } catch (e: Exception) {
                org.json.JSONObject()
            }
            for (i in 0 until 42) {
                val textId = CELL_TEXT[i]
                val markId = CELL_MARK[i]
                val day = i - offset + 1
                if (day < 1 || day > daysInMonth) {
                    views.setTextViewText(textId, "")
                    views.setViewVisibility(markId, View.GONE)
                    views.setViewVisibility(CELL_E1[i], View.GONE)
                    views.setViewVisibility(CELL_E2[i], View.GONE)
                    views.setOnClickPendingIntent(CELL_ROOT[i], openApp)
                    continue
                }
                views.setTextViewText(textId, day.toString())
                val key = String.format(Locale.US, "%04d%02d%02d", year, month + 1, day)
                // 칸을 누르면 앱이 그날 화면으로 열린다
                val dayKey = String.format(Locale.US, "%04d-%02d-%02d", year, month + 1, day)
                views.setOnClickPendingIntent(CELL_ROOT[i], appActionIntent(context, "ourday://day?date=$dayKey", 0))
                when {
                    day == today -> {
                        views.setViewVisibility(markId, View.VISIBLE)
                        views.setInt(markId, "setColorFilter", theme.accent)
                        views.setInt(markId, "setImageAlpha", 255)
                        views.setTextColor(textId, theme.onAccent)
                    }
                    events.contains(key) -> {
                        views.setViewVisibility(markId, View.VISIBLE)
                        views.setInt(markId, "setColorFilter", theme.accent)
                        views.setInt(markId, "setImageAlpha", 70)
                        views.setTextColor(textId, theme.text)
                    }
                    else -> {
                        views.setViewVisibility(markId, View.GONE)
                        views.setTextColor(textId, theme.text)
                    }
                }
                fillChips(views, CELL_E1[i], CELL_E2[i], cells.optJSONObject(key), theme)
            }
        }
    }
}
