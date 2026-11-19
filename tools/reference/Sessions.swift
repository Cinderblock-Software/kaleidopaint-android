// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
//
//	Reference values for editing a drawing:  strokes, taps, drags,
//	every undoable operation, and then undoing and redoing all of it.
//
//	Upstream's own KaleidoPaintDocument does the work.
//	The Kotlin twin is in ReferenceScenario.kt.

import Foundation
import simd
import SwiftUI


// MARK: -
// MARK: Strokes

//	Send one stroke through the document's touch handling.
//
//	Just before the finger lifts, write down which basepoints are still valid
//	and which one the document is about to choose.  That choice is whichever
//	element Swift's Set lists first, an accident of hashing, so the Kotlin twin
//	is told which one it was and checks only that it was a valid one.
func drawStroke(
	_ document: KaleidoPaintDocument,
	_ key: String,
	_ points: [DisplayPoint]
) {
	document.touchBegan(at: points[0])
	for thePoint in points.dropFirst() {
		document.touchMoved(to: thePoint)
	}

	let theBasepoints = Array(document.itsCurveInProgressValidBasepoints)
		.sorted { ($0[0], $0[1]) < ($1[0], $1[1]) }
	emit("\(key).basepoints", ints: theBasepoints.flatMap { [$0[0], $0[1]] })
	if let theChosenBasepoint = document.itsCurveInProgressValidBasepoints.first {
		emit("\(key).chosen", ints: [theChosenBasepoint[0], theChosenBasepoint[1]])
	} else {
		emit("\(key).chosen", ints: [])
	}
	emit("\(key).rawNodeCount", int: document.itsCurveInProgress?.itsSpline.itsNodes.count ?? 0)

	document.touchEnded()
}


// MARK: -
// MARK: A compact picture of a document

func emitSessionState(_ key: String, _ document: KaleidoPaintDocument) {

	emit("\(key).group", string: document.itsWallpaperGroup.rawValue)
	emit("\(key).placement", doubles: [
		document.itsUnitCellPlacement.itsCorner[0],
		document.itsUnitCellPlacement.itsCorner[1],
		document.itsUnitCellPlacement.itsTranslations[0][0],
		document.itsUnitCellPlacement.itsTranslations[0][1],
		document.itsUnitCellPlacement.itsTranslations[1][0],
		document.itsUnitCellPlacement.itsTranslations[1][1]])
	emit("\(key).colors", doubles: [
		document.itsBackgroundColor.r, document.itsBackgroundColor.g, document.itsBackgroundColor.b,
		document.itsBrushColor.r, document.itsBrushColor.g, document.itsBrushColor.b,
		document.itsFillColor.r, document.itsFillColor.g, document.itsFillColor.b])
	emit("\(key).brush", doubles: [document.itsBrushThickness, document.itsSmoothingTolerance])

	let theShape = document.getUnitCellShape()
	emit("\(key).shape", doubles: [theShape.aspectRatio, theShape.shear])
	emit("\(key).fillMarkerRadius", double: document.fillMarkerRadius())

	emit("\(key).counts", ints: [
		Int(document.changeCount),
		document.itsBaseDrawingTextureFullRedrawRequestCount,
		document.itsBaseDrawingTextureLastElementRequestCount,
		document.itsCurveInProgressTextureRedrawRequestCount,
		document.itsSingularitiesTextureRedrawRequestCount,
		document.itsCompositeTextureRedrawRequestCount,
		document.itsUndoRedoCount])
	emit("\(key).flags", ints: [
		document.itsUndoManager!.canUndo ? 1 : 0,
		document.itsUndoManager!.canRedo ? 1 : 0,
		document.itsCurveInProgress != nil ? 1 : 0,
		document.itsControlHandleHit != nil ? 1 : 0,
		document.itsContentIsLocked ? 1 : 0,
		document.itsTouchMode == .edit ? 1 : 0])

	emit("\(key).elementCount", int: document.itsElements.count)
	for (i, theElement) in document.itsElements.enumerated() {

		var theNumbers = [theElement.itsColor.r, theElement.itsColor.g, theElement.itsColor.b]
		let theKind: String

		if let theDot = theElement as? Dot {
			theKind = "dot"
			theNumbers += [theDot.itsThickness, theDot.itsCenter[0], theDot.itsCenter[1]]
		} else if let theCurve = theElement as? Curve {
			theKind = "curve"
			theNumbers += [theCurve.itsThickness]
			for theNode in theCurve.itsSpline.itsNodes {
				theNumbers += [
					theNode.itsNodeLocation[0],
					theNode.itsNodeLocation[1],
					theNode.itsNodeType == .corner ? 1.0 : 0.0]
			}
		} else if let theFill = theElement as? Fill {
			theKind = "fill"
			theNumbers += [theFill.itsFillPoint[0], theFill.itsFillPoint[1]]
		} else {
			theKind = "unknown"
		}

		emit("\(key).element.\(i).kind", string: theKind)
		emit("\(key).element.\(i).numbers", doubles: theNumbers)
	}
}


// MARK: -
// MARK: An editing session

func emitEditingSession() {

	//	The running app starts new drawings in the group 632.
	UserDefaults.standard.set("632", forKey: "default symmetry group")
	let theDocument = KaleidoPaintDocument()
	UserDefaults.standard.removeObject(forKey: "default symmetry group")

	//	One undo step per user action:  no run loop is turning here
	//	to group them, so each action is bracketed by hand.
	let theUndoManager = UndoManager()
	theUndoManager.groupsByEvent = false
	theDocument.itsUndoManager = theUndoManager

	let theWidth = 1080.0
	let theHeight = 2400.0
	func point(_ x: Double, _ y: Double) -> DisplayPoint {
		return DisplayPoint(x: x, y: y, viewWidth: theWidth, viewHeight: theHeight)
	}
	func displayPoint(of unitCellPoint: SIMD2<Double>) -> DisplayPoint {
		return convertExtendedUnitCellCoordinatesToDisplayCoordinates(
			unitCellPoint,
			unitCellPlacement: theDocument.itsUnitCellPlacement,
			viewWidth: theWidth,
			viewHeight: theHeight)
	}

	var theStepNames: [String] = []
	func step(_ name: String, _ action: () -> Void) {
		theUndoManager.beginUndoGrouping()
		action()
		theUndoManager.endUndoGrouping()
		theStepNames.append(name)
		emitSessionState("session.\(theStepNames.count).\(name)", theDocument)
	}
	func drag(from start: DisplayPoint, by motions: [(Double, Double)]) {
		theDocument.touchBegan(at: start)
		for (dx, dy) in motions {
			theDocument.touchMoved(to: point(start.x + dx, start.y + dy))
		}
		theDocument.touchEnded()
	}

	emitSessionState("session.0.new", theDocument)

	//	In an empty drawing there are no control handles to drag or tap.
	//	(Once a drawing has a few curves, the images of their handles'
	//	generous touch targets cover the whole screen.)
	theDocument.itsTouchMode = .edit
	drag(from: point(500.0, 1000.0), by: [(1.0, 1.0), (20.0, 30.0)])
	var theEmptyEditorIsShown = true
	var theEmptyEditorAnchor = PopoverAttachmentAnchor.point(UnitPoint(x: -1.0, y: -1.0))
	theDocument.singleTapForEditing(
		at: point(500.0, 1000.0),
		editorIsShown: Binding(get: { theEmptyEditorIsShown }, set: { theEmptyEditorIsShown = $0 }),
		editorAnchor: Binding(get: { theEmptyEditorAnchor }, set: { theEmptyEditorAnchor = $0 }))
	emit("session.tap.nothing", ints: [theEmptyEditorIsShown ? 1 : 0, theDocument.itsControlHandleHit == nil ? 1 : 0])
	theDocument.itsTouchMode = .draw
	emitSessionState("session.0.nothingToEdit", theDocument)

	//	--- Drawing

	step("stroke-arch") {
		var thePoints = [point(310.0, 1210.0)]
		for k in 1 ... 60 {
			let x = 310.0 + 8.0 * Double(k)
			let y = 1210.0 + 0.25 * Double(k * (60 - k)) + 1.5 * Double((k * 37) % 11)
			thePoints.append(point(x, y))
		}
		drawStroke(theDocument, "session.stroke.arch", thePoints)
	}

	step("tap-dot") {
		theDocument.singleTapForDrawing(at: point(537.0, 1493.0))
	}

	theDocument.itsBrushColor = LinearDisplayP3Color(r: 0.0, g: 0.5, b: 0.25, a: 1.0)
	theDocument.itsBrushThickness *= 2.0
	step("stroke-zigzag") {
		var thePoints = [point(205.0, 905.0)]
		for k in 1 ... 80 {
			let x = 205.0 + 6.0 * Double(k)
			let theTooth = k % 20
			let y = 905.0 + 9.0 * Double(theTooth < 10 ? theTooth : 20 - theTooth)
			thePoints.append(point(x, y))
		}
		drawStroke(theDocument, "session.stroke.zigzag", thePoints)
	}

	step("double-tap-fill") {
		theDocument.doubleTapForDrawing(at: point(123.0, 456.0))
	}

	//	A stroke so long that it runs out of valid basepoints,
	//	after which the rest of it is ignored.
	//
	//	It bends a little on purpose.  Along a perfectly straight stroke
	//	every point is equally far from the line (not at all, give or take
	//	rounding), so which points the smoothing keeps comes down to
	//	the last bit of the arithmetic, where Swift and Kotlin differ.
	step("stroke-too-long") {
		var thePoints = [point(40.0, 300.0)]
		for k in 1 ... 120 {
			thePoints.append(point(40.0 + 8.5 * Double(k), 300.0 + 16.0 * Double(k) + 0.03125 * Double(k * k)))
		}
		drawStroke(theDocument, "session.stroke.tooLong", thePoints)
	}

	step("background-color") {
		theDocument.changeBackgroundColor(to: LinearDisplayP3Color(r: 0.9, g: 0.8, b: 0.1, a: 1.0))
	}

	//	A stroke abandoned half way leaves nothing behind and nothing to undo.
	theDocument.touchBegan(at: point(600.0, 600.0))
	theDocument.touchMoved(to: point(640.0, 660.0))
	emitSessionState("session.cancel.before", theDocument)
	theDocument.touchCancelled()
	emitSessionState("session.cancel.after", theDocument)

	//	--- Editing

	theDocument.itsTouchMode = .edit
	let theArch = theDocument.itsElements[0] as! Curve
	let theDot = theDocument.itsElements[1] as! Dot
	let theZigzag = theDocument.itsElements[2] as! Curve
	let theFill = theDocument.itsElements[3] as! Fill

	step("drag-dot") {
		drag(from: displayPoint(of: theDot.itsCenter), by: [(10.0, -6.0), (25.0, -20.0), (61.0, -47.0)])
	}

	step("drag-node") {
		let theNode = theArch.itsSpline.itsNodes[2]
		drag(from: displayPoint(of: theNode.itsNodeLocation), by: [(-8.0, 12.0), (-30.0, 44.0), (-52.0, 90.0)])
	}

	//	Drag an end node so far that the curve gets re-centred in the unit cell.
	step("drag-node-far") {
		let theNode = theZigzag.itsSpline.itsNodes[0]
		drag(from: displayPoint(of: theNode.itsNodeLocation), by: [(-100.0, 0.0), (-400.0, 10.0), (-800.0, 20.0)])
	}

	step("drag-fill") {
		drag(from: displayPoint(of: theFill.itsFillPoint), by: [(3.0, 3.0), (40.0, 77.0)])
	}

	//	A drag abandoned half way puts the handle back.
	theDocument.touchBegan(at: displayPoint(of: theDot.itsCenter))
	theDocument.touchMoved(to: point(900.0, 900.0))
	emitSessionState("session.editCancel.before", theDocument)
	theDocument.touchCancelled()
	emitSessionState("session.editCancel.after", theDocument)

	//	A tap on a node selects it and says where to put the Editor.
	let theTappedNode = theArch.itsSpline.itsNodes[1]
	let theTapPoint = displayPoint(of: theTappedNode.itsNodeLocation)
	var theEditorIsShown = false
	var theEditorAnchor = PopoverAttachmentAnchor.point(UnitPoint(x: -1.0, y: -1.0))
	theDocument.singleTapForEditing(
		at: theTapPoint,
		editorIsShown: Binding(get: { theEditorIsShown }, set: { theEditorIsShown = $0 }),
		editorAnchor: Binding(get: { theEditorAnchor }, set: { theEditorAnchor = $0 }))
	if case .point(let theUnitPoint) = theEditorAnchor, theEditorIsShown {
		emit("session.tap.node.anchor", doubles: [Double(theUnitPoint.x), Double(theUnitPoint.y)])
	} else {
		emit("session.tap.node.anchor", doubles: [])
	}
	emit("session.tap.node.hit", ints: [
		theDocument.itsControlHandleHit?.itsElement === theArch ? 1 : 0,
		theDocument.itsControlHandleHit?.itsNode === theTappedNode ? 1 : 0])

	step("node-type") {
		theDocument.changeSplineNodeType(curve: theArch, node: theTappedNode, from: theTappedNode.itsNodeType, to: .corner)
	}

	step("split-node") {
		let theNode = theArch.itsSpline.itsNodes[2]
		let (theNodeA, theNodeB) = theArch.itsSpline.splitNode(theNode)
		theDocument.splitSplineNode(curve: theArch, oldNode: theNode, newNodeA: theNodeA, newNodeB: theNodeB)
	}

	step("delete-node") {
		theDocument.deleteSplineNode(curve: theZigzag, node: theZigzag.itsSpline.itsNodes[1])
	}

	step("color") {
		theDocument.changeColor(of: [theArch, theDot], to: LinearDisplayP3Color(r: 0.1, g: 0.2, b: 0.9, a: 1.0))
	}

	step("thickness") {
		theDocument.changeThickness(of: [theArch, theZigzag], from: theArch.itsThickness, to: 0.02)
	}

	step("element-array") {
		//	Delete the dot and bring the fill to the front.
		let theOldArray = theDocument.itsElements
		let theNewArray = theOldArray.filter { $0 !== theDot && $0 !== theFill } + [theFill]
		theDocument.changeElementArray(from: theOldArray, to: theNewArray)
	}

	step("legacy-thicknesses") {
		let theOldThicknesses = theDocument.itsElements.map { ($0 as? Brushstroke)?.itsThickness }
		let theNewThicknesses = theOldThicknesses.map { $0.map { 0.5 * $0 } }
		theDocument.changeLegacyDrawingBrushstrokeThicknesses(from: theOldThicknesses, to: theNewThicknesses)
	}

	step("nothing") {
		theDocument.changeNothing()
	}

	//	--- The unit cell

	step("realign") {
		let theOldPlacement = theDocument.itsUnitCellPlacement
		var theNewPlacement = theOldPlacement
		theNewPlacement.transform(using: similarity(
			cosθ: gCos003, sinθ: gSin003, scale: 1.25, translation: SIMD2<Double>(0.3, -0.2)))
		theNewPlacement.snapToViewAlignment()
		theNewPlacement.centerTheUnitCell()
		theDocument.changeUnitCellPlacement(oldPlacement: theOldPlacement, newPlacement: theNewPlacement)
	}

	let theGroupsAndShapes: [(WallpaperGroup, UnitCellShape)] = [
		(.wpg2222,  UnitCellShape(aspectRatio: 1.5, shear: 0.25)),	//	fully flexible
		(.wpgS2222, UnitCellShape(aspectRatio: 0.5, shear: 0.0)),	//	rectangular
		(.wpg2S22,  UnitCellShape(aspectRatio: 2.0, shear: 0.0)),	//	rhombic
		(.wpgS442,  UnitCellShape(aspectRatio: 3.0, shear: 1.0)),	//	rigid:  the shape is ignored
	]
	for (theGroup, theShape) in theGroupsAndShapes {
		step("group-\(theGroup.IUCName)") {
			theDocument.changeWallpaperGroup(
				to: theGroup,
				placement: UnitCellPlacement(defaultForWallpaperGroup: theGroup))
		}
		step("shape-\(theGroup.IUCName)") {
			theDocument.changeUnitCellShape(oldShape: theDocument.getUnitCellShape(), newShape: theShape)
		}
	}
	emit("session.defaultGroup", string: UserDefaults.standard.string(forKey: "default symmetry group") ?? "none")
	UserDefaults.standard.removeObject(forKey: "default symmetry group")

	//	--- A locked drawing ignores every touch

	theDocument.itsContentIsLocked = true
	theDocument.itsTouchMode = .draw
	theDocument.touchBegan(at: point(300.0, 300.0))
	theDocument.touchMoved(to: point(400.0, 400.0))
	theDocument.touchEnded()
	theDocument.singleTapForDrawing(at: point(500.0, 500.0))
	theDocument.doubleTapForDrawing(at: point(500.0, 500.0))
	emitSessionState("session.locked", theDocument)
	theDocument.itsContentIsLocked = false

	//	--- Undo everything, redo everything

	let theStepCount = theStepNames.count
	emit("session.stepCount", int: theStepCount)
	for i in (0 ..< theStepCount).reversed() {
		theUndoManager.undo()
		emitSessionState("session.undo.\(i)", theDocument)
	}
	theUndoManager.undo()	//	nothing left to undo
	emitSessionState("session.undo.extra", theDocument)

	for i in 0 ..< theStepCount {
		theUndoManager.redo()
		emitSessionState("session.redo.\(i)", theDocument)
	}
	theUndoManager.redo()	//	nothing left to redo
	emitSessionState("session.redo.extra", theDocument)

	//	--- Doing something new forgets what could have been redone

	for _ in 0 ..< 5 {
		theUndoManager.undo()
	}
	emitSessionState("session.branch.before", theDocument)
	theUndoManager.beginUndoGrouping()
	theDocument.singleTapForDrawing(at: point(700.0, 1700.0))
	theUndoManager.endUndoGrouping()
	emitSessionState("session.branch.after", theDocument)
}
