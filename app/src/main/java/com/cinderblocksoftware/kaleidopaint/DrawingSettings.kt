// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.cinderblocksoftware.kaleidopaint.geometry.Rigidity
import com.cinderblocksoftware.kaleidopaint.geometry.UnitCellShape
import kotlin.math.abs
import kotlin.math.log2
import kotlin.math.pow

@Composable
fun SmoothingControls(initial: Double, onDismiss: () -> Unit, onApply: (Double) -> Unit) {
    var value by remember { mutableFloatStateOf(initial.toFloat().coerceIn(.001f, .016f)) }
    var changed by remember { mutableStateOf(false) }
    val label = stringResource(R.string.line_smoothing)
    EditorSheet(
        onDismissRequest = onDismiss,
        title = { Text(label) },
        text = {
            Column {
                Text(stringResource(R.string.smoothing_explanation))
                Slider(
                    value = value,
                    onValueChange = {
                        value = it
                        changed = true
                    },
                    valueRange = 0.001f..0.016f,
                    modifier = Modifier.semantics { contentDescription = label },
                )
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(stringResource(R.string.less))
                    Text(stringResource(R.string.more))
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { onApply(if (changed) value.toDouble() else initial) }) {
                Text(stringResource(R.string.apply))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(android.R.string.cancel)) }
        },
    )
}

/** Original ShapePanel: two centered live sliders, captions below, no added action form. */
@Composable
fun CellShapeControls(
    initial: UnitCellShape,
    rigidity: Rigidity,
    onDismiss: () -> Unit,
    onChange: (UnitCellShape) -> Unit,
) {
    var aspect by remember {
        mutableFloatStateOf(log2(initial.aspectRatio).toFloat().coerceIn(-2f, 2f))
    }
    var shear by remember { mutableFloatStateOf(initial.shear.toFloat().coerceIn(-2f, 2f)) }
    val aspectLabel = stringResource(R.string.aspect_ratio)
    val shearLabel = stringResource(R.string.shear)
    fun preview() {
        onChange(UnitCellShape(2.0.pow(aspect.toDouble()), shear.toDouble()))
    }
    OriginalPanelSheet(stringResource(R.string.cell_shape), onDismiss) {
        Column(
            Modifier.width(288.dp).padding(16.dp),
            horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally,
        ) {
            if (rigidity != Rigidity.rigid) {
                OriginalSlider(
                    aspect,
                    -2f..2f,
                    aspectLabel,
                    Modifier.width(256.dp),
                    onChange = {
                        aspect = it
                        preview()
                    },
                    onFinished = {
                        // When released close to zero, snap exactly to the square aspect.
                        if (abs(aspect) < .125f) {
                            aspect = 0f
                            preview()
                        }
                    },
                )
                Text(aspectLabel, style = MaterialTheme.typography.bodySmall)
            }
            if (rigidity == Rigidity.fullyFlexible) {
                OriginalSlider(
                    shear,
                    -2f..2f,
                    shearLabel,
                    Modifier.width(256.dp),
                    onChange = {
                        shear = it
                        preview()
                    },
                    onFinished = {
                        // Support half-drop patterns: snap near an integer or half-integer.
                        val snap =
                            (.5 *
                                    (kotlin.math.floor(kotlin.math.abs(2.0 * shear) + .5) *
                                        kotlin.math.sign(shear.toDouble())))
                                .toFloat()
                        if (abs(shear - snap) < .125f) {
                            shear = snap
                            preview()
                        }
                    },
                )
                Text(shearLabel, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}
