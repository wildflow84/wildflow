package com.wildflow.magiccalc

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class MainActivity : Activity() {

    private val engine = CalcEngine()
    private lateinit var exprView: TextView
    private lateinit var displayView: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.BLACK
        window.navigationBarColor = Color.BLACK

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.BLACK)
            setPadding(dp(12), dp(12), dp(12), dp(12))
        }

        exprView = TextView(this).apply {
            setTextColor(Color.parseColor("#9AA0A6"))
            textSize = 20f
            gravity = Gravity.END or Gravity.BOTTOM
            maxLines = 2
        }
        displayView = TextView(this).apply {
            setTextColor(Color.WHITE)
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
            maxLines = 1
            setAutoSizeTextTypeUniformWithConfiguration(24, 72, 2, android.util.TypedValue.COMPLEX_UNIT_SP)
        }
        root.addView(exprView, LinearLayout.LayoutParams(-1, 0, 1f))
        root.addView(displayView, LinearLayout.LayoutParams(-1, 0, 1.4f))

        val rows = listOf(
            listOf("C", "⌫", "÷", "×"),
            listOf("7", "8", "9", "−"),
            listOf("4", "5", "6", "+"),
            listOf("1", "2", "3", "="),
            listOf("0"),
        )
        val grid = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        for (row in rows) {
            val line = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            for (label in row) {
                val weight = if (row.size == 1) row.size.toFloat() else 1f
                line.addView(makeButton(label), LinearLayout.LayoutParams(0, -1, weight).apply {
                    setMargins(dp(4), dp(4), dp(4), dp(4))
                })
            }
            grid.addView(line, LinearLayout.LayoutParams(-1, 0, 1f))
        }
        root.addView(grid, LinearLayout.LayoutParams(-1, 0, 5f))

        setContentView(root)
        refresh()
    }

    private fun makeButton(label: String): View {
        val isOp = label in listOf("÷", "×", "−", "+", "=")
        val isFn = label == "C" || label == "⌫"
        val bg = GradientDrawable().apply {
            cornerRadius = dp(40).toFloat()
            setColor(
                when {
                    isOp -> Color.parseColor("#FF9500")
                    isFn -> Color.parseColor("#A5A5A5")
                    else -> Color.parseColor("#333333")
                }
            )
        }
        return Button(this).apply {
            text = label
            textSize = 28f
            isAllCaps = false
            setTextColor(if (isFn) Color.BLACK else Color.WHITE)
            background = bg
            stateListAnimator = null
            setOnClickListener {
                when (label) {
                    "C" -> engine.clear()
                    "⌫" -> engine.backspace()
                    "=" -> engine.equals()
                    "+", "−", "×", "÷" -> engine.op(label[0])
                    else -> engine.digit(label[0])
                }
                refresh()
            }
        }
    }

    private fun refresh() {
        exprView.text = engine.expression
        displayView.text = engine.display
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
}
