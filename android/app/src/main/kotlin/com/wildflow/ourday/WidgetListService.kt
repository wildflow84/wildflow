package com.wildflow.ourday

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.StrikethroughSpan
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray
import org.json.JSONObject

/** 목록형 위젯의 스크롤 목록: 앱의 "목록" 탭처럼 날짜 머리글 + 날짜별 둥근 카드 */
class WidgetListService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsService.RemoteViewsFactory {
        return Factory(applicationContext, intent)
    }

    private class Row(
        val header: Boolean,
        val label: String,
        val kind: String,
        val note: String,
        val item: JSONObject?,
        val pos: Int // 카드 안 위치: 0=혼자, 1=맨 위, 2=가운데, 3=맨 아래
    )

    private class Factory(private val context: Context, intent: Intent) : RemoteViewsService.RemoteViewsFactory {
        private val widgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID
        )
        private var rows: List<Row> = emptyList()
        private var theme: WidgetTheme = WidgetTheme.all[0]

        override fun onCreate() {
            load()
        }

        override fun onDataSetChanged() {
            load()
        }

        override fun onDestroy() {}

        private fun load() {
            theme = WidgetTheme.all[WidgetPrefs(context).color(widgetId)]
            val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            val json = prefs.getString("agendaJson", "[]") ?: "[]"
            val out = ArrayList<Row>()
            try {
                val days = JSONArray(json)
                for (d in 0 until days.length()) {
                    val day = days.getJSONObject(d)
                    val items = day.getJSONArray("items")
                    out.add(Row(true, day.optString("label"), day.optString("kind"), day.optString("note"), null, 0))
                    for (i in 0 until items.length()) {
                        val pos = when {
                            items.length() == 1 -> 0
                            i == 0 -> 1
                            i == items.length() - 1 -> 3
                            else -> 2
                        }
                        out.add(Row(false, "", "", "", items.getJSONObject(i), pos))
                    }
                }
            } catch (e: Exception) {
                // 데이터가 깨졌으면 빈 목록
            }
            rows = out
        }

        override fun getCount(): Int = rows.size

        override fun getViewAt(position: Int): RemoteViews {
            val row = rows[position]
            return if (row.header) headerView(row) else itemView(row)
        }

        private fun px(dp: Int): Int = (dp * context.resources.displayMetrics.density).toInt()

        private fun headerView(row: Row): RemoteViews {
            val v = RemoteViews(context.packageName, R.layout.widget_row_header)
            v.setTextViewText(R.id.hdr_label, row.label)
            val color = when (row.kind) {
                "today" -> theme.accent
                "holiday" -> theme.red
                "sat" -> theme.blue
                else -> theme.text
            }
            v.setTextColor(R.id.hdr_label, color)
            v.setTextViewText(R.id.hdr_note, row.note)
            v.setTextColor(R.id.hdr_note, theme.sub)
            return v
        }

        private fun itemView(row: Row): RemoteViews {
            val item = row.item!!
            val v = RemoteViews(context.packageName, R.layout.widget_row_item)
            val todo = item.optBoolean("todo")
            val done = item.optBoolean("done")
            val catColor = item.optLong("color", 0xFF4A7BD9L).toInt()

            // 카드 배경 (위치에 따라 모서리 다르게)
            val bg = when (row.pos) {
                1 -> R.drawable.card_top
                2 -> R.drawable.card_mid
                3 -> R.drawable.card_bottom
                else -> R.drawable.card_single
            }
            v.setImageViewResource(R.id.row_bg, bg)
            v.setInt(R.id.row_bg, "setColorFilter", theme.card)
            v.setInt(R.id.row_bg, "setImageAlpha", theme.cardAlpha)
            v.setViewVisibility(R.id.row_divider, if (row.pos == 2 || row.pos == 3) View.VISIBLE else View.GONE)
            v.setInt(R.id.row_divider, "setBackgroundColor", theme.line)
            // 카드가 끝나는 줄 아래 여백
            val bottomPad = if (row.pos == 0 || row.pos == 3) px(2) else 0
            v.setViewPadding(R.id.row_root, px(8), 0, px(8), bottomPad)

            // 왼쪽 표시: 할 일은 체크박스, 일정은 카테고리 색 점
            if (todo) {
                v.setTextViewText(R.id.row_glyph, if (done) "☑" else "☐")
                v.setTextColor(R.id.row_glyph, theme.text)
            } else {
                v.setTextViewText(R.id.row_glyph, "●")
                v.setTextColor(R.id.row_glyph, catColor)
            }

            val title = SpannableStringBuilder(item.optString("t"))
            if (done) title.setSpan(StrikethroughSpan(), 0, title.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            v.setTextViewText(R.id.row_title, title)
            v.setTextColor(R.id.row_title, if (done) theme.sub else theme.text)

            v.setTextViewText(R.id.row_meta, metaText(item, catColor))
            v.setTextColor(R.id.row_meta, theme.sub)

            // 전체 줄은 앱 열기, 체크박스는 앱을 열지 않고 바로 완료 처리
            val id = item.optString("id")
            val space = item.optString("sp")
            val dk = item.optString("dk")
            val edit = Intent()
            if (id.isNotEmpty() && dk.isNotEmpty()) {
                edit.data = Uri.parse("ourday://edit?id=" + Uri.encode(id) + "&date=" + Uri.encode(dk))
            }
            v.setOnClickFillInIntent(R.id.row_root, edit)
            if (todo && item.optBoolean("can") && id.isNotEmpty() && space.isNotEmpty() && dk.isNotEmpty()) {
                val done = Intent()
                done.data = Uri.parse(
                    "ourday://done?space=" + Uri.encode(space) + "&id=" + Uri.encode(id) + "&date=" + Uri.encode(dk)
                )
                v.setOnClickFillInIntent(R.id.row_glyph, done)
            }
            return v
        }

        /** 시간 · 장소 · ● 카테고리 · 반복 · 나만 */
        private fun metaText(item: JSONObject, catColor: Int): CharSequence {
            val sb = SpannableStringBuilder()
            fun sep() {
                if (sb.isNotEmpty()) sb.append("   ")
            }
            val time = item.optString("time")
            if (time.isNotEmpty()) {
                sep()
                sb.append("🕒 ").append(time)
            }
            val place = item.optString("place")
            if (place.isNotEmpty()) {
                sep()
                sb.append("📍 ").append(place)
            }
            val cat = item.optString("cat")
            if (cat.isNotEmpty()) {
                sep()
                val start = sb.length
                sb.append("●")
                sb.setSpan(ForegroundColorSpan(catColor), start, start + 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                sb.append(" ").append(cat)
            }
            val rep = item.optString("rep")
            if (rep.isNotEmpty()) {
                sep()
                sb.append("🔁 ").append(rep)
            }
            if (item.optBoolean("priv")) {
                sep()
                sb.append("🔒 나만")
            }
            return sb
        }

        override fun getLoadingView(): RemoteViews? = null

        override fun getViewTypeCount(): Int = 2

        override fun getItemId(position: Int): Long = position.toLong()

        override fun hasStableIds(): Boolean = false
    }
}
