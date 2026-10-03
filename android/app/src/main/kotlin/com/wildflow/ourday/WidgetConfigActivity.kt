package com.wildflow.ourday

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView

/** 위젯을 놓을 때(그리고 위젯을 길게 눌러 "설정"을 고를 때) 모양, 투명도, 색을 고르는 화면 */
class WidgetConfigActivity : Activity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private var style = "list"
    private var opacity = 95
    private var color = 0
    private val swatches = ArrayList<View>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        widgetId = intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        val cfg = WidgetPrefs(this)
        style = cfg.style(widgetId)
        opacity = cfg.opacity(widgetId)
        color = cfg.color(widgetId)

        val dp = resources.displayMetrics.density
        fun px(v: Int) = (v * dp).toInt()

        val root = LinearLayout(this)
        root.orientation = LinearLayout.VERTICAL
        root.setPadding(px(22), px(20), px(22), px(20))

        fun label(text: String): TextView {
            val t = TextView(this)
            t.text = text
            t.textSize = 14f
            t.setTypeface(t.typeface, android.graphics.Typeface.BOLD)
            t.setPadding(0, px(16), 0, px(6))
            return t
        }

        val title = TextView(this)
        title.text = "위젯 설정"
        title.textSize = 20f
        title.setTypeface(title.typeface, android.graphics.Typeface.BOLD)
        root.addView(title)

        // 모양
        root.addView(label("모양"))
        val group = RadioGroup(this)
        group.orientation = RadioGroup.HORIZONTAL
        val rbList = RadioButton(this)
        rbList.id = View.generateViewId()
        rbList.text = "목록형"
        val rbCal = RadioButton(this)
        rbCal.id = View.generateViewId()
        rbCal.text = "달력형"
        group.addView(rbList)
        group.addView(rbCal)
        group.check(if (style == "calendar") rbCal.id else rbList.id)
        group.setOnCheckedChangeListener { _, checkedId ->
            style = if (checkedId == rbCal.id) "calendar" else "list"
        }
        root.addView(group)

        // 투명도
        val opacityLabel = label("")
        fun refreshOpacityLabel() {
            opacityLabel.text = "투명도  (불투명 ${opacity}%)"
        }
        refreshOpacityLabel()
        root.addView(opacityLabel)
        val seek = SeekBar(this)
        seek.max = 100
        seek.progress = opacity
        seek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(bar: SeekBar?, progress: Int, fromUser: Boolean) {
                opacity = progress.coerceAtLeast(10) // 너무 투명하면 안 보이니까 10% 아래로는 안 내림
                refreshOpacityLabel()
            }

            override fun onStartTrackingTouch(bar: SeekBar?) {}
            override fun onStopTrackingTouch(bar: SeekBar?) {}
        })
        root.addView(seek)

        // 색
        root.addView(label("색"))
        val grid = LinearLayout(this)
        grid.orientation = LinearLayout.HORIZONTAL
        grid.gravity = Gravity.CENTER_VERTICAL
        WidgetTheme.all.forEachIndexed { index, theme ->
            val v = View(this)
            val lp = LinearLayout.LayoutParams(px(30), px(30))
            lp.setMargins(px(3), px(3), px(3), px(3))
            v.layoutParams = lp
            v.tag = index
            v.setOnClickListener {
                color = index
                refreshSwatches()
            }
            swatches.add(v)
            grid.addView(v)
        }
        root.addView(grid)
        refreshSwatches()

        val ok = Button(this)
        ok.text = "저장"
        ok.setOnClickListener { save() }
        val okLp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        okLp.topMargin = px(22)
        root.addView(ok, okLp)

        val scroll = ScrollView(this)
        scroll.addView(root)
        setContentView(scroll)
    }

    private fun refreshSwatches() {
        val dp = resources.displayMetrics.density
        swatches.forEachIndexed { index, v ->
            val d = GradientDrawable()
            d.shape = GradientDrawable.OVAL
            d.setColor(WidgetTheme.all[index].bg)
            val selected = index == color
            d.setStroke(
                ((if (selected) 3 else 1) * dp).toInt(),
                if (selected) Color.parseColor("#D9772F") else Color.parseColor("#BBBBBB")
            )
            v.background = d
        }
    }

    private fun save() {
        WidgetPrefs(this).save(widgetId, style, opacity, color)
        val data = getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val mgr = AppWidgetManager.getInstance(this)
        mgr.updateAppWidget(widgetId, OurDayWidget.build(this, widgetId, data))
        val result = Intent()
        result.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        setResult(RESULT_OK, result)
        finish()
    }
}
