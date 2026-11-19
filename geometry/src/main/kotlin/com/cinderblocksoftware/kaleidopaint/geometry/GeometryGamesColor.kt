// Ported from GeometryGamesColor.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

@file:Suppress("PropertyName")

package com.cinderblocksoftware.kaleidopaint.geometry

//	Port note:  This is the first half of GeometryGamesColor.swift,
//	the colour profiles and the matrices that convert between
//	Linear sRGB and Linear Display P3.  The drawing-file decoder needs them.
//	The second half (HSV, SwiftUI colours, premultiplied alpha)
//	is not ported yet.

// MARK: -
// MARK: Basic definitions

class GeometryGamesChromaticity(

    //	The CIE 1931 x and y values are the "source of truth" for a chromaticity.
    val x: Double,
    val y: Double,
) {

    //	The CIE 1931 z value follows easily as z = 1 - (x + y).
    val z: Double = 1.0 - (x + y)
}

class GeometryGamesTristimulus(
    chromaticity: GeometryGamesChromaticity,
    multiple: Double,
) {

    //	The CIE 1931 (X,Y,Z) vector is a multiple
    //	of the CIE 1931 chromaticity (x,y,z).  (See above)
    //	The multiple depends not on a single chromaticity alone,
    //	but on a set of colors {Red, Green, Green, WhitePoint},
    //	with lengths chosen so that
    //
    //		Red + Green + Green = WhitePoint
    //	and
    //		the WhitePoint's Y component is 1.
    //
    val X: Double = multiple * chromaticity.x
    val Y: Double = multiple * chromaticity.y
    val Z: Double = multiple * chromaticity.z
}

class GeometryGamesColorProfile(
    rawRed: GeometryGamesChromaticity,
    rawGreen: GeometryGamesChromaticity,
    rawBlue: GeometryGamesChromaticity,
    rawWhite: GeometryGamesChromaticity,
) {

    val red: GeometryGamesTristimulus
    val green: GeometryGamesTristimulus
    val blue: GeometryGamesTristimulus
    val white: GeometryGamesTristimulus

    init {
        //	Let the white point's (X,Y,Z) be (x/y, y/y, z/y),
        //	to satisfy the convention that Y = 1 for the white point.
        white =
            GeometryGamesTristimulus(
                chromaticity = rawWhite,
                multiple = 1.0 / rawWhite.y,
            ) //	no risk of division by zero

        //	We now need to find what multiples (mR, mG, mB)
        //	of the red, green and blue primitives, that is
        //
        //		(Xr, Yr, Zr) = mR * (xr, yr, zr)
        //		(Xg, Yg, Zg) = mG * (xg, yg, zg)
        //		(Xb, Yb, Zb) = mB * (xb, yb, zb)
        //
        //	are required to get the red, green and blue (X,Y,Z) vectors
        //	to sum to the (X,Y,Z) vector of the white point.
        //	That is, we need to solve
        //
        //		(xr xg xb)(mR)   (Xw)
        //		(yr yg yb)(mG) = (Yw)
        //		(zr xg zb)(mB)   (Zw)
        //
        val theMatrix =
            Double3x3( //	columns of the matrix above are rows here
                Double3(rawRed.x, rawRed.y, rawRed.z),
                Double3(rawGreen.x, rawGreen.y, rawGreen.z),
                Double3(rawBlue.x, rawBlue.y, rawBlue.z),
            )
        val theRHS = Double3(white.X, white.Y, white.Z)
        val theMultiples = theMatrix.inverse * theRHS

        red = GeometryGamesTristimulus(chromaticity = rawRed, multiple = theMultiples[0])
        green = GeometryGamesTristimulus(chromaticity = rawGreen, multiple = theMultiples[1])
        blue = GeometryGamesTristimulus(chromaticity = rawBlue, multiple = theMultiples[2])
    }

    fun colorSpaceToXYZ(): Double3x3 {

        return Double3x3(
            Double3(red.X, red.Y, red.Z),
            Double3(green.X, green.Y, green.Z),
            Double3(blue.X, blue.Y, blue.Z),
        )
    }
}

// MARK: -
// MARK: sRGB and P3 gamuts

//	sRGB gamut from
//
//		https://en.wikipedia.org/wiki/SRGB#The_sRGB_gamut
//
val gColorProfileSRGB =
    GeometryGamesColorProfile(
        //	exact numbers, by definition (I hope!)
        rawRed = GeometryGamesChromaticity(x = 0.64, y = 0.33),
        rawGreen = GeometryGamesChromaticity(x = 0.30, y = 0.60),
        rawBlue = GeometryGamesChromaticity(x = 0.15, y = 0.06),
        rawWhite = GeometryGamesChromaticity(x = 0.3127, y = 0.3290),
    )

//	P3 gamut from
//
//		https://en.wikipedia.org/wiki/DCI-P3#System_colorimetry
//
val gColorProfileDisplayP3 =
    GeometryGamesColorProfile(
        rawRed = GeometryGamesChromaticity(x = 0.680, y = 0.320),
        rawGreen = GeometryGamesChromaticity(x = 0.265, y = 0.690),
        rawBlue = GeometryGamesChromaticity(x = 0.150, y = 0.060), // 	same blue  as in sRGB
        rawWhite = GeometryGamesChromaticity(x = 0.3127, y = 0.3290),
    ) //	same white as in sRGB

// MARK: -
// MARK: sRGB <-> P3 conversion

fun colorConversionMatrix(
    from: GeometryGamesColorProfile,
    to: GeometryGamesColorProfile,
): Double3x3 {
    val profileA = from
    val profileB = to

    //	Each color profile defines the transformation matrix
    //	from its color space to CIE XYZ coordinates.
    //
    //	A-to-XYZ
    //		( A.red.X, A.green.X, A.blue.X )
    //		( A.red.Y, A.green.Y, A.blue.Y )
    //		( A.red.Z, A.green.Z, A.blue.Z )
    //
    //	B-to-XYZ
    //		( B.red.X, B.green.X, B.blue.X )
    //		( B.red.Y, B.green.Y, B.blue.Y )
    //		( B.red.Z, B.green.Z, B.blue.Z )
    //
    //	In the matrix equation
    //
    //		(  A  )   (  B  )(  A   )
    //		( to  ) = ( to  )(  to  )
    //		( XYZ )   ( XYZ )(  B   )
    //
    //	we know sRGB-to-XYZ and P3-to-XYZ,
    //	so we may solve for P3-to-sRGB.

    val AtoXYZ = profileA.colorSpaceToXYZ()
    val BtoXYZ = profileB.colorSpaceToXYZ()
    val AtoB = BtoXYZ.inverse * AtoXYZ

    return AtoB
}

//	The following matrices serve to convert between Linear sRGB
//	and Linear Display P3.  Although it would work fine to simply
//	hard code these two matrices, for future reference and flexibility
//	I'm including the code that produces these matrices, and indeed
//	am letting that code re-create the matrices each time the app is run.
//
//		gP3toSRGB = simd_double3x3(
//			SIMD3<Double>( 1.22494017628056, -0.04205695470969, -0.01963755459033),
//			SIMD3<Double>(-0.22494017628056,  1.04205695470969, -0.07863604555063),
//			SIMD3<Double>( 0.00000000000000,  0.00000000000000,  1.09827360014097)
//		)
//
//		gSRGBtoP3 = simd_double3x3(
//			SIMD3<Double>( 0.82246196871436,  0.03319419885096,  0.01708263072112),
//			SIMD3<Double>( 0.17753803128564,  0.96680580114904,  0.07239744066396),
//			SIMD3<Double>( 0.00000000000000,  0.00000000000000,  0.91051992861492)
//		)
//
//	Those matrices also agree with the values one gets by letting
//	Core Graphics do the conversions (using CGColors and CGColorSpaces).
//	Well, they agree to ~4 decimal places, which I'm guessing is
//	all the precision that Core Graphics keeps for color components,
//	because in practice that's all that's needed.
//
val gP3toSRGB = colorConversionMatrix(from = gColorProfileDisplayP3, to = gColorProfileSRGB)
val gSRGBtoP3 = colorConversionMatrix(from = gColorProfileSRGB, to = gColorProfileDisplayP3)
