// Ported from KaleidoPaintContentView.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.*
import androidx.compose.ui.window.*
import com.cinderblocksoftware.kaleidopaint.geometry.*

/** The original phone's near-full-height white sheet, with no added title or action bar. */
@Composable
internal fun OriginalPanelSheet(
    label: String,
    onDismiss: () -> Unit,
    content: @Composable BoxScope.() -> Unit,
) {
    Dialog(
        onDismissRequest = onDismiss,
        properties =
            DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = true),
    ) {
        Box(Modifier.fillMaxSize().padding(top = 20.dp), contentAlignment = Alignment.Center) {
            val latestDismiss by rememberUpdatedState(onDismiss)
            Surface(
                Modifier.fillMaxSize()
                    .semantics {
                        paneTitle = label
                        dismiss {
                            latestDismiss()
                            true
                        }
                    }
                    .pointerInput(Unit) {
                        var distance = 0f
                        detectVerticalDragGestures(
                            onDragStart = { distance = 0f },
                            onVerticalDrag = { _, dy -> distance += dy },
                            onDragEnd = { if (distance > 80.dp.toPx()) latestDismiss() },
                        )
                    },
                shape = RoundedCornerShape(28.dp),
                color = Color.White,
                contentColor = Color.Black,
            ) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center, content = content)
            }
        }
    }
}

/** Thin blue/gray track and round white thumb, like the original UIKit slider. */
@Composable
internal fun OriginalSlider(
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    label: String,
    modifier: Modifier = Modifier,
    markers: List<Float> = emptyList(),
    onChange: (Float) -> Unit,
    onFinished: () -> Unit = {},
) {
    val change by rememberUpdatedState(onChange)
    val finish by rememberUpdatedState(onFinished)
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    fun select(x: Float, width: Int, margin: Float) {
        val t = ((x - margin) / (width - 2 * margin).coerceAtLeast(1f)).coerceIn(0f, 1f)
        change(range.start + (if (rtl) 1 - t else t) * (range.endInclusive - range.start))
    }
    Canvas(
        modifier
            .height(44.dp)
            .semantics {
                contentDescription = label
                progressBarRangeInfo = ProgressBarRangeInfo(value.coerceIn(range), range)
                setProgress {
                    change(it.coerceIn(range))
                    finish()
                    true
                }
            }
            .pointerInput(range, rtl) {
                detectTapGestures(
                    onTap = {
                        select(it.x, size.width, 3.dp.toPx())
                        finish()
                    }
                )
            }
            .pointerInput(range, rtl) {
                detectDragGestures(
                    onDragStart = { select(it.x, size.width, 3.dp.toPx()) },
                    onDragEnd = { finish() },
                    onDragCancel = { finish() },
                ) { event, _ ->
                    event.consume()
                    select(event.position.x, size.width, 3.dp.toPx())
                }
            }
    ) {
        val margin = 3.dp.toPx()
        val y = size.height / 2
        val t = ((value - range.start) / (range.endInclusive - range.start)).coerceIn(0f, 1f)
        val x = margin + (size.width - 2 * margin) * (if (rtl) 1 - t else t)
        drawLine(Color(0xFFE5E5EA), Offset(margin, y), Offset(size.width - margin, y), 6.dp.toPx())
        drawLine(
            EditorBlue,
            Offset(if (rtl) size.width - margin else margin, y),
            Offset(x, y),
            6.dp.toPx(),
        )
        for (marker in markers) {
            val m = ((marker - range.start) / (range.endInclusive - range.start)).coerceIn(0f, 1f)
            val mx = margin + (size.width - 2 * margin) * (if (rtl) 1 - m else m)
            drawLine(
                Color(0xFF00BF40),
                Offset(mx, y - 7.dp.toPx()),
                Offset(mx, y + 7.dp.toPx()),
                2.dp.toPx(),
            )
        }
        drawRoundRect(
            Color(0x18000000),
            Offset(x - 19.dp.toPx(), y - 11.dp.toPx()),
            androidx.compose.ui.geometry.Size(38.dp.toPx(), 26.dp.toPx()),
            androidx.compose.ui.geometry.CornerRadius(13.dp.toPx()),
        )
        drawRoundRect(
            Color.White,
            Offset(x - 18.dp.toPx(), y - 12.dp.toPx()),
            androidx.compose.ui.geometry.Size(36.dp.toPx(), 24.dp.toPx()),
            androidx.compose.ui.geometry.CornerRadius(12.dp.toPx()),
        )
    }
}

@Composable
internal fun OriginalCheck(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth()
            .heightIn(min = 28.dp)
            .toggleable(checked, role = Role.Checkbox, onValueChange = onChange),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            label,
            Modifier.weight(1f),
            style = MaterialTheme.typography.bodySmall,
            color = Color.Black,
        )
        Box(
            Modifier.padding(start = 8.dp)
                .size(18.dp)
                .border(1.5.dp, EditorBlue, RoundedCornerShape(2.dp)),
            contentAlignment = Alignment.Center,
        ) {
            if (checked) Text("✓", color = EditorBlue, style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
internal fun OriginalModes(label: String, previous: Boolean, onPrevious: (Boolean) -> Unit) {
    Row(Modifier.background(Color(0xFFEEEEF0), RoundedCornerShape(16.dp)).padding(3.dp)) {
        for (old in listOf(false, true)) {
            val description =
                label +
                    ": " +
                    stringResource(if (old) R.string.used_values else R.string.new_values)
            Box(
                Modifier.size(38.dp, 28.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(if (previous == old) Color.White else Color.Transparent)
                    .clickable(role = Role.Tab) { onPrevious(old) }
                    .semantics {
                        contentDescription = description
                        selected = previous == old
                    },
                contentAlignment = Alignment.Center,
            ) {
                EditorGlyph(if (old) "history" else "sun", Color.Black, Modifier.size(24.dp))
            }
        }
    }
}

@Composable
internal fun ExistingColors(
    colors: List<LinearDisplayP3Color>,
    selected: LinearDisplayP3Color,
    onColor: (LinearDisplayP3Color) -> Unit,
) {
    val unique = colors.distinct()
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        unique
            .chunked(
                if (androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp >= 600) 6
                else 5
            )
            .forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    row.forEach { color ->
                        val hex = toSRGBHex(color)
                        val label = stringResource(R.string.color_hex_format, hex)
                        Box(
                            Modifier.size(32.dp)
                                .background(
                                    Color(android.graphics.Color.parseColor("#$hex")),
                                    RoundedCornerShape(4.dp),
                                )
                                .border(
                                    if (color == selected) 2.dp else .5.dp,
                                    if (color == selected) EditorBlue else Color.LightGray,
                                    RoundedCornerShape(4.dp),
                                )
                                .clickable(role = Role.Button) { onColor(color) }
                                .semantics {
                                    contentDescription = label
                                    this.selected = color == selected
                                }
                        )
                    }
                }
            }
    }
}
