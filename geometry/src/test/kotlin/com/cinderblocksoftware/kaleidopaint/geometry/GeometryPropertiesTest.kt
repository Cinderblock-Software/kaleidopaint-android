// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

@file:Suppress("LocalVariableName")

package com.cinderblocksoftware.kaleidopaint.geometry

import kotlin.math.sqrt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Properties the port must have whatever the reference values say: the support types behave like
 * their Swift counterparts, a spline passes smoothly through its nodes, and a dot really is round
 * in the drawing.
 */
class GeometryPropertiesTest {

    private val epsilon = 1e-12

    private fun assertClose(
        message: String,
        expected: Double2,
        actual: Double2,
        tolerance: Double = epsilon,
    ) {
        assertEquals("$message (x)", expected[0], actual[0], tolerance)
        assertEquals("$message (y)", expected[1], actual[1], tolerance)
    }

    // MARK: -
    // MARK: Support types

    @Test
    fun roundSendsHalvesAwayFromZeroLikeSwiftAndC() {
        assertEquals(1.0, round(0.5), 0.0)
        assertEquals(-1.0, round(-0.5), 0.0)
        assertEquals(2.0, round(1.5), 0.0)
        assertEquals(3.0, round(2.5), 0.0)
        assertEquals(-3.0, round(-2.5), 0.0)
        assertEquals(0.0, round(0.49999999999999994), 0.0)
        assertEquals(0.0, round(-0.4), 0.0)
        assertEquals(7.0, round(7.0), 0.0)
    }

    @Test
    fun vectorsCompareAsNumbers() {
        assertEquals(Double2.zero, Double2(-0.0, 0.0))
        assertEquals(Double2.zero.hashCode(), Double2(-0.0, 0.0).hashCode())
        assertNotEquals(Double2(1.0, 2.0), Double2(2.0, 1.0))
    }

    @Test
    fun matrixTimesInverseIsTheIdentity() {
        val m2 = Double2x2(Double2(0.31, 0.04), Double2(0.17, 0.22))
        val p2 = m2 * m2.inverse
        assertClose("2×2 column 0", Double2(1.0, 0.0), p2[0])
        assertClose("2×2 column 1", Double2(0.0, 1.0), p2[1])

        val m3 = Double3x3(Double3(0.0, 1.0, 0.0), Double3(-1.0, 1.0, 0.0), Double3(3.0, -2.0, 1.0))
        val p3 = m3 * m3.inverse
        for (theColumn in 0..2) {
            for (theRow in 0..2) {
                assertEquals(if (theColumn == theRow) 1.0 else 0.0, p3[theColumn][theRow], epsilon)
            }
        }
        assertEquals(1.0, m3.determinant, epsilon)
    }

    @Test
    fun matricesActRightToLeftOnColumns() {
        //	Column 2 is the translation, as in the torus group tables.
        val m = Double3x3(Double3(1.0, 0.0, 0.0), Double3(0.0, 1.0, 0.0), Double3(5.0, 7.0, 1.0))
        assertEquals(Double3(5.25, 7.5, 1.0), m * Double3(0.25, 0.5, 1.0))

        val theQuarterTurn = Double2x2(Double2(0.0, 1.0), Double2(-1.0, 0.0))
        assertEquals(Double2(0.0, 1.0), theQuarterTurn * Double2(1.0, 0.0))
    }

    @Test
    fun splineCoefficientsAreCopiedNotShared() {
        val a = Double4x2()
        a[2, 1] = 4.0
        val b = a.copy()
        b[2, 1] = 9.0
        assertEquals(4.0, a[2][1], 0.0)
        assertEquals(9.0, b[2][1], 0.0)
    }

    @Test
    fun placementCopiesAreIndependentAndTheMetricFollowsTheTranslations() {
        val theOriginal = UnitCellPlacement(defaultForWallpaperGroup = WallpaperGroup.wpg333)
        val theOriginalMetric = theOriginal.itsMetricOfDet1

        val theCopy = theOriginal.copy()
        assertEquals(theOriginal.itsCorner, theCopy.itsCorner)
        assertEquals(theOriginal.itsTranslations, theCopy.itsTranslations)
        assertEquals(theOriginal.itsMetricOfDet1, theCopy.itsMetricOfDet1)

        theCopy.itsTranslations = Double2x2(Double2(0.5, 0.0), Double2(0.0, 0.125))
        assertEquals(theOriginalMetric, theOriginal.itsMetricOfDet1)

        //	A 4:1 rectangle, rescaled to unit area, measures 2 by 1/2.
        assertEquals(4.0, theCopy.itsMetricOfDet1[0][0], epsilon)
        assertEquals(0.25, theCopy.itsMetricOfDet1[1][1], epsilon)
        assertEquals(0.0, theCopy.itsMetricOfDet1[0][1], epsilon)
    }

    @Test
    fun everyDefaultMetricHasDeterminantOne() {
        for (theGroup in WallpaperGroup.entries) {
            val thePlacement = UnitCellPlacement(defaultForWallpaperGroup = theGroup)
            assertEquals(
                theGroup.orbifoldName,
                1.0,
                thePlacement.itsMetricOfDet1.determinant,
                epsilon,
            )
            assertTrue(theGroup.orbifoldName, !thePlacement.unitCellIsDegenerate())
        }
    }

    //	Swift's assertionFailure() stops a debug build;
    //	under the unit tests the JVM runs with assertions enabled, so ours does too.
    @Test
    fun aZeroAreaViewIsAnAssertionFailure() {
        assertThrows(AssertionError::class.java) {
            convertDisplayCoordinatesToDrawingCoordinates(
                DisplayPoint(x = 1.0, y = 1.0, viewWidth = 0.0, viewHeight = 100.0)
            )
        }
    }

    @Test
    fun anUnimplementedOverrideIsAPreconditionFailure() {
        assertThrows(IllegalStateException::class.java) {
            DrawingElement(color = gColorRotated0)
                .hitControlHandle(
                    touchPointInExtendedUnitCellCoordinates = Double2.zero,
                    wallpaperGroup = WallpaperGroup.wpgO,
                    metricOfDet1 = Double2x2.identity,
                    fillMarkerRadius = 0.0,
                )
        }
    }

    @Test
    fun drawingElementsAreEqualOnlyToThemselves() {
        val a = Dot(center = Double2(0.5, 0.5))
        val b = Dot(center = Double2(0.5, 0.5))
        assertEquals(a, a)
        assertNotEquals(a, b)
    }

    @Test
    fun nodeTypeNamesAreTheLocalizationKeys() {
        assertEquals("Smooth", SplineNodeType.smooth.localizedNameKey())
        assertEquals("Corner", SplineNodeType.corner.localizedNameKey())
    }

    // MARK: -
    // MARK: Coordinate systems

    @Test
    fun thePageHasDiagonalOneAndTheViewsAspectRatio() {
        val (w, h) = convertPageSizeToDrawingCoordinates(1080.0, 2400.0)
        assertEquals(1.0, w * w + h * h, epsilon)
        assertEquals(1080.0 / 2400.0, w / h, epsilon)
    }

    @Test
    fun coordinateConversionsRoundTrip() {
        val thePlacement = UnitCellPlacement(defaultForWallpaperGroup = WallpaperGroup.wpg632)
        val theDisplayPoint =
            DisplayPoint(x = 123.0, y = 1777.0, viewWidth = 1080.0, viewHeight = 2400.0)

        val theExtended =
            convertDisplayCoordinatesToExtendedUnitCellCoordinates(
                theDisplayPoint,
                unitCellPlacement = thePlacement,
            )
        val theBack =
            convertExtendedUnitCellCoordinatesToDisplayCoordinates(
                theExtended,
                unitCellPlacement = thePlacement,
                viewWidth = 1080.0,
                viewHeight = 2400.0,
            )
        assertEquals(123.0, theBack.x, 1e-9)
        assertEquals(1777.0, theBack.y, 1e-9)

        val theStrict =
            convertExtendedUnitCellCoordinatesToStrictUnitCellCoordinates(Double2(-1.25, 8.5))
        assertEquals(Double2(0.75, 0.5), theStrict)
    }

    // MARK: -
    // MARK: Splines

    private fun wave(): CubicSpline {
        val theSpline = CubicSpline()
        val theNodes =
            listOf(
                Double2(0.10, 0.50),
                Double2(0.20, 0.72),
                Double2(0.35, 0.31),
                Double2(0.50, 0.66),
                Double2(0.62, 0.28),
                Double2(0.80, 0.55),
                Double2(0.93, 0.47),
            )
        for (theLocation in theNodes) {
            theSpline.append(SplineNode(location = theLocation, type = SplineNodeType.smooth))
        }
        theSpline.refreshParameterization()
        return theSpline
    }

    //	S(u) = ξ₀(1-u) + ξ₁u + ξ₂(1-u)³ + ξ₃u³
    private fun position(ξ: Double4x2, u: Double): Double2 {
        val uu = 1.0 - u
        return uu * ξ[0] + u * ξ[1] + (uu * uu * uu) * ξ[2] + (u * u * u) * ξ[3]
    }

    private fun firstDerivative(ξ: Double4x2, u: Double): Double2 {
        val uu = 1.0 - u
        return -ξ[0] + ξ[1] - (3.0 * uu * uu) * ξ[2] + (3.0 * u * u) * ξ[3]
    }

    private fun secondDerivative(ξ: Double4x2, u: Double): Double2 {
        val uu = 1.0 - u
        return (6.0 * uu) * ξ[2] + (6.0 * u) * ξ[3]
    }

    @Test
    fun eachArcRunsFromItsNodeToTheNext() {
        val theNodes = wave().itsNodes
        for (i in 0 until theNodes.size - 1) {
            assertClose(
                "arc $i starts at node $i",
                theNodes[i].itsNodeLocation,
                position(theNodes[i].ξ, 0.0),
            )
            assertClose(
                "arc $i ends at node ${i + 1}",
                theNodes[i + 1].itsNodeLocation,
                position(theNodes[i].ξ, 1.0),
            )
        }
    }

    //	The spline is parameterized by chord length t;  within arc i,
    //	u = (t - tᵢ)/Δtᵢ, so d/dt = (1/Δtᵢ) d/du.
    @Test
    fun firstAndSecondDerivativesAgreeAtSmoothNodes() {
        val theNodes = wave().itsNodes
        for (i in 1 until theNodes.size - 1) {
            val Δt0 = length(theNodes[i].itsNodeLocation - theNodes[i - 1].itsNodeLocation)
            val Δt1 = length(theNodes[i + 1].itsNodeLocation - theNodes[i].itsNodeLocation)
            assertClose(
                "velocity at node $i",
                firstDerivative(theNodes[i - 1].ξ, 1.0) / Δt0,
                firstDerivative(theNodes[i].ξ, 0.0) / Δt1,
                1e-10,
            )
            assertClose(
                "acceleration at node $i",
                secondDerivative(theNodes[i - 1].ξ, 1.0) / (Δt0 * Δt0),
                secondDerivative(theNodes[i].ξ, 0.0) / (Δt1 * Δt1),
                1e-9,
            )
        }
    }

    @Test
    fun aNaturalSplineHasNoCurvatureAtItsEnds() {
        val theNodes = wave().itsNodes
        assertClose("start", Double2.zero, secondDerivative(theNodes.first().ξ, 0.0))
        assertClose("end", Double2.zero, secondDerivative(theNodes[theNodes.size - 2].ξ, 1.0))
    }

    @Test
    fun aCornerNodeBreaksTheSplineIntoTwoNaturalSplines() {
        val theSpline = wave()
        theSpline.itsNodes[3].itsNodeType = SplineNodeType.corner
        theSpline.refreshParameterization()
        val theNodes = theSpline.itsNodes
        assertClose("into the corner", Double2.zero, secondDerivative(theNodes[2].ξ, 1.0))
        assertClose("out of the corner", Double2.zero, secondDerivative(theNodes[3].ξ, 0.0))
        assertClose(
            "still passes through it",
            theNodes[3].itsNodeLocation,
            position(theNodes[2].ξ, 1.0),
        )
    }

    @Test
    fun recenteringMovesACurveByWholeCells() {
        val theSpline = CubicSpline()
        theSpline.append(SplineNode(location = Double2(0.2, 1.6), type = SplineNodeType.smooth))
        theSpline.append(SplineNode(location = Double2(0.2, 1.9), type = SplineNodeType.smooth))
        theSpline.keepCenteredInUnitCell()
        assertClose("first", Double2(0.2, 0.6), theSpline.itsNodes[0].itsNodeLocation, 1e-12)
        assertClose("second", Double2(0.2, 0.9), theSpline.itsNodes[1].itsNodeLocation, 1e-12)
    }

    // MARK: -
    // MARK: Brushstrokes

    private class Recorder : BrushstrokeRenderEncoder {
        val itsStrips = mutableListOf<List<Float2>>()

        override fun drawTriangleStrip(
            vertices: VertexScratchBuffer,
            vertexCount: Int,
            instanceCount: Int,
        ) {
            itsStrips.add((0 until vertexCount).map { vertices[it] })
        }

        override fun drawControlHandle(
            placement: ControlHandlePlacement,
            colors: ControlHandleColors,
            vertexCount: Int,
            instanceCount: Int,
        ) {}
    }

    //	|v|² measured in the drawing, via the metric.
    private fun squaredLength(v: Double2, g: Double2x2): Double =
        v[0] * g[0][0] * v[0] +
            v[0] * g[0][1] * v[1] +
            v[1] * g[1][0] * v[0] +
            v[1] * g[1][1] * v[1]

    //	"A dot gets rendered as an ellipse in the unit cell
    //	so that it comes out as a perfect circle in the drawing."
    @Test
    fun aDotIsRoundInTheDrawing() {
        val thePlacement = UnitCellPlacement(defaultForWallpaperGroup = WallpaperGroup.wpgO)
        thePlacement.itsTranslations = Double2x2(Double2(0.31, 0.04), Double2(0.17, 0.22))
        val theMetric = thePlacement.itsMetricOfDet1

        val theDot = Dot(center = Double2(0.4, 0.6), thickness = 0.08)
        val theRecorder = Recorder()
        theDot.render(
            renderEncoder = theRecorder,
            metricOfDet1 = theMetric,
            scratchBuffer = VertexScratchBuffer(vertexCapacity = Dot.triStripBufferVertexCount),
            symmetryCount = 1,
        )

        assertEquals(1, theRecorder.itsStrips.size)
        assertEquals(22, theRecorder.itsStrips[0].size)
        for (theVertex in theRecorder.itsStrips[0]) {
            val theOffset =
                Double2(theVertex.x.toDouble(), theVertex.y.toDouble()) - theDot.itsCenter
            assertEquals(0.04, sqrt(squaredLength(theOffset, theMetric)), 1e-6)
        }
    }

    //	"Adjust the triangle strip's (varying!) thickness in unit cell coordinates
    //	to give the desired constant thickness."
    @Test
    fun aCurveHasConstantWidthInTheDrawing() {
        val thePlacement = UnitCellPlacement(defaultForWallpaperGroup = WallpaperGroup.wpg333)
        val theMetric = thePlacement.itsMetricOfDet1

        val theCurve = Curve(thickness = 0.03)
        theCurve.itsSpline = wave()
        val theRecorder = Recorder()
        theCurve.render(
            renderEncoder = theRecorder,
            metricOfDet1 = theMetric,
            scratchBuffer = VertexScratchBuffer(vertexCapacity = Curve.triStripBufferVertexCount),
            symmetryCount = 1,
        )

        //	Six arcs, a half-dot at the start and a half-dot at the end.
        assertEquals(8, theRecorder.itsStrips.size)
        val theArcs = theRecorder.itsStrips.filter { it.size != gUnitHalfCircleVertexCount }
        assertEquals(6, theArcs.size)
        for (theArc in theArcs) {
            assertTrue(theArc.size % 2 == 0 && theArc.size <= Curve.maxArcVertexCount)
            for (i in theArc.indices step 2) {
                val theAcross =
                    Double2(
                        (theArc[i + 1].x - theArc[i].x).toDouble(),
                        (theArc[i + 1].y - theArc[i].y).toDouble(),
                    )
                assertEquals(0.03, sqrt(squaredLength(theAcross, theMetric)), 1e-6)
            }
        }
    }

    @Test
    fun aTapOnAnImageOfADotFindsTheSymmetryThatTakesItHome() {
        val theGroup = WallpaperGroup.wpgS632
        val theMetric = UnitCellPlacement(defaultForWallpaperGroup = theGroup).itsMetricOfDet1
        val theDot = Dot(center = Double2(0.3, 0.2), thickness = 0.02)

        for (theElement in theGroup.torusGroup.itsElements) {
            val theImage = theElement.itsMatrix * Double3(0.3, 0.2, 1.0)
            val theTouch = Double2(theImage[0] + 3.0, theImage[1] - 2.0)

            val theHit =
                theDot.hitControlHandle(
                    touchPointInExtendedUnitCellCoordinates = theTouch,
                    wallpaperGroup = theGroup,
                    metricOfDet1 = theMetric,
                    fillMarkerRadius = 0.0,
                )

            assertTrue(theHit != null)
            assertTrue(theHit!!.itsElement === theDot)
            assertClose("hit centre", theTouch, theHit.itsHitCenter, 1e-12)
            assertEquals(0.0, theHit.itsTapError, 1e-12)

            //	itsSymmetry takes the hit centre back to the home centre.
            val theHome = theHit.itsSymmetry * Double3(theHit.itsHitCenter, 1.0)
            assertEquals(0.3, theHome[0], 1e-12)
            assertEquals(0.2, theHome[1], 1e-12)
        }
    }

    @Test
    fun aTapFarFromEveryImageHitsNothing() {
        val theGroup = WallpaperGroup.wpgO
        val theMetric = UnitCellPlacement(defaultForWallpaperGroup = theGroup).itsMetricOfDet1
        val theDot = Dot(center = Double2(0.3, 0.2), thickness = 0.02)
        assertTrue(
            theDot.hitControlHandle(
                touchPointInExtendedUnitCellCoordinates = Double2(0.8, 0.7),
                wallpaperGroup = theGroup,
                metricOfDet1 = theMetric,
                fillMarkerRadius = 0.0,
            ) == null
        )
    }
}
