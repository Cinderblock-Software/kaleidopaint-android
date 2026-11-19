// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
//
//	Reference drawings and reference values for the file format.
//
//	Upstream's own KaleidoPaintDocument builds the drawings, writes them
//	with encodeFileFormat() and reads them back with decodeFileFormat().
//	The Kotlin twin is the second half of ReferenceScenario.kt.

import Foundation
import simd


// MARK: -
// MARK: Files

//	Where the drawings get written, and where the hand-built
//	legacy drawings are read from.  Set in main.swift.
var gDrawingsDirectory = URL(fileURLWithPath: ".")
var gLegacyDirectory = URL(fileURLWithPath: ".")

func writeDrawing(_ fileName: String, _ text: String) {
	//	The same conversion as KaleidoPaintDocument.fileWrapper(snapshot:configuration:).
	let theData = text.data(using: .utf8)!
	try! theData.write(to: gDrawingsDirectory.appendingPathComponent(fileName))
}

func newDocument() -> KaleidoPaintDocument {
	let theDocument = KaleidoPaintDocument()
	//	Without an undo manager the document ignores every edit.
	theDocument.itsUndoManager = UndoManager()
	return theDocument
}


// MARK: -
// MARK: Document state

func emitColor(_ key: String, _ color: LinearDisplayP3Color) {
	emit(key, doubles: [color.r, color.g, color.b, color.a])
}

func emitDocument(_ key: String, _ document: KaleidoPaintDocument) {

	emit("\(key).wallpaperGroup", string: document.itsWallpaperGroup.rawValue)
	emitPlacement("\(key).placement", document.itsUnitCellPlacement)
	emitColor("\(key).backgroundColor", document.itsBackgroundColor)
	emitColor("\(key).brushColor", document.itsBrushColor)
	emitColor("\(key).fillColor", document.itsFillColor)
	emit("\(key).brushThickness", double: document.itsBrushThickness)
	emit("\(key).smoothingTolerance", double: document.itsSmoothingTolerance)
	emit("\(key).flags", ints: [
		document.itsShowSingularitiesFlag ? 1 : 0,
		document.itsColorBySymmetryFlag ? 1 : 0,
		document.itsContentIsLocked ? 1 : 0])

	emit("\(key).elementCount", int: document.itsElements.count)
	for (i, theElement) in document.itsElements.enumerated() {

		let k = "\(key).element.\(i)"
		emitColor("\(k).color", theElement.itsColor)

		if let theDot = theElement as? Dot {
			emit("\(k).kind", string: "dot")
			emit("\(k).center", vector: theDot.itsCenter)
			emit("\(k).thickness", double: theDot.itsThickness)
		}
		if let theCurve = theElement as? Curve {
			emit("\(k).kind", string: "curve")
			emit("\(k).thickness", double: theCurve.itsThickness)
			emitSpline("\(k).spline", theCurve.itsSpline)
		}
		if let theFill = theElement as? Fill {
			emit("\(k).kind", string: "fill")
			emit("\(k).fillPoint", vector: theFill.itsFillPoint)
		}
	}
}

//	Write the drawing, read it back, and record what was read
//	and whether writing it again gives the same text.
func writeAndReadBack(_ name: String, _ document: KaleidoPaintDocument) {

	let theText = document.encodeFileFormat()
	writeDrawing("\(name).kaleidopaint", theText)
	readBack(name, theText)
}

func readBack(_ name: String, _ text: String) {

	let theDecodedDocument = newDocument()
	do {
		try theDecodedDocument.decodeFileFormat(text)
	} catch {
		fatalError("upstream could not read back \(name): \(error)")
	}
	emitDocument("document.\(name)", theDecodedDocument)

	//	A drawing may change when it is read (old formats get converted,
	//	curves get re-centred, numbers were rounded when written),
	//	so what gets written the second time is recorded too.
	let theSecondText = theDecodedDocument.encodeFileFormat()
	writeDrawing("\(name).rewritten.kaleidopaint", theSecondText)
}


// MARK: -
// MARK: Drawings built in memory

func copyOfSpline(_ name: String) -> CubicSpline {
	let theSpline = namedSplines().first(where: { $0.0 == name })!.1
	theSpline.refreshParameterization()
	return theSpline
}

//	One drawing for each wallpaper group, with every kind of element.
func makeGroupDocument(_ index: Int, _ group: WallpaperGroup) -> KaleidoPaintDocument {

	let theDocument = newDocument()
	let f = Double(index) / 16.0

	theDocument.itsWallpaperGroup = group

	var thePlacement = UnitCellPlacement(defaultForWallpaperGroup: group)
	thePlacement.transform(using: similarity(
		cosθ: gCos02,
		sinθ: gSin02,
		scale: 1.0 + 0.0625 * Double(index),
		translation: SIMD2<Double>(0.01 * Double(index), -0.02 * Double(index))))
	theDocument.itsUnitCellPlacement = thePlacement

	theDocument.itsBackgroundColor = LinearDisplayP3Color(r: f, g: 1.0 - f, b: 0.5, a: 1.0)
	theDocument.itsBrushColor = LinearDisplayP3Color(r: 1.0 - f, g: 0.25, b: f, a: 1.0)
	theDocument.itsFillColor = LinearDisplayP3Color(r: 0.125, g: f, b: 1.0 - 0.5 * f, a: 1.0)
	theDocument.itsBrushThickness = gDefaultThickness / sqrt(Double(group.torusGroup.itsElements.count))
	theDocument.itsSmoothingTolerance = 0.002 + 0.001 * Double(index)
	theDocument.itsShowSingularitiesFlag = (index % 2 == 0)
	theDocument.itsColorBySymmetryFlag = (index % 3 == 0)
	theDocument.itsContentIsLocked = (index % 5 == 0)

	theDocument.itsElements.append(Dot(
		color: LinearDisplayP3Color(r: 1.0, g: f, b: 0.0, a: 1.0),
		center: SIMD2<Double>(0.3 + 0.01 * Double(index), 0.2),
		thickness: 0.02))

	let theSplineNames = ["two", "three", "wave", "corners", "coincident", "far", "halves", "long"]
	let theCurve = Curve(
		color: LinearDisplayP3Color(r: 0.0, g: 0.5, b: f, a: 1.0),
		thickness: 0.01 + 0.001 * Double(index))
	theCurve.itsSpline = copyOfSpline(theSplineNames[index % theSplineNames.count])
	theDocument.itsElements.append(theCurve)

	theDocument.itsElements.append(Fill(
		color: LinearDisplayP3Color(r: f, g: f, b: 1.0, a: 1.0),
		fillPoint: SIMD2<Double>(0.6, 0.4 + 0.01 * Double(index))))

	theDocument.itsElements.append(Dot(
		color: LinearDisplayP3Color(r: 0.2, g: 0.4, b: 0.6, a: 1.0),
		center: SIMD2<Double>(1.0 / 3.0, 2.0 / 3.0),
		thickness: 1.0 / 64.0))

	let theSecondCurve = Curve(
		color: LinearDisplayP3Color(r: 1.0 / 3.0, g: 2.0 / 3.0, b: 1.0 / 7.0, a: 1.0),
		thickness: 1.0 / 96.0)
	theSecondCurve.itsSpline = copyOfSpline("corners")
	theDocument.itsElements.append(theSecondCurve)

	return theDocument
}

//	Numbers that sit exactly half way between two printed values,
//	numbers that round to a negative zero, and numbers too wide for their field.
func makeRoundingDocument() -> KaleidoPaintDocument {

	let theDocument = newDocument()

	let a = 1.0 / 512.0		//	0.001953125 : half way, at 8 decimal places
	let b = 1.0 / 131072.0	//	0.00000762939453125 : half way, at 16 decimal places

	theDocument.itsBackgroundColor = LinearDisplayP3Color(r: a, g: 3.0 * a, b: 5.0 * a, a: 1.0)
	theDocument.itsBrushColor = LinearDisplayP3Color(r: -a, g: -3.0 * a, b: 1.0 - a, a: 1.0)
	theDocument.itsFillColor = LinearDisplayP3Color(r: -1e-10, g: -0.0, b: 1234.5, a: 1.0)
	theDocument.itsBrushThickness = b
	theDocument.itsSmoothingTolerance = 3.0 * b

	var thePlacement = UnitCellPlacement(defaultForWallpaperGroup: .wpgO)
	thePlacement.itsTranslations = simd_double2x2(
		SIMD2<Double>(0.25 + b, -1e-18),
		SIMD2<Double>(-0.0, 0.25 + 3.0 * b)
	)
	thePlacement.itsCorner = SIMD2<Double>(-5.0 * b, 123456.789)
	theDocument.itsUnitCellPlacement = thePlacement

	theDocument.itsElements.append(Dot(
		color: LinearDisplayP3Color(r: 7.0 * a, g: 0.5, b: 9.0 * a, a: 1.0),
		center: SIMD2<Double>(b, 7.0 * b),
		thickness: 9.0 * b))

	let theCurve = Curve(
		color: LinearDisplayP3Color(r: 0.0, g: 0.0, b: 0.0, a: 1.0),
		thickness: 11.0 * b)
	for (x, y, type) in [
		(a, 3.0 * a, SplineNodeType.corner),
		(0.25 + 5.0 * a, 0.5 - a, SplineNodeType.smooth),
		(0.5 - 1e-10, 0.75 + 7.0 * a, SplineNodeType.smooth),
		(0.75, 1.0 - 1e-12, SplineNodeType.corner)] {
		theCurve.itsSpline.append(SplineNode(location: SIMD2<Double>(x, y), type: type))
	}
	theCurve.itsSpline.refreshParameterization()
	theDocument.itsElements.append(theCurve)

	theDocument.itsElements.append(Fill(
		color: LinearDisplayP3Color(r: 1.0, g: 1.0, b: 1.0, a: 1.0),
		fillPoint: SIMD2<Double>(-b, 1.0 + b)))

	return theDocument
}

//	A drawing made the way a finger makes one:  two strokes and two taps,
//	sent through the document's own touch handling, which smooths
//	each stroke into a few spline nodes.
func makeTouchDrawnDocument(_ name: String, _ group: WallpaperGroup) -> KaleidoPaintDocument {

	let theDocument = newDocument()
	theDocument.itsWallpaperGroup = group
	theDocument.itsUnitCellPlacement = UnitCellPlacement(defaultForWallpaperGroup: group)

	let theWidth = 1080.0
	let theHeight = 2400.0
	func point(_ x: Double, _ y: Double) -> DisplayPoint {
		return DisplayPoint(x: x, y: y, viewWidth: theWidth, viewHeight: theHeight)
	}

	//	A wobbly arch.
	var theArch = [point(300.0, 1200.0)]
	for k in 1 ... 60 {
		let x = 300.0 + 8.0 * Double(k)
		let y = 1200.0 + 0.25 * Double(k * (60 - k)) + 1.5 * Double((k * 37) % 11)
		theArch.append(point(x, y))
	}
	drawStroke(theDocument, "document.\(name).stroke.arch", theArch)

	theDocument.singleTapForDrawing(at: point(540.0, 1500.0))

	//	A zigzag with sharp turns.
	theDocument.itsBrushColor = LinearDisplayP3Color(r: 0.0, g: 0.5, b: 0.25, a: 1.0)
	theDocument.itsBrushThickness *= 2.0
	var theZigzag = [point(200.0, 900.0)]
	for k in 1 ... 80 {
		let x = 200.0 + 6.0 * Double(k)
		let theTooth = k % 20
		let y = 900.0 + 9.0 * Double(theTooth < 10 ? theTooth : 20 - theTooth)
		theZigzag.append(point(x, y))
	}
	drawStroke(theDocument, "document.\(name).stroke.zigzag", theZigzag)

	theDocument.singleTapForDrawing(at: point(123.0, 456.0))

	return theDocument
}

func emitDrawings() {

	//	A new, empty drawing, exactly as the app creates it.
	UserDefaults.standard.removeObject(forKey: "default symmetry group")
	writeAndReadBack("empty", newDocument())

	for (i, theGroup) in WallpaperGroup.allCases.enumerated() {
		let theName = String(format: "group-%02d-", i) + theGroup.IUCName
		writeAndReadBack(theName, makeGroupDocument(i, theGroup))
	}

	writeAndReadBack("rounding", makeRoundingDocument())

	for (theName, theGroup) in [("touch-drawn-p1", WallpaperGroup.wpgO), ("touch-drawn-p6m", .wpgS632), ("touch-drawn-pgg", .wpg22X)] {
		let theDocument = makeTouchDrawnDocument(theName, theGroup)
		//	The drawing as it stands in memory, before it is written:
		//	the Kotlin port, given the same touches, must arrive at the same.
		emitDocument("document.\(theName).asDrawn", theDocument)
		writeAndReadBack(theName, theDocument)
	}

	//	The hand-built drawings in older file formats (tools/reference/legacy).
	let theLegacyNames = (try! FileManager.default.contentsOfDirectory(atPath: gLegacyDirectory.path))
		.filter { $0.hasSuffix(".kaleidopaint") }
		.sorted()
	emit("document.legacy.names", string: theLegacyNames.joined(separator: " "))
	for theFileName in theLegacyNames {
		let theData = try! Data(contentsOf: gLegacyDirectory.appendingPathComponent(theFileName))
		let theText = String(data: theData, encoding: .utf8)!
		let theName = "legacy-" + theFileName.replacingOccurrences(of: ".kaleidopaint", with: "")
		writeDrawing("\(theName).kaleidopaint", theText)
		readBack(theName, theText)
	}
}


// MARK: -
// MARK: Drawings from elsewhere

//	Drawings that are not part of this repository (real drawings made
//	with KaleidoPaint, fetched by tools/reference/fetch-public-drawings.sh).
//	Upstream reads each one and writes it again;  the results go
//	beside the drawings, for the Kotlin port to be compared with.
func emitExternalDrawings(_ directory: URL) {

	gDrawingsDirectory = directory

	let theFileNames = (try! FileManager.default.contentsOfDirectory(atPath: directory.path))
		.filter { $0.hasSuffix(".kaleidopaint") && !$0.hasSuffix(".rewritten.kaleidopaint") }
		.sorted()
	emit("external.names", string: theFileNames.joined(separator: "/"))

	for theFileName in theFileNames {

		let theData = try! Data(contentsOf: directory.appendingPathComponent(theFileName))
		guard let theText = String(data: theData, encoding: .utf8) else {
			emit("external.\(theFileName).result", string: "not UTF-8")
			continue
		}

		let theResult = decodingResult(theText)
		emit("external.\(theFileName).result", string: theResult)
		if theResult != "accepted" {
			continue
		}

		let theDocument = newDocument()
		try! theDocument.decodeFileFormat(theText)
		emitDocument("external.\(theFileName)", theDocument)

		let theName = theFileName.replacingOccurrences(of: ".kaleidopaint", with: "")
		writeDrawing("\(theName).rewritten.kaleidopaint", theDocument.encodeFileFormat())
	}
}


// MARK: -
// MARK: Files that must be refused

//	Each case changes one thing in a valid drawing.  Every case must reach
//	one of decodeFileFormat()'s own error messages:  upstream stops with
//	an array-index trap if a file simply runs out of tokens, so no case here
//	shortens the file below what the decoder reads before it complains.
let gMalformedCases: [(String, String, String)] = [
	("valid", "", ""),
	("header-word", "KaleidoPaint Drawing", "KaleidoPaint Painting"),
	("header-format", "format 1.10", "version 1.10"),
	("major-unparsable", "format 1.10", "format one.10"),
	("minor-unparsable", "format 1.10", "format 1.ten"),
	("minor-negative", "format 1.10", "format 1.-3"),
	("minor-from-the-future", "format 1.10", "format 1.99"),
	("major-from-the-future", "format 1.10", "format 7.10"),
	("wallpaper-group-label", "wallpaper group", "wallpaper troupe"),
	("wallpaper-group-name", "wallpaper group ××", "wallpaper group *532"),
	("placement-label", "unit cell placement", "unit cell position"),
	("placement-number", "0.2165063509461097", "0.21650635O9461097"),
	("resolution-label", "log2 unit cell resolution", "log3 unit cell resolution"),
	("resolution-not-a-number", "log2 unit cell resolution 11", "log2 unit cell resolution eleven"),
	("background-label", "background color", "backdrop color"),
	("background-number", "background color 0.9", "background color 0,9"),
	("background-opacity", "background color 0.9 0.5 0.25 1.0", "background color 0.9 0.5 0.25 0.5"),
	("brush-color-label", "brush color", "brush colour"),
	("fill-color-label", "fill color", "fill colour"),
	("brush-thickness-label", "brush thickness", "brush width"),
	("brush-thickness-number", "brush thickness  0.0078125", "brush thickness  thin"),
	("smoothing-label", "smoothing tolerance", "smoothing strength"),
	("smoothing-factor", "smoothing tolerance", "smoothing factor"),
	("smoothing-number", "smoothing tolerance  0.0125", "smoothing tolerance  lots"),
	("singularities-label", "show singularities", "hide singularities"),
	("singularities-value", "show singularities false", "show singularities no"),
	("symmetry-label", "color by symmetry", "color by number"),
	("symmetry-value", "color by symmetry  true", "color by symmetry  yes"),
	("locked-label", "content is locked", "content is frozen"),
	("locked-value", "content is locked  true", "content is locked  True"),
	("elements-label", "\nelements\n", "\nelemenTs\n"),
	("no-more-elements", "no-more-elements", "no-more-elements please"),
	("element-kind", "\nfill\n", "\nblob\n"),
	("dot-property", "\tdiameter  0.015625", "\tradius  0.015625"),
	("dot-center", "\tcenter    0.3125 0.71875", "\tcenter    0.3125 north"),
	("dot-diameter", "\tdiameter  0.015625", "\tdiameter  wide"),
	("dot-old-names", "\tcenter    0.3125 0.71875\n\tdiameter  0.015625", "\tlocation  0.3125 0.71875\n\tthickness 0.015625"),
	("dot-color-opacity", "\tcolor     1.0 0.5 0.0 1.0", "\tcolor     1.0 0.5 0.0 0.99"),
	("curve-property", "\tthickness 0.01171875", "\twidth 0.01171875"),
	("curve-thickness", "\tthickness 0.01171875", "\tthickness thick"),
	("curve-node-number", "\tnode      2.25 -1.5   smooth", "\tnode      2.25 x   smooth"),
	("curve-node-type", "\tnode      2.25 -1.5   smooth", "\tnode      2.25 -1.5   wavy"),
	("fill-property", "\tfillPoint 0.6 0.4", "\tfillpoint 0.6 0.4"),
	("fill-point", "\tfillPoint 0.6 0.4", "\tfillPoint 0.6 0..4"),
	("fill-old-name", "\tfillPoint 0.6 0.4", "\tlocation 0.6 0.4"),
]

//	Files too short to be drawings at all.
let gShortCases: [(String, String)] = [
	("empty-file", ""),
	("three-tokens", "KaleidoPaint Drawing format"),
	("header-only", "KaleidoPaint Drawing\nformat 1.10\n"),
	("forty-three-tokens", "KaleidoPaint Drawing format 1.7 wallpaper group 2222 unit cell placement 0 0 1 0 0 1 background color 1 1 1 1 brush color 0 0 0 1 brush thickness 0.01 show singularities true color by symmetry false content is locked false elements"),
	("forty-seven-tokens-old-format", "KaleidoPaint Drawing format 1.4 wallpaper group 1 unit cell placement 0 0 1 0 0 1 background color 1 1 1 1 | 1 brush color 0 0 0 1 | 1 brush thickness 0.01 show singularities true color by symmetry false content is locked false elements"),
]

func decodingResult(_ text: String) -> String {
	let theDocument = newDocument()
	do {
		try theDocument.decodeFileFormat(text)
		return "accepted"
	} catch KaleidoPaintDocument.KaleidoPaintFileEncodingError.fileFormatError(let theReason) {
		return theReason
	} catch {
		return "some other error"
	}
}

func emitMalformedDrawings() {

	//	The valid drawing that the cases start from.
	let theBaseData = try! Data(contentsOf: gLegacyDirectory.appendingPathComponent("whitespace.kaleidopaint"))
	let theBaseText = String(data: theBaseData, encoding: .utf8)!
		.replacingOccurrences(of: "\r\n", with: "\n")
		.replacingOccurrences(of: "\u{00A0}", with: " ")
		.replacingOccurrences(of: "\u{3000}", with: "  ")

	for (theName, theOld, theNew) in gMalformedCases {
		precondition(theOld.isEmpty || theBaseText.contains(theOld), "case \(theName) changes nothing")
		let theText = theOld.isEmpty ? theBaseText : theBaseText.replacingOccurrences(of: theOld, with: theNew)
		emit("malformed.\(theName)", string: decodingResult(theText))
	}
	for (theName, theText) in gShortCases {
		emit("malformed.\(theName)", string: decodingResult(theText))
	}
}


// MARK: -
// MARK: How Swift reads numbers

//	decodeFileFormat() reads its numbers with Double(String) and Int(String).
//	What those accept is part of the file format, so write it down.
let gNumberStrings = [
	"1", "1.", ".5", "+1.5", "-0.0", "-.5", "1e5", "1E-3", "1e+2", "1.5e", "e5",
	"inf", "-inf", "+inf", "infinity", "Infinity", "INF", "nan", "NaN", "-nan", "nan(1)",
	"0x1p3", "0x10", "0X1.8p1", "1.5f", "1.5d", "1,5", "1_000", "--1", "1.2.3", "0.1.",
	"", ".", "+", "-", "1-", "１", "٣", "1e400", "-1e400", "1e-400", "0.1e1",
	"00012.50", "+.5e-1", "1 ", " 1", "1\t", "0b101", "1/2", "∞",
]
let gIntegerStrings = [
	"5", "+5", "-5", "05", "5.0", "", "0x10", "1e3", "９", "5 ", " 5", "+", "-", "--5",
	"9223372036854775807", "9223372036854775808", "-9223372036854775808", "1_000", "٣",
]

func emitNumberParsing() {
	for (i, theString) in gNumberStrings.enumerated() {
		if let theValue = Double(theString) {
			emit("numbers.double.\(i)", doubles: [theValue])
		} else {
			emit("numbers.double.\(i)", string: "nil")
		}
	}
	for (i, theString) in gIntegerStrings.enumerated() {
		if let theValue = Int(theString) {
			emit("numbers.integer.\(i)", string: "\(theValue)")
		} else {
			emit("numbers.integer.\(i)", string: "nil")
		}
	}
}
