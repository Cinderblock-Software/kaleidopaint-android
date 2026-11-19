// Ported from KaleidoPaintLinearDisplayP3Color.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint.geometry

import kotlin.math.abs
import kotlin.math.pow

//	Port note:  init?(fromSwiftUIColor:) and asSwiftUIColor() convert
//	to and from SwiftUI's Color.  Their Android counterparts belong
//	with the colour picker in the app module, and are not here.

data class LinearDisplayP3Color(

    //	Color Space
    //
    //		One design decision was what color space to store a color in.
    //
    //			Extended sRGB (linear, not gamma-encoded)
    //				Metal interprets the frame buffer in gamma-encoded Extended sRGB,
    //				so other than Metal's automatic gamma encoding,
    //				no conversion would be needed at render time.
    //
    //			Display P3 (linear, not gamma-encoded)
    //				makes it easy to know where the corners and edges
    //				of the available color triangle are, and also makes
    //				it easy to find a color of maximal brightness.
    //				Furthermore, to support both transpancy (for compositing
    //				the intermediate unit cell textures) and a 32-bit pixel format
    //				(for doing flood fills on the GPU, which supports uint32_t input buffers
    //				but not uint64_t input buffers), the only practical choice
    //				is some sort of BRGA8 pixel format.  Because BRGA8 color components
    //				are limited to the range [0.0, 1.0], the only way to get Wide Color
    //				is to render in P3.
    //
    //		Display P3 is the clear winner.  So KaleidoPaint
    //
    //			- stores a color in Linear Display P3, where it's easy to work with,
    //
    //			- renders into the intermediate unit cell textures as Display P3,
    //
    //			- and then, when compositing the intermediate unit cell textures
    //				to get itsUnitCellComposedTexture, lets our compositor convert
    //				from Linear Display P3 to Linear Extended Range sRGB.
    val r: Double, // 	(αR, αG, αB, α), with α = 1
    val g: Double, // 	Linear Display P3 color space (see comment immediately above)
    val b: Double,
    val a: Double, // 	= 1
) {

    //	Port note:  SIMD4<Float16> becomes four Float32.
    fun asSIMDHalf(): Float4 {

        return Float4(
            r.toFloat(),
            g.toFloat(),
            b.toFloat(),
            a.toFloat(),
        )
    }

    fun isAlmostTheSameAs(otherColor: LinearDisplayP3Color): Boolean {

        //	When the user transfers a color using the SwiftUI ColorPicker's
        //	customizable palette, the color's RGB components may change
        //	by a few parts in 10⁷ (Float32 precision).
        //
        //	When the user transfers a color using the SwiftUI ColorPicker's
        //	hex code, the color's RGB components may change
        //	by a few parts in 10³ (Int8 precision).
        //
        //	To recognize colors that the user intends to be identical,
        //	let's allow a tolerance of 0.01 in each color component.

        return (abs(this.r - otherColor.r) < 0.01 &&
            abs(this.g - otherColor.g) < 0.01 &&
            abs(this.b - otherColor.b) < 0.01 &&
            abs(this.a - otherColor.a) < 0.01)
    }
}

fun clampToZeroOne(x: Double): Double {

    if (x < 0.0) {
        return 0.0
    }
    if (x > 1.0) {
        return 1.0
    }
    return x
}

fun gammaEncode(
    linearValue: Double
): Double { //	returns gamma-encoded value (using sRGB transfer function)

    //	The encoding curve for negative values is
    //	symmetrical with the curve for positive values.
    //
    if (linearValue < 0.0) {
        return -gammaEncode(-linearValue)
    }

    //	The sRGB transfer function begins with a short linear segment
    //	(to avoid an infinite slope near zero), followed by a gamma curve
    //	with power 1/2.4 thereafter.  The overall curve closely follows
    //	a traditional gamma curve (with no linear segment) with power 1/2.2.
    //
    //	My understanding is that the following numerical values are exact
    //	(defined in the IEC standard), they're not approximations.
    //
    val theGammaEncodedValue =
        (if (linearValue < 0.0031308) 12.92 * linearValue
        else 1.055 * linearValue.pow(1.0 / 2.4) - 0.055)

    return theGammaEncodedValue
}

fun gammaDecode(
    gammaEncodedValue: Double // 	encoded using sRGB transfer function
): Double { //	returns linear value

    //	The decoding curve for negative values is
    //	symmetrical with the curve for positive values.
    //
    if (gammaEncodedValue < 0.0) {
        return -gammaDecode(-gammaEncodedValue)
    }

    //	The sRGB transfer function begins with a short linear segment
    //	(to avoid zero slope near zero), followed by a gamma curve
    //	with power 2.4 thereafter.  The overall curve closely follows
    //	a traditional gamma curve (with no linear segment) with power 2.2.
    //
    //	My understanding is that the following numerical values are exact
    //	(defined in the IEC standard), they're not approximations.
    //
    val theLinearValue =
        (if (gammaEncodedValue < 0.04045) (1.0 / 12.92) * gammaEncodedValue
        else ((1.0 / 1.055) * gammaEncodedValue + (0.055 / 1.055)).pow(2.4))

    return theLinearValue
}
