package com.wildflow.polestarautooff

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

class MainActivity : Activity() {
    private lateinit var status: TextView
    private lateinit var logView: TextView
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 32, 32, 32)
        }
        status = TextView(this).apply { textSize = 18f }
        root.addView(status)

        fun button(label: String, onClick: () -> Unit) {
            root.addView(Button(this).apply {
                text = label
                setOnClickListener { onClick() }
            })
        }

        button("접근성 서비스 켜기") {
            if (!Access.ensureEnabled(this)) {
                startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            }
            refresh()
        }
        button("지금 실행") {
            val svc = AutoOffService.instance
            if (svc == null) toast("접근성 서비스가 꺼져 있어요") else svc.trigger("manual", force = true)
        }
        button("10초 뒤 현재 화면 덤프 (그 사이 대상 화면으로 이동)") {
            toast("10초 뒤 덤프해요")
            handler.postDelayed({ AutoOffService.instance?.dumpScreen() }, 10_000)
        }
        button("로그 새로고침") { refresh() }
        button("로그 지우기") {
            Logger.clear(this)
            refresh()
        }

        logView = TextView(this).apply {
            textSize = 12f
            setTextIsSelectable(true)
        }
        root.addView(
            ScrollView(this).apply { addView(logView) },
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f),
        )
        setContentView(root)
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    private fun refresh() {
        status.text = if (AutoOffService.instance != null) "서비스: 켜짐" else "서비스: 꺼짐"
        logView.text = Logger.read(this)
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
}
