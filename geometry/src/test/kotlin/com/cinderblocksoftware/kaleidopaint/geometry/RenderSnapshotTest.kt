// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint.geometry

import org.junit.Assert.*
import org.junit.Test

class RenderSnapshotTest {
    private fun drawing() =
        KaleidoPaintDocument(WallpaperGroup.wpgO).apply {
            itsElements.add(
                Curve().apply {
                    itsSpline.append(SplineNode(Double2(.1, .1), SplineNodeType.corner))
                    itsSpline.append(SplineNode(Double2(.8, .8), SplineNodeType.corner))
                    itsSpline.refreshParameterization()
                }
            )
            itsElements.add(Fill())
        }

    @Test
    fun coordinatesAndSplineCoefficientsCannotRaceTheLiveDocument() {
        val source = drawing()
        val snap = RenderSnapshot.capture(source)
        val actual = (source.itsElements[0] as Curve).itsSpline.itsNodes[0]
        val frozen = (snap.model.itsElements[0] as Curve).itsSpline.itsNodes[0]
        val coefficient = frozen.ξ[0]
        actual.itsNodeLocation = Double2(.4, .6)
        actual.ξ[0, 0] = 999.0
        assertEquals(Double2(.1, .1), frozen.itsNodeLocation)
        assertEquals(coefficient, frozen.ξ[0])
    }

    @Test
    fun cachesPublishAcrossAppendsButNotEarlierEdits() {
        val source = drawing()
        val snap = RenderSnapshot.capture(source)
        val mask = FillMask(4, intArrayOf(0, 4))
        (snap.model.itsElements[1] as Fill).itsCachedRLERunsBuffer = mask
        source.itsElements.add(Dot())
        snap.publishCaches(source)
        assertSame(mask, (source.itsElements[1] as Fill).itsCachedRLERunsBuffer)
        (source.itsElements[1] as Fill).itsCachedRLERunsBuffer = null
        val stale = RenderSnapshot.capture(source)
        (stale.model.itsElements[1] as Fill).itsCachedRLERunsBuffer = mask
        (source.itsElements[0] as Curve).itsThickness = .9
        stale.publishCaches(source)
        assertNull((source.itsElements[1] as Fill).itsCachedRLERunsBuffer)
    }

    @Test
    fun changedPredecessorMaskRejectsLaterCachePublication() {
        val source = drawing()
        source.itsElements.add(Fill(fillPoint = Double2(.2, .3)))
        val snap = RenderSnapshot.capture(source)
        (snap.model.itsElements[2] as Fill).itsCachedRLERunsBuffer = FillMask(4, intArrayOf(2, 1))
        (source.itsElements[1] as Fill).itsCachedRLERunsBuffer = FillMask(4, intArrayOf(0, 1))
        snap.publishCaches(source)
        assertNull((source.itsElements[2] as Fill).itsCachedRLERunsBuffer)
    }

    @Test
    fun drawingPanAndBackgroundReuseCellsButEditsAndHandlesInvalidate() {
        val source = drawing()
        val first = RenderSnapshot.capture(source)
        first.complete()
        source.itsUnitCellPlacement.itsCorner += Double2(.1, .2)
        source.itsBackgroundColor = LinearDisplayP3Color(.1, .2, .3, 1.0)
        val second = RenderSnapshot.capture(source, first)
        assertSame(first.model, second.model)
        (source.itsElements[0] as Curve).itsThickness = .7
        val edited = RenderSnapshot.capture(source, second)
        assertNotSame(second.model, edited.model)
        source.itsTouchMode = TouchMode.edit
        val handles = RenderSnapshot.capture(source, edited)
        handles.complete()
        source.itsUnitCellPlacement.itsCorner += Double2(.1, .1)
        assertSame(handles.model, RenderSnapshot.capture(source, handles).model)
    }

    @Test
    fun changingProgressReusesCompletedCopiesButChangedPredecessorsAreCloned() {
        val source = drawing()
        val first = RenderSnapshot.capture(source)
        source.itsCurveInProgress =
            Curve().apply { itsSpline.append(SplineNode(Double2(.3, .4), SplineNodeType.corner)) }
        val second = RenderSnapshot.capture(source, first)
        assertSame(first.model.itsElements[0], second.model.itsElements[0])
        assertSame(first.model.itsElements[1], second.model.itsElements[1])
        val frozen = (second.model.itsCurveInProgress!!).itsSpline.itsNodes[0].itsNodeLocation
        source.itsCurveInProgress!!.itsSpline.itsNodes[0].itsNodeLocation = Double2(.7, .9)
        val third = RenderSnapshot.capture(source, second)
        assertEquals(
            frozen,
            second.model.itsCurveInProgress!!.itsSpline.itsNodes[0].itsNodeLocation,
        )
        assertNotSame(second.model.itsCurveInProgress, third.model.itsCurveInProgress)
        (source.itsElements[0] as Curve).itsThickness = .2
        val fourth = RenderSnapshot.capture(source, third)
        assertNotSame(third.model.itsElements[0], fourth.model.itsElements[0])
        assertSame(third.model.itsElements[1], fourth.model.itsElements[1])
    }

    @Test
    fun editPanRetainsPixelsButFillHandleZoomChangesTheKey() {
        val source = drawing().apply { itsTouchMode = TouchMode.edit }
        val first = RenderSnapshot.capture(source)
        source.itsUnitCellPlacement.itsCorner += Double2(.3, .7)
        assertEquals(first.completedState, RenderSnapshot.state(source))
        source.itsUnitCellPlacement.itsTranslations =
            source.itsUnitCellPlacement.itsTranslations * 8.0
        assertNotEquals(first.completedState, RenderSnapshot.state(source))
    }

    @Test
    fun largeStrokeSnapshotsReuseEveryCompletedSpline() {
        val source =
            KaleidoPaintDocument().apply {
                repeat(400) {
                    itsElements.add(
                        Curve().apply {
                            repeat(20) { i ->
                                itsSpline.append(
                                    SplineNode(Double2(i / 20.0, .3), SplineNodeType.corner)
                                )
                            }
                        }
                    )
                }
                itsCurveInProgress = Curve()
            }
        var previous = RenderSnapshot.capture(source)
        val start = System.nanoTime()
        repeat(30) { i ->
            source.itsCurveInProgress!!
                .itsSpline
                .append(SplineNode(Double2(i / 30.0, .5), SplineNodeType.corner))
            val next = RenderSnapshot.capture(source, previous)
            assertTrue(
                previous.model.itsElements.indices.all {
                    previous.model.itsElements[it] === next.model.itsElements[it]
                }
            )
            previous = next
        }
        println(
            "400 x 20-node splines, 30 progress snapshots: ${(System.nanoTime()-start)/1e6} ms; completed clones=0"
        )
    }
}
