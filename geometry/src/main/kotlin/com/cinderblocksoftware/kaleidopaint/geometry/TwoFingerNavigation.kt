// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint.geometry

/**
 * Android adapter for upstream's simultaneous rotation, pinch and two-finger translation gestures.
 * Scale and rotation are about the view center, as in KaleidoPaintGestureHandler.swift. These
 * viewport changes are not undo steps.
 */
fun navigateWithTwoFingers(
    placement: UnitCellPlacement,
    previousA: DisplayPoint,
    previousB: DisplayPoint,
    currentA: DisplayPoint,
    currentB: DisplayPoint,
): UnitCellPlacement {
    val a0 = convertDisplayCoordinatesToDrawingCoordinates(previousA)
    val b0 = convertDisplayCoordinatesToDrawingCoordinates(previousB)
    val a1 = convertDisplayCoordinatesToDrawingCoordinates(currentA)
    val b1 = convertDisplayCoordinatesToDrawingCoordinates(currentB)
    val old = b0 - a0
    val next = b1 - a1
    val denominator = old.x * old.x + old.y * old.y
    if (denominator < 1e-12) return placement.copy()
    val real = (next.x * old.x + next.y * old.y) / denominator
    val imaginary = (next.y * old.x - next.x * old.y) / denominator
    if (!real.isFinite() || !imaginary.isFinite()) return placement.copy()
    val translation = (a1 + b1 - a0 - b0) * 0.5
    val result = placement.copy()
    result.transform(Double3x2(Double2(real, imaginary), Double2(-imaginary, real), translation))
    // Match upstream's protection against singular or unusably large cells.
    if (!result.unitCellIsDegenerate()) return result
    // Reject only the inadmissible pinch, keeping simultaneous rotation/pan.
    val magnitude = kotlin.math.hypot(real, imaginary)
    val rotationReal = if (magnitude > 0.0) real / magnitude else 1.0
    val rotationImaginary = if (magnitude > 0.0) imaginary / magnitude else 0.0
    return placement.copy().apply {
        transform(
            Double3x2(
                Double2(rotationReal, rotationImaginary),
                Double2(-rotationImaginary, rotationReal),
                translation,
            )
        )
    }
}
