package com.wildflow.ourday

import android.content.Context
import android.graphics.Color

/** 위젯 색 모음 (배경, 글자, 보조 글자, 강조, 강조 위 글자) */
class WidgetTheme(
    val name: String,
    val bg: Int,
    val text: Int,
    val sub: Int,
    val accent: Int,
    val onAccent: Int
) {
    /** 배경이 밝은 색인지 (밝으면 어두운 글자, 어두우면 밝은 글자) */
    val lightBg: Boolean
        get() = (Color.red(bg) * 299 + Color.green(bg) * 587 + Color.blue(bg) * 114) / 1000 > 160

    /** 카드(날짜별 묶음) 색 */
    val card: Int
        get() = when {
            !lightBg -> Color.argb(0x33, 255, 255, 255)
            bg == Color.WHITE -> Color.parseColor("#F4F1EA")
            else -> Color.WHITE
        }

    /** 카드 안 구분선 색 */
    val line: Int
        get() = if (lightBg) Color.parseColor("#14000000") else Color.parseColor("#33FFFFFF")

    val red: Int
        get() = if (lightBg) Color.parseColor("#D9534F") else Color.WHITE
    val blue: Int
        get() = if (lightBg) Color.parseColor("#3D7DCA") else Color.WHITE

    companion object {
        val all: List<WidgetTheme> = listOf(
            WidgetTheme("크림", Color.parseColor("#FBF5EA"), Color.parseColor("#3A2E26"), Color.parseColor("#9A8B7D"), Color.parseColor("#D9772F"), Color.WHITE),
            WidgetTheme("화이트", Color.WHITE, Color.parseColor("#222222"), Color.parseColor("#8A8A8A"), Color.parseColor("#D9772F"), Color.WHITE),
            WidgetTheme("다크", Color.parseColor("#2A2F45"), Color.WHITE, Color.parseColor("#A9AEC4"), Color.parseColor("#F7B267"), Color.parseColor("#2A2F45")),
            WidgetTheme("블랙", Color.parseColor("#151515"), Color.WHITE, Color.parseColor("#A0A0A0"), Color.parseColor("#F7B267"), Color.parseColor("#151515")),
            WidgetTheme("주황", Color.parseColor("#D9772F"), Color.WHITE, Color.parseColor("#FBE3CC"), Color.WHITE, Color.parseColor("#D9772F")),
            WidgetTheme("파랑", Color.parseColor("#3D7DCA"), Color.WHITE, Color.parseColor("#D6E6F8"), Color.WHITE, Color.parseColor("#3D7DCA")),
            WidgetTheme("초록", Color.parseColor("#3FA45B"), Color.WHITE, Color.parseColor("#DDF1E3"), Color.WHITE, Color.parseColor("#3FA45B")),
            WidgetTheme("분홍", Color.parseColor("#E5588C"), Color.WHITE, Color.parseColor("#FADCE8"), Color.WHITE, Color.parseColor("#E5588C"))
        )
    }
}

/** 위젯마다 따로 저장하는 설정: 모양(목록/달력), 투명도, 색 */
class WidgetPrefs(context: Context) {
    private val sp = context.getSharedPreferences("ourday_widget_cfg", Context.MODE_PRIVATE)

    fun style(id: Int): String = sp.getString("style_$id", "list") ?: "list"
    /** 불투명도 0~100 (100이면 완전 불투명) */
    fun opacity(id: Int): Int = sp.getInt("opacity_$id", 95)
    fun color(id: Int): Int = sp.getInt("color_$id", 0).coerceIn(0, WidgetTheme.all.size - 1)

    fun save(id: Int, style: String, opacity: Int, color: Int) {
        sp.edit().putString("style_$id", style).putInt("opacity_$id", opacity).putInt("color_$id", color).apply()
    }

    fun remove(id: Int) {
        sp.edit().remove("style_$id").remove("opacity_$id").remove("color_$id").apply()
    }
}
