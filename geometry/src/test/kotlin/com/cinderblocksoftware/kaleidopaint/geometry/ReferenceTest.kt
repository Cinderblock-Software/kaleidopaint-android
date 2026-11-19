// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint.geometry

import kotlin.math.abs
import kotlin.math.max
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Compares the Kotlin port with upstream's Swift code.
 *
 * `reference.txt` is what Jeff Weeks's own, unmodified Swift files print for the inputs in
 * `tools/reference/main.swift` (regenerate it with `tools/reference/build.sh` on a Mac).
 * [ReferenceScenario] runs the same inputs through the Kotlin port. Every key must be present on
 * both sides and every value must agree.
 */
class ReferenceTest {

    companion object {

        //	The two sides do the same arithmetic in the same order, so most
        //	values agree to the last bit.  The rest differ in the last place
        //	or two, because simd's matrix products use fused multiply-adds
        //	and its inverse orders its operations differently.
        const val doubleTolerance = 1e-12

        //	Vertices are rounded to single precision for the GPU;
        //	a last-place difference in the double can move the float by one step.
        const val floatTolerance = 5e-7f

        val reference: Map<String, ReferenceValue> by lazy { loadReference() }

        val scenario: Map<String, ReferenceValue> by lazy {
            val theScenario = ReferenceScenario(reference)
            theScenario.emitWallpaperGroups()
            theScenario.emitConstants()
            theScenario.emitUnitCellPlacements()
            theScenario.emitCoordinateSystems()
            theScenario.emitSplines()
            theScenario.emitVectorComputations()
            theScenario.emitRendering()
            theScenario.emitHitTesting()
            theScenario.emitDrawings()
            theScenario.emitMalformedDrawings()
            theScenario.emitNumberParsing()
            theScenario.emitEditingSession()
            theScenario.emitTileExports()
            theScenario.itsLines
        }

        private fun parseDouble(token: String): Double =
            when {
                token == "inf" || token == "+inf" -> Double.POSITIVE_INFINITY
                token == "-inf" -> Double.NEGATIVE_INFINITY
                token.startsWith("nan") || token.startsWith("-nan") ->
                    Double.NaN // 	also "nan(0x1)"
                else -> token.toDouble()
            }

        private fun loadReference(): Map<String, ReferenceValue> {
            val theStream =
                ReferenceTest::class.java.getResourceAsStream("/reference.txt")
                    ?: error("reference.txt is missing; run tools/reference/build.sh")
            return loadReference(theStream)
        }

        fun loadReference(theStream: java.io.InputStream): Map<String, ReferenceValue> {
            val theLines = LinkedHashMap<String, ReferenceValue>()
            theStream.bufferedReader(Charsets.UTF_8).useLines { lines ->
                for (theLine in lines) {
                    if (theLine.isEmpty()) continue
                    val theFields = theLine.split("\t", limit = 3)
                    check(theFields.size == 3) { "malformed reference line: $theLine" }
                    val (theKey, theType, theText) = theFields
                    val theTokens = theText.split(" ").filter { it.isNotEmpty() }
                    val theValue =
                        when (theType) {
                            "S" -> ReferenceValue.Text(theText)
                            "I" -> ReferenceValue.Ints(theTokens.map { it.toLong() })
                            "D" -> ReferenceValue.Doubles(theTokens.map { parseDouble(it) })
                            "F" ->
                                ReferenceValue.Floats(theTokens.map { parseDouble(it).toFloat() })
                            else -> error("unknown type $theType in reference line: $theLine")
                        }
                    check(theLines.put(theKey, theValue) == null) {
                        "duplicate reference key $theKey"
                    }
                }
            }
            return theLines
        }

        private fun doublesAgree(a: Double, b: Double): Boolean {
            if (a == b) return true // 	also covers -0.0 == 0.0 and equal infinities
            if (a.isNaN() && b.isNaN()) return true
            return abs(a - b) <= doubleTolerance * max(1.0, max(abs(a), abs(b)))
        }

        private fun floatsAgree(a: Float, b: Float): Boolean {
            if (a == b) return true
            if (a.isNaN() && b.isNaN()) return true
            return abs(a - b) <= floatTolerance * max(1.0f, max(abs(a), abs(b)))
        }

        //	Returns null if the two values agree, or a description of the disagreement.
        fun disagreement(expected: ReferenceValue, actual: ReferenceValue): String? {
            if (expected is ReferenceValue.Text && actual is ReferenceValue.Text) {
                return if (expected.string == actual.string) null
                else "Swift \"${expected.string}\", Kotlin \"${actual.string}\""
            }
            if (expected is ReferenceValue.Ints && actual is ReferenceValue.Ints) {
                return if (expected.ints == actual.ints) null
                else "Swift ${expected.ints}, Kotlin ${actual.ints}"
            }
            if (expected is ReferenceValue.Doubles && actual is ReferenceValue.Doubles) {
                if (expected.doubles.size != actual.doubles.size) {
                    return "Swift has ${expected.doubles.size} numbers, Kotlin ${actual.doubles.size}"
                }
                for (i in expected.doubles.indices) {
                    if (!doublesAgree(expected.doubles[i], actual.doubles[i])) {
                        return "number $i: Swift ${expected.doubles[i]}, Kotlin ${actual.doubles[i]}"
                    }
                }
                return null
            }
            if (expected is ReferenceValue.Floats && actual is ReferenceValue.Floats) {
                if (expected.floats.size != actual.floats.size) {
                    return "Swift has ${expected.floats.size} numbers, Kotlin ${actual.floats.size}"
                }
                for (i in expected.floats.indices) {
                    if (!floatsAgree(expected.floats[i], actual.floats[i])) {
                        return "number $i: Swift ${expected.floats[i]}, Kotlin ${actual.floats[i]}"
                    }
                }
                return null
            }
            return "Swift wrote ${expected::class.simpleName}, Kotlin ${actual::class.simpleName}"
        }
    }

    private fun compareSection(prefix: String, expectedMinimumLineCount: Int) {

        val theExpected = reference.filterKeys { it.startsWith(prefix) }
        val theActual = scenario.filterKeys { it.startsWith(prefix) }

        assertTrue(
            "the reference has only ${theExpected.size} lines under $prefix",
            theExpected.size >= expectedMinimumLineCount,
        )

        val theProblems = mutableListOf<String>()
        for ((theKey, theExpectedValue) in theExpected) {
            val theActualValue = theActual[theKey]
            if (theActualValue == null) {
                theProblems.add("$theKey: Swift has it, Kotlin doesn't")
                continue
            }
            // Intentional Android input-safety divergence: unknown versions are rejected.
            val expectedValue =
                if (
                    theKey in
                        setOf("malformed.minor-from-the-future", "malformed.major-from-the-future")
                )
                    ReferenceValue.Text("Invalid drawing-file format version")
                else theExpectedValue
            disagreement(expectedValue, theActualValue)?.let { theProblems.add("$theKey: $it") }
        }
        for (theKey in theActual.keys) {
            if (theKey !in theExpected) {
                theProblems.add("$theKey: Kotlin has it, Swift doesn't")
            }
        }

        if (theProblems.isNotEmpty()) {
            fail(
                "${theProblems.size} of ${theExpected.size} reference lines under $prefix disagree:\n" +
                    theProblems.take(25).joinToString("\n")
            )
        }
    }

    @Test fun wallpaperGroups() = compareSection("groups.", 350)

    @Test fun constants() = compareSection("constants.", 20)

    @Test fun unitCellPlacements() = compareSection("placement.", 500)

    @Test fun coordinateSystems() = compareSection("coordinates.", 400)

    @Test fun splines() = compareSection("spline.", 900)

    @Test fun vectorComputations() = compareSection("vectors.", 50)

    @Test fun rendering() = compareSection("render.", 1800)

    @Test fun hitTesting() = compareSection("hit.", 3200)

    //	Every drawing upstream wrote, and every hand-built drawing in an older
    //	file format, read back by the Kotlin decoder:  the group, the placement,
    //	the colours and every element must be what upstream's decoder read.
    @Test fun drawingsReadBack() = compareSection("document.", 2000)

    //	Files that upstream refuses must be refused for the same stated reason.
    @Test fun malformedDrawings() = compareSection("malformed.", 45)

    //	Which strings count as numbers in a drawing file.
    @Test fun numberParsing() = compareSection("numbers.", 60)

    //	An editing session:  strokes, taps, drags of every kind of handle,
    //	every undoable operation, then everything undone and redone.
    //	After each step the drawing must be what upstream's drawing is.
    @Test fun editingSession() = compareSection("session.", 1500)

    @Test
    fun everyReferenceLineBelongsToASection() {
        val theSections =
            listOf(
                "groups.",
                "constants.",
                "placement.",
                "coordinates.",
                "spline.",
                "vectors.",
                "render.",
                "hit.",
                "document.",
                "malformed.",
                "numbers.",
                "session.",
            )
        val theStrays = reference.keys.filter { key -> theSections.none { key.startsWith(it) } }
        assertEquals(listOf<String>(), theStrays)
        assertEquals(reference.size, scenario.size)
    }

    //	How close is "agree"?  Not an assertion, just a number worth seeing:
    //	run with --info to read it.
    @Test
    fun reportHowManyNumbersAreBitIdentical() {
        var theTotal = 0
        var theIdentical = 0
        var theWorst = 0.0
        for ((theKey, theExpected) in reference) {
            val theActual = scenario[theKey]
            if (
                theExpected is ReferenceValue.Doubles &&
                    theActual is ReferenceValue.Doubles &&
                    theExpected.doubles.size == theActual.doubles.size
            ) {
                for (i in theExpected.doubles.indices) {
                    theTotal += 1
                    val a = theExpected.doubles[i]
                    val b = theActual.doubles[i]
                    if (a == b || (a.isNaN() && b.isNaN())) {
                        theIdentical += 1
                    } else {
                        theWorst = max(theWorst, abs(a - b) / max(1.0, max(abs(a), abs(b))))
                    }
                }
            }
        }
        println(
            "reference doubles: $theIdentical of $theTotal bit-identical; worst relative difference $theWorst"
        )
        assertTrue(theTotal > 10000)
    }
}
