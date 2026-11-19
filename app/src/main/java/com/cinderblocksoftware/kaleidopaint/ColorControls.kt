// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import androidx.compose.foundation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.cinderblocksoftware.kaleidopaint.geometry.*

// Document colors remain Linear Display P3. Android UI colors use encoded sRGB.
internal fun toSRGBHex(color: LinearDisplayP3Color): String {
    val rgb = gP3toSRGB * Double3(color.r, color.g, color.b)
    return listOf(rgb.x, rgb.y, rgb.z).joinToString("") {
        "%02X".format((gammaEncode(it).coerceIn(0.0, 1.0) * 255 + .5).toInt())
    }
}

internal fun LinearDisplayP3Color.toComposeColor() =
    Color(android.graphics.Color.parseColor("#" + toSRGBHex(this)))

internal fun fromSRGBHex(hex: String): LinearDisplayP3Color {
    val rgb =
        Double3(
            gammaDecode(hex.substring(0, 2).toInt(16) / 255.0),
            gammaDecode(hex.substring(2, 4).toInt(16) / 255.0),
            gammaDecode(hex.substring(4, 6).toInt(16) / 255.0),
        )
    val p3 = gSRGBtoP3 * rgb
    return LinearDisplayP3Color(p3.x, p3.y, p3.z, 1.0)
}

/** Draft settings are committed only on Apply; Cancel never changes a document. */
@Composable
fun ColorControls(
    title: String,
    initial: LinearDisplayP3Color,
    onDismiss: () -> Unit,
    onApply: (LinearDisplayP3Color) -> Unit,
) {
    val initialHex = remember { toSRGBHex(initial) }
    var hex by remember { mutableStateOf(initialHex) }
    val hsv = remember {
        FloatArray(3).also {
            android.graphics.Color.colorToHSV(
                android.graphics.Color.parseColor("#$initialHex"),
                it,
            )
        }
    }
    var hue by remember { mutableFloatStateOf(hsv[0]) }
    var saturation by remember { mutableFloatStateOf(hsv[1]) }
    var brightness by remember { mutableFloatStateOf(hsv[2]) }
    val hueLabel = stringResource(R.string.hue)
    val saturationLabel = stringResource(R.string.saturation)
    val brightnessLabel = stringResource(R.string.brightness)
    var tab by remember { mutableIntStateOf(0) }
    val palette = remember { editorColorGrid() }
    val valid = hex.matches(Regex("[0-9A-Fa-f]{6}"))
    fun setHex(value: String) {
        hex = value
        if (value.matches(Regex("[0-9A-Fa-f]{6}"))) {
            val next = FloatArray(3)
            android.graphics.Color.colorToHSV(android.graphics.Color.parseColor("#$value"), next)
            hue = next[0]
            saturation = next[1]
            brightness = next[2]
        }
    }
    fun setHSV() {
        hex =
            "%06X"
                .format(
                    android.graphics.Color.HSVToColor(floatArrayOf(hue, saturation, brightness)) and
                        0xffffff
                )
    }
    EditorSheet(
        onDismissRequest = onDismiss,
        title = { Text(title, style = MaterialTheme.typography.titleMedium) },
        text = {
            Column(Modifier.heightIn(max = 440.dp).verticalScroll(rememberScrollState())) {
                Row(
                    Modifier.fillMaxWidth()
                        .background(Color(0xFFEEEEF0), RoundedCornerShape(18.dp))
                        .padding(3.dp)
                ) {
                    listOf(R.string.color_grid, R.string.color_spectrum, R.string.color_sliders)
                        .forEachIndexed { index, label ->
                            Text(
                                stringResource(label),
                                color = Color.Black,
                                style = MaterialTheme.typography.bodyMedium,
                                modifier =
                                    Modifier.weight(1f)
                                        .clip(RoundedCornerShape(16.dp))
                                        .background(
                                            if (tab == index) Color.White else Color.Transparent
                                        )
                                        .clickable(role = Role.Tab) { tab = index }
                                        .semantics { selected = tab == index }
                                        .padding(vertical = 8.dp),
                                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                            )
                        }
                }
                Spacer(Modifier.height(14.dp))
                when (tab) {
                    0 ->
                        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))) {
                            palette.forEach { row ->
                                Row(Modifier.fillMaxWidth()) {
                                    row.forEach { value ->
                                        val label = stringResource(R.string.color_hex_format, value)
                                        Box(
                                            Modifier.weight(1f)
                                                .aspectRatio(1f)
                                                .background(
                                                    Color(
                                                        android.graphics.Color.parseColor("#$value")
                                                    )
                                                )
                                                .then(
                                                    if (value.equals(hex, true))
                                                        Modifier.border(2.dp, Color.White)
                                                    else Modifier
                                                )
                                                .clickable(role = Role.Button) { setHex(value) }
                                                .semantics { contentDescription = label }
                                        )
                                    }
                                }
                            }
                        }
                    1 -> {
                        fun choose(p: Offset, w: Float, h: Float) {
                            val x = (p.x / w).coerceIn(0f, 1f)
                            val y = (p.y / h).coerceIn(0f, 1f)
                            setHex(
                                "%06X"
                                    .format(
                                        android.graphics.Color.HSVToColor(
                                            floatArrayOf(
                                                x * 360f,
                                                (y * 2).coerceAtMost(1f),
                                                ((1 - y) * 2).coerceAtMost(1f),
                                            )
                                        ) and 0xffffff
                                    )
                            )
                        }
                        Canvas(
                            Modifier.fillMaxWidth()
                                .aspectRatio(1.1f)
                                .clip(RoundedCornerShape(12.dp))
                                .pointerInput(Unit) {
                                    detectTapGestures {
                                        choose(it, size.width.toFloat(), size.height.toFloat())
                                    }
                                }
                                .pointerInput(Unit) {
                                    detectDragGestures { change, _ ->
                                        change.consume()
                                        choose(
                                            change.position,
                                            size.width.toFloat(),
                                            size.height.toFloat(),
                                        )
                                    }
                                }
                        ) {
                            drawRect(
                                Brush.horizontalGradient(
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
                            drawRect(
                                Brush.verticalGradient(
                                    0f to Color.White,
                                    .5f to Color.Transparent,
                                    1f to Color.Black,
                                )
                            )
                        }
                    }
                    else -> {
                        OutlinedTextField(
                            value = hex,
                            onValueChange = { setHex(it.removePrefix("#").take(6)) },
                            label = { Text(stringResource(R.string.hex_color)) },
                            textStyle =
                                LocalTextStyle.current.copy(
                                    textDirection = androidx.compose.ui.text.style.TextDirection.Ltr
                                ),
                            singleLine = true,
                            isError = !valid,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        Text(stringResource(R.string.hue))
                        Slider(
                            value = hue,
                            onValueChange = {
                                hue = it
                                setHSV()
                            },
                            valueRange = 0f..360f,
                            modifier = Modifier.semantics { contentDescription = hueLabel },
                        )
                        Text(stringResource(R.string.saturation))
                        Slider(
                            value = saturation,
                            onValueChange = {
                                saturation = it
                                setHSV()
                            },
                            modifier = Modifier.semantics { contentDescription = saturationLabel },
                        )
                        Text(stringResource(R.string.brightness))
                        Slider(
                            value = brightness,
                            onValueChange = {
                                brightness = it
                                setHSV()
                            },
                            modifier = Modifier.semantics { contentDescription = brightnessLabel },
                        )
                    }
                }
                Spacer(Modifier.height(12.dp))
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                ) {
                    if (valid)
                        Box(
                            Modifier.size(58.dp, 46.dp)
                                .background(
                                    Color(android.graphics.Color.parseColor("#$hex")),
                                    RoundedCornerShape(10.dp),
                                )
                                .border(1.dp, Color.LightGray, RoundedCornerShape(10.dp))
                        )
                    listOf("000000", "FFFFFF", "E53935", "1976D2", "43A047").forEach { value ->
                        val label = stringResource(R.string.color_hex_format, value)
                        Box(
                            Modifier.size(30.dp)
                                .clip(RoundedCornerShape(50))
                                .background(Color(android.graphics.Color.parseColor("#$value")))
                                .border(1.dp, Color.LightGray, RoundedCornerShape(50))
                                .clickable(role = Role.Button) { setHex(value) }
                                .semantics { contentDescription = label }
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = valid,
                onClick = {
                    // Opening and applying a dialog without changing color must not clip
                    // an existing P3 color to sRGB or quantize it to 8-bit channels.
                    val color =
                        if (hex.equals(initialHex, ignoreCase = true)) initial else fromSRGBHex(hex)
                    onApply(color)
                },
            ) {
                Text(stringResource(R.string.apply))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(android.R.string.cancel)) }
        },
    )
}

/** A regular hue/value grid; the original app uses the operating system's color picker. */
private fun editorColorGrid(): List<List<String>> =
    (0..9).map { row ->
        (0..11).map { column ->
            val rgb =
                if (row == 0)
                    android.graphics.Color.rgb(
                        255 - column * 255 / 11,
                        255 - column * 255 / 11,
                        255 - column * 255 / 11,
                    )
                else {
                    val saturation = if (row <= 6) 1f else (10 - row) / 4f
                    val value = if (row <= 6) .20f + row * .8f / 6 else 1f
                    android.graphics.Color.HSVToColor(
                        floatArrayOf((190f + column * 30) % 360, saturation, value)
                    )
                }
            "%06X".format(rgb and 0xffffff)
        }
    }
