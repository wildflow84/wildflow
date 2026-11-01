package com.wildflow.magiccalc

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.ZonedDateTime

class CalcEngineTest {
    private fun at(y: Int, mo: Int, d: Int, h: Int, mi: Int) =
        { ZonedDateTime.of(y, mo, d, h, mi, 30, 0, CalcEngine.ZONE) }

    private fun CalcEngine.type(s: String) {
        for (c in s) when (c) {
            '+', '−', '×', '÷' -> op(c)
            '=' -> equals()
            else -> digit(c)
        }
    }

    @Test fun magicExample() {
        val e = CalcEngine(at(2026, 11, 1, 17, 53)) // +1분 => 2611011754
        e.type("12×34×567+")
        e.type("9876543210") // 아무 숫자
        assertEquals("2611011754", e.run { equals(); display })
    }

    @Test fun magicShownDigitsAreAPrefixOfAnswerMinusProduct() {
        val e = CalcEngine(at(2026, 11, 1, 17, 53))
        e.type("99×99×99+")
        e.type("0000")
        assertEquals((2611011754L - 99L * 99 * 99).toString().take(4), e.display)
    }

    @Test fun magicEarlyEqualsStillCorrect() {
        val e = CalcEngine(at(2027, 1, 2, 3, 59)) // +1분 => 2701020400
        e.type("100×200×300+")
        e.type("12=")
        assertEquals("2701020400", e.display)
    }

    @Test fun magicExtraDigitsIgnored() {
        val e = CalcEngine(at(2026, 11, 1, 17, 53))
        e.type("11×22×33+")
        e.type("1".repeat(30))
        assertEquals(10, e.display.length)
        e.equals()
        assertEquals("2611011754", e.display)
    }

    @Test fun normalCalcPrecedence() {
        val e = CalcEngine()
        e.type("2+3×4=")
        assertEquals("14", e.display)
    }

    @Test fun normalDivision() {
        val e = CalcEngine()
        e.type("7÷2=")
        assertEquals("3.5", e.display)
        e.clear(); e.type("5÷0=")
        assertEquals(CalcEngine.ERROR, e.display)
    }

    @Test fun nonMagicPatternIsNormal() {
        val e = CalcEngine()
        e.type("12×34+56=")
        assertEquals("464", e.display)
    }

    @Test fun lineShowsWholeExpression() {
        val e = CalcEngine()
        e.type("12×34+5")
        assertEquals("12×34+5", e.line)
        e.equals()
        assertEquals("413", e.line)
        assertEquals("12 × 34 + 5 =", e.previous)
    }

    @Test fun decimalAndPercent() {
        val e = CalcEngine()
        e.type("0"); e.decimal(); e.type("5+2=")
        assertEquals("2.5", e.line)
        e.clear(); e.type("50"); e.percent()
        assertEquals("0.5", e.line)
    }

    @Test fun magicLineShowsTypedDigits() {
        val e = CalcEngine(at(2026, 11, 1, 17, 53))
        e.type("12×34×567+123")
        assertEquals("12×34×567+261", e.line)
    }
}
