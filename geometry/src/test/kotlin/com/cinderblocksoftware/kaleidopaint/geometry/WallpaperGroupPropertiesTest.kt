// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint.geometry

import kotlin.math.abs
import kotlin.math.floor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Checks on the wallpaper group tables that follow from the mathematics, independent of the Swift
 * reference values: a table that was copied faithfully from a wrong original would pass
 * [ReferenceTest] and fail here.
 */
class WallpaperGroupPropertiesTest {

    private val epsilon = 1e-12

    private fun fractionalPart(x: Double) = x - floor(x)

    //	Two torus matrices are the same symmetry of the torus
    //	iff they agree up to an integer translation.
    private fun sameTorusSymmetry(a: Double3x3, b: Double3x3): Boolean {
        for (theColumn in 0..1) {
            for (theRow in 0..2) {
                if (abs(a[theColumn][theRow] - b[theColumn][theRow]) > epsilon) return false
            }
        }
        for (theRow in 0..1) {
            val theDifference = a[2][theRow] - b[2][theRow]
            if (abs(theDifference - Math.rint(theDifference)) > epsilon) return false
        }
        return abs(a[2][2] - b[2][2]) <= epsilon
    }

    private fun linearDeterminant(m: Double3x3) = m[0][0] * m[1][1] - m[0][1] * m[1][0]

    //	p ↦ M p, as a point of the torus.
    private fun image(m: Double3x3, p: Double2): Double2 {
        val theImage = m * Double3(p, 1.0)
        return Double2(theImage[0], theImage[1])
    }

    private fun sameTorusPoint(p: Double2, q: Double2): Boolean {
        val dx = p[0] - q[0]
        val dy = p[1] - q[1]
        return abs(dx - Math.rint(dx)) <= epsilon && abs(dy - Math.rint(dy)) <= epsilon
    }

    @Test
    fun thereAreSeventeenGroupsWithDistinctNames() {
        assertEquals(17, WallpaperGroup.entries.size)
        assertEquals(17, WallpaperGroup.entries.map { it.orbifoldName }.toSet().size)
        assertEquals(17, WallpaperGroup.entries.map { it.IUCName }.toSet().size)
        for (theGroup in WallpaperGroup.entries) {
            assertSame(theGroup, WallpaperGroup.fromRawValue(theGroup.rawValue))
        }
        assertNull(WallpaperGroup.fromRawValue("*532"))
    }

    //	Conway's Magic Theorem:  the features of a wallpaper pattern's
    //	orbifold name cost exactly 2 in total, where
    //
    //		○ costs 2,
    //		a digit n before any * costs (n-1)/n,
    //		* and × cost 1 each,
    //		a digit n after a * costs (n-1)/2n.
    //
    @Test
    fun everyOrbifoldNameCostsExactlyTwo() {
        for (theGroup in WallpaperGroup.entries) {
            var theCost = 0.0
            var theStarHasBeenSeen = false
            for (theSymbol in theGroup.orbifoldName) {
                when {
                    theSymbol == '○' -> theCost += 2.0
                    theSymbol == '*' -> {
                        theCost += 1.0
                        theStarHasBeenSeen = true
                    }
                    theSymbol == '×' -> theCost += 1.0
                    theSymbol.isDigit() -> {
                        val n = theSymbol.digitToInt().toDouble()
                        theCost += if (theStarHasBeenSeen) (n - 1.0) / (2.0 * n) else (n - 1.0) / n
                    }
                    else ->
                        throw AssertionError(
                            "unexpected symbol $theSymbol in ${theGroup.orbifoldName}"
                        )
                }
            }
            assertEquals("cost of ${theGroup.orbifoldName}", 2.0, theCost, epsilon)
        }
    }

    //	The torus group has as many elements as the order of the point group.
    @Test
    fun torusGroupsHaveTheRightOrder() {
        val theExpectedOrders =
            mapOf(
                "○" to 1,
                "2222" to 2,
                "333" to 3,
                "442" to 4,
                "632" to 6,
                "*2222" to 4,
                "*333" to 6,
                "*442" to 8,
                "*632" to 12,
                "22*" to 4,
                "2*22" to 4,
                "3*3" to 6,
                "4*2" to 8,
                "**" to 2,
                "22×" to 4,
                "*×" to 2,
                "××" to 2,
            )
        for (theGroup in WallpaperGroup.entries) {
            assertEquals(
                theGroup.orbifoldName,
                theExpectedOrders[theGroup.orbifoldName],
                theGroup.torusGroup.itsElements.size,
            )
        }
    }

    @Test
    fun torusGroupsStartWithTheIdentityAndHaveNoRepeats() {
        for (theGroup in WallpaperGroup.entries) {
            val theMatrices = theGroup.torusGroup.itsElements.map { it.itsMatrix }
            assertEquals(theGroup.orbifoldName, Double3x3.identity, theMatrices[0])
            for (i in theMatrices.indices) {
                for (j in 0 until i) {
                    assertTrue(
                        "${theGroup.orbifoldName}: elements $j and $i coincide",
                        !sameTorusSymmetry(theMatrices[i], theMatrices[j]),
                    )
                }
            }
        }
    }

    //	Each element acts on the torus only if its linear part has integer
    //	entries, and is invertible only if that part has determinant ±1.
    @Test
    fun torusMatricesAreIntegralAndUnimodular() {
        for (theGroup in WallpaperGroup.entries) {
            for (theElement in theGroup.torusGroup.itsElements) {
                val m = theElement.itsMatrix
                for (theColumn in 0..1) {
                    for (theRow in 0..1) {
                        assertEquals(
                            theGroup.orbifoldName,
                            Math.rint(m[theColumn][theRow]),
                            m[theColumn][theRow],
                            0.0,
                        )
                    }
                }
                assertEquals(theGroup.orbifoldName, 1.0, abs(linearDeterminant(m)), 0.0)
                assertEquals(
                    theGroup.orbifoldName,
                    Double3(0.0, 0.0, 1.0),
                    Double3(m[0][2], m[1][2], m[2][2]),
                )
            }
        }
    }

    @Test
    fun torusGroupsAreClosedUnderCompositionAndInverse() {
        for (theGroup in WallpaperGroup.entries) {
            val theMatrices = theGroup.torusGroup.itsElements.map { it.itsMatrix }
            for (a in theMatrices) {
                assertTrue(
                    "${theGroup.orbifoldName}: an inverse is missing",
                    theMatrices.any { sameTorusSymmetry(it, a.inverse) },
                )
                for (b in theMatrices) {
                    assertTrue(
                        "${theGroup.orbifoldName}: a product is missing",
                        theMatrices.any { sameTorusSymmetry(it, a * b) },
                    )
                }
            }
        }
    }

    //	Rotations get the saturated colours and reflections the pastels.
    @Test
    fun colorBySymmetryDistinguishesRotationsFromReflections() {
        val theRotationColors =
            listOf(
                gColorRotated0,
                gColorRotated2,
                gColorRotated3,
                gColorRotated4,
                gColorRotated6,
                gColorRotated8,
                gColorRotated9,
                gColorRotated10,
            )
        val theReflectionColors =
            listOf(
                gColorReflected0,
                gColorReflected2,
                gColorReflected3,
                gColorReflected4,
                gColorReflected6,
                gColorReflected8,
                gColorReflected9,
                gColorReflected10,
            )
        for (theGroup in WallpaperGroup.entries) {
            val theElements = theGroup.torusGroup.itsElements
            for (theElement in theElements) {
                val theColors =
                    if (linearDeterminant(theElement.itsMatrix) > 0.0) theRotationColors
                    else theReflectionColors
                assertTrue(theGroup.orbifoldName, theColors.any { it === theElement.itsColor })
            }
            assertEquals(
                "${theGroup.orbifoldName}: two symmetries share a colour",
                theElements.size,
                theElements.map { it.itsColor }.toSet().size,
            )
        }
    }

    //	"The translations have been chosen so that the translated image
    //	extends to the left of the fundamental square, below it or below-left
    //	of it, but never above nor to the right of it."
    @Test
    fun imagesOfTheFundamentalSquareSpillOnlyLeftwardAndDownward() {
        val theCorners =
            listOf(Double2(0.0, 0.0), Double2(1.0, 0.0), Double2(0.0, 1.0), Double2(1.0, 1.0))
        for (theGroup in WallpaperGroup.entries) {
            for (theElement in theGroup.torusGroup.itsElements) {
                for (theCorner in theCorners) {
                    val theImage = image(theElement.itsMatrix, theCorner)
                    assertTrue(
                        "${theGroup.orbifoldName}: $theCorner goes to $theImage",
                        theImage[0] in -1.0..1.0 && theImage[1] in -1.0..1.0,
                    )
                }
            }
        }
    }

    @Test
    fun rigidityMatchesTheListsInTheComments() {
        val theExpected =
            mapOf(
                Rigidity.fullyFlexible to setOf("○", "2222"),
                Rigidity.rectangular to setOf("*2222", "22*", "22×", "**", "××"),
                Rigidity.rhombic to setOf("2*22", "*×"),
                Rigidity.rigid to setOf("333", "*333", "3*3", "442", "*442", "4*2", "632", "*632"),
            )
        for ((theRigidity, theNames) in theExpected) {
            assertEquals(
                theRigidity.name,
                theNames,
                WallpaperGroup.entries
                    .filter { it.torusGroup.itsRigidity == theRigidity }
                    .map { it.orbifoldName }
                    .toSet(),
            )
        }
    }

    //	A gyration point is the centre of a rotation in the group.
    @Test
    fun everyGyrationPointIsFixedByARotation() {
        for (theGroup in WallpaperGroup.entries) {
            val theRotations =
                theGroup.torusGroup.itsElements
                    .map { it.itsMatrix }
                    .filter {
                        linearDeterminant(it) > 0.0 && !sameTorusSymmetry(it, Double3x3.identity)
                    }
            for (thePoint in theGroup.torusGroup.itsGyrationPoints) {
                assertTrue(
                    "${theGroup.orbifoldName}: no rotation fixes $thePoint",
                    theRotations.any { sameTorusPoint(image(it, thePoint), thePoint) },
                )
            }
        }
    }

    //	A mirror segment lies on the axis of a reflection in the group:
    //	some reflection fixes every point of it.
    @Test
    fun everyMirrorSegmentIsFixedByAReflection() {
        for (theGroup in WallpaperGroup.entries) {
            val theReflections =
                theGroup.torusGroup.itsElements
                    .map { it.itsMatrix }
                    .filter { linearDeterminant(it) < 0.0 }
            for ((theStart, theEnd) in theGroup.torusGroup.itsMirrorSegments) {
                val theMiddle = (theStart + theEnd) * 0.5
                val theQuarter = theStart * 0.75 + theEnd * 0.25
                assertTrue(
                    "${theGroup.orbifoldName}: no reflection fixes the segment $theStart–$theEnd",
                    theReflections.any { m ->
                        listOf(theStart, theEnd, theMiddle, theQuarter).all {
                            sameTorusPoint(image(m, it), it)
                        }
                    },
                )
            }
        }
    }

    //	A glide reflection maps its axis to itself, shifting it along by half
    //	a period, and fixes no point of it.
    @Test
    fun everyGlideSegmentIsShiftedAlongItselfByAReflection() {
        for (theGroup in WallpaperGroup.entries) {
            val theReflections =
                theGroup.torusGroup.itsElements
                    .map { it.itsMatrix }
                    .filter { linearDeterminant(it) < 0.0 }
            for ((theStart, theEnd) in theGroup.torusGroup.itsGlideReflectionSegments) {
                val theDirection = theEnd - theStart
                assertTrue(
                    "${theGroup.orbifoldName}: no glide reflection runs along $theStart–$theEnd",
                    theReflections.any { m ->
                        val theImageOfStart = image(m, theStart)
                        val theImageOfEnd = image(m, theEnd)
                        //	The image of the segment is parallel to the segment…
                        val theImageDirection = theImageOfEnd - theImageOfStart
                        val isParallel =
                            abs(theImageDirection[0] - theDirection[0]) <= epsilon &&
                                abs(theImageDirection[1] - theDirection[1]) <= epsilon
                        //	…and displaced along its own line (up to a lattice translation),
                        //	but not onto itself point for point.
                        val theDisplacement = theImageOfStart - theStart
                        val isAlongTheAxis =
                            listOf(-2, -1, 0, 1, 2).any { i ->
                                listOf(-2, -1, 0, 1, 2).any { j ->
                                    abs(
                                        (theDisplacement[0] + i) * theDirection[1] -
                                            (theDisplacement[1] + j) * theDirection[0]
                                    ) <= epsilon
                                }
                            }
                        isParallel && isAlongTheAxis && !sameTorusPoint(theImageOfStart, theStart)
                    },
                )
            }
        }
    }

    @Test
    fun shiftConstantsCoverAFourByFourBlock() {
        assertEquals(16, gNumShifts)
        assertEquals(0.125, gSafeRegionInset, 0.0)
        assertEquals(fractionalPart(3.75), fractionalPart(-1.25), epsilon)
    }
}
