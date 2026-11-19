// Ported from KaleidoPaintRenderer.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
package com.cinderblocksoftware.kaleidopaint.geometry

import kotlin.math.cos
import kotlin.math.sin

fun singularityMarkers(wallpaperGroup: WallpaperGroup): List<Curve> {
    val color =
        LinearDisplayP3Color(
            r = .125, // opaque 7/8 black
            g = .125,
            b = .125,
            a = 1.0,
        )
    val thickness = .00390625 // in unit cell coordinates
    val theta = 1.4 // a generic angle
    val radius = .03125 // radius of "gyration star"
    val ray = radius * Double2(cos(theta), sin(theta))
    val group = wallpaperGroup.torusGroup
    fun segment(a: Double2, b: Double2) =
        Curve(color = color, thickness = thickness).apply {
            itsSpline.append(SplineNode(location = a, type = SplineNodeType.corner))
            itsSpline.append(SplineNode(location = b, type = SplineNodeType.corner))
            itsSpline.refreshParameterization()
        }
    val mirrors = group.itsMirrorSegments.map { (a, b) -> segment(a, b) }
    val gyrations = group.itsGyrationPoints.map { point -> segment(point, point + ray) }
    val dashCount = 4
    val interval = 1.0 / dashCount
    val glides =
        group.itsGlideReflectionSegments.flatMap { (a, b) ->
            (0 until dashCount).map { i ->
                val s0 = (i + .25) * interval
                val t0 = 1.0 - s0
                val s1 = (i + .75) * interval
                val t1 = 1.0 - s1
                segment(s0 * a + t0 * b, s1 * a + t1 * b)
            }
        }
    return mirrors + gyrations + glides
}
