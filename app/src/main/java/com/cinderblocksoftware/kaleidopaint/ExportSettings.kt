// Ported from GeometryGamesExportView.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint

import com.cinderblocksoftware.kaleidopaint.geometry.*

internal data class ExportSettings(
    val size: Int = 1024,
    val transparent: Boolean = false,
    val rectangle: Boolean = false,
)

/** Compute the caption without temporarily changing the live document. */
internal fun exportDimensions(
    document: KaleidoPaintDocument,
    settings: ExportSettings,
): Pair<Int, Int> =
    synchronized(document) {
        if (!settings.rectangle) settings.size to settings.size
        else
            KaleidoPaintDocument(document.itsWallpaperGroup)
                .apply {
                    itsUnitCellPlacement = document.itsUnitCellPlacement.copy()
                }
                .prepareModelToExportTileableRectangle(settings.size, settings.size)
    }
