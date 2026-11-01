package com.wildflow.magiccalc

import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/** 상단/키패드에 쓰는 선 아이콘들 (24x24 좌표계). */
class IconView(ctx: Context, private val kind: String, private val color: Int) : View(ctx) {
    private val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1.9f
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        color = this@IconView.color
    }

    override fun onDraw(c: Canvas) {
        c.scale(width / 24f, height / 24f)
        when (kind) {
            "history" -> {
                c.drawArc(RectF(3f, 3f, 21f, 21f), -60f, 310f, false, p)
                c.drawLine(12f, 7.5f, 12f, 12f, p)
                c.drawLine(12f, 12f, 15.5f, 14f, p)
                c.drawLine(5.8f, 2.8f, 5.8f, 6.8f, p)
                c.drawLine(5.8f, 6.8f, 9.8f, 6.8f, p)
            }
            "ruler" -> {
                c.save()
                c.rotate(-45f, 12f, 12f)
                c.drawRoundRect(RectF(1.5f, 7.5f, 22.5f, 16.5f), 2f, 2f, p)
                for (x in listOf(6f, 10f, 14f, 18f)) c.drawLine(x, 7.5f, x, 11f, p)
                c.restore()
            }
            "sqrt" -> {
                c.drawRoundRect(RectF(2.5f, 2.5f, 21.5f, 21.5f), 3.5f, 3.5f, p)
                val path = Path().apply {
                    moveTo(6.5f, 12.8f); lineTo(9f, 16f); lineTo(12f, 8.5f); lineTo(17.5f, 8.5f)
                }
                c.drawPath(path, p)
            }
            "back" -> {
                val path = Path().apply {
                    moveTo(2.5f, 12f); lineTo(8f, 5f); lineTo(21f, 5f)
                    lineTo(21f, 19f); lineTo(8f, 19f); close()
                }
                c.drawPath(path, p)
                c.drawLine(11.5f, 9.5f, 16.5f, 14.5f, p)
                c.drawLine(16.5f, 9.5f, 11.5f, 14.5f, p)
            }
        }
    }
}

class MainActivity : Activity() {

    private val engine = CalcEngine()
    private lateinit var prevView: TextView
    private lateinit var lineView: TextView
    private lateinit var cursor: View
    private val handler = Handler(Looper.getMainLooper())
    private val blink = object : Runnable {
        override fun run() {
            cursor.visibility = if (cursor.visibility == View.VISIBLE) View.INVISIBLE else View.VISIBLE
            handler.postDelayed(this, 500)
        }
    }

    override fun onResume() { super.onResume(); handler.postDelayed(blink, 500) }
    override fun onPause() { super.onPause(); handler.removeCallbacks(blink) }

    private val cNum = Color.parseColor("#1A1A1A")
    private val cOp = Color.parseColor("#262626")
    private val cPressed = Color.parseColor("#3A3A3A")
    private val cEq = Color.parseColor("#1F8575")
    private val cRed = Color.parseColor("#EE7570")
    private val cTeal = Color.parseColor("#3FC1B0")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.BLACK
        window.navigationBarColor = Color.BLACK

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.BLACK)
            setPadding(dp(16), dp(16), dp(16), dp(10))
        }

        // 상단 아이콘 줄
        val top = FrameLayout(this)
        top.addView(
            IconView(this, "history", Color.parseColor("#E6E6E6")),
            FrameLayout.LayoutParams(dp(30), dp(30), Gravity.START or Gravity.CENTER_VERTICAL)
        )
        val rightIcons = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        rightIcons.addView(
            IconView(this, "ruler", Color.parseColor("#E6E6E6")),
            LinearLayout.LayoutParams(dp(30), dp(30)).apply { rightMargin = dp(22) }
        )
        rightIcons.addView(IconView(this, "sqrt", Color.parseColor("#E6E6E6")), LinearLayout.LayoutParams(dp(30), dp(30)))
        top.addView(rightIcons, FrameLayout.LayoutParams(-2, -2, Gravity.END or Gravity.CENTER_VERTICAL))
        root.addView(top, LinearLayout.LayoutParams(-1, dp(56)).apply { topMargin = dp(8); leftMargin = dp(8); rightMargin = dp(8) })

        // 디스플레이
        val displayBox = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setGravity(Gravity.END or Gravity.CENTER_VERTICAL)
            setPadding(dp(8), 0, dp(8), 0)
        }
        prevView = TextView(this).apply {
            setTextColor(Color.parseColor("#8E8E8E"))
            textSize = 20f
            typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
            maxLines = 1
            gravity = Gravity.END
        }
        lineView = TextView(this).apply {
            setTextColor(Color.WHITE)
            typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
            maxLines = 1
            includeFontPadding = false
        }
        cursor = View(this).apply { setBackgroundColor(cTeal) }
        val lineRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setGravity(Gravity.END or Gravity.CENTER_VERTICAL)
        }
        lineRow.addView(lineView, LinearLayout.LayoutParams(-2, -2))
        lineRow.addView(cursor, LinearLayout.LayoutParams(dp(2), dp(58)).apply { leftMargin = dp(3) })
        displayBox.addView(prevView, LinearLayout.LayoutParams(-2, -2))
        displayBox.addView(lineRow, LinearLayout.LayoutParams(-2, -2))
        root.addView(displayBox, LinearLayout.LayoutParams(-1, 0, 1f))

        // 키패드
        val rows = listOf(
            listOf("C", "back", "%", "÷"),
            listOf("7", "8", "9", "×"),
            listOf("4", "5", "6", "−"),
            listOf("1", "2", "3", "+"),
            listOf("()", "0", ".", "="),
        )
        val cell = (resources.displayMetrics.widthPixels - dp(32)) / 4
        val size = (cell * 0.8f).toInt()
        val grid = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        for (row in rows) {
            val line = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            for (label in row) {
                val holder = FrameLayout(this)
                holder.addView(makeButton(label), FrameLayout.LayoutParams(size, size, Gravity.CENTER))
                line.addView(holder, LinearLayout.LayoutParams(0, cell, 1f))
            }
            grid.addView(line, LinearLayout.LayoutParams(-1, -2))
        }
        root.addView(grid, LinearLayout.LayoutParams(-1, -2))

        setContentView(root)
        refresh()
    }

    private fun circle(color: Int) = GradientDrawable().apply {
        setShape(GradientDrawable.OVAL)
        setColor(color)
    }

    private fun makeButton(label: String): View {
        val isOp = label in listOf("÷", "×", "−", "+", "%")
        val base = when {
            label == "=" -> cEq
            isOp || label == "C" || label == "back" || label == "()" -> cOp
            else -> cNum
        }
        // 숫자/. 은 약간 더 어두운 색, 기능키는 조금 밝게
        val normalColor = if (label == "C" || label == "back" || label == "()" || isOp) cOp else base
        val bg = StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_pressed), circle(if (label == "=") Color.parseColor("#2AA390") else cPressed))
            addState(intArrayOf(), circle(normalColor))
        }
        val btn = FrameLayout(this).apply {
            background = bg
            isClickable = true
            setOnClickListener {
                when (label) {
                    "C" -> engine.clear()
                    "back" -> engine.backspace()
                    "=" -> engine.equals()
                    "%" -> engine.percent()
                    "()" -> {} // 괄호는 지원하지 않음 (모양만)
                    "." -> engine.decimal()
                    "+", "−", "×", "÷" -> engine.op(label[0])
                    else -> engine.digit(label[0])
                }
                refresh()
            }
        }
        if (label == "back") {
            btn.addView(IconView(this, "back", cRed), FrameLayout.LayoutParams(dp(30), dp(30), Gravity.CENTER))
        } else {
            btn.addView(TextView(this).apply {
                text = label
                gravity = Gravity.CENTER
                typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
                setTextColor(if (label == "C") cRed else Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, if (label == "()" ) 28f else 38f)
                includeFontPadding = false
            }, FrameLayout.LayoutParams(-1, -1))
        }
        return btn
    }

    private fun refresh() {
        val text = engine.line
        lineView.text = text
        lineView.setTextSize(
            TypedValue.COMPLEX_UNIT_SP,
            when {
                text.length <= 7 -> 68f
                text.length <= 9 -> 56f
                text.length <= 11 -> 46f
                text.length <= 14 -> 36f
                text.length <= 18 -> 28f
                text.length <= 23 -> 22f
                else -> 18f
            }
        )
        prevView.text = engine.previous
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
}
