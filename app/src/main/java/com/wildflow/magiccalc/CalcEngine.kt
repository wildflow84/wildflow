package com.wildflow.magiccalc

import java.math.BigDecimal
import java.math.RoundingMode
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

/**
 * 마술용 계산기 엔진 (안드로이드 의존성 없음).
 *
 * 평소엔 일반 계산기. 단, 아래 패턴이면 마술 모드가 켜진다.
 *
 *   A × B × C +      (A, B, C는 1~3자리)
 *
 * '+' 를 누른 뒤 입력하는 숫자는 사실 아무 키나 눌러도 "정해진 숫자 X" 의 자릿수가
 * 한 글자씩 화면에 나타난다. X = (목표 yyMMddHHmm) - A*B*C 이므로 '=' 를 누르면
 * 결과가 항상 목표 시각(현재 + OFFSET_MINUTES분)이 된다.
 */
class CalcEngine(
    private val now: () -> ZonedDateTime = { ZonedDateTime.now(ZONE) },
) {
    companion object {
        val ZONE: ZoneId = ZoneId.of("Asia/Seoul")
        /** 말하는 시간을 고려해 현재 시각에 더해 주는 분. */
        const val OFFSET_MINUTES = 1L
        private val FMT = DateTimeFormatter.ofPattern("yyMMddHHmm")
        private const val MAX_DIGITS = 15
        private const val MAGIC_MAX_OPERAND_DIGITS = 3
        const val ERROR = "오류"
    }

    private val tokens = mutableListOf<String>() // 숫자와 연산자(+ − × ÷)가 번갈아
    private var current = ""
    private var justEvaluated = false
    private var error = false
    private var lastExpr = ""

    // 마술 상태
    private var magicArmed = false
    private var magicProduct = 0L
    private var forced: String? = null

    val display: String
        get() = when {
            error -> ERROR
            current.isNotEmpty() -> current
            tokens.size >= 2 -> tokens[tokens.size - 2]
            else -> "0"
        }

    val expression: String
        get() = if (justEvaluated) lastExpr else tokens.joinToString(" ")

    /** 삼성 계산기처럼 한 줄에 보여줄 전체 수식 (예: 12×34×567+98). 결과 직후엔 결과만. */
    val line: String
        get() = when {
            error -> ERROR
            justEvaluated -> current
            tokens.isEmpty() && current.isEmpty() -> "0"
            else -> tokens.joinToString("") + current
        }

    /** 결과 직후 위에 작게 보여줄 지난 수식. */
    val previous: String
        get() = if (justEvaluated && !error) lastExpr else ""

    fun decimal() {
        if (error) clear()
        if (magicArmed) return
        if (justEvaluated) { current = ""; justEvaluated = false; lastExpr = "" }
        if (current.contains('.') || current.length >= MAX_DIGITS) return
        current = if (current.isEmpty()) "0." else "$current."
    }

    fun percent() {
        if (error || magicArmed || current.isEmpty()) return
        val v = runCatching { BigDecimal(current).divide(BigDecimal(100)) }.getOrNull() ?: return
        current = v.stripTrailingZeros().toPlainString()
    }

    fun clear() {
        tokens.clear(); current = ""; justEvaluated = false; error = false
        lastExpr = ""; magicArmed = false; forced = null
    }

    fun backspace() {
        if (error || justEvaluated) return
        if (current.isNotEmpty()) current = current.dropLast(1)
    }

    fun digit(d: Char) {
        if (error) clear()
        if (justEvaluated) { current = ""; justEvaluated = false; lastExpr = "" }

        if (magicArmed) {
            if (forced == null) forced = computeForced()
            val f = forced
            if (f != null) {
                if (current.length < f.length) current = f.substring(0, current.length + 1)
                return
            }
            magicArmed = false // 목표를 만들 수 없으면 일반 계산기로
        }
        if (current.length >= MAX_DIGITS) return
        current = if (current == "0") d.toString() else current + d
    }

    fun op(o: Char) {
        if (error) return
        if (magicArmed) return // 마술 숫자 입력 중에는 연산자 무시
        if (justEvaluated) { justEvaluated = false; lastExpr = "" }

        if (current.isEmpty()) {
            if (tokens.isNotEmpty()) tokens[tokens.size - 1] = o.toString() // 연산자 교체
            return
        }
        tokens += current
        tokens += o.toString()
        current = ""
        if (o == '+') tryArm()
    }

    fun equals() {
        if (error || justEvaluated || (tokens.isEmpty() && current.isEmpty())) return
        if (magicArmed) {
            if (forced == null) forced = computeForced()
            val f = forced
            if (f != null) {
                // 덜 눌렀어도 마저 채워서 결과를 맞춘다
                tokens += f
                finish(runCatching { evaluate(tokens) }.getOrNull())
                return
            }
            magicArmed = false
            if (tokens.isNotEmpty()) tokens.removeAt(tokens.size - 1) // 마지막 '+' 제거
        } else {
            if (current.isNotEmpty()) tokens += current
            else if (tokens.isNotEmpty()) tokens.removeAt(tokens.size - 1)
        }
        if (tokens.isEmpty()) return
        finish(runCatching { evaluate(tokens) }.getOrNull())
    }

    private fun finish(result: String?) {
        lastExpr = tokens.joinToString(" ") + " ="
        tokens.clear()
        magicArmed = false
        forced = null
        if (result == null) { error = true; current = ""; justEvaluated = false; return }
        current = result
        justEvaluated = true
    }

    private fun tryArm() {
        // [A, ×, B, ×, C, +]
        if (tokens.size != 6) return
        if (tokens[1] != "×" || tokens[3] != "×") return
        val nums = listOf(tokens[0], tokens[2], tokens[4])
        if (nums.any { it.length !in 1..MAGIC_MAX_OPERAND_DIGITS || !it.all(Char::isDigit) }) return
        magicProduct = nums.fold(1L) { acc, s -> acc * s.toLong() }
        magicArmed = true
        forced = null
    }

    /** 첫 자리를 누르는 순간의 시각 기준으로 X를 정한다. */
    private fun computeForced(): String? {
        val target = now().plusMinutes(OFFSET_MINUTES).format(FMT).toLong()
        val x = target - magicProduct
        return if (x > 0) x.toString() else null
    }

    private fun evaluate(t: List<String>): String {
        // 1단계: × ÷
        val nums = mutableListOf(BigDecimal(t[0]))
        val ops = mutableListOf<String>()
        var i = 1
        while (i < t.size) {
            val o = t[i]
            val n = BigDecimal(t[i + 1])
            when (o) {
                "×" -> nums[nums.size - 1] = nums.last().multiply(n)
                "÷" -> {
                    if (n.signum() == 0) throw ArithmeticException("div0")
                    nums[nums.size - 1] = nums.last().divide(n, 10, RoundingMode.HALF_UP)
                }
                else -> { ops += o; nums += n }
            }
            i += 2
        }
        // 2단계: + −
        var acc = nums[0]
        for (k in ops.indices) {
            acc = if (ops[k] == "+") acc.add(nums[k + 1]) else acc.subtract(nums[k + 1])
        }
        val s = acc.stripTrailingZeros()
        return (if (s.signum() == 0) BigDecimal.ZERO else s).toPlainString()
    }
}
