// Ported from GeometryGamesExportView.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.cinderblocksoftware.kaleidopaint.geometry.*

/** The original controls and preview, with a separate Android Save-to-file action. */
@Composable
internal fun OriginalExportPanel(
    document: KaleidoPaintDocument,
    revision: Int,
    settings: ExportSettings,
    maximumSize: Int,
    onSettings: (ExportSettings) -> Unit,
    onExport: (ExportSettings, Boolean) -> Unit,
    onPreview: (ExportSettings, (Result<ByteArray>) -> Unit) -> Unit,
) {
    var sizes by remember { mutableStateOf(false) }
    var preview by remember { mutableStateOf<ImageBitmap?>(null) }
    var previewFailed by remember { mutableStateOf(false) }
    val latest by rememberUpdatedState(settings)
    val latestRevision by rememberUpdatedState(revision)
    LaunchedEffect(settings, revision) {
        val request = settings
        val frame = revision
        onPreview(settings.copy(size = minOf(settings.size, 1024))) { result ->
            if (latest == request && latestRevision == frame) {
                previewFailed = result.isFailure
                preview =
                    result.getOrNull()?.let {
                        android.graphics.BitmapFactory.decodeByteArray(it, 0, it.size)
                            ?.asImageBitmap()
                    }
            }
        }
    }
    val dimensions = exportDimensions(document, settings)
    val dims = "${dimensions.first} × ${dimensions.second}"
    val bidi =
        android.text.BidiFormatter.getInstance(
            androidx.compose.ui.platform.LocalLayoutDirection.current ==
                androidx.compose.ui.unit.LayoutDirection.Rtl
        )
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(
            Modifier.clickable { onExport(settings, true) }.padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            EditorGlyph("share", modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(6.dp))
            Text(stringResource(R.string.share_image), color = EditorBlue)
        }
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(stringResource(R.string.image_size))
            Box {
                Text(
                    bidi.unicodeWrap(
                        "${settings.size} × ${settings.size} ⌃",
                        android.text.TextDirectionHeuristics.LTR,
                    ),
                    color = EditorBlue,
                    modifier = Modifier.clickable { sizes = true }.padding(vertical = 6.dp),
                )
                DropdownMenu(
                    expanded = sizes,
                    onDismissRequest = { sizes = false },
                    containerColor = Color.White,
                ) {
                    listOf(256, 512, 1024, 2048, 4096)
                        .filter { it <= maximumSize }
                        .forEach { size ->
                            DropdownMenuItem(
                                text = { Text("$size × $size", color = EditorBlue) },
                                onClick = {
                                    sizes = false
                                    onSettings(settings.copy(size = size))
                                },
                            )
                        }
                }
            }
        }
        ChromeToggle(stringResource(R.string.transparent_background), settings.transparent) {
            onSettings(settings.copy(transparent = !settings.transparent))
        }
        ChromeToggle(
            stringResource(
                if (
                    document.itsWallpaperGroup in
                        listOf(WallpaperGroup.wpgO, WallpaperGroup.wpg2222)
                )
                    R.string.rectangle
                else R.string.export_tile
            ),
            settings.rectangle,
        ) {
            onSettings(settings.copy(rectangle = !settings.rectangle))
        }
        // Display the rendered drawing over light gray so transparent regions
        // remain visible, as in GeometryGamesExportView.
        Box(
            Modifier.size(256.dp).background(Color(0xFFF0F0F0)),
            contentAlignment = Alignment.Center,
        ) {
            val image = preview
            if (image != null)
                Image(
                    image,
                    stringResource(R.string.export_image),
                    Modifier.fillMaxSize(),
                    contentScale = ContentScale.Fit,
                )
            else if (previewFailed)
                Text(
                    stringResource(R.string.file_operation_failed),
                    style = MaterialTheme.typography.bodySmall,
                )
            else CircularProgressIndicator(Modifier.size(24.dp))
        }
        Text(
            bidi.unicodeWrap(dims, android.text.TextDirectionHeuristics.LTR),
            style = MaterialTheme.typography.bodySmall,
            color = Color.Gray,
        )
        Text(
            stringResource(R.string.export_image),
            color = EditorBlue,
            modifier = Modifier.clickable { onExport(settings, false) }.padding(vertical = 4.dp),
        )
    }
}
