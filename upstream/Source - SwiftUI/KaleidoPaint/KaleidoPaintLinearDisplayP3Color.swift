//	KaleidoPaintLinearDisplayP3Color.swift
//
//	© 2026 by Jeff Weeks
//	See TermsOfUse.txt

import SwiftUI


struct LinearDisplayP3Color: Hashable {

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
	//
	var	r: Double	//	(αR, αG, αB, α), with α = 1
	var	g: Double	//	Linear Display P3 color space (see comment immediately above)
	var	b: Double
	var	a: Double	//	= 1
	
	init(
		r: Double,
		g: Double,
		b: Double,
		a: Double
	) {
		self.r = r
		self.g = g
		self.b = b
		self.a = a
	}
	
	init?(fromSwiftUIColor color: Color) {
	
		//	Note:  I've include lots of error checking --
		//	perhaps way more than's needed -- but I just
		//	wanted to make sure that the conversion
		//	goes as expected.
		
		let theCGColor = color.cgColor ?? CGColor.init(
							red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0)

		//	Prepare a linear P3 color space
		guard let theLinearP3ColorSpace = CGColorSpace(
				name: CGColorSpace.extendedLinearDisplayP3) else {
			assertionFailure("Failed to create extendedLinearDisplayP3")
			return nil
		}
		
		//	theCGColor could be using any color space internally.
		//	Convert it to a CGColor that uses the linear P3 color space.
		guard let theLinearP3CGColor = theCGColor.converted(
		
				to: theLinearP3ColorSpace,
				
					//	Setting absoluteColorimetric sometimes gives an undesirable result.
					//	It sends
					//
					//		Color(.displayP3, red: 1.0, green: 1.0, blue: 1.0)
					//	to
					//		LinearDisplayP3(1.0, 1.0, 1.0)
					//
					//	as desired, but it sends
					//
					//		Color.white
					//	to
					//		LinearDisplayP3(0.8619166016578674 1.0 1.0)
					//
					//	By contrast, setting relativeColorimetric send both
					//
					//		Color(.displayP3, red: 1.0, green: 1.0, blue: 1.0)
					//	  and
					//		Color.white
					//	to
					//		LinearDisplayP3(1.0, 1.0, 1.0)
					//
					//	Apple's documentation says that
					//
					//		relativeColorimetric
					//			The relative colorimetric shifts all colors
					//			(including those within the gamut) to account
					//			for the difference between the white point
					//			of the graphics context and the white point
					//			of the output device.
					//
					//		absoluteColorimetric
					//			absolute colorimetric does not modify colors
					//			inside the gamut of the output device.
					//
					//	where, in the present context,
					//		"the graphics context" = theCGColor
					//		"the output device" = theLinearP3ColorSpace
					//
					//	My unconfirmed, but perhaps nevertheless correct,
					//	interpretation of what's going on is that Color.white
					//	is based on a color space with a different white point,
					//	and relativeColorimetric is needed to adjust colors
					//	to the linear Display P3 white point.  At first
					//	I thought this might be related to iOS's True Tone
					//	and/or Night Shift features, but those features are
					//	both disabled on my iPhone.  In any case, Color.white
					//	isn't well defined:  Apple's documentation says only
					//	that it's "a white color suitable for use in UI elements".
					//
					//
					//	A further curiosity is that absoluteColorimetric
					//	converts theCGColor = ExtendedSRGB( 1 1 1 1 ) to
					//	theLinearP3CGColor = LinearExtendedDisplayP3( 0.861917 1.01581 1.33586 1 ),
					//	which would see to be "brighter than the maximum".
					//	The bigger problem, though, is that even with
					//	the calls to clampToZeroOne() suppressed,
					//	when that extended range color gets converted
					//	at render time (using this same function we're in now),
					//	the conversion
					//
					//		let theUIColor = UIColor(color)
					//
					//	takes
					//
					//		color = DisplayP3(
					//			red: 0.9366604171605396,
					//			green: 1.006918761658408,
					//			blue: 1.135289442245407,
					//			opacity: 1.0)
					//	to
					//		theUIColor = (kCGColorSpaceModelRGB 0.93666 1 1 1)
					//
					//	with its green and blue components clipped.
					//
					//
					//	Solution:  I changed absoluteColorimetric to relativeColorimetric.
					//
				intent: CGColorRenderingIntent.relativeColorimetric,
				options: nil) else {
			assertionFailure("failed to convert to theLinearP3CGColor")
			return nil
		}
		if theLinearP3CGColor.numberOfComponents != 4 {
			assertionFailure("theLinearP3CGColor has the wrong number of components")
			return nil
		}
		if theLinearP3CGColor.colorSpace?.name != CGColorSpace.extendedLinearDisplayP3 {
			assertionFailure("theLinearP3CGColor isn't based on extendedLinearDisplayP3")
			return nil
		}
		
		//	Extract theLinearP3CGColor's components as an array of CGFloats
		guard let theLinearP3ColorComponents = theLinearP3CGColor.components else {
			assertionFailure("failed to retrieve the components of theLinearP3ColorComponents")
			return nil
		}
		if theLinearP3ColorComponents.count != 4 {
			assertionFailure("theLinearP3ColorComponents has unexpected length")
			return nil
		}
		
		//	Use theLinearP3ColorComponents to initialize this LinearDisplayP3Color.
		self.r = clampToZeroOne(theLinearP3ColorComponents[0])
		self.g = clampToZeroOne(theLinearP3ColorComponents[1])
		self.b = clampToZeroOne(theLinearP3ColorComponents[2])
		self.a = 1.0	//	= clampToZeroOne(theLinearP3ColorComponents[3])
	}
	
	func asSIMDHalf() -> SIMD4<Float16> {

		return SIMD4<Float16>(
			Float16(r),
			Float16(g),
			Float16(b),
			Float16(a)
		)
	}

	func asSwiftUIColor() -> Color {

		//	If the SwiftUI Color struct someday supports linearDisplayP3,
		//	then we won't need to gammaEncode the color components here.
		return Color(
			.displayP3,	//	with sRGB transfer function, not linear transfer function
			red:   gammaEncode(r),
			green: gammaEncode(g),
			blue:  gammaEncode(b),
			opacity: a)	//	alpha is never gamma-encoded
	}
	
	func isAlmostTheSameAs(
		_ otherColor: LinearDisplayP3Color
	) -> Bool {
	
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
		
		return (
			abs(self.r - otherColor.r) < 0.01
		 && abs(self.g - otherColor.g) < 0.01
		 && abs(self.b - otherColor.b) < 0.01
		 && abs(self.a - otherColor.a) < 0.01 )
	}
}

func clampToZeroOne(
	_ x: Double
) -> Double {

	if x < 0.0 {
		return 0.0
	}
	if x > 1.0 {
		return 1.0
	}
	return x
}

func gammaEncode(
	_ linearValue: Double
) -> Double {	//	returns gamma-encoded value (using sRGB transfer function)

	//	The encoding curve for negative values is
	//	symmetrical with the curve for positive values.
	//
	if linearValue < 0.0 {
		return -gammaEncode( -linearValue )
	}
	
	//	The sRGB transfer function begins with a short linear segment
	//	(to avoid an infinite slope near zero), followed by a gamma curve
	//	with power 1/2.4 thereafter.  The overall curve closely follows
	//	a traditional gamma curve (with no linear segment) with power 1/2.2.
	//
	//	My understanding is that the following numerical values are exact
	//	(defined in the IEC standard), they're not approximations.
	//
	let theGammaEncodedValue = (
		linearValue < 0.0031308 ?
			12.92 * linearValue :
			1.055 * pow(linearValue, 1.0/2.4) - 0.055
	)

	return theGammaEncodedValue
}

func gammaDecode(
	_ gammaEncodedValue: Double	//	encoded using sRGB transfer function
) -> Double {	//	returns linear value

	//	The decoding curve for negative values is
	//	symmetrical with the curve for positive values.
	//
	if gammaEncodedValue < 0.0 {
		return -gammaDecode( -gammaEncodedValue )
	}

	//	The sRGB transfer function begins with a short linear segment
	//	(to avoid zero slope near zero), followed by a gamma curve
	//	with power 2.4 thereafter.  The overall curve closely follows
	//	a traditional gamma curve (with no linear segment) with power 2.2.
	//
	//	My understanding is that the following numerical values are exact
	//	(defined in the IEC standard), they're not approximations.
	//
	let theLinearValue = (
		gammaEncodedValue < 0.04045 ?
			(1.0 / 12.92) * gammaEncodedValue :
			pow((1.0/1.055) * gammaEncodedValue + (0.055/1.055), 2.4)
	)

	return theLinearValue
}
