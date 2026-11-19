// Ported from KaleidoPaintContentView.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import android.text.BidiFormatter
import android.text.TextDirectionHeuristics
import android.view.View
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.*
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.*
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.*
import com.cinderblocksoftware.kaleidopaint.geometry.*
import kotlin.math.*

internal val EditorBlue = Color(0xFF0088FF)

/** Original white islands, blue controls and 16-point rounding, over the full canvas. */
@Composable
internal fun ChromeFrame(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Surface(
        modifier =
            modifier.pointerInput(Unit) {
                detectTapGestures(onTap = {})
            },
        color = Color.White,
        contentColor = Color.Black,
        shape = RoundedCornerShape(16.dp),
        border = BorderStroke(1.dp, Color(0xFFABABAF)),
    ) {
        content()
    }
}

@Composable
internal fun GlyphButton(
    glyph: String,
    label: String,
    enabled: Boolean = true,
    selected: Boolean = false,
    tint: Color = EditorBlue,
    onClick: () -> Unit,
) {
    Box(
        Modifier.size(44.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(if (selected) Color(0xFFE0E0E0) else Color.Transparent)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics {
                contentDescription = label
                if (selected) this.selected = true
            },
        contentAlignment = Alignment.Center,
    ) {
        val ink = if (enabled) tint else Color(0xFFC6C6C8)
        if (glyph == "fill")
            Icon(
                painterResource(R.drawable.editor_paint_bucket),
                null,
                tint = ink,
                modifier = Modifier.size(29.dp),
            )
        else EditorGlyph(glyph, ink)
    }
}

/** Independent vector drawings for standard actions; symmetry glyphs use original artwork. */
@Composable
internal fun EditorGlyph(
    kind: String,
    color: Color = EditorBlue,
    modifier: Modifier = Modifier.size(29.dp),
) {
    val mirrorBack =
        androidx.compose.ui.platform.LocalLayoutDirection.current == LayoutDirection.Rtl &&
            kind == "back"
    Canvas(modifier) {
        withTransform({
            scale(size.width / 24, size.height / 24, pivot = Offset.Zero)
            if (mirrorBack) scale(-1f, 1f, Offset(12f, 12f))
        }) {
            val stroke = Stroke(1.9f, cap = StrokeCap.Round, join = StrokeJoin.Round)
            fun path(vararg xy: Float) {
                val p = Path()
                p.moveTo(xy[0], xy[1])
                for (i in 2 until xy.size step 2) p.lineTo(xy[i], xy[i + 1])
                drawPath(p, color, style = stroke)
            }
            when (kind) {
                "back" -> path(15f, 4f, 7f, 12f, 15f, 20f)
                "chevron" -> path(8f, 10f, 12f, 14f, 16f, 10f)
                "help" -> {
                    drawCircle(color, 10f, Offset(12f, 12f), style = stroke)
                    val p =
                        Path().apply {
                            moveTo(9f, 8f)
                            cubicTo(10f, 4f, 17f, 6f, 15f, 10f)
                            cubicTo(14f, 12f, 12f, 11f, 12f, 15f)
                        }
                    drawPath(p, color, style = stroke)
                    drawCircle(color, 1f, Offset(12f, 18f))
                }
                "undo",
                "redo" -> {
                    drawCircle(color, 10f, Offset(12f, 12f), style = stroke)
                    withTransform({ if (kind == "redo") scale(-1f, 1f, Offset(12f, 12f)) }) {
                        path(11f, 6f, 6f, 10f, 11f, 14f)
                        val p =
                            Path().apply {
                                moveTo(7f, 10f)
                                cubicTo(16f, 8f, 19f, 15f, 14f, 18f)
                            }
                        drawPath(p, color, style = stroke)
                    }
                }
                "lock",
                "unlock" -> {
                    drawRoundRect(
                        color,
                        Offset(4f, 11f),
                        Size(15f, 11f),
                        androidx.compose.ui.geometry.CornerRadius(2f),
                    )
                    val p =
                        Path().apply {
                            moveTo(8f, 11f)
                            lineTo(8f, 7f)
                            cubicTo(8f, 0f, 19f, 0f, 19f, 7f)
                            if (kind == "lock") lineTo(19f, 11f)
                        }
                    drawPath(p, color, style = stroke)
                }
                "brush" -> {
                    path(8f, 15f, 18f, 3f, 22f, 2f, 21f, 6f, 11f, 18f, 8f, 15f)
                    val p =
                        Path().apply {
                            moveTo(8f, 15f)
                            cubicTo(1f, 14f, 6f, 20f, 2f, 22f)
                            cubicTo(9f, 23f, 13f, 19f, 8f, 15f)
                        }
                    drawPath(p, color, style = stroke)
                }
                "fill" -> {
                    path(6f, 3f, 16f, 13f, 8f, 21f, 0f, 13f, 10f, 3f)
                    path(2f, 12f, 15f, 12f)
                    val p =
                        Path().apply {
                            moveTo(20f, 13f)
                            cubicTo(17f, 17f, 16f, 21f, 20f, 22f)
                            cubicTo(25f, 21f, 22f, 16f, 20f, 13f)
                        }
                    drawPath(p, color, style = stroke)
                }
                "width" -> {
                    path(3f, 5f, 21f, 5f)
                    drawRect(color, Offset(3f, 10f), Size(18f, 3f))
                    drawRect(color, Offset(3f, 17f), Size(18f, 6f))
                }
                "smoothing" -> {
                    val p =
                        Path().apply {
                            moveTo(2f, 18f)
                            cubicTo(26f, -8f, 21f, -1f, 6f, 17f)
                            cubicTo(-1f, 27f, 20f, 2f, 18f, 16f)
                            cubicTo(17f, 27f, 23f, 16f, 23f, 16f)
                        }
                    drawPath(p, color, style = stroke)
                }
                "background" ->
                    drawRoundRect(
                        color,
                        Offset(3f, 3f),
                        Size(18f, 18f),
                        androidx.compose.ui.geometry.CornerRadius(3f),
                        style = Stroke(1f),
                    )
                "share" -> {
                    path(6f, 8f, 3f, 8f, 3f, 22f, 21f, 22f, 21f, 8f, 18f, 8f)
                    path(12f, 16f, 12f, 1f)
                    path(7f, 6f, 12f, 1f, 17f, 6f)
                }
                "sun" -> {
                    drawCircle(color, 5f, Offset(12f, 12f), style = stroke)
                    for (i in 0..7) {
                        val a = i * kotlin.math.PI / 4
                        path(
                            (12 + 8 * cos(a)).toFloat(),
                            (12 + 8 * sin(a)).toFloat(),
                            (12 + 11 * cos(a)).toFloat(),
                            (12 + 11 * sin(a)).toFloat(),
                        )
                    }
                }
                "history" -> {
                    drawArc(
                        color,
                        -150f,
                        300f,
                        false,
                        Offset(3f, 3f),
                        Size(18f, 18f),
                        style = stroke,
                    )
                    path(2f, 4f, 2f, 10f, 7f, 10f)
                    path(12f, 6f, 12f, 12f, 16f, 15f)
                }
                "trash" -> {
                    path(5f, 7f, 6f, 22f, 18f, 22f, 19f, 7f)
                    path(3f, 5f, 21f, 5f)
                    path(8f, 5f, 8f, 2f, 16f, 2f, 16f, 5f)
                    path(10f, 9f, 10f, 18f)
                    path(14f, 9f, 14f, 18f)
                }
                "close" -> {
                    path(5f, 5f, 19f, 19f)
                    path(19f, 5f, 5f, 19f)
                }
            }
        }
    }
}

@Composable
internal fun FloatingEditorChrome(
    document: KaleidoPaintDocument,
    revision: Int,
    undo: Boolean,
    redo: Boolean,
    filling: Boolean,
    onAction: (EditorAction) -> Unit,
    onColor: (ColorTarget) -> Unit,
    onPaletteColor: (ColorTarget, LinearDisplayP3Color) -> Unit,
    onGroup: (WallpaperGroup) -> Unit,
    onWidth: (Double) -> Unit,
    onSmoothing: (Double) -> Unit,
    onFile: (FileAction) -> Unit,
    maximumExportSize: Int,
    onExport: (ExportSettings, Boolean) -> Unit,
    onPreview: (ExportSettings, (Result<ByteArray>) -> Unit) -> Unit,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val exportPreferences = remember {
        context.getSharedPreferences("editor-export", android.content.Context.MODE_PRIVATE)
    }
    var exportSettings by remember {
        mutableStateOf(
            ExportSettings(
                exportPreferences.getInt("size", 1024),
                exportPreferences.getBoolean("transparent", false),
                exportPreferences.getBoolean("rectangle", false),
            )
        )
    }
    revision // Subscribe to mutations from the native canvas.
    var panel by remember { mutableStateOf<ChromePanel?>(null) }
    var brushPrevious by remember { mutableStateOf(false) }
    var fillPrevious by remember { mutableStateOf(false) }
    var files by remember { mutableStateOf(false) }
    val locked = document.itsContentIsLocked
    val editing = document.itsTouchMode == TouchMode.edit
    val group = document.itsWallpaperGroup
    fun display(color: LinearDisplayP3Color) = color.toComposeColor()
    val backgroundLabel = stringResource(R.string.background)
    val contextSymmetry = stringResource(R.string.symmetry_format, group.orbifoldName)
    val config = LocalConfiguration.current
    val bidi = BidiFormatter.getInstance(config.layoutDirection == View.LAYOUT_DIRECTION_RTL)
    fun toggle(value: ChromePanel) {
        panel = if (panel == value) null else value
        files = false
    }
    BackHandler(panel != null || files) {
        panel = null
        files = false
    }
    BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding().padding(8.dp)) {
        val landscape = maxWidth > maxHeight
        val barBottom = if (landscape) 48.dp else 52.dp
        Row(Modifier.align(Alignment.TopStart), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = .9f))) {
                GlyphButton(
                    "back",
                    stringResource(R.string.saved_drawings),
                    onClick = {
                        panel = null
                        onFile(FileAction.LIBRARY)
                    },
                )
            }
            Box {
                Row(
                    Modifier.clip(RoundedCornerShape(12.dp))
                        .background(Color.White.copy(alpha = .9f))
                        .clickable {
                            files = !files
                            panel = null
                        }
                        .padding(horizontal = 8.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        stringResource(R.string.drawing_name_default),
                        color = Color.Black,
                        style = MaterialTheme.typography.titleMedium,
                    )
                    EditorGlyph("chevron", modifier = Modifier.size(20.dp))
                }
                DropdownMenu(
                    expanded = files,
                    onDismissRequest = { files = false },
                    containerColor = Color.White,
                ) {
                    listOf(
                            FileAction.NEW to R.string.new_drawing,
                            FileAction.LIBRARY to R.string.saved_drawings,
                            FileAction.SNAPSHOT to R.string.keep_copy,
                            FileAction.OPEN to R.string.open_drawing,
                            FileAction.SAVE to R.string.save_drawing,
                        )
                        .forEach { (action, label) ->
                            DropdownMenuItem(
                                text = { Text(stringResource(label)) },
                                onClick = {
                                    files = false
                                    onFile(action)
                                },
                            )
                        }
                    // The original hides drawing tools in Edit/locked mode; keep
                    // non-mutating export reachable through document actions.
                    if (editing || locked)
                        listOf(
                                Triple(false, false, R.string.export_image),
                                Triple(true, false, R.string.export_tile),
                                Triple(false, true, R.string.share_image),
                            )
                            .forEach { (tile, share, label) ->
                                DropdownMenuItem(
                                    text = { Text(stringResource(label)) },
                                    onClick = {
                                        files = false
                                        onExport(exportSettings.copy(rectangle = tile), share)
                                    },
                                )
                            }
                    DropdownMenuItem(
                        enabled = !locked,
                        text = { Text(stringResource(R.string.clear_drawing)) },
                        onClick = {
                            files = false
                            onAction(EditorAction.CLEAR)
                        },
                    )
                }
            }
        }
        if (!locked)
            ChromeFrame(Modifier.align(Alignment.TopCenter).padding(top = 52.dp)) {
                Row(Modifier.padding(5.dp)) {
                    GlyphButton(
                        "undo",
                        stringResource(R.string.undo),
                        undo,
                        onClick = { onAction(EditorAction.UNDO) },
                    )
                    GlyphButton(
                        "redo",
                        stringResource(R.string.redo),
                        redo,
                        onClick = { onAction(EditorAction.REDO) },
                    )
                }
            }
        ChromeFrame(Modifier.align(Alignment.TopEnd).padding(top = 52.dp)) {
            Box(Modifier.padding(5.dp)) {
                GlyphButton(
                    if (locked) "lock" else "unlock",
                    stringResource(
                        if (locked) R.string.unlock else R.string.lock_drawing,
                        stringResource(R.string.drawing_name_default),
                    ),
                    onClick = {
                        panel = null
                        onAction(EditorAction.LOCK)
                    },
                )
            }
        }
        if (!locked && !editing) {
            ChromeFrame(Modifier.align(Alignment.BottomStart)) {
                Column(Modifier.padding(5.dp)) {
                    GlyphButton(
                        "brush",
                        stringResource(R.string.brush),
                        selected = panel == ChromePanel.BRUSH,
                        tint = display(document.itsBrushColor),
                        onClick = { toggle(ChromePanel.BRUSH) },
                    )
                    GlyphButton(
                        "fill",
                        stringResource(R.string.fill_color),
                        selected = panel == ChromePanel.FILL || filling,
                        tint = display(document.itsFillColor),
                        onClick = { toggle(ChromePanel.FILL) },
                    )
                    GlyphButton(
                        "width",
                        stringResource(R.string.brush_width),
                        selected = panel == ChromePanel.WIDTH,
                        onClick = { toggle(ChromePanel.WIDTH) },
                    )
                    GlyphButton(
                        "smoothing",
                        stringResource(R.string.line_smoothing),
                        selected = panel == ChromePanel.SMOOTHING,
                        onClick = { toggle(ChromePanel.SMOOTHING) },
                    )
                }
            }
            ChromeFrame(Modifier.align(Alignment.BottomEnd).padding(bottom = barBottom)) {
                Column(Modifier.padding(5.dp)) {
                    Box(
                        Modifier.size(44.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(
                                if (panel == ChromePanel.BACKGROUND) Color(0xFFE0E0E0)
                                else Color.Transparent
                            )
                            .clickable(role = Role.Button) { toggle(ChromePanel.BACKGROUND) }
                            .semantics { contentDescription = backgroundLabel },
                        contentAlignment = Alignment.Center,
                    ) {
                        Box(
                            Modifier.size(25.dp)
                                .background(
                                    display(document.itsBackgroundColor),
                                    RoundedCornerShape(4.dp),
                                )
                                .border(1.dp, Color.Gray, RoundedCornerShape(4.dp))
                        )
                    }
                    Box(
                        Modifier.size(44.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(
                                if (panel == ChromePanel.SYMMETRY) Color(0xFFE0E0E0)
                                else Color.Transparent
                            )
                            .clickable(role = Role.Button) { toggle(ChromePanel.SYMMETRY) }
                            .semantics { contentDescription = contextSymmetry }
                    ) {
                        Icon(
                            painterResource(groupArtwork(group, true)),
                            null,
                            tint = EditorBlue,
                            modifier = Modifier.size(30.dp).align(Alignment.Center),
                        )
                    }
                    GlyphButton(
                        "share",
                        stringResource(R.string.share_image),
                        selected = panel == ChromePanel.EXPORT,
                        onClick = { toggle(ChromePanel.EXPORT) },
                    )
                }
            }
        }
        if (!locked)
            ChromeFrame(Modifier.align(Alignment.BottomCenter)) {
                Row(
                    Modifier.padding(6.dp).background(Color(0xFFEEEEF0), RoundedCornerShape(14.dp))
                ) {
                    for (mode in listOf(TouchMode.draw, TouchMode.edit)) {
                        val chosen = mode == document.itsTouchMode
                        Text(
                            stringResource(
                                if (mode == TouchMode.draw) R.string.draw_mode
                                else R.string.edit_mode
                            ),
                            color = Color.Black,
                            style = MaterialTheme.typography.bodyMedium,
                            modifier =
                                Modifier.clip(RoundedCornerShape(12.dp))
                                    .background(if (chosen) Color.White else Color.Transparent)
                                    .clickable(role = Role.Tab) {
                                        panel = null
                                        onAction(
                                            if (mode == TouchMode.draw) EditorAction.DRAW
                                            else EditorAction.EDIT
                                        )
                                    }
                                    .semantics { selected = chosen }
                                    .padding(horizontal = 13.dp, vertical = 8.dp),
                        )
                    }
                }
            }
        ChromeFrame(Modifier.align(Alignment.BottomEnd)) {
            Box(Modifier.padding(5.dp)) {
                GlyphButton(
                    "help",
                    stringResource(R.string.help),
                    selected = panel == ChromePanel.HELP,
                    onClick = { toggle(ChromePanel.HELP) },
                )
            }
        }
        panel?.let { active ->
            val maxPanelHeight = (maxHeight - 164.dp).coerceAtLeast(100.dp)
            val wide =
                active in
                    listOf(
                        ChromePanel.SYMMETRY,
                        ChromePanel.WIDTH,
                        ChromePanel.SMOOTHING,
                        ChromePanel.EXPORT,
                    )
            ChromeFrame(
                Modifier.align(Alignment.BottomCenter)
                    .padding(bottom = 62.dp)
                    .widthIn(max = if (wide) 340.dp else 300.dp)
                    .fillMaxWidth(if (wide) .92f else .64f)
                    .heightIn(max = maxPanelHeight)
            ) {
                Column(
                    Modifier.verticalScroll(rememberScrollState()).padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    when (active) {
                        ChromePanel.BRUSH,
                        ChromePanel.FILL,
                        ChromePanel.BACKGROUND -> {
                            val label =
                                stringResource(
                                    when (active) {
                                        ChromePanel.BRUSH -> R.string.brush_color
                                        ChromePanel.FILL -> R.string.fill_color
                                        else -> R.string.background
                                    }
                                )
                            val color =
                                when (active) {
                                    ChromePanel.BRUSH -> document.itsBrushColor
                                    ChromePanel.FILL -> document.itsFillColor
                                    else -> document.itsBackgroundColor
                                }
                            val previous =
                                if (active == ChromePanel.BRUSH) brushPrevious else fillPrevious
                            if (active != ChromePanel.BACKGROUND)
                                OriginalModes(label, previous) {
                                    if (active == ChromePanel.BRUSH) brushPrevious = it
                                    else fillPrevious = it
                                }
                            if (active != ChromePanel.BACKGROUND && previous) {
                                // Upstream ColorPalette: stable first-use order, exact values,
                                // background last; brush/fill changes apply immediately without
                                // undo.
                                ExistingColors(
                                    document.itsElements.map { it.itsColor } +
                                        document.itsBackgroundColor,
                                    color,
                                ) {
                                    onPaletteColor(checkNotNull(active.colorTarget), it)
                                }
                            } else
                                Row(
                                    Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                ) {
                                    Text(label, Modifier.weight(1f))
                                    ColorWell(color, stringResource(R.string.hex_color)) {
                                        onColor(checkNotNull(active.colorTarget))
                                    }
                                }
                            if (active == ChromePanel.FILL)
                                TextButton(
                                    onClick = {
                                        panel = null
                                        onAction(EditorAction.FILL)
                                    }
                                ) {
                                    Text(
                                        stringResource(
                                            if (filling) R.string.paint else R.string.fill
                                        )
                                    )
                                }
                        }
                        ChromePanel.WIDTH -> {
                            Text(stringResource(R.string.brush_width))
                            var width by remember {
                                mutableFloatStateOf(log2(document.itsBrushThickness).toFloat())
                            }
                            Box(
                                Modifier.align(Alignment.CenterHorizontally).size(54.dp),
                                contentAlignment = Alignment.Center,
                            ) {
                                Canvas(Modifier.fillMaxSize()) {
                                    drawCircle(
                                        document.itsBrushColor.toComposeColor(),
                                        radius =
                                            (2.0.pow(width.toDouble()) * size.width * 8)
                                                .toFloat()
                                                .coerceIn(1f, size.width / 2),
                                    )
                                }
                            }
                            val label = stringResource(R.string.brush_width)
                            Slider(
                                value = width.coerceIn(-9f, -2f),
                                onValueChange = { width = it },
                                onValueChangeFinished = { onWidth(2.0.pow(width.toDouble())) },
                                valueRange = -9f..-2f,
                                modifier = Modifier.semantics { contentDescription = label },
                            )
                        }
                        ChromePanel.SMOOTHING -> {
                            Text(stringResource(R.string.line_smoothing))
                            var smooth by remember {
                                mutableFloatStateOf(document.itsSmoothingTolerance.toFloat())
                            }
                            val label = stringResource(R.string.line_smoothing)
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                SmoothedLineExample(true, display(document.itsBrushColor))
                                Slider(
                                    value = smooth.coerceIn(.001f, .016f),
                                    onValueChange = { smooth = it },
                                    onValueChangeFinished = { onSmoothing(smooth.toDouble()) },
                                    valueRange = 0.001f..0.016f,
                                    modifier =
                                        Modifier.weight(1f).semantics {
                                            contentDescription = label
                                        },
                                )
                                SmoothedLineExample(false, display(document.itsBrushColor))
                            }
                        }
                        ChromePanel.SYMMETRY -> {
                            Text(
                                stringResource(
                                    R.string.symmetry_format,
                                    bidi.unicodeWrap(
                                        group.orbifoldName,
                                        TextDirectionHeuristics.LTR,
                                    ),
                                ),
                                modifier = Modifier.align(Alignment.CenterHorizontally),
                            )
                            val order =
                                listOf(
                                    WallpaperGroup.wpg2222,
                                    WallpaperGroup.wpgS2222,
                                    WallpaperGroup.wpg2S22,
                                    WallpaperGroup.wpg333,
                                    WallpaperGroup.wpgS333,
                                    WallpaperGroup.wpg3S3,
                                    WallpaperGroup.wpg442,
                                    WallpaperGroup.wpgS442,
                                    WallpaperGroup.wpg4S2,
                                    WallpaperGroup.wpg632,
                                    WallpaperGroup.wpgS632,
                                    WallpaperGroup.wpg22S,
                                    WallpaperGroup.wpg22X,
                                    WallpaperGroup.wpgSS,
                                    WallpaperGroup.wpgSX,
                                    WallpaperGroup.wpgXX,
                                    WallpaperGroup.wpgO,
                                )
                            val state =
                                androidx.compose.foundation.lazy.rememberLazyListState(
                                    initialFirstVisibleItemIndex =
                                        order.indexOf(group).coerceIn(0, order.size - 4)
                                )
                            LazyRow(
                                state = state,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                items(order) { choice ->
                                    Column(
                                        Modifier.width(64.dp)
                                            .clickable(role = Role.Button) { onGroup(choice) }
                                            .semantics { selected = choice == group },
                                        horizontalAlignment = Alignment.CenterHorizontally,
                                    ) {
                                        Image(
                                            painterResource(groupArtwork(choice, false)),
                                            null,
                                            Modifier.size(64.dp)
                                                .clip(RoundedCornerShape(16.dp))
                                                .background(
                                                    if (choice == group) EditorBlue else Color.White
                                                )
                                                .border(
                                                    1.dp,
                                                    Color(0xFF9999BF),
                                                    RoundedCornerShape(16.dp),
                                                ),
                                        )
                                        Text(
                                            bidi.unicodeWrap(
                                                choice.orbifoldName,
                                                TextDirectionHeuristics.LTR,
                                            ),
                                            color =
                                                if (choice == group) EditorBlue else Color.Black,
                                        )
                                        Text(
                                            choice.IUCName,
                                            style = MaterialTheme.typography.labelSmall,
                                            color = Color.Gray,
                                        )
                                    }
                                }
                            }
                            ChromeToggle(
                                stringResource(R.string.color_grid),
                                document.itsShowSingularitiesFlag,
                                stringResource(R.string.symmetry_guides),
                            ) {
                                onAction(EditorAction.GUIDES)
                            }
                            ChromeToggle(
                                stringResource(R.string.color_by_symmetry),
                                document.itsColorBySymmetryFlag,
                            ) {
                                onAction(EditorAction.COLORS)
                            }
                            Row(
                                Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceEvenly,
                            ) {
                                TextButton(onClick = { onAction(EditorAction.REALIGN) }) {
                                    Text(stringResource(R.string.realign))
                                }
                                TextButton(
                                    enabled = group.torusGroup.itsRigidity != Rigidity.rigid,
                                    onClick = { onAction(EditorAction.SHAPE) },
                                ) {
                                    Text(stringResource(R.string.aspect_ratio))
                                }
                            }
                        }
                        ChromePanel.EXPORT ->
                            OriginalExportPanel(
                                document,
                                revision,
                                exportSettings,
                                maximumExportSize,
                                onSettings = { next ->
                                    exportSettings = next
                                    exportPreferences
                                        .edit()
                                        .putInt("size", next.size)
                                        .putBoolean("transparent", next.transparent)
                                        .putBoolean("rectangle", next.rectangle)
                                        .apply()
                                },
                                onExport = { options, share ->
                                    panel = null
                                    onExport(options, share)
                                },
                                onPreview = onPreview,
                            )
                        ChromePanel.HELP -> {
                            TextButton(
                                onClick = {
                                    panel = null
                                    onAction(EditorAction.HELP)
                                }
                            ) {
                                Text(stringResource(R.string.help_editor_title))
                            }
                            TextButton(
                                onClick = {
                                    panel = null
                                    onAction(EditorAction.ABOUT)
                                }
                            ) {
                                Text(stringResource(R.string.about))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
internal fun ChromeToggle(
    label: String,
    value: Boolean,
    description: String = label,
    onClick: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth()
            .toggleable(value = value, role = Role.Switch, onValueChange = { onClick() })
            .semantics { contentDescription = description },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        Box(
            Modifier.padding(start = 8.dp)
                .size(44.dp, 27.dp)
                .background(
                    if (value) Color(0xFF34C759) else Color(0xFFE5E5E7),
                    RoundedCornerShape(50),
                )
                .padding(2.dp)
        ) {
            Box(
                Modifier.align(if (value) Alignment.CenterEnd else Alignment.CenterStart)
                    .size(23.dp)
                    .background(Color.White, RoundedCornerShape(50))
            )
        }
    }
}

@Composable
internal fun ColorWell(color: LinearDisplayP3Color, label: String, onClick: () -> Unit) {
    Box(
        Modifier.size(34.dp)
            .clip(RoundedCornerShape(50))
            .background(
                Brush.sweepGradient(
                    listOf(
                        Color.Red,
                        Color.Yellow,
                        Color.Green,
                        Color.Cyan,
                        Color.Blue,
                        Color.Magenta,
                        Color.Red,
                    )
                )
            )
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label }
            .padding(3.dp)
            .background(Color.White, RoundedCornerShape(50))
            .padding(2.dp)
            .background(color.toComposeColor(), RoundedCornerShape(50))
    )
}

/** Original SmoothedLine shape, including its deliberately wiggly quadratic control points. */
@Composable
private fun SmoothedLineExample(wiggly: Boolean, color: Color) {
    Canvas(Modifier.size(28.dp)) {
        // Note: A SwiftUI Path's origin sits at the upper left.
        // Choose the control points.
        val c =
            if (wiggly)
                listOf(
                    Offset(.110f, .865f),
                    Offset(.100f, .605f),
                    Offset(.260f, .510f),
                    Offset(.255f, .245f),
                    Offset(.510f, .260f),
                    Offset(.605f, .085f),
                    Offset(.865f, .110f),
                )
            else listOf(Offset(.25f, .125f))
        // Compute the points on the curve.
        val p = listOf(Offset(0f, 1f)) + c.zipWithNext { a, b -> (a + b) / 2f } + Offset(1f, 0f)
        // Scale the control point and regular points to fit the given CGRect.
        fun scaled(v: Offset) = Offset(v.x * size.width, v.y * size.height)
        // Create thePath.
        val path =
            Path().apply {
                moveTo(0f, size.height)
                for (i in c.indices) {
                    val control = scaled(c[i])
                    val end = scaled(p[i + 1])
                    quadraticBezierTo(control.x, control.y, end.x, end.y)
                }
            }
        drawPath(path, color, style = Stroke(3.5.dp.toPx(), cap = StrokeCap.Round))
    }
}
