// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint.geometry

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * The drawing files themselves, compared byte for byte.
 *
 * `src/test/resources/drawings/` holds drawings written by upstream's own
 * `KaleidoPaintDocument.encodeFileFormat()` (see `tools/reference/build.sh`):
 *
 * - `NAME.kaleidopaint` is a drawing as upstream first wrote it;
 * - `NAME.rewritten.kaleidopaint` is what upstream wrote after reading that file back. Reading may
 *   change a drawing: old formats are converted, curves are re-centred, and the numbers were
 *   rounded.
 *
 * [ReferenceTest.drawingsReadBack] checks that the Kotlin decoder reads what upstream reads. This
 * class checks that the Kotlin encoder writes what upstream writes.
 */
class DrawingFileTest {

    private val scenario = ReferenceScenario(ReferenceTest.reference)

    private val allNames: List<String> =
        scenario.builtDocuments().map { it.first } +
            ReferenceScenario.touchDrawnNames +
            ReferenceScenario.legacyNames.map { "legacy-$it" }

    private fun decode(text: String): KaleidoPaintDocument {
        val theDocument = KaleidoPaintDocument()
        theDocument.decodeFileFormat(text)
        return theDocument
    }

    //	Tells where two texts first differ, which a 3 kB assertEquals() doesn't.
    private fun assertSameText(name: String, expected: String, actual: String) {
        if (expected == actual) return
        val theExpectedLines = expected.split("\n")
        val theActualLines = actual.split("\n")
        for (i in 0 until minOf(theExpectedLines.size, theActualLines.size)) {
            if (theExpectedLines[i] != theActualLines[i]) {
                fail(
                    "$name, line ${i + 1}:\n  upstream <${theExpectedLines[i]}>\n  Kotlin   <${theActualLines[i]}>"
                )
            }
        }
        fail("$name: upstream wrote ${theExpectedLines.size} lines, Kotlin ${theActualLines.size}")
    }

    //	The file KaleidoPaint 3.1.2 itself saved, running on an iOS simulator,
    //	when asked for a new drawing (see resources/from-the-app/README.md).
    //	The app starts new drawings in the group 632.
    @Test
    fun aNewDrawingIsWrittenAsTheAppItselfWritesIt() {
        val theStream =
            DrawingFileTest::class
                .java
                .getResourceAsStream("/from-the-app/new-drawing.kaleidopaint")
                ?: error("from-the-app/new-drawing.kaleidopaint is missing")
        val theAppsFile = theStream.use { it.readBytes().toString(Charsets.UTF_8) }

        val theNewDrawing = KaleidoPaintDocument(defaultSymmetryGroup = WallpaperGroup.wpg632)
        assertSameText("a new drawing", theAppsFile, theNewDrawing.encodeFileFormat())
        assertSameText(
            "the app's file, read and rewritten",
            theAppsFile,
            decode(theAppsFile).encodeFileFormat(),
        )
    }

    //	A drawing built in memory, with numbers at full precision,
    //	must be written exactly as upstream writes the same drawing.
    @Test
    fun drawingsBuiltInMemoryAreWrittenAsUpstreamWritesThem() {
        val theDocuments = scenario.builtDocuments()
        assertEquals(19, theDocuments.size)
        for ((theName, theDocument) in theDocuments) {
            assertSameText(
                theName,
                ReferenceScenario.drawingText(theName),
                theDocument.encodeFileFormat(),
            )
        }
    }

    //	Reading a file and writing it again must give what upstream gives:
    //	for its own drawings, for drawings made by its touch handling,
    //	and for drawings in every older file format.
    @Test
    fun everyDrawingIsRewrittenAsUpstreamRewritesIt() {
        assertEquals(33, allNames.size)
        for (theName in allNames) {
            val theRewritten = decode(ReferenceScenario.drawingText(theName)).encodeFileFormat()
            assertSameText(
                theName,
                ReferenceScenario.drawingText("$theName.rewritten"),
                theRewritten,
            )
        }
    }

    //	Once rewritten, a drawing no longer changes:  open, save, open, save…
    //
    //	…with one exception, which upstream shares.  A curve whose middle
    //	lies exactly on a cell boundary is re-centred on every reading,
    //	one cell this way and then one cell back.  The "halves" curve in
    //	group-06 and group-14 is built to sit there, and so, it turns out,
    //	does a stroke drawn symmetrically across the middle of the screen.
    //	Either way the drawing looks the same, and two rewrites always
    //	bring the same text back.
    @Test
    fun aRewrittenDrawingIsStable() {
        val theOscillating = mutableListOf<String>()
        for (theName in allNames) {
            val theRewritten = ReferenceScenario.drawingText("$theName.rewritten")
            val theSecond = decode(theRewritten).encodeFileFormat()
            if (theSecond != theRewritten) {
                theOscillating.add(theName)
            }
            val theThird = decode(theSecond).encodeFileFormat()
            assertSameText("$theName, rewritten twice more", theRewritten, theThird)
        }
        assertEquals(
            listOf("group-06-p3m1", "group-14-pgg", "touch-drawn-p1", "touch-drawn-pgg"),
            theOscillating,
        )
    }

    //	A file cut short anywhere must be refused as a bad file, never crash.
    //	(Upstream stops the app here;  see the port note on decodeFileFormat().)
    @Test
    fun aTruncatedDrawingIsRefusedNotFatal() {
        val theText = ReferenceScenario.drawingText("group-08-p6m")
        val theTokens = theText.split(Regex("\\s+")).filter { it.isNotEmpty() }
        assertTrue(theTokens.size > 100)

        var theRefusals = 0
        for (theLength in 0 until theTokens.size) {
            val theTruncatedText = theTokens.take(theLength).joinToString(" ")
            try {
                decode(theTruncatedText)
                fail("a drawing cut to $theLength tokens was accepted")
            } catch (theError: KaleidoPaintDocument.KaleidoPaintFileEncodingError) {
                theRefusals += 1
            }
        }
        assertEquals(theTokens.size, theRefusals)

        //	A version number with no dot in it is what stops upstream's app.
        for (theVersion in listOf("1", ".", "10.")) {
            assertEquals(
                "drawing file is incomplete",
                scenario.decodingResult(theText.replace("format 1.10", "format $theVersion")),
            )
        }
    }

    @Test
    fun theFormatterRoundsHalvesToEvenAndKeepsTheSignOfZero() {
        assertEquals("  0.00195312", stringWithFormat("%12.8f", 1.0 / 512.0))
        assertEquals("  0.00585938", stringWithFormat("%12.8f", 3.0 / 512.0))
        assertEquals(" -0.00000000", stringWithFormat("%12.8f", -1e-10))
        assertEquals(" -0.00000000", stringWithFormat("%12.8f", -0.0))
        assertEquals("1234.50000000", stringWithFormat("%12.8f", 1234.5))
        assertEquals("  0.0000076293945312", stringWithFormat("%20.16lf", 1.0 / 131072.0))
        assertEquals("format 1.10\n", stringWithFormat("format %d.%d\n", 1, 10))
        assertEquals("0.500000", stringWithFormat("%f", 0.5))
        assertEquals(
            "nan inf -inf",
            stringWithFormat(
                "%f %f %f",
                Double.NaN,
                Double.POSITIVE_INFINITY,
                Double.NEGATIVE_INFINITY,
            ),
        )
    }

    @Test
    fun whiteSpaceIsSplitAsFoundationSplitsIt() {
        assertEquals(
            listOf("a", "b", "", "c", "d", "e", "f", "g", "h", ""),
            componentsSeparatedByWhitespacesAndNewlines("a b\t\nc d　e\u0085f g​h\r"),
        )
    }

    //	The matrices are computed from the colour profiles;  upstream's
    //	comment quotes their values to 14 places.
    @Test
    fun theSRGBToP3MatrixMatchesTheValuesQuotedInTheComments() {
        val theExpected =
            listOf(
                listOf(0.82246196871436, 0.03319419885096, 0.01708263072112),
                listOf(0.17753803128564, 0.96680580114904, 0.07239744066396),
                listOf(0.00000000000000, 0.00000000000000, 0.91051992861492),
            )
        for (theColumn in 0..2) {
            for (theRow in 0..2) {
                assertEquals(theExpected[theColumn][theRow], gSRGBtoP3[theColumn][theRow], 1e-13)
            }
        }
        val theProduct = gSRGBtoP3 * gP3toSRGB
        for (theColumn in 0..2) {
            for (theRow in 0..2) {
                assertEquals(
                    if (theColumn == theRow) 1.0 else 0.0,
                    theProduct[theColumn][theRow],
                    1e-13,
                )
            }
        }
    }
}
