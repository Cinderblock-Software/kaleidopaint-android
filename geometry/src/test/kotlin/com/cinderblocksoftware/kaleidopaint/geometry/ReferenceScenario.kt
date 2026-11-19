// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

@file:Suppress("LocalVariableName")

package com.cinderblocksoftware.kaleidopaint.geometry

import kotlin.math.max

//	The Kotlin twin of tools/reference/main.swift.
//
//	It runs the same fixed inputs through the Kotlin port and records
//	the results under the same keys.  ReferenceTest compares them with
//	what upstream's Swift code printed (src/test/resources/reference.txt).
//
//	Keep the two scenario files in step:  a line added here
//	needs its twin there, with the same key.

sealed class ReferenceValue {
    data class Text(val string: String) : ReferenceValue()

    data class Ints(val ints: List<Long>) : ReferenceValue()

    data class Doubles(val doubles: List<Double>) : ReferenceValue()

    data class Floats(val floats: List<Float>) : ReferenceValue()
}

class ReferenceScenario(

    //	Upstream's reference values, consulted for one thing only:  which
    //	basepoint upstream happened to choose for each stroke (see drawStroke()).
    private val itsReference: Map<String, ReferenceValue>? = null
) {

    val itsLines = LinkedHashMap<String, ReferenceValue>()

    // MARK: -
    // MARK: Output

    private fun put(key: String, value: ReferenceValue) {
        check(itsLines.put(key, value) == null) { "duplicate key $key" }
    }

    private fun emitString(key: String, string: String) = put(key, ReferenceValue.Text(string))

    private fun emitInts(key: String, ints: List<Int>) =
        put(key, ReferenceValue.Ints(ints.map { it.toLong() }))

    private fun emitInt(key: String, int: Int) = emitInts(key, listOf(int))

    private fun emitBool(key: String, bool: Boolean) = emitInts(key, listOf(if (bool) 1 else 0))

    private fun emitDoubles(key: String, doubles: List<Double>) =
        put(key, ReferenceValue.Doubles(doubles))

    private fun emitDouble(key: String, double: Double) = emitDoubles(key, listOf(double))

    private fun emitFloats(key: String, floats: List<Float>) =
        put(key, ReferenceValue.Floats(floats))

    private fun emitVector(key: String, vector: Double2) =
        emitDoubles(key, listOf(vector[0], vector[1]))

    private fun emitMatrix(key: String, matrix: Double2x2) =
        emitDoubles(key, listOf(matrix[0][0], matrix[0][1], matrix[1][0], matrix[1][1]))

    private fun emitMatrix(key: String, matrix: Double3x3) {
        val theEntries = mutableListOf<Double>()
        for (theColumn in 0 until 3) {
            for (theRow in 0 until 3) {
                theEntries.add(matrix[theColumn][theRow])
            }
        }
        emitDoubles(key, theEntries)
    }

    private fun flattenSegments(segments: List<Pair<Double2, Double2>>): List<Double> =
        segments.flatMap {
            listOf(it.first[0], it.first[1], it.second[0], it.second[1])
        }

    private fun flattenPoints(points: List<Double2>): List<Double> = points.flatMap {
        listOf(it[0], it[1])
    }

    // MARK: -
    // MARK: Shared inputs

    private fun similarity(
        cosθ: Double,
        sinθ: Double,
        scale: Double,
        translation: Double2,
    ): Double3x2 {
        return Double3x2(
            Double2(scale * cosθ, scale * sinθ),
            Double2(-scale * sinθ, scale * cosθ),
            translation,
        )
    }

    private val gCos003 = 0.99955003374898754
    private val gSin003 = 0.029995500202495660
    private val gCos02 = 0.98006657784124163
    private val gSin02 = 0.19866933079506122

    private fun namedPlacements(): List<Pair<String, UnitCellPlacement>> {

        val theSquare = UnitCellPlacement(defaultForWallpaperGroup = WallpaperGroup.wpgO)
        val theRhombus = UnitCellPlacement(defaultForWallpaperGroup = WallpaperGroup.wpg333)

        val theSheared = UnitCellPlacement(defaultForWallpaperGroup = WallpaperGroup.wpg2222)
        theSheared.itsTranslations =
            Double2x2(
                Double2(0.31, 0.04),
                Double2(0.17, 0.22),
            )
        theSheared.itsCorner = Double2(-0.07, 0.11)

        return listOf(
            Pair("square", theSquare),
            Pair("rhombus", theRhombus),
            Pair("sheared", theSheared),
        )
    }

    private fun namedSplines(): List<Pair<String, CubicSpline>> {

        fun spline(vararg nodes: Triple<Double, Double, String>): CubicSpline {
            val theSpline = CubicSpline()
            for ((x, y, type) in nodes) {
                theSpline.append(
                    SplineNode(
                        location = Double2(x, y),
                        type = if (type == "c") SplineNodeType.corner else SplineNodeType.smooth,
                    )
                )
            }
            return theSpline
        }
        fun n(x: Double, y: Double, type: String) = Triple(x, y, type)

        val theLongNodes = mutableListOf<Triple<Double, Double, String>>()
        for (i in 0 until 40) {
            val x = (i.toDouble() * 0.6180339887) % 1.0
            val y = (i.toDouble() * 0.7548776662) % 1.0
            theLongNodes.add(n(0.2 + 0.6 * x, 0.2 + 0.6 * y, if (i % 7 == 3) "c" else "s"))
        }

        return listOf(
            Pair(
                "single",
                spline(n(0.4, 0.6, "s")),
            ),
            Pair(
                "two",
                spline(
                    n(0.1, 0.2, "s"),
                    n(0.8, 0.6, "s"),
                ),
            ),
            Pair(
                "three",
                spline(
                    n(0.1, 0.2, "s"),
                    n(0.45, 0.7, "s"),
                    n(0.8, 0.3, "s"),
                ),
            ),
            Pair(
                "wave",
                spline(
                    n(0.10, 0.50, "s"),
                    n(0.20, 0.72, "s"),
                    n(0.35, 0.31, "s"),
                    n(0.50, 0.66, "s"),
                    n(0.62, 0.28, "s"),
                    n(0.80, 0.55, "s"),
                    n(0.93, 0.47, "s"),
                ),
            ),
            Pair(
                "corners",
                spline(
                    n(0.15, 0.15, "c"),
                    n(0.30, 0.60, "s"),
                    n(0.50, 0.80, "c"),
                    n(0.55, 0.35, "c"),
                    n(0.75, 0.20, "s"),
                    n(0.90, 0.65, "s"),
                ),
            ),
            Pair(
                "coincident",
                spline(
                    n(0.2, 0.2, "s"),
                    n(0.5, 0.5, "s"),
                    n(0.5, 0.5, "s"),
                    n(0.8, 0.3, "s"),
                ),
            ),
            Pair(
                "far",
                spline(
                    n(1.62, -2.31, "s"),
                    n(1.75, -2.12, "s"),
                    n(1.93, -2.44, "c"),
                    n(2.21, -2.20, "s"),
                ),
            ),
            Pair(
                "halves",
                spline(
                    n(1.75, 2.5, "s"),
                    n(2.25, 3.5, "s"),
                ),
            ),
            Pair("long", spline(*theLongNodes.toTypedArray())),
        )
    }

    private fun indexOfNode(node: SplineNode?, spline: CubicSpline): Int {
        if (node == null) {
            return -1
        }
        return spline.itsNodes.indexOfFirst { it === node }
    }

    // MARK: -
    // MARK: Wallpaper groups

    fun emitWallpaperGroups() {

        emitInt("groups.count", WallpaperGroup.entries.size)

        for ((i, theGroup) in WallpaperGroup.entries.withIndex()) {

            val k = "groups.$i"
            val theTorusGroup = theGroup.torusGroup

            emitString("$k.rawValue", theGroup.rawValue)
            emitString("$k.id", theGroup.id)
            emitString("$k.orbifoldName", theGroup.orbifoldName)
            emitString("$k.IUCName", theGroup.IUCName)

            emitInt("$k.elementCount", theTorusGroup.itsElements.size)
            for ((j, theElement) in theTorusGroup.itsElements.withIndex()) {
                emitMatrix("$k.element.$j.matrix", theElement.itsMatrix)
                emitDoubles(
                    "$k.element.$j.color",
                    listOf(
                        theElement.itsColor.r,
                        theElement.itsColor.g,
                        theElement.itsColor.b,
                        theElement.itsColor.a,
                    ),
                )
            }

            emitBool(
                "$k.constraints.rhombus",
                theTorusGroup.itsUnitCellShapeConstraints.contains(ShapeConstraint.rhombus),
            )
            emitBool(
                "$k.constraints.angle_2π_over_4",
                theTorusGroup.itsUnitCellShapeConstraints.contains(ShapeConstraint.angle_2π_over_4),
            )
            emitBool(
                "$k.constraints.angle_2π_over_6",
                theTorusGroup.itsUnitCellShapeConstraints.contains(ShapeConstraint.angle_2π_over_6),
            )
            emitString("$k.rigidity", theTorusGroup.itsRigidity.name)

            emitDoubles("$k.mirrorSegments", flattenSegments(theTorusGroup.itsMirrorSegments))
            emitDoubles("$k.gyrationPoints", flattenPoints(theTorusGroup.itsGyrationPoints))
            emitDoubles(
                "$k.glideReflectionSegments",
                flattenSegments(theTorusGroup.itsGlideReflectionSegments),
            )
        }
    }

    // MARK: -
    // MARK: Constants

    fun emitConstants() {

        emitDouble("constants.gSafeRegionInset", gSafeRegionInset)
        emitInts("constants.shifts", listOf(gMinShift, gMaxShift, gNumShifts))

        emitDoubles("constants.gUnitCircleVertices", flattenPoints(gUnitCircleVertices))
        emitInt("constants.gUnitCircleVertexCount", gUnitCircleVertexCount)
        emitInt("constants.gUnitHalfCircleVertexCount", gUnitHalfCircleVertexCount)
        emitDoubles("constants.gRawControlHandleVertices", flattenPoints(gRawControlHandleVertices))
        emitInt("constants.gControlHandleVertexCount", gControlHandleVertexCount)

        emitInts(
            "constants.Curve",
            listOf(
                Curve.maxArcSegmentCount,
                Curve.maxArcVertexCount,
                Curve.maxPointVertexCount,
                Curve.triStripBufferVertexCount,
            ),
        )
        emitInt("constants.Dot.triStripBufferVertexCount", Dot.triStripBufferVertexCount)

        emitString(
            "constants.SplineNodeType",
            SplineNodeType.entries.joinToString(",") { "${it.rawValue}/${it.id}" },
        )

        for ((i, theValue) in
            listOf(-0.5, -0.001, 0.0, 0.001, 0.0031308, 0.02, 0.04045, 0.18, 0.5, 1.0, 1.25)
                .withIndex()) {
            emitDoubles(
                "constants.gamma.$i",
                listOf(
                    gammaEncode(theValue),
                    gammaDecode(theValue),
                    clampToZeroOne(theValue),
                ),
            )
        }

        val theColor = LinearDisplayP3Color(r = 0.25, g = 0.5, b = 0.75, a = 1.0)
        emitInts(
            "constants.color.almostSame",
            listOf(
                if (
                    theColor.isAlmostTheSameAs(
                        LinearDisplayP3Color(r = 0.2501, g = 0.5, b = 0.7499, a = 1.0)
                    )
                )
                    1
                else 0,
                if (
                    theColor.isAlmostTheSameAs(
                        LinearDisplayP3Color(r = 0.2601, g = 0.5, b = 0.75, a = 1.0)
                    )
                )
                    1
                else 0,
                if (
                    theColor.isAlmostTheSameAs(
                        LinearDisplayP3Color(r = 0.25, g = 0.5, b = 0.75, a = 0.98)
                    )
                )
                    1
                else 0,
            ),
        )
        val theHalf = theColor.asSIMDHalf()
        emitFloats(
            "constants.color.asSIMDHalf",
            listOf(theHalf[0], theHalf[1], theHalf[2], theHalf[3]),
        )
    }

    // MARK: -
    // MARK: Unit cell placement

    private fun emitPlacement(key: String, placement: UnitCellPlacement) {
        emitVector("$key.corner", placement.itsCorner)
        emitMatrix("$key.translations", placement.itsTranslations)
        emitMatrix("$key.metric", placement.itsMetricOfDet1)
        emitBool("$key.degenerate", placement.unitCellIsDegenerate())
    }

    fun emitUnitCellPlacements() {

        for ((i, theGroup) in WallpaperGroup.entries.withIndex()) {

            val k = "placement.$i"

            val theDefault = UnitCellPlacement(defaultForWallpaperGroup = theGroup)
            emitPlacement("$k.default", theDefault)

            //	Rotate by 0.2 radians, dilate and translate…
            val theTransformed = theDefault.copy()
            theTransformed.transform(
                using =
                    similarity(
                        cosθ = gCos02,
                        sinθ = gSin02,
                        scale = 1.7,
                        translation = Double2(0.4, -0.9),
                    )
            )
            emitPlacement("$k.transformed", theTransformed)

            //	…bring the cell back to the origin…
            theTransformed.centerTheUnitCell()
            emitPlacement("$k.centered", theTransformed)

            //	…and check that a tilt that large doesn't snap.
            theTransformed.snapToViewAlignment()
            emitPlacement("$k.notSnapped", theTransformed)

            //	A tilt of 0.03 radians does snap.
            val theTilted = theDefault.copy()
            theTilted.transform(
                using =
                    similarity(
                        cosθ = gCos003,
                        sinθ = gSin003,
                        scale = 1.0,
                        translation = Double2(0.0, 0.0),
                    )
            )
            emitPlacement("$k.tilted", theTilted)
            theTilted.snapToViewAlignment()
            emitPlacement("$k.snapped", theTilted)

            //	The same tilt the other way.
            val theTiltedBack = theDefault.copy()
            theTiltedBack.transform(
                using =
                    similarity(
                        cosθ = gCos003,
                        sinθ = -gSin003,
                        scale = 1.0,
                        translation = Double2(0.0, 0.0),
                    )
            )
            theTiltedBack.snapToViewAlignment()
            emitPlacement("$k.snappedBack", theTiltedBack)
        }

        //	Cells that are too small, too big, too lopsided or too flat.
        val theDegenerateCells: List<Pair<String, Double2x2>> =
            listOf(
                Pair("tiny", Double2x2(Double2(0.01, 0.0), Double2(0.0, 0.01))),
                Pair("huge", Double2x2(Double2(65.0, 0.0), Double2(0.0, 65.0))),
                Pair("lopsided", Double2x2(Double2(9.0, 0.0), Double2(0.0, 1.0))),
                Pair("flat", Double2x2(Double2(1.0, 0.0), Double2(1.0, 0.05))),
                Pair("mirrored", Double2x2(Double2(0.0, 1.0), Double2(1.0, 0.0))),
                Pair("fine", Double2x2(Double2(1.0, 0.0), Double2(0.9, 0.5))),
            )
        for ((theName, theTranslations) in theDegenerateCells) {
            val thePlacement = UnitCellPlacement(defaultForWallpaperGroup = WallpaperGroup.wpgO)
            thePlacement.itsTranslations = theTranslations
            emitPlacement("placement.cell.$theName", thePlacement)
        }

        emitInts(
            "placement.shape.equal",
            listOf(
                if (
                    UnitCellShape(aspectRatio = 1.5, shear = 0.25) ==
                        UnitCellShape(aspectRatio = 1.5, shear = 0.25)
                )
                    1
                else 0,
                if (
                    UnitCellShape(aspectRatio = 1.5, shear = 0.25) ==
                        UnitCellShape(aspectRatio = 1.5, shear = 0.5)
                )
                    1
                else 0,
            ),
        )
    }

    // MARK: -
    // MARK: Coordinate systems

    fun emitCoordinateSystems() {

        val theViewSizes: List<Pair<Double, Double>> =
            listOf(Pair(390.0, 844.0), Pair(1024.0, 768.0), Pair(1080.0, 2400.0))
        val theFractions: List<Pair<Double, Double>> =
            listOf(
                Pair(0.0, 0.0),
                Pair(0.5, 0.5),
                Pair(0.03125, 0.9375),
                Pair(1.0, 1.0),
                Pair(0.71, 0.13),
            )

        for ((i, theSize) in (listOf(Pair(0.0, 0.0)) + theViewSizes).withIndex()) {
            val (w, h) = convertPageSizeToDrawingCoordinates(theSize.first, theSize.second)
            emitDoubles("coordinates.pageSize.$i", listOf(w, h))
        }

        for ((thePlacementName, thePlacement) in namedPlacements()) {
            for ((v, theSize) in theViewSizes.withIndex()) {
                val (theWidth, theHeight) = theSize
                for ((p, theFraction) in theFractions.withIndex()) {
                    val (fx, fy) = theFraction

                    val k = "coordinates.$thePlacementName.view$v.point$p"

                    val theDisplayPoint =
                        DisplayPoint(
                            x = fx * theWidth,
                            y = fy * theHeight,
                            viewWidth = theWidth,
                            viewHeight = theHeight,
                        )

                    val theDrawingPoint =
                        convertDisplayCoordinatesToDrawingCoordinates(theDisplayPoint)
                    emitVector("$k.displayToDrawing", theDrawingPoint)

                    val theRoundTrip =
                        convertDrawingCoordinatesToDisplayCoordinates(
                            theDrawingPoint,
                            viewWidth = theWidth,
                            viewHeight = theHeight,
                        )
                    emitDoubles(
                        "$k.drawingToDisplay",
                        listOf(
                            theRoundTrip.x,
                            theRoundTrip.y,
                            theRoundTrip.viewWidth,
                            theRoundTrip.viewHeight,
                        ),
                    )

                    val theMotion =
                        DisplayPointMotion(
                            Δx = (fx - 0.25) * theWidth,
                            Δy = (0.4 - fy) * theHeight,
                            viewWidth = theWidth,
                            viewHeight = theHeight,
                        )
                    emitVector(
                        "$k.displayTranslationToDrawing",
                        convertDisplayTranslationToDrawingTranslation(theMotion),
                    )

                    val theExtendedPoint =
                        convertDrawingCoordinatesToExtendedUnitCellCoordinates(
                            theDrawingPoint,
                            unitCellPlacement = thePlacement,
                        )
                    emitVector("$k.drawingToExtended", theExtendedPoint)

                    emitVector(
                        "$k.extendedToDrawing",
                        convertExtendedUnitCellCoordinatesToDrawingCoordinates(
                            theExtendedPoint,
                            unitCellPlacement = thePlacement,
                        ),
                    )

                    emitVector(
                        "$k.extendedToStrict",
                        convertExtendedUnitCellCoordinatesToStrictUnitCellCoordinates(
                            theExtendedPoint
                        ),
                    )

                    emitVector(
                        "$k.displayToExtended",
                        convertDisplayCoordinatesToExtendedUnitCellCoordinates(
                            theDisplayPoint,
                            unitCellPlacement = thePlacement,
                        ),
                    )

                    emitVector(
                        "$k.displayToStrict",
                        convertDisplayCoordinatesToStrictUnitCellCoordinates(
                            theDisplayPoint,
                            unitCellPlacement = thePlacement,
                        ),
                    )

                    val theBack =
                        convertExtendedUnitCellCoordinatesToDisplayCoordinates(
                            Double2(fx * 3.0 - 1.0, fy * 3.0 - 1.0),
                            unitCellPlacement = thePlacement,
                            viewWidth = theWidth,
                            viewHeight = theHeight,
                        )
                    emitDoubles(
                        "$k.extendedToDisplay",
                        listOf(
                            theBack.x,
                            theBack.y,
                            theBack.viewWidth,
                            theBack.viewHeight,
                        ),
                    )
                }
            }
        }
    }

    // MARK: -
    // MARK: Splines

    private fun emitSpline(key: String, spline: CubicSpline) {

        emitInt("$key.nodeCount", spline.itsNodes.size)

        for ((i, theNode) in spline.itsNodes.withIndex()) {

            emitVector("$key.node.$i.location", theNode.itsNodeLocation)
            emitString("$key.node.$i.type", theNode.itsNodeType.rawValue)

            val ξ = theNode.ξ
            emitDoubles(
                "$key.node.$i.ξ",
                listOf(
                    ξ[0][0],
                    ξ[0][1],
                    ξ[1][0],
                    ξ[1][1],
                    ξ[2][0],
                    ξ[2][1],
                    ξ[3][0],
                    ξ[3][1],
                ),
            )

            //	S(u) = ξ₀(1-u) + ξ₁u + ξ₂(1-u)³ + ξ₃u³  at fixed values of u.
            val theSamples = mutableListOf<Double>()
            for (u in listOf(0.0, 0.125, 0.25, 0.5, 0.75, 0.875, 1.0)) {
                val uu = 1.0 - u
                val thePoint: Double2 =
                    (uu * ξ[0] + u * ξ[1] + uu * uu * uu * ξ[2] + u * u * u * ξ[3])
                theSamples.add(thePoint[0])
                theSamples.add(thePoint[1])
            }
            emitDoubles("$key.node.$i.samples", theSamples)
        }
    }

    fun emitSplines() {

        for ((theName, theSpline) in namedSplines()) {

            val k = "spline.$theName"

            emitSpline("$k.beforeRefresh", theSpline)

            theSpline.refreshParameterization()
            emitSpline("$k.refreshed", theSpline)

            //	Split the first, the last and a middle node.
            val theCount = theSpline.itsNodes.size
            for ((theLabel, theIndex) in
                listOf(
                    Pair("first", 0),
                    Pair("middle", theCount / 2),
                    Pair("last", theCount - 1),
                )) {
                val (theNodeA, theNodeB) = theSpline.splitNode(theSpline.itsNodes[theIndex])
                emitVector("$k.split.$theLabel.A", theNodeA.itsNodeLocation)
                emitString("$k.split.$theLabel.A.type", theNodeA.itsNodeType.rawValue)
                emitVector("$k.split.$theLabel.B", theNodeB.itsNodeLocation)
                emitString("$k.split.$theLabel.B.type", theNodeB.itsNodeType.rawValue)
            }

            emitVector("$k.shift", theSpline.computeShiftToKeepCenteredInUnitCell())
            theSpline.keepCenteredInUnitCell()
            theSpline.refreshParameterization()
            emitSpline("$k.centered", theSpline)

            theSpline.applyShift(Double2(-2.0, 3.0))
            emitDoubles(
                "$k.shiftedBy(-2,3)",
                flattenPoints(theSpline.itsNodes.map { it.itsNodeLocation }),
            )
        }

        //	An empty curve asks for no shift at all.
        emitVector("spline.empty.shift", CubicSpline().computeShiftToKeepCenteredInUnitCell())
    }

    // MARK: -
    // MARK: Vector computations

    fun emitVectorComputations() {

        val theVectors: List<Double2> =
            listOf(
                Double2(1.0, 0.0),
                Double2(0.0, 1.0),
                Double2(0.3, -0.4),
                Double2(-2.5, 1.75),
                Double2(1e-9, 2e-9),
                Double2(0.0, 0.0),
            )

        for ((thePlacementName, thePlacement) in namedPlacements()) {
            for ((i, theVector) in theVectors.withIndex()) {

                val k = "vectors.$thePlacementName.$i"
                val theMetric = thePlacement.itsMetricOfDet1

                val theUnitVector = unitLengthVector(v = theVector, metricOfDet1 = theMetric)
                emitVector("$k.unitLengthVector", theUnitVector)
                emitVector(
                    "$k.orthogonalVector",
                    orthogonalVector(to = theVector, metricOfDet1 = theMetric),
                )
                emitVector(
                    "$k.orthogonalToUnit",
                    orthogonalVector(to = theUnitVector, metricOfDet1 = theMetric),
                )
            }
        }
    }

    // MARK: -
    // MARK: Rendering

    //	The counterpart of tools/reference/RecordingRenderEncoder.swift.
    private class RecordingRenderEncoder : BrushstrokeRenderEncoder {

        class RecordedDraw(
            val vertexCount: Int,
            val instanceCount: Int,
            val vertices: List<Float>,
            val controlHandlePlacement: List<Float>,
            val controlHandleColors: List<Float>,
        )

        val itsDraws = mutableListOf<RecordedDraw>()

        fun reset() {
            itsDraws.clear()
        }

        override fun drawTriangleStrip(
            vertices: VertexScratchBuffer,
            vertexCount: Int,
            instanceCount: Int,
        ) {
            itsDraws.add(
                RecordedDraw(
                    vertexCount = vertexCount,
                    instanceCount = instanceCount,
                    vertices = vertices.itsFloats.take(2 * vertexCount),
                    controlHandlePlacement = listOf(),
                    controlHandleColors = listOf(),
                )
            )
        }

        override fun drawControlHandle(
            placement: ControlHandlePlacement,
            colors: ControlHandleColors,
            vertexCount: Int,
            instanceCount: Int,
        ) {
            val i = colors.itsInnerColor
            val o = colors.itsOuterColor
            itsDraws.add(
                RecordedDraw(
                    vertexCount = vertexCount,
                    instanceCount = instanceCount,
                    vertices = listOf(),
                    controlHandlePlacement =
                        listOf(placement.itsCenter[0], placement.itsCenter[1], placement.itsRadius),
                    controlHandleColors = listOf(i[0], i[1], i[2], i[3], o[0], o[1], o[2], o[3]),
                )
            )
        }
    }

    private fun emitDraws(key: String, encoder: RecordingRenderEncoder) {

        emitInt("$key.drawCount", encoder.itsDraws.size)

        for ((i, theDraw) in encoder.itsDraws.withIndex()) {
            //	The first number is Metal's vertexStart, which upstream always passes as 0.
            emitInts("$key.draw.$i.counts", listOf(0, theDraw.vertexCount, theDraw.instanceCount))
            emitFloats("$key.draw.$i.vertices", theDraw.vertices)
        }
    }

    private fun emitControlHandles(key: String, encoder: RecordingRenderEncoder) {

        emitInt("$key.drawCount", encoder.itsDraws.size)

        for ((i, theDraw) in encoder.itsDraws.withIndex()) {
            emitInts("$key.draw.$i.counts", listOf(0, theDraw.vertexCount, theDraw.instanceCount))
            emitFloats("$key.draw.$i.placement", theDraw.controlHandlePlacement)
            emitFloats("$key.draw.$i.colors", theDraw.controlHandleColors)
        }
    }

    fun emitRendering() {

        val theEncoder = RecordingRenderEncoder()
        val theScratchBuffer =
            VertexScratchBuffer(
                vertexCapacity = max(Curve.triStripBufferVertexCount, Dot.triStripBufferVertexCount)
            )

        for ((thePlacementName, thePlacement) in namedPlacements()) {

            val theMetric = thePlacement.itsMetricOfDet1

            //	Curves
            for ((theSplineName, theSpline) in namedSplines()) {
                if (theSpline.itsNodes.size < 2) {
                    continue
                }

                val k = "render.$thePlacementName.curve.$theSplineName"

                theSpline.refreshParameterization()

                val theCurve =
                    Curve(
                        color = LinearDisplayP3Color(r = 0.0, g = 0.5, b = 1.0, a = 1.0),
                        thickness = 0.03,
                    )
                theCurve.itsSpline = theSpline

                theEncoder.reset()
                theCurve.render(
                    renderEncoder = theEncoder,
                    metricOfDet1 = theMetric,
                    scratchBuffer = theScratchBuffer,
                    symmetryCount = 4,
                )
                emitDraws(k, theEncoder)

                theEncoder.reset()
                theCurve.renderControlHandles(
                    selectedNode = theSpline.itsNodes[1],
                    renderEncoder = theEncoder,
                    symmetryCount = 6,
                )
                emitControlHandles("$k.handles", theEncoder)

                theEncoder.reset()
                theCurve.renderControlHandles(
                    selectedNode = null,
                    renderEncoder = theEncoder,
                    symmetryCount = 6,
                )
                emitControlHandles("$k.handlesUnselected", theEncoder)
            }

            //	Dots
            val theDots: List<Pair<Double2, Double>> =
                listOf(
                    Pair(Double2(0.5, 0.5), 0.01),
                    Pair(Double2(0.125, 0.875), 0.08),
                    Pair(Double2(-0.3, 1.2), 0.0025),
                )
            for ((i, theDotSpec) in theDots.withIndex()) {
                val (theCenter, theThickness) = theDotSpec

                val k = "render.$thePlacementName.dot.$i"

                val theDot =
                    Dot(
                        color = LinearDisplayP3Color(r = 1.0, g = 0.5, b = 0.0, a = 1.0),
                        center = theCenter,
                        thickness = theThickness,
                    )

                theEncoder.reset()
                theDot.render(
                    renderEncoder = theEncoder,
                    metricOfDet1 = theMetric,
                    scratchBuffer = theScratchBuffer,
                    symmetryCount = 12,
                )
                emitDraws(k, theEncoder)

                theEncoder.reset()
                theDot.renderControlHandle(
                    isSelected = true,
                    renderEncoder = theEncoder,
                    symmetryCount = 12,
                )
                theDot.renderControlHandle(
                    isSelected = false,
                    renderEncoder = theEncoder,
                    symmetryCount = 12,
                )
                emitControlHandles("$k.handles", theEncoder)
            }
        }

        //	Default constructors
        val theDefaultDot = Dot()
        emitDoubles(
            "render.defaults.dot",
            listOf(
                theDefaultDot.itsCenter[0],
                theDefaultDot.itsCenter[1],
                theDefaultDot.itsThickness,
                theDefaultDot.itsColor.r,
                theDefaultDot.itsColor.g,
                theDefaultDot.itsColor.b,
                theDefaultDot.itsColor.a,
            ),
        )
        val theDefaultCurve = Curve()
        emitDoubles(
            "render.defaults.curve",
            listOf(
                theDefaultCurve.itsSpline.itsNodes.size.toDouble(),
                theDefaultCurve.itsThickness,
                theDefaultCurve.itsColor.r,
                theDefaultCurve.itsColor.g,
                theDefaultCurve.itsColor.b,
                theDefaultCurve.itsColor.a,
            ),
        )
    }

    // MARK: -
    // MARK: Hit testing

    private fun emitHit(key: String, hit: ControlHandleHit?, spline: CubicSpline?) {

        if (hit == null) {
            emitBool("$key.hit", false)
            return
        }

        emitBool("$key.hit", true)
        emitInt(
            "$key.node",
            if (spline != null) indexOfNode(hit.itsNode, spline)
            else (if (hit.itsNode == null) -1 else -2),
        )
        emitVector("$key.homeCenter", hit.itsHomeCenter)
        emitVector("$key.hitCenter", hit.itsHitCenter)
        emitMatrix("$key.symmetry", hit.itsSymmetry)
        emitDouble("$key.tapError", hit.itsTapError)
    }

    fun emitHitTesting() {

        val theFixedTouchPoints: List<Double2> =
            listOf(
                Double2(0.3, 0.2),
                Double2(0.31, 0.21),
                Double2(1.3, -0.8),
                Double2(0.7, 0.8),
                Double2(0.52, 0.48),
                Double2(-0.69, 1.21),
                Double2(2.05, 3.1),
                Double2(0.123, 0.456),
                Double2(0.2, 0.7),
                Double2(0.36, 0.33),
                Double2(-3.38, 5.69),
            )

        val theWave = namedSplines().first { it.first == "wave" }.second
        theWave.refreshParameterization()

        for ((i, theGroup) in WallpaperGroup.entries.withIndex()) {

            val theMetric = UnitCellPlacement(defaultForWallpaperGroup = theGroup).itsMetricOfDet1

            val theDot = Dot(center = Double2(0.3, 0.2), thickness = 0.02)
            val theCurve = Curve(thickness = 0.02)
            theCurve.itsSpline = theWave

            //	The fixed touch points, plus one just beside
            //	each image of the dot under the torus group.
            val theTouchPoints = theFixedTouchPoints.toMutableList()
            for (theElement in theGroup.torusGroup.itsElements) {
                val theImage = theElement.itsMatrix * Double3(0.3, 0.2, 1.0)
                theTouchPoints.add(Double2(theImage[0] + 0.004, theImage[1] - 0.003))
                theTouchPoints.add(Double2(theImage[0] + 2.0 - 0.002, theImage[1] - 1.0 + 0.005))
            }

            for ((j, theTouchPoint) in theTouchPoints.withIndex()) {

                emitHit(
                    "hit.$i.dot.$j",
                    theDot.hitControlHandle(
                        touchPointInExtendedUnitCellCoordinates = theTouchPoint,
                        wallpaperGroup = theGroup,
                        metricOfDet1 = theMetric,
                        fillMarkerRadius = 0.0,
                    ),
                    null,
                )

                emitHit(
                    "hit.$i.curve.$j",
                    theCurve.hitControlHandle(
                        touchPointInExtendedUnitCellCoordinates = theTouchPoint,
                        wallpaperGroup = theGroup,
                        metricOfDet1 = theMetric,
                        fillMarkerRadius = 0.0,
                    ),
                    theWave,
                )
            }

            //	Touches exactly half way between two images of a fat dot,
            //	where the choice of image depends on how a half gets rounded.
            val theFatDot = Dot(center = Double2(0.25, 0.25), thickness = 0.25)
            val theHalfwayPoints: List<Double2> =
                listOf(
                    Double2(0.75, 2.75),
                    Double2(-1.25, -0.25),
                    Double2(-2.25, 3.75),
                    Double2(0.75, 0.25),
                )
            for ((j, theTouchPoint) in theHalfwayPoints.withIndex()) {
                emitHit(
                    "hit.$i.halfway.$j",
                    theFatDot.hitControlHandle(
                        touchPointInExtendedUnitCellCoordinates = theTouchPoint,
                        wallpaperGroup = theGroup,
                        metricOfDet1 = theMetric,
                        fillMarkerRadius = 0.0,
                    ),
                    null,
                )
            }
        }
    }

    // MARK: -
    // MARK: Drawing files
    //
    //	The twin of tools/reference/Documents.swift.

    companion object {

        fun drawingText(name: String): String {
            val theStream =
                ReferenceScenario::class.java.getResourceAsStream("/drawings/$name.kaleidopaint")
                    ?: error("drawings/$name.kaleidopaint is missing; run tools/reference/build.sh")
            return theStream.use { it.readBytes().toString(Charsets.UTF_8) }
        }

        //	The hand-built drawings in older file formats (tools/reference/legacy).
        val legacyNames =
            listOf(
                "format-1.0",
                "format-1.1",
                "format-1.2",
                "format-1.3",
                "format-1.4",
                "format-1.5",
                "format-1.6",
                "format-1.7",
                "format-1.8",
                "format-1.9",
                "whitespace",
            )

        //	The drawings made by sending strokes and taps through the touch handling.
        val touchDrawnNames = listOf("touch-drawn-p1", "touch-drawn-p6m", "touch-drawn-pgg")
        val touchDrawnGroups =
            listOf(WallpaperGroup.wpgO, WallpaperGroup.wpgS632, WallpaperGroup.wpg22X)
    }

    private fun emitColor(key: String, color: LinearDisplayP3Color) =
        emitDoubles(key, listOf(color.r, color.g, color.b, color.a))

    private fun emitDocument(key: String, document: KaleidoPaintDocument) {

        emitString("$key.wallpaperGroup", document.itsWallpaperGroup.rawValue)
        emitPlacement("$key.placement", document.itsUnitCellPlacement)
        emitColor("$key.backgroundColor", document.itsBackgroundColor)
        emitColor("$key.brushColor", document.itsBrushColor)
        emitColor("$key.fillColor", document.itsFillColor)
        emitDouble("$key.brushThickness", document.itsBrushThickness)
        emitDouble("$key.smoothingTolerance", document.itsSmoothingTolerance)
        emitInts(
            "$key.flags",
            listOf(
                if (document.itsShowSingularitiesFlag) 1 else 0,
                if (document.itsColorBySymmetryFlag) 1 else 0,
                if (document.itsContentIsLocked) 1 else 0,
            ),
        )

        emitInt("$key.elementCount", document.itsElements.size)
        for ((i, theElement) in document.itsElements.withIndex()) {

            val k = "$key.element.$i"
            emitColor("$k.color", theElement.itsColor)

            if (theElement is Dot) {
                emitString("$k.kind", "dot")
                emitVector("$k.center", theElement.itsCenter)
                emitDouble("$k.thickness", theElement.itsThickness)
            }
            if (theElement is Curve) {
                emitString("$k.kind", "curve")
                emitDouble("$k.thickness", theElement.itsThickness)
                emitSpline("$k.spline", theElement.itsSpline)
            }
            if (theElement is Fill) {
                emitString("$k.kind", "fill")
                emitVector("$k.fillPoint", theElement.itsFillPoint)
            }
        }
    }

    private fun readBack(name: String, text: String) {
        val theDecodedDocument = KaleidoPaintDocument()
        theDecodedDocument.decodeFileFormat(text)
        emitDocument("document.$name", theDecodedDocument)
    }

    //	A drawing from outside the repository (see ExternalDrawingsTest).
    fun emitExternalDrawing(fileName: String, text: String) {

        val theResult = decodingResult(text)
        emitString("external.$fileName.result", theResult)
        if (theResult != "accepted") {
            return
        }

        val theDocument = KaleidoPaintDocument()
        theDocument.decodeFileFormat(text)
        emitDocument("external.$fileName", theDocument)
    }

    private fun copyOfSpline(name: String): CubicSpline {
        val theSpline = namedSplines().first { it.first == name }.second
        theSpline.refreshParameterization()
        return theSpline
    }

    //	One drawing for each wallpaper group, with every kind of element.
    fun makeGroupDocument(index: Int, group: WallpaperGroup): KaleidoPaintDocument {

        val theDocument = KaleidoPaintDocument()
        val f = index.toDouble() / 16.0

        theDocument.itsWallpaperGroup = group

        val thePlacement = UnitCellPlacement(defaultForWallpaperGroup = group)
        thePlacement.transform(
            using =
                similarity(
                    cosθ = gCos02,
                    sinθ = gSin02,
                    scale = 1.0 + 0.0625 * index.toDouble(),
                    translation = Double2(0.01 * index.toDouble(), -0.02 * index.toDouble()),
                )
        )
        theDocument.itsUnitCellPlacement = thePlacement

        theDocument.itsBackgroundColor = LinearDisplayP3Color(r = f, g = 1.0 - f, b = 0.5, a = 1.0)
        theDocument.itsBrushColor = LinearDisplayP3Color(r = 1.0 - f, g = 0.25, b = f, a = 1.0)
        theDocument.itsFillColor =
            LinearDisplayP3Color(r = 0.125, g = f, b = 1.0 - 0.5 * f, a = 1.0)
        theDocument.itsBrushThickness =
            gDefaultThickness / kotlin.math.sqrt(group.torusGroup.itsElements.size.toDouble())
        theDocument.itsSmoothingTolerance = 0.002 + 0.001 * index.toDouble()
        theDocument.itsShowSingularitiesFlag = (index % 2 == 0)
        theDocument.itsColorBySymmetryFlag = (index % 3 == 0)
        theDocument.itsContentIsLocked = (index % 5 == 0)

        theDocument.itsElements.add(
            Dot(
                color = LinearDisplayP3Color(r = 1.0, g = f, b = 0.0, a = 1.0),
                center = Double2(0.3 + 0.01 * index.toDouble(), 0.2),
                thickness = 0.02,
            )
        )

        val theSplineNames =
            listOf("two", "three", "wave", "corners", "coincident", "far", "halves", "long")
        val theCurve =
            Curve(
                color = LinearDisplayP3Color(r = 0.0, g = 0.5, b = f, a = 1.0),
                thickness = 0.01 + 0.001 * index.toDouble(),
            )
        theCurve.itsSpline = copyOfSpline(theSplineNames[index % theSplineNames.size])
        theDocument.itsElements.add(theCurve)

        theDocument.itsElements.add(
            Fill(
                color = LinearDisplayP3Color(r = f, g = f, b = 1.0, a = 1.0),
                fillPoint = Double2(0.6, 0.4 + 0.01 * index.toDouble()),
            )
        )

        theDocument.itsElements.add(
            Dot(
                color = LinearDisplayP3Color(r = 0.2, g = 0.4, b = 0.6, a = 1.0),
                center = Double2(1.0 / 3.0, 2.0 / 3.0),
                thickness = 1.0 / 64.0,
            )
        )

        val theSecondCurve =
            Curve(
                color = LinearDisplayP3Color(r = 1.0 / 3.0, g = 2.0 / 3.0, b = 1.0 / 7.0, a = 1.0),
                thickness = 1.0 / 96.0,
            )
        theSecondCurve.itsSpline = copyOfSpline("corners")
        theDocument.itsElements.add(theSecondCurve)

        return theDocument
    }

    //	Numbers that sit exactly half way between two printed values,
    //	numbers that round to a negative zero, and numbers too wide for their field.
    fun makeRoundingDocument(): KaleidoPaintDocument {

        val theDocument = KaleidoPaintDocument()

        val a = 1.0 / 512.0 // 	0.001953125 : half way, at 8 decimal places
        val b = 1.0 / 131072.0 // 	0.00000762939453125 : half way, at 16 decimal places

        theDocument.itsBackgroundColor =
            LinearDisplayP3Color(r = a, g = 3.0 * a, b = 5.0 * a, a = 1.0)
        theDocument.itsBrushColor = LinearDisplayP3Color(r = -a, g = -3.0 * a, b = 1.0 - a, a = 1.0)
        theDocument.itsFillColor = LinearDisplayP3Color(r = -1e-10, g = -0.0, b = 1234.5, a = 1.0)
        theDocument.itsBrushThickness = b
        theDocument.itsSmoothingTolerance = 3.0 * b

        val thePlacement = UnitCellPlacement(defaultForWallpaperGroup = WallpaperGroup.wpgO)
        thePlacement.itsTranslations =
            Double2x2(
                Double2(0.25 + b, -1e-18),
                Double2(-0.0, 0.25 + 3.0 * b),
            )
        thePlacement.itsCorner = Double2(-5.0 * b, 123456.789)
        theDocument.itsUnitCellPlacement = thePlacement

        theDocument.itsElements.add(
            Dot(
                color = LinearDisplayP3Color(r = 7.0 * a, g = 0.5, b = 9.0 * a, a = 1.0),
                center = Double2(b, 7.0 * b),
                thickness = 9.0 * b,
            )
        )

        val theCurve =
            Curve(
                color = LinearDisplayP3Color(r = 0.0, g = 0.0, b = 0.0, a = 1.0),
                thickness = 11.0 * b,
            )
        for ((x, y, type) in
            listOf(
                Triple(a, 3.0 * a, SplineNodeType.corner),
                Triple(0.25 + 5.0 * a, 0.5 - a, SplineNodeType.smooth),
                Triple(0.5 - 1e-10, 0.75 + 7.0 * a, SplineNodeType.smooth),
                Triple(0.75, 1.0 - 1e-12, SplineNodeType.corner),
            )) {
            theCurve.itsSpline.append(SplineNode(location = Double2(x, y), type = type))
        }
        theCurve.itsSpline.refreshParameterization()
        theDocument.itsElements.add(theCurve)

        theDocument.itsElements.add(
            Fill(
                color = LinearDisplayP3Color(r = 1.0, g = 1.0, b = 1.0, a = 1.0),
                fillPoint = Double2(-b, 1.0 + b),
            )
        )

        return theDocument
    }

    //	Send one stroke through the document's touch handling.
    //
    //	Just before the finger lifts, record which basepoints are still valid
    //	(these must be the ones upstream found) and choose the one that
    //	upstream chose.  Upstream's choice is whichever element Swift's Set
    //	lists first, an accident of hashing;  any valid one gives the same
    //	drawing, stored relative to a different copy of the unit cell.
    private fun drawStroke(
        document: KaleidoPaintDocument,
        key: String,
        points: List<DisplayPoint>,
        emitting: Boolean = true,
    ) {
        document.touchBegan(at = points[0])
        for (thePoint in points.drop(1)) {
            document.touchMoved(to = thePoint)
        }

        val theBasepoints =
            document.itsCurveInProgressValidBasepoints.sortedWith(compareBy({ it.x }, { it.y }))

        val theReferenceChoice = itsReference?.get("$key.chosen")
        val theChosenBasepoint: Int2? =
            if (theReferenceChoice is ReferenceValue.Ints && theReferenceChoice.ints.size == 2) {
                Int2(theReferenceChoice.ints[0].toInt(), theReferenceChoice.ints[1].toInt())
            } else {
                document.itsCurveInProgressValidBasepoints.firstOrNull()
            }

        if (
            theChosenBasepoint != null &&
                theChosenBasepoint in document.itsCurveInProgressValidBasepoints
        ) {
            //	Put the chosen basepoint first, where touchEnded() will find it.
            val theReorderedBasepoints = mutableSetOf(theChosenBasepoint)
            theReorderedBasepoints.addAll(document.itsCurveInProgressValidBasepoints)
            document.itsCurveInProgressValidBasepoints = theReorderedBasepoints
        }

        if (emitting) {
            emitInts("$key.basepoints", theBasepoints.flatMap { listOf(it.x, it.y) })
            emitInts(
                "$key.chosen",
                if (theChosenBasepoint != null) listOf(theChosenBasepoint.x, theChosenBasepoint.y)
                else listOf(),
            )
            emitInt(
                "$key.rawNodeCount",
                document.itsCurveInProgress?.itsSpline?.itsNodes?.size ?: 0,
            )
        }

        document.touchEnded()
    }

    private fun newDocument(
        defaultSymmetryGroup: WallpaperGroup = WallpaperGroup.wpgO
    ): KaleidoPaintDocument {
        val theDocument = KaleidoPaintDocument(defaultSymmetryGroup = defaultSymmetryGroup)
        //	Without an undo manager the document ignores every edit.
        theDocument.itsUndoManager = UndoManager()
        return theDocument
    }

    //	A drawing made the way a finger makes one:  two strokes and two taps,
    //	sent through the document's own touch handling, which smooths
    //	each stroke into a few spline nodes.
    fun makeTouchDrawnDocument(
        name: String,
        group: WallpaperGroup,
        emitting: Boolean,
    ): KaleidoPaintDocument {

        val theDocument = newDocument()
        theDocument.itsWallpaperGroup = group
        theDocument.itsUnitCellPlacement = UnitCellPlacement(defaultForWallpaperGroup = group)

        val theWidth = 1080.0
        val theHeight = 2400.0
        fun point(x: Double, y: Double): DisplayPoint {
            return DisplayPoint(x = x, y = y, viewWidth = theWidth, viewHeight = theHeight)
        }

        //	A wobbly arch.
        val theArch = mutableListOf(point(300.0, 1200.0))
        for (k in 1..60) {
            val x = 300.0 + 8.0 * k.toDouble()
            val y = 1200.0 + 0.25 * (k * (60 - k)).toDouble() + 1.5 * ((k * 37) % 11).toDouble()
            theArch.add(point(x, y))
        }
        drawStroke(theDocument, "document.$name.stroke.arch", theArch, emitting)

        theDocument.singleTapForDrawing(at = point(540.0, 1500.0))

        //	A zigzag with sharp turns.
        theDocument.itsBrushColor = LinearDisplayP3Color(r = 0.0, g = 0.5, b = 0.25, a = 1.0)
        theDocument.itsBrushThickness *= 2.0
        val theZigzag = mutableListOf(point(200.0, 900.0))
        for (k in 1..80) {
            val x = 200.0 + 6.0 * k.toDouble()
            val theTooth = k % 20
            val y = 900.0 + 9.0 * (if (theTooth < 10) theTooth else 20 - theTooth).toDouble()
            theZigzag.add(point(x, y))
        }
        drawStroke(theDocument, "document.$name.stroke.zigzag", theZigzag, emitting)

        theDocument.singleTapForDrawing(at = point(123.0, 456.0))

        return theDocument
    }

    //	The drawings the Kotlin port can build in memory, by file name.
    fun builtDocuments(): List<Pair<String, KaleidoPaintDocument>> {

        val theDocuments = mutableListOf<Pair<String, KaleidoPaintDocument>>()

        //	A new, empty drawing, exactly as the app creates it.
        theDocuments.add(Pair("empty", KaleidoPaintDocument()))

        for ((i, theGroup) in WallpaperGroup.entries.withIndex()) {
            val theName = "group-%02d-".format(i) + theGroup.IUCName
            theDocuments.add(Pair(theName, makeGroupDocument(i, theGroup)))
        }

        theDocuments.add(Pair("rounding", makeRoundingDocument()))

        return theDocuments
    }

    fun emitDrawings() {

        //	Read back what upstream wrote.  (That the Kotlin port writes
        //	the same bytes is checked separately, in DrawingFileTest.)
        for ((theName, _) in builtDocuments()) {
            readBack(theName, drawingText(theName))
        }

        //	The drawings made by touch:  draw them here with the same touches,
        //	and read back the ones upstream drew.
        for ((theName, theGroup) in touchDrawnNames.zip(touchDrawnGroups)) {
            val theDocument = makeTouchDrawnDocument(theName, theGroup, emitting = true)
            emitDocument("document.$theName.asDrawn", theDocument)
            readBack(theName, drawingText(theName))
        }

        emitString("document.legacy.names", legacyNames.joinToString(" ") { "$it.kaleidopaint" })
        for (theLegacyName in legacyNames) {
            val theName = "legacy-$theLegacyName"
            readBack(theName, drawingText(theName))
        }
    }

    // MARK: -
    // MARK: Files that must be refused

    private val gMalformedCases: List<Triple<String, String, String>> =
        listOf(
            Triple("valid", "", ""),
            Triple("header-word", "KaleidoPaint Drawing", "KaleidoPaint Painting"),
            Triple("header-format", "format 1.10", "version 1.10"),
            Triple("major-unparsable", "format 1.10", "format one.10"),
            Triple("minor-unparsable", "format 1.10", "format 1.ten"),
            Triple("minor-negative", "format 1.10", "format 1.-3"),
            Triple("minor-from-the-future", "format 1.10", "format 1.99"),
            Triple("major-from-the-future", "format 1.10", "format 7.10"),
            Triple("wallpaper-group-label", "wallpaper group", "wallpaper troupe"),
            Triple("wallpaper-group-name", "wallpaper group ××", "wallpaper group *532"),
            Triple("placement-label", "unit cell placement", "unit cell position"),
            Triple("placement-number", "0.2165063509461097", "0.21650635O9461097"),
            Triple("resolution-label", "log2 unit cell resolution", "log3 unit cell resolution"),
            Triple(
                "resolution-not-a-number",
                "log2 unit cell resolution 11",
                "log2 unit cell resolution eleven",
            ),
            Triple("background-label", "background color", "backdrop color"),
            Triple("background-number", "background color 0.9", "background color 0,9"),
            Triple(
                "background-opacity",
                "background color 0.9 0.5 0.25 1.0",
                "background color 0.9 0.5 0.25 0.5",
            ),
            Triple("brush-color-label", "brush color", "brush colour"),
            Triple("fill-color-label", "fill color", "fill colour"),
            Triple("brush-thickness-label", "brush thickness", "brush width"),
            Triple("brush-thickness-number", "brush thickness  0.0078125", "brush thickness  thin"),
            Triple("smoothing-label", "smoothing tolerance", "smoothing strength"),
            Triple("smoothing-factor", "smoothing tolerance", "smoothing factor"),
            Triple("smoothing-number", "smoothing tolerance  0.0125", "smoothing tolerance  lots"),
            Triple("singularities-label", "show singularities", "hide singularities"),
            Triple("singularities-value", "show singularities false", "show singularities no"),
            Triple("symmetry-label", "color by symmetry", "color by number"),
            Triple("symmetry-value", "color by symmetry  true", "color by symmetry  yes"),
            Triple("locked-label", "content is locked", "content is frozen"),
            Triple("locked-value", "content is locked  true", "content is locked  True"),
            Triple("elements-label", "\nelements\n", "\nelemenTs\n"),
            Triple("no-more-elements", "no-more-elements", "no-more-elements please"),
            Triple("element-kind", "\nfill\n", "\nblob\n"),
            Triple("dot-property", "\tdiameter  0.015625", "\tradius  0.015625"),
            Triple("dot-center", "\tcenter    0.3125 0.71875", "\tcenter    0.3125 north"),
            Triple("dot-diameter", "\tdiameter  0.015625", "\tdiameter  wide"),
            Triple(
                "dot-old-names",
                "\tcenter    0.3125 0.71875\n\tdiameter  0.015625",
                "\tlocation  0.3125 0.71875\n\tthickness 0.015625",
            ),
            Triple(
                "dot-color-opacity",
                "\tcolor     1.0 0.5 0.0 1.0",
                "\tcolor     1.0 0.5 0.0 0.99",
            ),
            Triple("curve-property", "\tthickness 0.01171875", "\twidth 0.01171875"),
            Triple("curve-thickness", "\tthickness 0.01171875", "\tthickness thick"),
            Triple(
                "curve-node-number",
                "\tnode      2.25 -1.5   smooth",
                "\tnode      2.25 x   smooth",
            ),
            Triple(
                "curve-node-type",
                "\tnode      2.25 -1.5   smooth",
                "\tnode      2.25 -1.5   wavy",
            ),
            Triple("fill-property", "\tfillPoint 0.6 0.4", "\tfillpoint 0.6 0.4"),
            Triple("fill-point", "\tfillPoint 0.6 0.4", "\tfillPoint 0.6 0..4"),
            Triple("fill-old-name", "\tfillPoint 0.6 0.4", "\tlocation 0.6 0.4"),
        )

    private val gShortCases: List<Pair<String, String>> =
        listOf(
            Pair("empty-file", ""),
            Pair("three-tokens", "KaleidoPaint Drawing format"),
            Pair("header-only", "KaleidoPaint Drawing\nformat 1.10\n"),
            Pair(
                "forty-three-tokens",
                "KaleidoPaint Drawing format 1.7 wallpaper group 2222 unit cell placement 0 0 1 0 0 1 background color 1 1 1 1 brush color 0 0 0 1 brush thickness 0.01 show singularities true color by symmetry false content is locked false elements",
            ),
            Pair(
                "forty-seven-tokens-old-format",
                "KaleidoPaint Drawing format 1.4 wallpaper group 1 unit cell placement 0 0 1 0 0 1 background color 1 1 1 1 | 1 brush color 0 0 0 1 | 1 brush thickness 0.01 show singularities true color by symmetry false content is locked false elements",
            ),
        )

    fun malformedBaseText(): String =
        drawingText("legacy-whitespace")
            .replace("\r\n", "\n")
            .replace("\u00A0", " ")
            .replace("\u3000", "  ")

    fun decodingResult(text: String): String {
        val theDocument = KaleidoPaintDocument()
        try {
            theDocument.decodeFileFormat(text)
            return "accepted"
        } catch (theError: KaleidoPaintDocument.KaleidoPaintFileEncodingError.fileFormatError) {
            return theError.reason
        }
    }

    fun emitMalformedDrawings() {

        val theBaseText = malformedBaseText()

        for ((theName, theOld, theNew) in gMalformedCases) {
            check(theOld.isEmpty() || theBaseText.contains(theOld)) {
                "case $theName changes nothing"
            }
            val theText = if (theOld.isEmpty()) theBaseText else theBaseText.replace(theOld, theNew)
            emitString("malformed.$theName", decodingResult(theText))
        }
        for ((theName, theText) in gShortCases) {
            emitString("malformed.$theName", decodingResult(theText))
        }
    }

    // MARK: -
    // MARK: How Swift reads numbers

    private val gNumberStrings =
        listOf(
            "1",
            "1.",
            ".5",
            "+1.5",
            "-0.0",
            "-.5",
            "1e5",
            "1E-3",
            "1e+2",
            "1.5e",
            "e5",
            "inf",
            "-inf",
            "+inf",
            "infinity",
            "Infinity",
            "INF",
            "nan",
            "NaN",
            "-nan",
            "nan(1)",
            "0x1p3",
            "0x10",
            "0X1.8p1",
            "1.5f",
            "1.5d",
            "1,5",
            "1_000",
            "--1",
            "1.2.3",
            "0.1.",
            "",
            ".",
            "+",
            "-",
            "1-",
            "１",
            "٣",
            "1e400",
            "-1e400",
            "1e-400",
            "0.1e1",
            "00012.50",
            "+.5e-1",
            "1 ",
            " 1",
            "1\t",
            "0b101",
            "1/2",
            "∞",
        )
    private val gIntegerStrings =
        listOf(
            "5",
            "+5",
            "-5",
            "05",
            "5.0",
            "",
            "0x10",
            "1e3",
            "９",
            "5 ",
            " 5",
            "+",
            "-",
            "--5",
            "9223372036854775807",
            "9223372036854775808",
            "-9223372036854775808",
            "1_000",
            "٣",
        )

    fun emitNumberParsing() {
        for ((i, theString) in gNumberStrings.withIndex()) {
            val theValue = swiftDouble(theString)
            if (theValue != null) {
                emitDoubles("numbers.double.$i", listOf(theValue))
            } else {
                emitString("numbers.double.$i", "nil")
            }
        }
        for ((i, theString) in gIntegerStrings.withIndex()) {
            val theValue = swiftInt(theString)
            emitString("numbers.integer.$i", theValue?.toString() ?: "nil")
        }
    }

    // MARK: -
    // MARK: An editing session
    //
    //	The twin of tools/reference/Sessions.swift.

    //	The drawing that the editing session ends with.
    var itsSessionDocument: KaleidoPaintDocument? = null

    private fun emitSessionState(key: String, document: KaleidoPaintDocument) {

        emitString("$key.group", document.itsWallpaperGroup.rawValue)
        emitDoubles(
            "$key.placement",
            listOf(
                document.itsUnitCellPlacement.itsCorner[0],
                document.itsUnitCellPlacement.itsCorner[1],
                document.itsUnitCellPlacement.itsTranslations[0][0],
                document.itsUnitCellPlacement.itsTranslations[0][1],
                document.itsUnitCellPlacement.itsTranslations[1][0],
                document.itsUnitCellPlacement.itsTranslations[1][1],
            ),
        )
        emitDoubles(
            "$key.colors",
            listOf(
                document.itsBackgroundColor.r,
                document.itsBackgroundColor.g,
                document.itsBackgroundColor.b,
                document.itsBrushColor.r,
                document.itsBrushColor.g,
                document.itsBrushColor.b,
                document.itsFillColor.r,
                document.itsFillColor.g,
                document.itsFillColor.b,
            ),
        )
        emitDoubles(
            "$key.brush",
            listOf(document.itsBrushThickness, document.itsSmoothingTolerance),
        )

        val theShape = document.getUnitCellShape()
        emitDoubles("$key.shape", listOf(theShape.aspectRatio, theShape.shear))
        emitDouble("$key.fillMarkerRadius", document.fillMarkerRadius())

        emitInts(
            "$key.counts",
            listOf(
                document.changeCount.toInt(),
                document.itsBaseDrawingTextureFullRedrawRequestCount,
                document.itsBaseDrawingTextureLastElementRequestCount,
                document.itsCurveInProgressTextureRedrawRequestCount,
                document.itsSingularitiesTextureRedrawRequestCount,
                document.itsCompositeTextureRedrawRequestCount,
                document.itsUndoRedoCount,
            ),
        )
        emitInts(
            "$key.flags",
            listOf(
                if (document.itsUndoManager!!.canUndo) 1 else 0,
                if (document.itsUndoManager!!.canRedo) 1 else 0,
                if (document.itsCurveInProgress != null) 1 else 0,
                if (document.itsControlHandleHit != null) 1 else 0,
                if (document.itsContentIsLocked) 1 else 0,
                if (document.itsTouchMode == TouchMode.edit) 1 else 0,
            ),
        )

        emitInt("$key.elementCount", document.itsElements.size)
        for ((i, theElement) in document.itsElements.withIndex()) {

            val theNumbers =
                mutableListOf(theElement.itsColor.r, theElement.itsColor.g, theElement.itsColor.b)
            val theKind: String

            if (theElement is Dot) {
                theKind = "dot"
                theNumbers +=
                    listOf(
                        theElement.itsThickness,
                        theElement.itsCenter[0],
                        theElement.itsCenter[1],
                    )
            } else if (theElement is Curve) {
                theKind = "curve"
                theNumbers += listOf(theElement.itsThickness)
                for (theNode in theElement.itsSpline.itsNodes) {
                    theNumbers +=
                        listOf(
                            theNode.itsNodeLocation[0],
                            theNode.itsNodeLocation[1],
                            if (theNode.itsNodeType == SplineNodeType.corner) 1.0 else 0.0,
                        )
                }
            } else if (theElement is Fill) {
                theKind = "fill"
                theNumbers += listOf(theElement.itsFillPoint[0], theElement.itsFillPoint[1])
            } else {
                theKind = "unknown"
            }

            emitString("$key.element.$i.kind", theKind)
            emitDoubles("$key.element.$i.numbers", theNumbers)
        }
    }

    fun emitEditingSession() {

        //	The running app starts new drawings in the group 632.
        val theDocument = KaleidoPaintDocument(defaultSymmetryGroup = WallpaperGroup.wpg632)

        val theUndoManager = UndoManager()
        theDocument.itsUndoManager = theUndoManager

        var theDefaultGroup = "none"
        theDocument.itsDefaultSymmetryGroupObserver = { theDefaultGroup = it.rawValue }

        val theWidth = 1080.0
        val theHeight = 2400.0
        fun point(x: Double, y: Double): DisplayPoint {
            return DisplayPoint(x = x, y = y, viewWidth = theWidth, viewHeight = theHeight)
        }
        fun displayPoint(unitCellPoint: Double2): DisplayPoint {
            return convertExtendedUnitCellCoordinatesToDisplayCoordinates(
                unitCellPoint,
                unitCellPlacement = theDocument.itsUnitCellPlacement,
                viewWidth = theWidth,
                viewHeight = theHeight,
            )
        }

        val theStepNames = mutableListOf<String>()
        fun step(name: String, action: () -> Unit) {
            action()
            theStepNames.add(name)
            emitSessionState("session.${theStepNames.size}.$name", theDocument)
        }
        fun drag(start: DisplayPoint, motions: List<Pair<Double, Double>>) {
            theDocument.touchBegan(at = start)
            for ((dx, dy) in motions) {
                theDocument.touchMoved(to = point(start.x + dx, start.y + dy))
            }
            theDocument.touchEnded()
        }

        emitSessionState("session.0.new", theDocument)

        //	In an empty drawing there are no control handles to drag or tap.
        //	(Once a drawing has a few curves, the images of their handles'
        //	generous touch targets cover the whole screen.)
        theDocument.itsTouchMode = TouchMode.edit
        drag(point(500.0, 1000.0), listOf(Pair(1.0, 1.0), Pair(20.0, 30.0)))
        val theEmptyAnchor = theDocument.singleTapForEditing(at = point(500.0, 1000.0))
        emitInts(
            "session.tap.nothing",
            listOf(
                if (theEmptyAnchor != null) 1 else 0,
                if (theDocument.itsControlHandleHit == null) 1 else 0,
            ),
        )
        theDocument.itsTouchMode = TouchMode.draw
        emitSessionState("session.0.nothingToEdit", theDocument)

        //	--- Drawing

        step("stroke-arch") {
            val thePoints = mutableListOf(point(310.0, 1210.0))
            for (k in 1..60) {
                val x = 310.0 + 8.0 * k.toDouble()
                val y = 1210.0 + 0.25 * (k * (60 - k)).toDouble() + 1.5 * ((k * 37) % 11).toDouble()
                thePoints.add(point(x, y))
            }
            drawStroke(theDocument, "session.stroke.arch", thePoints)
        }

        step("tap-dot") {
            theDocument.singleTapForDrawing(at = point(537.0, 1493.0))
        }

        theDocument.itsBrushColor = LinearDisplayP3Color(r = 0.0, g = 0.5, b = 0.25, a = 1.0)
        theDocument.itsBrushThickness *= 2.0
        step("stroke-zigzag") {
            val thePoints = mutableListOf(point(205.0, 905.0))
            for (k in 1..80) {
                val x = 205.0 + 6.0 * k.toDouble()
                val theTooth = k % 20
                val y = 905.0 + 9.0 * (if (theTooth < 10) theTooth else 20 - theTooth).toDouble()
                thePoints.add(point(x, y))
            }
            drawStroke(theDocument, "session.stroke.zigzag", thePoints)
        }

        step("double-tap-fill") {
            theDocument.doubleTapForDrawing(at = point(123.0, 456.0))
        }

        //	A stroke so long that it runs out of valid basepoints,
        //	after which the rest of it is ignored.
        //	(It bends a little on purpose;  see Sessions.swift.)
        step("stroke-too-long") {
            val thePoints = mutableListOf(point(40.0, 300.0))
            for (k in 1..120) {
                thePoints.add(
                    point(
                        40.0 + 8.5 * k.toDouble(),
                        300.0 + 16.0 * k.toDouble() + 0.03125 * (k * k).toDouble(),
                    )
                )
            }
            drawStroke(theDocument, "session.stroke.tooLong", thePoints)
        }

        step("background-color") {
            theDocument.changeBackgroundColor(
                to = LinearDisplayP3Color(r = 0.9, g = 0.8, b = 0.1, a = 1.0)
            )
        }

        //	A stroke abandoned half way leaves nothing behind and nothing to undo.
        theDocument.touchBegan(at = point(600.0, 600.0))
        theDocument.touchMoved(to = point(640.0, 660.0))
        emitSessionState("session.cancel.before", theDocument)
        theDocument.touchCancelled()
        emitSessionState("session.cancel.after", theDocument)

        //	--- Editing

        theDocument.itsTouchMode = TouchMode.edit
        val theArch = theDocument.itsElements[0] as Curve
        val theDot = theDocument.itsElements[1] as Dot
        val theZigzag = theDocument.itsElements[2] as Curve
        val theFill = theDocument.itsElements[3] as Fill

        step("drag-dot") {
            drag(
                displayPoint(theDot.itsCenter),
                listOf(Pair(10.0, -6.0), Pair(25.0, -20.0), Pair(61.0, -47.0)),
            )
        }

        step("drag-node") {
            val theNode = theArch.itsSpline.itsNodes[2]
            drag(
                displayPoint(theNode.itsNodeLocation),
                listOf(Pair(-8.0, 12.0), Pair(-30.0, 44.0), Pair(-52.0, 90.0)),
            )
        }

        //	Drag an end node so far that the curve gets re-centred in the unit cell.
        step("drag-node-far") {
            val theNode = theZigzag.itsSpline.itsNodes[0]
            drag(
                displayPoint(theNode.itsNodeLocation),
                listOf(Pair(-100.0, 0.0), Pair(-400.0, 10.0), Pair(-800.0, 20.0)),
            )
        }

        step("drag-fill") {
            drag(displayPoint(theFill.itsFillPoint), listOf(Pair(3.0, 3.0), Pair(40.0, 77.0)))
        }

        //	A drag abandoned half way puts the handle back.
        theDocument.touchBegan(at = displayPoint(theDot.itsCenter))
        theDocument.touchMoved(to = point(900.0, 900.0))
        emitSessionState("session.editCancel.before", theDocument)
        theDocument.touchCancelled()
        emitSessionState("session.editCancel.after", theDocument)

        //	A tap on a node selects it and says where to put the Editor.
        val theTappedNode = theArch.itsSpline.itsNodes[1]
        val theTapPoint = displayPoint(theTappedNode.itsNodeLocation)
        val theEditorAnchor = theDocument.singleTapForEditing(at = theTapPoint)
        emitDoubles(
            "session.tap.node.anchor",
            if (theEditorAnchor != null) listOf(theEditorAnchor[0], theEditorAnchor[1])
            else listOf(),
        )
        emitInts(
            "session.tap.node.hit",
            listOf(
                if (theDocument.itsControlHandleHit?.itsElement === theArch) 1 else 0,
                if (theDocument.itsControlHandleHit?.itsNode === theTappedNode) 1 else 0,
            ),
        )

        step("node-type") {
            theDocument.changeSplineNodeType(
                curve = theArch,
                node = theTappedNode,
                from = theTappedNode.itsNodeType,
                to = SplineNodeType.corner,
            )
        }

        step("split-node") {
            val theNode = theArch.itsSpline.itsNodes[2]
            val (theNodeA, theNodeB) = theArch.itsSpline.splitNode(theNode)
            theDocument.splitSplineNode(
                curve = theArch,
                oldNode = theNode,
                newNodeA = theNodeA,
                newNodeB = theNodeB,
            )
        }

        step("delete-node") {
            theDocument.deleteSplineNode(curve = theZigzag, node = theZigzag.itsSpline.itsNodes[1])
        }

        step("color") {
            theDocument.changeColor(
                of = listOf(theArch, theDot),
                to = LinearDisplayP3Color(r = 0.1, g = 0.2, b = 0.9, a = 1.0),
            )
        }

        step("thickness") {
            theDocument.changeThickness(
                of = listOf(theArch, theZigzag),
                from = theArch.itsThickness,
                to = 0.02,
            )
        }

        step("element-array") {
            //	Delete the dot and bring the fill to the front.
            val theOldArray = theDocument.itsElements.toList()
            val theNewArray =
                theOldArray.filter { it !== theDot && it !== theFill } + listOf(theFill)
            theDocument.changeElementArray(from = theOldArray, to = theNewArray)
        }

        step("legacy-thicknesses") {
            val theOldThicknesses =
                theDocument.itsElements.map { (it as? Brushstroke)?.itsThickness }
            val theNewThicknesses = theOldThicknesses.map { if (it != null) 0.5 * it else null }
            theDocument.changeLegacyDrawingBrushstrokeThicknesses(
                from = theOldThicknesses,
                to = theNewThicknesses,
            )
        }

        step("nothing") {
            theDocument.changeNothing()
        }

        //	--- The unit cell

        step("realign") {
            val theOldPlacement = theDocument.itsUnitCellPlacement
            val theNewPlacement = theOldPlacement.copy()
            theNewPlacement.transform(
                using =
                    similarity(
                        cosθ = gCos003,
                        sinθ = gSin003,
                        scale = 1.25,
                        translation = Double2(0.3, -0.2),
                    )
            )
            theNewPlacement.snapToViewAlignment()
            theNewPlacement.centerTheUnitCell()
            theDocument.changeUnitCellPlacement(
                oldPlacement = theOldPlacement,
                newPlacement = theNewPlacement,
            )
        }

        val theGroupsAndShapes: List<Pair<WallpaperGroup, UnitCellShape>> =
            listOf(
                Pair(
                    WallpaperGroup.wpg2222,
                    UnitCellShape(aspectRatio = 1.5, shear = 0.25),
                ), //	fully flexible
                Pair(
                    WallpaperGroup.wpgS2222,
                    UnitCellShape(aspectRatio = 0.5, shear = 0.0),
                ), //	rectangular
                Pair(
                    WallpaperGroup.wpg2S22,
                    UnitCellShape(aspectRatio = 2.0, shear = 0.0),
                ), //	rhombic
                Pair(
                    WallpaperGroup.wpgS442,
                    UnitCellShape(aspectRatio = 3.0, shear = 1.0),
                ), //	rigid:  the shape is ignored
            )
        for ((theGroup, theShape) in theGroupsAndShapes) {
            step("group-${theGroup.IUCName}") {
                theDocument.changeWallpaperGroup(
                    to = theGroup,
                    placement = UnitCellPlacement(defaultForWallpaperGroup = theGroup),
                )
            }
            step("shape-${theGroup.IUCName}") {
                theDocument.changeUnitCellShape(
                    oldShape = theDocument.getUnitCellShape(),
                    newShape = theShape,
                )
            }
        }
        emitString("session.defaultGroup", theDefaultGroup)

        //	--- A locked drawing ignores every touch

        theDocument.itsContentIsLocked = true
        theDocument.itsTouchMode = TouchMode.draw
        theDocument.touchBegan(at = point(300.0, 300.0))
        theDocument.touchMoved(to = point(400.0, 400.0))
        theDocument.touchEnded()
        theDocument.singleTapForDrawing(at = point(500.0, 500.0))
        theDocument.doubleTapForDrawing(at = point(500.0, 500.0))
        emitSessionState("session.locked", theDocument)
        theDocument.itsContentIsLocked = false

        //	--- Undo everything, redo everything

        val theStepCount = theStepNames.size
        emitInt("session.stepCount", theStepCount)
        for (i in (0 until theStepCount).reversed()) {
            theUndoManager.undo()
            emitSessionState("session.undo.$i", theDocument)
        }
        theUndoManager.undo() // 	nothing left to undo
        emitSessionState("session.undo.extra", theDocument)

        for (i in 0 until theStepCount) {
            theUndoManager.redo()
            emitSessionState("session.redo.$i", theDocument)
        }
        theUndoManager.redo() // 	nothing left to redo
        emitSessionState("session.redo.extra", theDocument)

        //	--- Doing something new forgets what could have been redone

        for (i in 0 until 5) {
            theUndoManager.undo()
        }
        emitSessionState("session.branch.before", theDocument)
        theDocument.singleTapForDrawing(at = point(700.0, 1700.0))
        emitSessionState("session.branch.after", theDocument)

        itsSessionDocument = theDocument
    }

    fun emitTileExports() {
        for ((g, group) in WallpaperGroup.entries.withIndex()) for (variant in 0..1) {
            for ((format, size) in listOf(1080 to 1781, 801 to 599).withIndex()) {
                val document = KaleidoPaintDocument()
                document.itsWallpaperGroup = group
                document.itsUnitCellPlacement = UnitCellPlacement(group)
                if (variant == 1) {
                    when (group.torusGroup.itsRigidity) {
                        Rigidity.fullyFlexible -> document.setUnitCellShape(UnitCellShape(1.7, 0.6))
                        Rigidity.rectangular -> document.setUnitCellShape(UnitCellShape(1.6, 0.0))
                        Rigidity.rhombic -> document.setUnitCellShape(UnitCellShape(0.7, 0.0))
                        Rigidity.rigid -> Unit
                    }
                    document.itsUnitCellPlacement.transform(
                        Double3x2(Double2(.9, .2), Double2(-.2, .9), Double2(.13, -.21))
                    )
                }
                val key = "session.tile.$g.$variant.$format"
                fun placement(suffix: String) {
                    val p = document.itsUnitCellPlacement
                    emitDoubles(
                        key + suffix,
                        listOf(
                            p.itsCorner.x,
                            p.itsCorner.y,
                            p.itsTranslations[0].x,
                            p.itsTranslations[0].y,
                            p.itsTranslations[1].x,
                            p.itsTranslations[1].y,
                        ),
                    )
                }
                val (w, h) = document.prepareModelToExportTileableRectangle(size.first, size.second)
                emitInts(key + ".size", listOf(w, h))
                placement(".placement")
                document.restoreModelAfterExportingTileableRectangle()
                placement(".restored")
            }
        }
    }
}
