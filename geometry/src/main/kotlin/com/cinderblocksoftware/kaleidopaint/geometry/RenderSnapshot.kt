// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint.geometry

/** Value keys for pixels, separate from page placement and background. */
data class RenderContext(
    val group: WallpaperGroup,
    val metric: Double2x2,
    val symmetryColors: Boolean,
)

sealed interface ElementRenderState

data class DotRenderState(
    val color: LinearDisplayP3Color,
    val thickness: Double,
    val center: Double2,
) : ElementRenderState

data class FillRenderState(
    val color: LinearDisplayP3Color,
    val point: Double2,
    val mask: FillMask?,
) : ElementRenderState

data class NodeRenderState(
    val location: Double2,
    val type: SplineNodeType,
    val coefficients: List<Double2>,
)

data class CurveRenderState(
    val color: LinearDisplayP3Color,
    val thickness: Double,
    val nodes: List<NodeRenderState>,
) : ElementRenderState

data class HandleRenderState(
    val fillRadius: Double?,
    val selectedElement: Int,
    val selectedNode: Int?,
)

data class RenderState(
    val context: RenderContext,
    val elements: List<ElementRenderState>,
    val progress: ElementRenderState?,
    val guides: Boolean,
    val handles: HandleRenderState?,
)

/** GL-owned model copy. Never render or encode the live UI document under its monitor. */
class RenderSnapshot
private constructor(
    val model: KaleidoPaintDocument,
    private val originals: List<DrawingElement>,
    private val originalState: RenderState,
    private val originalMasks: List<FillMask?>,
    val captureWaitNs: Long,
    val captureHoldNs: Long,
) {
    var completedState = originalState
        private set

    /** Only fill-mask caches may be changed by GL on this private model. */
    fun complete() {
        completedState =
            originalState.copy(
                elements =
                    originalState.elements.mapIndexed { i, key ->
                        if (key is FillRenderState)
                            key.copy(mask = (model.itsElements[i] as Fill).itsCachedRLERunsBuffer)
                        else key
                    }
            )
    }

    /** Publish all eligible caches atomically, before our own publications alter prefix keys. */
    fun publishCaches(source: KaleidoPaintDocument) =
        synchronized(source) {
            // Most stroke frames have no new fill cache to publish. Avoid rescanning them.
            if (
                originals.indices.none { i ->
                    originals[i] is Fill &&
                        (model.itsElements[i] as Fill).itsCachedRLERunsBuffer !== originalMasks[i]
                }
            )
                return@synchronized
            val current = state(source, false)
            if (current.context != originalState.context) return@synchronized
            var prefix = 0
            while (
                prefix < originals.size &&
                    prefix < source.itsElements.size &&
                    source.itsElements[prefix] === originals[prefix] &&
                    current.elements[prefix] == originalState.elements[prefix]
            ) prefix++
            for (i in 0 until prefix) {
                val original = originals[i] as? Fill ?: continue
                val computed = (model.itsElements[i] as Fill).itsCachedRLERunsBuffer
                if (computed != null && original.itsCachedRLERunsBuffer === originalMasks[i])
                    original.itsCachedRLERunsBuffer = computed
            }
        }

    companion object {
        fun capture(
            source: KaleidoPaintDocument,
            previous: RenderSnapshot? = null,
            exporting: Boolean = false,
        ): RenderSnapshot {
            val waiting = System.nanoTime()
            return synchronized(source) {
                val acquired = System.nanoTime()
                val key = state(source, exporting)
                val originals = source.itsElements.toList()
                val masks = originals.map { (it as? Fill)?.itsCachedRLERunsBuffer }
                val model =
                    if (previous != null && previous.completedState == key) previous.model
                    else copyModel(source, key, previous)
                // These values may change without changing any unit-cell pixels.
                model.itsUnitCellPlacement = source.itsUnitCellPlacement.copy()
                model.itsBackgroundColor = source.itsBackgroundColor
                RenderSnapshot(
                    model,
                    originals,
                    key,
                    masks,
                    acquired - waiting,
                    System.nanoTime() - acquired,
                )
            }
        }

        fun state(document: KaleidoPaintDocument, exporting: Boolean = false): RenderState {
            val hit = document.itsControlHandleHit
            val handles =
                if (document.itsTouchMode == TouchMode.edit && !exporting)
                    HandleRenderState(
                        if (document.itsElements.any { it is Fill }) document.fillMarkerRadius()
                        else null,
                        document.itsElements.indexOf(hit?.itsElement),
                        (hit?.itsElement as? Curve)?.itsSpline?.itsNodes?.indexOf(hit.itsNode),
                    )
                else null
            return RenderState(
                RenderContext(
                    document.itsWallpaperGroup,
                    document.itsUnitCellPlacement.itsMetricOfDet1,
                    document.itsColorBySymmetryFlag,
                ),
                document.itsElements.map(::elementState),
                document.itsCurveInProgress?.let(::elementState),
                document.itsShowSingularitiesFlag,
                handles,
            )
        }

        private fun elementState(element: DrawingElement): ElementRenderState =
            when (element) {
                is Dot -> DotRenderState(element.itsColor, element.itsThickness, element.itsCenter)
                is Fill ->
                    FillRenderState(
                        element.itsColor,
                        element.itsFillPoint,
                        element.itsCachedRLERunsBuffer,
                    )
                is Curve ->
                    CurveRenderState(
                        element.itsColor,
                        element.itsThickness,
                        element.itsSpline.itsNodes.map { node ->
                            NodeRenderState(
                                node.itsNodeLocation,
                                node.itsNodeType,
                                (0..3).map { node.ξ[it] },
                            )
                        },
                    )
                else -> error("Unsupported drawing element")
            }

        private fun copyModel(
            source: KaleidoPaintDocument,
            key: RenderState,
            previous: RenderSnapshot?,
        ): KaleidoPaintDocument {
            fun copy(element: DrawingElement): DrawingElement =
                when (element) {
                    is Dot -> Dot(element.itsColor, element.itsCenter, element.itsThickness)
                    is Fill ->
                        Fill(element.itsColor, element.itsFillPoint).apply {
                            itsCachedRLERunsBuffer = element.itsCachedRLERunsBuffer
                        }
                    is Curve ->
                        Curve(element.itsColor, element.itsThickness).apply {
                            itsSpline.itsNodes =
                                element.itsSpline.itsNodes
                                    .map { node ->
                                        SplineNode(node.itsNodeLocation, node.itsNodeType).apply {
                                            ξ = node.ξ.copy()
                                        }
                                    }
                                    .toMutableList()
                        }
                    else -> error("Unsupported drawing element")
                }
            return KaleidoPaintDocument(source.itsWallpaperGroup).apply {
                itsUnitCellPlacement = source.itsUnitCellPlacement.copy()
                itsBackgroundColor = source.itsBackgroundColor
                itsBrushColor = source.itsBrushColor
                itsFillColor = source.itsFillColor
                itsBrushThickness = source.itsBrushThickness
                itsSmoothingTolerance = source.itsSmoothingTolerance
                itsContentIsLocked = source.itsContentIsLocked
                itsElements =
                    source.itsElements
                        .mapIndexed { index, element ->
                            // Reuse only GL-owned copies with the same source identity AND value.
                            // Later UI edits still clone the changed element, keeping snapshots
                            // isolated.
                            if (
                                previous != null &&
                                    index < previous.originals.size &&
                                    previous.originals[index] === element &&
                                    previous.completedState.elements[index] == key.elements[index]
                            )
                                previous.model.itsElements[index]
                            else copy(element)
                        }
                        .toMutableList()
                itsCurveInProgress = source.itsCurveInProgress?.let { copy(it) as Curve }
                itsShowSingularitiesFlag = source.itsShowSingularitiesFlag
                itsColorBySymmetryFlag = source.itsColorBySymmetryFlag
                itsTouchMode = source.itsTouchMode
                source.itsControlHandleHit?.let { hit ->
                    val index = source.itsElements.indexOf(hit.itsElement)
                    if (index >= 0) {
                        val element = itsElements[index]
                        val nodeIndex =
                            (hit.itsElement as? Curve)?.itsSpline?.itsNodes?.indexOf(hit.itsNode)
                                ?: -1
                        val node =
                            if (nodeIndex >= 0) (element as Curve).itsSpline.itsNodes[nodeIndex]
                            else null
                        itsControlHandleHit =
                            ControlHandleHit(
                                element,
                                node,
                                hit.itsHomeCenter,
                                hit.itsHitCenter,
                                hit.itsSymmetry,
                                hit.itsTapError,
                            )
                    }
                }
            }
        }
    }
}
