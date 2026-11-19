// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint.geometry

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * Drawings that the reference harness did not make, read by the Kotlin port.
 *
 * Two directories, each holding the drawings, what upstream wrote after reading each one
 * (`NAME.rewritten.kaleidopaint`), and what upstream read from all of them (`reference.txt`), the
 * last two made by `tools/reference/build.sh`:
 *
 * - `src/test/resources/from-the-app/` — files saved by KaleidoPaint itself, running on an iOS
 *   simulator. Committed, so always tested.
 * - `src/test/external-drawings/` — real drawings made by people with KaleidoPaint. Their licence
 *   is not the GPL, so they are fetched (`tools/reference/fetch-public-drawings.sh`) rather than
 *   committed, and those tests are skipped, not failed, where the files are absent.
 */
class ExternalDrawingsTest {

    private val fromTheApp = File("src/test/resources/from-the-app")
    private val fromElsewhere = File("src/test/external-drawings")

    private fun drawingFiles(directory: File): List<File> =
        (directory.listFiles() ?: arrayOf())
            .filter {
                it.name.endsWith(".kaleidopaint") && !it.name.endsWith(".rewritten.kaleidopaint")
            }
            .sortedBy { it.name }

    private fun compareReading(directory: File, minimumLineCount: Int) {

        val theReference =
            File(directory, "reference.txt").inputStream().use { ReferenceTest.loadReference(it) }

        val theScenario = ReferenceScenario()
        val theFiles = drawingFiles(directory)
        for (theFile in theFiles) {
            theScenario.emitExternalDrawing(theFile.name, theFile.readText(Charsets.UTF_8))
        }
        val theActual = theScenario.itsLines

        val theExpected = theReference.filterKeys { it != "external.names" }
        assertEquals(
            ReferenceValue.Text(theFiles.joinToString("/") { it.name }),
            theReference["external.names"],
        )
        assertTrue(theExpected.size >= minimumLineCount)

        val theProblems = mutableListOf<String>()
        for ((theKey, theExpectedValue) in theExpected) {
            val theActualValue = theActual[theKey]
            if (theActualValue == null) {
                theProblems.add("$theKey: Swift has it, Kotlin doesn't")
                continue
            }
            ReferenceTest.disagreement(theExpectedValue, theActualValue)?.let {
                theProblems.add("$theKey: $it")
            }
        }
        for (theKey in theActual.keys) {
            if (theKey !in theExpected) {
                theProblems.add("$theKey: Kotlin has it, Swift doesn't")
            }
        }
        if (theProblems.isNotEmpty()) {
            fail(
                "${theProblems.size} of ${theExpected.size} lines disagree:\n" +
                    theProblems.take(25).joinToString("\n")
            )
        }
        println(
            "${directory.name}: ${theFiles.size} files, ${theExpected.size} reference lines agree"
        )
    }

    private fun compareRewriting(directory: File) {
        for (theFile in drawingFiles(directory)) {
            val theRewrittenFile =
                File(
                    directory,
                    theFile.name.removeSuffix(".kaleidopaint") + ".rewritten.kaleidopaint",
                )
            assertTrue("run tools/reference/build.sh", theRewrittenFile.isFile)

            val theDocument = KaleidoPaintDocument()
            theDocument.decodeFileFormat(theFile.readText(Charsets.UTF_8))
            assertEquals(
                theFile.name,
                theRewrittenFile.readText(Charsets.UTF_8),
                theDocument.encodeFileFormat(),
            )
        }
    }

    @Test
    fun filesSavedByTheAppAreReadAsUpstreamReadsThem() {
        assertEquals(2, drawingFiles(fromTheApp).size)
        compareReading(fromTheApp, 100)
    }

    @Test
    fun filesSavedByTheAppAreRewrittenAsUpstreamRewritesThem() {
        compareRewriting(fromTheApp)
    }

    //	A new drawing saved by the app comes back unchanged.  (A drawing with
    //	curves need not:  the app saves a stroke where the finger drew it, and
    //	re-centres it in the unit cell when the file is next opened.)
    @Test
    fun aNewDrawingSavedByTheAppSurvivesARoundTripUnchanged() {
        val theText = File(fromTheApp, "new-drawing.kaleidopaint").readText(Charsets.UTF_8)
        val theDocument = KaleidoPaintDocument()
        theDocument.decodeFileFormat(theText)
        assertEquals(theText, theDocument.encodeFileFormat())
    }

    @Test
    fun realDrawingsAreReadAsUpstreamReadsThem() {
        assumeTrue(
            "no external drawings have been fetched",
            File(fromElsewhere, "reference.txt").isFile,
        )
        compareReading(fromElsewhere, 100)
    }

    @Test
    fun realDrawingsAreRewrittenAsUpstreamRewritesThem() {
        assumeTrue(
            "no external drawings have been fetched",
            drawingFiles(fromElsewhere).isNotEmpty(),
        )
        compareRewriting(fromElsewhere)
    }
}
