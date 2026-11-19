//	KaleidoPaintGestureHandler.swift
//
//	© 2026 by Jeff Weeks
//	See TermsOfUse.txt

import SwiftUI

class KaleidoPaintGestureHandler {

	//	makePlatformDependentGestureRecognizers()
	//	will set the correct values.
	var modelData: KaleidoPaintDocument = KaleidoPaintDocument()		//	dummy value
	var activePanel: Binding<PanelType> = .constant(.noPanel)			//	dummy value
	var editorIsShown: Binding<Bool> = .constant(false)					//	dummy value
	var editorAnchor: Binding<PopoverAttachmentAnchor>
			= .constant(.point(UnitPoint(x: 0.5, y: 0.5)))				//	dummy value
	var cursorIsOverDrawingOnMacOS: Binding<Bool> = .constant(false)	//	dummy value

	//	Remember a 1-finger gesture's first point
	//	while we wait for its second point to arrive.
	var pendingStartPoint: DisplayPoint? = nil


	func makePlatformDependentGestureRecognizers(
		modelData: KaleidoPaintDocument,
		activePanel: Binding<PanelType>,
		editorIsShown: Binding<Bool>,
		editorAnchor: Binding<PopoverAttachmentAnchor>,
		cursorIsOverDrawingOnMacOS: Binding<Bool>	//	ignored on iOS
	) -> [GeometryGamesPlatformDependentGestureRecognizer] {

		self.modelData = modelData
		self.activePanel = activePanel
		self.editorIsShown = editorIsShown
		self.editorAnchor = editorAnchor
		self.cursorIsOverDrawingOnMacOS = cursorIsOverDrawingOnMacOS

		//	Really we need to set this once.
		//	Any subsequent assignments will be redundant.
		//
		//		Note: This is a weak reference, so there's
		//		no risk of a strong reference cycle here.
		//
		modelData.itsGestureRecognizerDelegate.modelData = modelData
		
#if os(macOS)
		enableMacOSScrollEvents()
#endif

		var theGestureRecognizers: [GeometryGamesPlatformDependentGestureRecognizer] = []

		let theOneFingerDragGestureRecognizer = GeometryGamesPanRecognizerWithInitialTouch(
			target: self,
			action: #selector(handleOneFingerDragGesture))
#if os(iOS)
		theOneFingerDragGestureRecognizer.minimumNumberOfTouches = 1
		theOneFingerDragGestureRecognizer.maximumNumberOfTouches = 1
#endif
		theOneFingerDragGestureRecognizer.delegate = modelData.itsGestureRecognizerDelegate
		theGestureRecognizers.append(theOneFingerDragGestureRecognizer)

		let theRotationGestureRecognizer = GeometryGamesPlatformDependentRotationGestureRecognizer(
			target: self,
			action: #selector(handleRotationGesture))
		theRotationGestureRecognizer.delegate = modelData.itsGestureRecognizerDelegate
		theGestureRecognizers.append(theRotationGestureRecognizer)

		let thePinchGestureRecognizer = GeometryGamesPlatformDependentPinchGestureRecognizer(
			target: self,
			action: #selector(handlePinchGesture))
		thePinchGestureRecognizer.delegate = modelData.itsGestureRecognizerDelegate
		theGestureRecognizers.append(thePinchGestureRecognizer)

#if os(iOS)
		let theTwoFingerDragGestureRecognizer = UIPanGestureRecognizer(
			target: self,
			action: #selector(handleTwoFingerDragGesture))
		theTwoFingerDragGestureRecognizer.minimumNumberOfTouches = 2
		theTwoFingerDragGestureRecognizer.maximumNumberOfTouches = 2
		theTwoFingerDragGestureRecognizer.delegate = modelData.itsGestureRecognizerDelegate
		theGestureRecognizers.append(theTwoFingerDragGestureRecognizer)
#endif

		let theSingleTapGestureRecognizer = GeometryGamesPlatformDependentTapGestureRecognizer(
			target: self,
			action: #selector(handleSingleTapGesture))
#if os(iOS)
		theSingleTapGestureRecognizer.numberOfTapsRequired = 1		//	how many taps
		theSingleTapGestureRecognizer.numberOfTouchesRequired = 1	//	...with how many fingers
#endif
#if os(macOS)
		theSingleTapGestureRecognizer.numberOfClicksRequired = 1
#endif
		theSingleTapGestureRecognizer.delegate = modelData.itsGestureRecognizerDelegate
		theGestureRecognizers.append(theSingleTapGestureRecognizer)
		
		let theDoubleTapGestureRecognizer = GeometryGamesPlatformDependentTapGestureRecognizer(
			target: self,
			action: #selector(handleDoubleTapGesture))
#if os(iOS)
		theDoubleTapGestureRecognizer.numberOfTapsRequired = 2
		theDoubleTapGestureRecognizer.numberOfTouchesRequired = 1
#endif
#if os(macOS)
		theDoubleTapGestureRecognizer.numberOfClicksRequired = 2
#endif
		theDoubleTapGestureRecognizer.delegate = modelData.itsGestureRecognizerDelegate
		theGestureRecognizers.append(theDoubleTapGestureRecognizer)

		//	In Draw mode, the gesture recognizer delegate
		//	will make theSingleTapGestureRecognizer wait
		//	for theDoubleTapGestureRecognizer to fail,
		//	but in Edit mode it won't, because Edit mode
		//	ignores double taps.
		
		return theGestureRecognizers
	}


// MARK: -
// MARK: macOS scroll events

#if os(macOS)
	func enableMacOSScrollEvents() {
	
		//	macOS treats a 2-finger drag on the trackpad not as a gesture,
		//	but rather as a scrollWheel event, presumably because back
		//	in the old days Macs had no trackpads but some mice had
		//	a little 1D scroll wheel between their left and right buttons,
		//	which later evolved to a 2D scroll wheel.
		
		NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel], handler: { event in
		
			//	On iOS, a pan gesture dismisses the Editor if it's up,
			//	but on macOS a scroll event doesn't. So on macOS let's
			//	ignore scroll events while the Editor is up. We don't
			//	want to move the selected DrawingElement away from
			//	the little arrow on the panel that edits it.
			let theEditorIsShown = self.editorIsShown.wrappedValue

			if event.type == .scrollWheel
			&& self.cursorIsOverDrawingOnMacOS.wrappedValue
			&& !theEditorIsShown {
			
				let theRawIncrement = SIMD2<Double>(	//	undefined units
										 event.scrollingDeltaX,
										-event.scrollingDeltaY)	//	flip vertically

				let drawingUnitsPerScrollUnit = 0.0001
				let theIncrementInDrawingUnits = drawingUnitsPerScrollUnit * theRawIncrement

				self.modelData.itsUnitCellPlacement.itsCorner += theIncrementInDrawingUnits
				self.modelData.itsUnitCellPlacement.centerTheUnitCell()
				self.modelData.changeCount += 1
			}
			
			return event
		})
	}
#endif


// MARK: -
// MARK: One-finger drag gesture

	@objc func handleOneFingerDragGesture(
		_ panGestureRecognizer: GeometryGamesPanRecognizerWithInitialTouch
	) {

		//	The compiler doesn't check the type
		//	of #selector(handleOneFingerDragGesture),
		//	so let's check it at run time.
		guard panGestureRecognizer.isKind(of:
			GeometryGamesPanRecognizerWithInitialTouch.self)
		else { return }

		guard let theGestureLocation
			= getGestureLocation(gestureRecognizer: panGestureRecognizer)
		else { return }
		
		switch panGestureRecognizer.state {
		
		case .possible:
			//	Never called.
			break
			
		case .began:

			let theInitialPoint = getGestureLocation(
									gestureRecognizer: panGestureRecognizer,
									alternateLocation: panGestureRecognizer.initialTouchLocation)

			//	In .draw mode, every curve must have at least two points, and
			//	in .edit mode, every motion must move a non-zero distance.
			//	So let's remember the first point we receive, but not
			//	do anything with it until a second point arrives.
			pendingStartPoint = theInitialPoint
			
		case .changed:
		
			//	If the start point is pending, submit it now.
			if let thePendingStartPoint = pendingStartPoint {
				modelData.touchBegan(at: thePendingStartPoint)
				pendingStartPoint = nil
			}
			modelData.touchMoved(to: theGestureLocation)
			
		case .ended:
		
			//	If the pendingStartPoint was never submitted
			//	to touchBegan(), then there nothing to end.
			if pendingStartPoint == nil {
				modelData.touchEnded()
			}
		
		case .cancelled:
		
			//	If the pendingStartPoint was never submitted
			//	to touchBegan(), then there nothing to cancel.
			if pendingStartPoint == nil {
				modelData.touchCancelled()
			}
			
		case .failed:
			break
			
		@unknown default:
			break
			
		}
		
		modelData.changeCount += 1
	}


// MARK: -
// MARK: Rotation gesture

	@objc func handleRotationGesture(
		_ rotationGestureRecognizer: GeometryGamesPlatformDependentRotationGestureRecognizer
	) {

		//	The compiler doesn't check the type
		//	of #selector(handleRotationGesture),
		//	so let's check it at run time.
		guard rotationGestureRecognizer.isKind(of:
			GeometryGamesPlatformDependentRotationGestureRecognizer.self)
		else { return }

		switch rotationGestureRecognizer.state {

		case .possible:
			break
			
		case .began, .changed:	//	Includes the initial small rotation
								//		at time of gesture recognition

#if os(macOS)
			//	On iOS, a rotation gesture dismisses the Editor if it's up,
			//	but on macOS it doesn't. So on macOS let's ignore rotation
			//	gestures while the Editor is up. We don't want to move
			//	the selected DrawingElement away from the little arrow
			//	on the panel that edits it.
			if editorIsShown.wrappedValue {
				break
			}
#endif
			
			//	The SwiftUI RotateGesture() sometimes reports θ = NaN.
			//	I'm not sure whether the UIRotationGestureRecognizer
			//	and NSRotationGestureRecognizer also have this bug,
			//	but just to be safe let's check.
			let theRawAngle = rotationGestureRecognizer.rotation
			if theRawAngle.isNaN {
				return
			}

			//	We want incremental rotation angles, not cumulative ones,
			//	so reset the rotationGestureRecognizer's rotation angle to zero.
			rotationGestureRecognizer.rotation = 0.0

#if os(iOS)
			let θ = -Double(theRawAngle)
#endif
#if os(macOS)
			let θ = +Double(theRawAngle)
#endif
			
			let theRotation = simd_double3x2(
				SIMD2<Double>( cos(θ), sin(θ)),
				SIMD2<Double>(-sin(θ), cos(θ)),
				SIMD2<Double>(  0.0,    0.0  ) )

			modelData.itsUnitCellPlacement.transform(using: theRotation)

		case .ended, .cancelled:
		
			modelData.itsUnitCellPlacement.snapToViewAlignment()
			modelData.itsUnitCellPlacement.centerTheUnitCell()

		case .failed:
			break
			
		@unknown default:
			break
		}
		
		modelData.changeCount += 1
	}


// MARK: -
// MARK: Pinch gesture

	@objc func handlePinchGesture(
		_ pinchGestureRecognizer: GeometryGamesPlatformDependentPinchGestureRecognizer
	) {

		//	The compiler doesn't check the type
		//	of #selector(handlePinchGesture),
		//	so let's check it at run time.
		guard pinchGestureRecognizer.isKind(of:
			GeometryGamesPlatformDependentPinchGestureRecognizer.self)
		else { return }

		switch pinchGestureRecognizer.state {

		case .possible:
			break
			
		case .began,	//	Includes the initial small pinching at time of gesture recognition
			.changed:

#if os(macOS)
			//	On iOS, a pinch gesture dismisses the Editor if it's up,
			//	but on macOS it doesn't. So on macOS let's ignore pinch
			//	gestures while the Editor is up. We don't want to move
			//	the selected DrawingElement away from the little arrow
			//	on the panel that edits it.
			if editorIsShown.wrappedValue {
				break
			}
#endif

			//	We want incremental pinches, not cumulative ones.
#if os(iOS)
			let theFactor = pinchGestureRecognizer.scale
			pinchGestureRecognizer.scale = 1.0
#endif
#if os(macOS)
			let theFactor = 1.0 + pinchGestureRecognizer.magnification
			pinchGestureRecognizer.magnification = 0.0
#endif

			let thePinch = simd_double3x2(
				SIMD2<Double>( theFactor,    0.0    ),
				SIMD2<Double>(    0.0,    theFactor ),
				SIMD2<Double>(    0.0,       0.0    ) )
			
			var theNewPlacement = modelData.itsUnitCellPlacement
			theNewPlacement.transform(using: thePinch)

			//	Ignore pinches that would make the unit cell too small or too large.
			if !theNewPlacement.unitCellIsDegenerate() {
				modelData.itsUnitCellPlacement = theNewPlacement
			}

		case .ended, .cancelled:
		
			modelData.itsUnitCellPlacement.centerTheUnitCell()

		case .failed:
			break
			
		@unknown default:
			break
		}
		
		modelData.changeCount += 1
	}


// MARK: -
// MARK: Two-finger drag gesture

#if os(iOS)

	@objc func handleTwoFingerDragGesture(
		_ panGestureRecognizer: UIPanGestureRecognizer
	) {

		//	The compiler doesn't check the type
		//	of #selector(handleTwoFingerDragGesture),
		//	so let's check it at run time.
		guard panGestureRecognizer.isKind(of:
			UIPanGestureRecognizer.self)
		else { return }

		guard let theTranslationInDisplayCoordinates
			= getPanGestureTranslation(panGestureRecognizer: panGestureRecognizer)
		else { return }
		
		let theTranslationInDrawingCoordinates
			= convertDisplayTranslationToDrawingTranslation(theTranslationInDisplayCoordinates)
		
		switch panGestureRecognizer.state {
		
		case .possible:
			//	Never called.
			break
			
		case .began, .changed:	//	Includes the initial small translation
								//		at time of gesture recognition

			modelData.itsUnitCellPlacement.itsCorner += theTranslationInDrawingCoordinates

			if let theView = panGestureRecognizer.view {	//	should never fail
				panGestureRecognizer.setTranslation(.zero, in: theView)
			}
			
		case .ended, .cancelled:
		
			modelData.itsUnitCellPlacement.centerTheUnitCell()
			
		case .failed:
			//	Never called.
			break
			
		@unknown default:
			break
			
		}
		
		modelData.changeCount += 1
	}
	
#endif	//	os(iOS)
#if os(macOS)
	//	On macOS we use scrollWheel to handle 2-finger drags.
#endif


// MARK: -
// MARK: Double-tap gesture

	@objc func handleDoubleTapGesture(
		_ tapGestureRecognizer: GeometryGamesPlatformDependentTapGestureRecognizer) {

		//	The compiler doesn't check the type
		//	of #selector(handleDoubleTapGesture),
		//	so let's check it at run time.
		guard tapGestureRecognizer.isKind(of:
			GeometryGamesPlatformDependentTapGestureRecognizer.self)
		else { return }

		guard let theTapPoint = getGestureLocation(gestureRecognizer: tapGestureRecognizer)
		else { return }
	
		switch modelData.itsTouchMode {
		
		case .draw:
			//	In Draw mode we always want to recognize double taps
			//	and pass them through to the KaleidoPaintDocument,
			//	even if a panel is up.  Only single taps can close panels.
			modelData.doubleTapForDrawing(at: theTapPoint)
			
		case .edit:
			//	Ignore double taps in Edit mode.
			break
		}
	}


// MARK: -
// MARK: Single-tap gesture

	@objc func handleSingleTapGesture(
		_ tapGestureRecognizer: GeometryGamesPlatformDependentTapGestureRecognizer) {

		//	The compiler doesn't check the type
		//	of #selector(handleSingleTapGesture),
		//	so let's check it at run time.
		guard tapGestureRecognizer.isKind(of:
			GeometryGamesPlatformDependentTapGestureRecognizer.self)
		else { return }

		if activePanel.wrappedValue != .noPanel {

			activePanel.wrappedValue = .noPanel	//	dismiss panel

		} else {

			guard let theTapPoint = getGestureLocation(gestureRecognizer: tapGestureRecognizer)
			else { return }
		
			switch modelData.itsTouchMode {
			
			case .draw:
				modelData.singleTapForDrawing(at: theTapPoint)
				
			case .edit:

				modelData.singleTapForEditing(
					at: theTapPoint,
					editorIsShown: editorIsShown,
					editorAnchor: editorAnchor)
			}
		}
	}
}


// MARK: -
// MARK: Gesture recognizer delegate

class KaleidoPaintGestureRecognizerDelegate: NSObject, GeometryGamesPlatformDependentGestureRecognizerDelegate {

	//	The KaleidoPaintDocument keeps a strong reference to us,
	//	so we should keep only a weak reference to it.
	weak var modelData: KaleidoPaintDocument? = nil

	func gestureRecognizer(
		_ gestureRecognizer: GeometryGamesPlatformDependentGestureRecognizer,
		shouldRecognizeSimultaneouslyWith otherGestureRecognizer: GeometryGamesPlatformDependentGestureRecognizer
	) -> Bool {
	
		//	The 2-finger gestures (for rotate, pinch and scroll)
		//	may all run simultaneously, but we want the 1-finger drag
		//	to end or fail before any 2-finger drag begins.
		
		let bothGesturesAreTwoFinger = isTwoFingerGesture(gestureRecognizer)
									&& isTwoFingerGesture(otherGestureRecognizer)

		return bothGesturesAreTwoFinger
	}
	
	private func isTwoFingerGesture(
		_ gestureRecognizer: GeometryGamesPlatformDependentGestureRecognizer
	) -> Bool {
			
		if let thePanGestureRecognizer = gestureRecognizer as? GeometryGamesPlatformDependentPanGestureRecognizer {

#if os(iOS)
			//	Is it a 2-finger pan gesture?
			return thePanGestureRecognizer.maximumNumberOfTouches == 2
#endif
#if os(macOS)
			//	macOS doesn't support 2-finger drags.
			//	(We use scrollWheel instead.)
			return false
#endif
		} else {
		
			//	It's a 2-finger gesture (rotate or pinch).
			return true
		}
	}
	
	func gestureRecognizer(
		_ gestureRecognizer: GeometryGamesPlatformDependentGestureRecognizer,
		shouldRequireFailureOf otherGestureRecognizer: GeometryGamesPlatformDependentGestureRecognizer
	) -> Bool {
	
		//	Edit mode doesn't use the double-tap gesture,
		//	so there's no need to wait for it to fail
		//	before accepting a single-tap gesture.
		if let theModelData = modelData,
		   theModelData.itsTouchMode == .edit
		{
			return false
		}
		
		//	In Draw mode, theSingleTapGestureRecognizer must
		//	wait for theDoubleTapGestureRecognizer to fail.
		
		if let theFirst = gestureRecognizer
							as? GeometryGamesPlatformDependentTapGestureRecognizer,
		   let theSecond = otherGestureRecognizer
							as? GeometryGamesPlatformDependentTapGestureRecognizer,
		   requiredTapCount(of: theFirst ) == 1,
		   requiredTapCount(of: theSecond) == 2
		{
			return true
		} else {
			return false
		}
		
		func requiredTapCount(
			of tapGestureRecognizer: GeometryGamesPlatformDependentTapGestureRecognizer
		) -> Int {
#if os(iOS)
			return tapGestureRecognizer.numberOfTapsRequired
#endif
#if os(macOS)
			return tapGestureRecognizer.numberOfClicksRequired
#endif
		}
	}
}
