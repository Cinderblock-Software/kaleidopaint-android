// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint.geometry

import java.math.BigDecimal
import java.math.RoundingMode
import kotlin.math.abs
import kotlin.math.sign
import kotlin.math.truncate

//	A few Swift and C library behaviours that the translated code relies on,
//	under the names the original uses for them.

//	Swift's assertionFailure() stops a debug build and does nothing
//	in a release build.  Kotlin's assert() behaves the same way:
//	it throws when the JVM runs with assertions enabled
//	(as it does under the unit tests) and does nothing on Android.
internal fun assertionFailure(message: String) {
    assert(false) { message }
}

//	Swift's precondition() stops the program in every build.
internal fun precondition(condition: Boolean, message: String) {
    if (!condition) {
        throw IllegalStateException(message)
    }
}

internal fun preconditionFailure(message: String): Nothing {
    throw IllegalStateException(message)
}

//	Both C's round() and Swift's Double.rounded() round
//	to the nearest integer, with halves going away from zero.
//	(Kotlin's own round() sends halves to the nearest even integer,
//	and Math.round() sends them upwards, so neither will do.)
internal fun round(x: Double): Double {
    val theIntegerPart = truncate(x)
    return if (abs(x - theIntegerPart) >= 0.5) theIntegerPart + sign(x) else theIntegerPart
}

//	C's fabs()
internal fun fabs(x: Double): Double = abs(x)

// MARK: -
// MARK: Writing numbers the way C's printf() does

//	Swift's String(format:), for the conversions the drawing-file encoder uses:
//	%d, and %f or %lf with an optional width and precision, as in "%20.16lf".
//
//	java.util.Formatter would not do.  When a number sits exactly half way
//	between two printable values (1/512 = 0.001953125 printed to 8 places)
//	printf() rounds to the even neighbour and Java rounds up, and Java
//	prints a negative zero without its sign.  A drawing written here must
//	match, byte for byte, the one KaleidoPaint itself would write.
internal fun stringWithFormat(format: String, vararg arguments: Any): String {

    val theResult = StringBuilder()
    var theArgumentIndex = 0

    var i = 0
    while (i < format.length) {

        if (format[i] != '%') {
            theResult.append(format[i])
            i += 1
            continue
        }
        i += 1

        val zeroPad = format[i] == '0'
        var theWidth = 0
        while (format[i] in '0'..'9') {
            theWidth = 10 * theWidth + (format[i] - '0')
            i += 1
        }

        var thePrecision = 6 // 	printf()'s default
        if (format[i] == '.') {
            i += 1
            thePrecision = 0
            while (format[i] in '0'..'9') {
                thePrecision = 10 * thePrecision + (format[i] - '0')
                i += 1
            }
        }

        if (format[i] == 'l') { // 	"%lf" means the same as "%f"
            i += 1
        }

        val theText =
            when (format[i]) {
                'd' -> (arguments[theArgumentIndex] as Number).toLong().toString()
                'f' -> fixedPointText(arguments[theArgumentIndex] as Double, thePrecision)
                else -> throw IllegalArgumentException("unsupported conversion %${format[i]}")
            }
        theArgumentIndex += 1
        i += 1

        //	Right-justify in a field of the given width.
        //	A number too wide for its field is printed in full.
        val padding = (theWidth - theText.length).coerceAtLeast(0)
        if (zeroPad && theText.none { it.isLetter() }) {
            if (theText.startsWith("-")) theResult.append('-')
            repeat(padding) { theResult.append('0') }
            theResult.append(if (theText.startsWith("-")) theText.drop(1) else theText)
        } else {
            repeat(padding) { theResult.append(' ') }
            theResult.append(theText)
        }
    }

    return theResult.toString()
}

private fun fixedPointText(x: Double, precision: Int): String {

    if (x.isNaN()) {
        return "nan"
    }
    if (x.isInfinite()) {
        return if (x > 0.0) "inf" else "-inf"
    }

    //	BigDecimal(x) is the exact value of the double,
    //	which is what printf() rounds.
    val theDigits = BigDecimal(x).setScale(precision, RoundingMode.HALF_EVEN).abs().toPlainString()

    //	Keep the sign even when the digits are all zeros,
    //	as for -0.0 and for a small negative number that rounds to zero.
    val isNegative = (x < 0.0 || (x == 0.0 && 1.0 / x < 0.0))

    return if (isNegative) "-$theDigits" else theDigits
}

// MARK: -
// MARK: Reading numbers the way Swift does

//	Swift's Double(String), which the drawing-file decoder reads its numbers with.
//	It accepts what C's strtod() accepts, provided the whole string is used:
//	decimal numbers with an optional sign, fraction and exponent,
//	"inf", "infinity" and "nan" in any case, and hexadecimal numbers.
//	Kotlin's toDoubleOrNull() also accepts "1.5f" and " 1 " and refuses "0x10",
//	so the rules are spelled out here.
private val gDecimalNumber = Regex("""[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?""")
private val gHexadecimalNumber =
    Regex("""[+-]?0[xX]([0-9a-fA-F]+\.?[0-9a-fA-F]*|\.[0-9a-fA-F]+)([pP][+-]?[0-9]+)?""")
private val gInfinity = Regex("""[+-]?(inf|infinity)""", RegexOption.IGNORE_CASE)
private val gNotANumber = Regex("""[+-]?nan(\([0-9a-zA-Z_]*\))?""", RegexOption.IGNORE_CASE)

internal fun swiftDouble(string: String): Double? {

    if (gDecimalNumber.matches(string)) {
        return string.toDouble()
    }
    if (gInfinity.matches(string)) {
        return if (string.startsWith("-")) Double.NEGATIVE_INFINITY else Double.POSITIVE_INFINITY
    }
    if (gNotANumber.matches(string)) {
        return Double.NaN
    }
    if (gHexadecimalNumber.matches(string)) {
        //	Java insists on a binary exponent;  C and Swift don't.
        val hasExponent = string.contains('p') || string.contains('P')
        return (if (hasExponent) string else string + "p0").toDouble()
    }

    return null
}

//	Swift's Int(String):  an optional sign and ASCII digits, nothing else,
//	and nil if the value doesn't fit in 64 bits.
private val gInteger = Regex("""[+-]?[0-9]+""")

internal fun swiftInt(string: String): Long? {

    if (!gInteger.matches(string)) {
        return null
    }

    return string.toLongOrNull()
}

//	Foundation's String.components(separatedBy: .whitespacesAndNewlines).
//	That character set is Unicode's space separators, line separator
//	and paragraph separator, plus tab, U+000A through U+000D, U+0085 and U+200B.
//	Like the original, the result includes an empty string
//	wherever two separators are adjacent.
internal fun componentsSeparatedByWhitespacesAndNewlines(string: String): List<String> {

    val theComponents = mutableListOf<String>()
    val theComponent = StringBuilder()

    for (theCharacter in string) {
        val isSeparator =
            (theCharacter == '\t' ||
                theCharacter in '\n'..'\r' ||
                theCharacter == '\u0085' ||
                theCharacter == '\u200B' ||
                Character.isSpaceChar(theCharacter))
        if (isSeparator) {
            theComponents.add(theComponent.toString())
            theComponent.setLength(0)
        } else {
            theComponent.append(theCharacter)
        }
    }
    theComponents.add(theComponent.toString())

    return theComponents
}
