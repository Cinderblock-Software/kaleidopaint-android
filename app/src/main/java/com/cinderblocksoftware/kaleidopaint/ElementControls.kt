// Ported from KaleidoPaintContentView.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cinderblocksoftware.kaleidopaint.geometry.*
import kotlin.math.*

/** Original EditorPanel: color, thickness, node actions and deletion are separate white cards. */
@Composable
fun ElementControls(
    document: KaleidoPaintDocument,
    revision: Int,
    hit: ControlHandleHit,
    onDismiss: () -> Unit,
    onColor: (LinearDisplayP3Color, Boolean) -> Unit,
    onWidth: (Double, Boolean, Boolean) -> Unit,
    onDelete: (Boolean) -> Unit,
    onNodeType: () -> Unit,
    onDeleteNode: () -> Unit,
    onSplitNode: () -> Unit,
) {
    // Subscribe to mutable model changes, including node-style actions.
    @Suppress("UNUSED_VARIABLE") val modelRevision = revision
    val element = hit.itsElement
    val curve = element as? Curve
    var currentColor by remember(element) { mutableStateOf(element.itsColor) }
    var draftColor by remember(element) { mutableStateOf(element.itsColor) }
    var picking by remember { mutableStateOf(false) }
    var colorPrevious by remember { mutableStateOf(false) }
    var widthPrevious by remember { mutableStateOf(false) }
    var matchColor by remember { mutableStateOf(false) }
    var matchWidth by remember { mutableStateOf(false) }
    var matchingDelete by remember { mutableStateOf(false) }
    var width by
        remember(element) {
            mutableDoubleStateOf((element as? Brushstroke)?.itsThickness ?: gDefaultThickness)
        }
    val colorLabel =
        stringResource(
            when (element) {
                is Dot -> R.string.new_dot_color
                is Fill -> R.string.new_fill_color
                else -> R.string.new_line_color
            }
        )
    val widthLabel =
        stringResource(if (element is Dot) R.string.dot_size else R.string.line_thickness)
    val deleteLabel =
        stringResource(
            when (element) {
                is Dot -> R.string.delete_dot
                is Fill -> R.string.delete_fill
                else -> R.string.delete_line
            }
        )
    OriginalPanelSheet(stringResource(R.string.edit_element), onDismiss) {
        Column(
            Modifier.fillMaxWidth()
                .drawBehind {
                    // Upstream extends the gray underlay by 128 points to cover its popover arrow.
                    drawRect(
                        Color(0xFFDFDFDF),
                        Offset(0f, -64.dp.toPx()),
                        Size(size.width, size.height + 128.dp.toPx()),
                    )
                }
                .verticalScroll(rememberScrollState())
                .padding(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            EditorCard {
                OriginalModes(colorLabel, colorPrevious) { colorPrevious = it }
                if (colorPrevious)
                    ExistingColors(
                        document.itsElements.map { it.itsColor } + document.itsBackgroundColor,
                        draftColor,
                    ) {
                        draftColor = it
                    }
                else
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(colorLabel, Modifier.weight(1f))
                        ColorWell(draftColor, colorLabel) { picking = true }
                    }
                Text(
                    stringResource(R.string.apply),
                    color = if (draftColor == currentColor) Color.LightGray else EditorBlue,
                    style = MaterialTheme.typography.titleLarge.copy(fontSize = 20.sp),
                    modifier =
                        Modifier.clickable(enabled = draftColor != currentColor) {
                                onColor(draftColor, matchColor)
                                currentColor = element.itsColor
                            }
                            .padding(vertical = 4.dp),
                )
                Row(Modifier.width(128.dp).height(32.dp).clip(RoundedCornerShape(4.dp))) {
                    for (color in listOf(draftColor, currentColor)) Box(
                        Modifier.weight(1f).fillMaxHeight().background(color.toComposeColor())
                    )
                }
                OriginalCheck(stringResource(R.string.match_color), matchColor) { matchColor = it }
            }
            if (element is Brushstroke)
                EditorCard {
                    OriginalModes(widthLabel, widthPrevious) { widthPrevious = it }
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 54.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(widthLabel)
                        val sample = (16 * width / gDefaultThickness).toFloat().coerceIn(2f, 90f)
                        Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                            Box(
                                Modifier.size(if (element is Dot) sample.dp else 112.dp, sample.dp)
                                    .background(
                                        currentColor.toComposeColor(),
                                        RoundedCornerShape(50),
                                    )
                            )
                        }
                    }
                    // Work with the underlying thickness values as much as possible,
                    // so that in-use thicknesses may get reused exactly, without
                    // numerical errors from a logarithm round trip.
                    val used =
                        document.itsElements
                            .filterIsInstance<Brushstroke>()
                            .map { it.itsThickness }
                            .distinct()
                            .sorted()
                    val factor = log2(width / gDefaultThickness).toFloat()
                    OriginalSlider(
                        factor,
                        -2.8f..2f,
                        widthLabel,
                        Modifier.width(256.dp),
                        markers =
                            if (widthPrevious) used.map { log2(it / gDefaultThickness).toFloat() }
                            else emptyList(),
                        onChange = { v ->
                            width =
                                if (widthPrevious && used.isNotEmpty())
                                    used.minBy { abs(log2(it / gDefaultThickness) - v) }
                                else gDefaultThickness * 2.0.pow(v.toDouble())
                            onWidth(width, matchWidth, false)
                        },
                        onFinished = { onWidth(width, matchWidth, true) },
                    )
                    OriginalCheck(stringResource(R.string.match_width), matchWidth) {
                        matchWidth = it
                    }
                }
            if (curve != null && hit.itsNode != null)
                EditorCard {
                    val node = hit.itsNode!!
                    if (
                        node !== curve.itsSpline.itsNodes.first() &&
                            node !== curve.itsSpline.itsNodes.last()
                    ) {
                        Row(
                            Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(stringResource(R.string.point_style))
                            TextButton(onClick = onNodeType) {
                                Text(
                                    stringResource(
                                        if (node.itsNodeType == SplineNodeType.corner)
                                            R.string.make_smooth
                                        else R.string.make_corner
                                    )
                                )
                            }
                        }
                    }
                    if (curve.itsSpline.itsNodes.size > 2)
                        TextButton(onClick = onDeleteNode) {
                            Text(stringResource(R.string.delete_point))
                        }
                    TextButton(onClick = onSplitNode) { Text(stringResource(R.string.split_point)) }
                }
            EditorCard {
                Row(
                    Modifier.fillMaxWidth()
                        .clickable { onDelete(matchingDelete) }
                        .padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        deleteLabel,
                        Modifier.weight(1f),
                        color = Color(0xFFFF3B30),
                        style = MaterialTheme.typography.titleLarge.copy(fontSize = 20.sp),
                    )
                    EditorGlyph("trash", Color(0xFFFF3B30))
                }
                OriginalCheck(stringResource(R.string.delete_matching_color), matchingDelete) {
                    matchingDelete = it
                }
            }
        }
    }
    // Keep the editor sheet alive underneath the picker, like the original.
    if (picking)
        ColorControls(
            colorLabel,
            draftColor,
            onDismiss = { picking = false },
            onApply = { color ->
                draftColor = color
                picking = false
            },
        )
}

@Composable
private fun EditorCard(content: @Composable ColumnScope.() -> Unit) {
    Surface(
        Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = Color.White,
        contentColor = Color.Black,
    ) {
        Column(
            Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
            content = content,
        )
    }
}
