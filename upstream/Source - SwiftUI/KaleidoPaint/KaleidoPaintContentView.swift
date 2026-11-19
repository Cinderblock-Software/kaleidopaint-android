//	KaleidoPaintContentView.swift
//
//	© 2026 by Jeff Weeks
//	See TermsOfUse.txt

import SwiftUI
import simd
import CoreMedia


enum SelectionMode: CaseIterable, Identifiable {

	case new		//	select a new color or thickness
	case previous	//	choose from among the colors or thicknesses already in use in the drawing

	var id: Self {self}

	func symbolSystemName() -> String {
		
		switch self {
		
		case .new:
			return "rays"
			
		case .previous:
			return "clock.arrow.circlepath"
		}
	}
}

//	The current version of KaleidoPaint uses a fixed unit cell resolution
//	of 11, which strikes a good balance between image quality and speed.
//
//		2¹¹ × 2¹¹ = 2048 × 2048 pixels
//
//let log2UnitCellResolution: Int = 11

let toolbarPadding: CGFloat = 8.0
let selectedButtonCornerRadius: CGFloat = geometryGamesCornerRadius - toolbarPadding
let selectedButtonBackgroundColor: Color = Color(white: 0.875)

//	At log2UnitCellResolution = 9 (the value we use for thumbnails)
//	a sample drawing that Amber sent leaks (with 4-way flood fill)
//	at -2.906769, but stops leaking at -2.895961.  Given that my own
//	fairly extensive leak-test sample drawing stopped leaking at -2.98,
//	it's clear that the thickness at which leakage occurs can vary
//	from one drawing to another.  So I'm raising the minimum to -2.8
//	to allow a little slack.
//
//	With my own leak-test sample drawing, here's the comparison
//	between 4-way and 8-way flood fills:
//
//		With 8-way flood fill
//			-2.51	already leaks (might leak even for thicker lines)
//
//		With 4-way flood fill
//			-2.98	no leakage detected in limited testing
//			-2.99	just a little leakage
//			-3.01	lots of leakage
//
let minLog2ThicknessFactor = -2.8	//	allows some slack relative to -2.895961 value noted above;
									//	somewhat more than 1/8 of the default thickness
let maxLog2ThicknessFactor = +2.0	//	4 times the default thickness
let thicknessSliderLength = 256.0

//#warning("disable screenshots")
let gMakeScreenshots = false	//	always false in release version


struct KaleidoPaintContentView: View {

	@Environment(\.horizontalSizeClass) var horizontalSizeClass

	//	Our KaleidoPaintDocument is a ReferenceFileDocument
	//	which, when we close the document, will save its contents
	//	iff there are un-doable changes sitting on the UndoManager
	//	that it passes to us as an @Environment variable.
	//	So it's essential that our document use that default UndoManager
	//	and not one that we allocate ourselves.
	@Environment(\.undoManager) var defaultUndoManager

	@State var document: KaleidoPaintDocument
	let fileURL: URL?

	@State var renderer: KaleidoPaintRenderer?
		= KaleidoPaintRenderer(log2UnitCellResolution: log2UnitCellResolution)

	//	Unlike SwiftUI Gestures, which keep all the information they need,
	//	UIKit's UIGestureRecognizers don't keep strong references to their targets.
	//	So let's keep a reference to our KaleidoPaintGestureHandler here.
	//	makePlatformDependentGestureRecognizers() will set the correct
	//	value for the KaleidoPaintDocument.
	//
	//	It shouldn't create a strong reference cycle, but be aware
	//	that the kaleidoPaintGestureHandler will hold a strong reference
	//	to the document.
	//
	//	If KaleidoPaint someday migrates to SwiftUI gestures (if they ever
	//	support 2-finger drags), this @State variable can be removed.
	//
	@State var kaleidoPaintGestureHandler = KaleidoPaintGestureHandler()

	@State var itsActivePanel: PanelType = .noPanel

	//	Let the SelectionMode and "Change all of…" settings
	//	persist even when the user closes and reopens
	//	a ColorPanel or ThicknessPanel.
	@State var brushColorSelectionMode = SelectionMode.new
	@State var brushThicknessSelectionMode = SelectionMode.new
	@State var fillColorSelectionMode = SelectionMode.new
	@State var backgroundColorSelectionMode = SelectionMode.new
	@State var editorColorSelectionMode = SelectionMode.new
	@State var editorChangeAllOfSameColor = false
	@State var editorThicknessSelectionMode = SelectionMode.new
	@State var editorChangeAllOfSameThickness = false
	@State var editorDeleteAllOfSameColor = false

	//	Auto-show the helpQuickStart and helpEditor panels once per session.
	@Binding var quickStartHelpShouldBeShown: Bool
	@Binding var editorHelpShouldBeShown: Bool

	@State var itsShapePanelIsShown: Bool = false
	@State var itsEditorIsShown: Bool = false
	@State var itsEditorAnchor: PopoverAttachmentAnchor = .point(UnitPoint(x: 0.5, y: 0.5))
	@State var itsCursorIsOverDrawingOnMacOS: Bool = false	//	ignored on iOS


	var body: some View {

		//	Our KaleidoPaintDocument is a ReferenceFileDocument
		//	which, when we close the document, will save its contents
		//	iff there are un-doable changes sitting on the UndoManager
		//	that it passes to us as an @Environment variable.
		//	So it's essential that our document use that default UndoManager
		//	and not one that we allocate ourselves.
		if let theDefaultUndoManager = defaultUndoManager {
			document.itsUndoManager = theDefaultUndoManager
		} else {
#if os(iOS)
			//	When running on iOS, SwiftUI calls this body() function
			//	a total of four times for each drawing that I open.
			//	The defaultUndoManager is non-nil in all four calls.
			assertionFailure("The defaultUndoManager is missing")
#endif
#if os(macOS)
			//	When running on macOS, SwiftUI calls this body() function
			//	three times for each drawing that I open. On the first call
			//	the defaultUndoManager is still nil, but then on the second
			//	and third calls it's non-nil, so everything works fine.
#endif
		}

		let theGestureRecognizers
			= kaleidoPaintGestureHandler.makePlatformDependentGestureRecognizers(
				modelData: document,
				activePanel: $itsActivePanel,
				editorIsShown: $itsEditorIsShown,
				editorAnchor: $itsEditorAnchor,
				cursorIsOverDrawingOnMacOS: $itsCursorIsOverDrawingOnMacOS)
		
		//	This top-level ZStack lets the controls overlay the main view.
		return ZStack(alignment: .center) {

			//	Main animation view
			if let theRenderer = renderer {

				GeometryGamesViewRep(
					modelData: document,
					renderer: theRenderer,
					gestureRecognizers: theGestureRecognizers
				)
				.ignoresSafeArea(edges: .all)	//	Title may be less noticeable
				.onHover() { cursorIsOverDrawing in
					itsCursorIsOverDrawingOnMacOS = cursorIsOverDrawing
				}
				.popover(
					isPresented: $itsEditorIsShown,
					attachmentAnchor: itsEditorAnchor
					) {
						EditorPanel(
							document: document,
							colorSelectionMode: $editorColorSelectionMode,
							changeAllOfSameColor: $editorChangeAllOfSameColor,
							thicknessSelectionMode: $editorThicknessSelectionMode,
							changeAllOfSameThickness: $editorChangeAllOfSameThickness,
							deleteAllOfSameColor: $editorDeleteAllOfSameColor,
							editorIsShown: $itsEditorIsShown)
					}
				.onChange(of: itsEditorIsShown) {

					if !itsEditorIsShown {

						//	The user dismissed the Editor popover,
						//	so unselect the selection.

						document.itsControlHandleHit = nil

						document.itsBaseDrawingTextureFullRedrawRequestCount += 1
						document.changeCount += 1
					}
				}
			}

			//	Controls
			VStack(alignment: .center) {

				ButtonsAtTop(
					document: document,
					fileURL: fileURL
				)
				.onChange(of: document.itsContentIsLocked) {

					if document.itsContentIsLocked {
					
						if document.itsTouchMode != .draw {
							document.itsTouchMode = .draw
							document.itsBaseDrawingTextureFullRedrawRequestCount += 1
							document.changeCount += 1
						}

						itsActivePanel = .noPanel

						//	When the user locks a drawing, we can disable
						//	KaleidoPaint's own Undo/Redo buttons, but there
						//	doesn't seem to be any way to disable SwiftUI's
						//	built-in 3-finger swipe left / swipe right
						//	gestures for undo/redo on iOS or its built-in
						//	⌘Z / ⇧⌘Z on macOS.
						//
						//	KaleidoPaint 3.0.7 and earlier took the somewhat
						//	drastic step of completely clearing the Undo/Redo
						//	stacks at this point
						//
						//		document.itsUndoManager?.removeAllActions()
						//		document.itsUndoRedoCount += 1
						//
						//	so that 3-finger swipes and ⌘Z have no effect.
						//	But this is a bit countertuitive: if a user locks
						//	and then unlocks a drawing, they expect the changes
						//	on the Undo/Redo stack to still be there.
						//
						//	(There's also the question of whether the Lock operation
						//	is guaranteed to get saved if when the user closes
						//	the document with an empty Undo stack, although
						//	in practice it seems to work.)
						//
					}
				}

				Spacer()
				
				if horizontalSizeClass == .regular
				|| document.itsTouchMode == .edit {
				
					PossibleControlPanel(
						document: document,
						renderer: renderer,
						activePanel: $itsActivePanel,
						brushColorSelectionMode: $brushColorSelectionMode,
						brushThicknessSelectionMode: $brushThicknessSelectionMode,
						fillColorSelectionMode: $fillColorSelectionMode,
						backgroundColorSelectionMode: $backgroundColorSelectionMode,
						quickStartHelpShouldBeShown: $quickStartHelpShouldBeShown,
						shapePanelIsShown: $itsShapePanelIsShown,
						fileURL: fileURL)
					
					//	This ZStack lets the TouchModePicker be perfectly centered.
					ZStack(alignment: .bottom) {

						if !document.itsContentIsLocked {
						
							TouchModePicker(
								activePanel: $itsActivePanel,
								document: document,
								editorHelpShouldBeShown: $editorHelpShouldBeShown)
						}
		
						HStack(alignment: .bottom) {

							if !document.itsContentIsLocked
								&& document.itsTouchMode == .draw {
							
								ButtonsAtBottomLeading(
									activePanel: $itsActivePanel,
									document: document)
							}
							
							Spacer()
						
							ButtonsAtBottomTrailing(
								activePanel: $itsActivePanel,
								document: document)
						}
					}
					
				} else {	//	horizontalSizeClass == .compact (or nil) and
							//	document.itsTouchMode == .draw
							
					let theToolbarOpacity
						= itsActivePanel.wantsSemiTransparentToolbarsInNarrowLayouts ? 0.75 : 1.0

					//	This ZStack lets the TouchModePicker and
					//	the PossibleControlPanel be perfectly centered.
					ZStack(alignment: .bottom) {

						HStack(alignment: .bottom, spacing: 0.0) {

							if !document.itsContentIsLocked {
							
								ButtonsAtBottomLeading(
									activePanel: $itsActivePanel,
									document: document)
								.opacity(theToolbarOpacity)
							}
							
							Spacer()

							ButtonsAtBottomTrailing(
								activePanel: $itsActivePanel,
								document: document)
						}
						.opacity(theToolbarOpacity)

						VStack() {

							PossibleControlPanel(
								document: document,
								renderer: renderer,
								activePanel: $itsActivePanel,
								brushColorSelectionMode: $brushColorSelectionMode,
								brushThicknessSelectionMode: $brushThicknessSelectionMode,
								fillColorSelectionMode: $fillColorSelectionMode,
								backgroundColorSelectionMode: $backgroundColorSelectionMode,
								quickStartHelpShouldBeShown:
									$quickStartHelpShouldBeShown,
								shapePanelIsShown: $itsShapePanelIsShown,
								fileURL: fileURL)
							.padding(EdgeInsets(
								top: 0.0,
								leading: geometryGamesPanelMargin,
								bottom: 0.0,
								trailing: geometryGamesPanelMargin))

							if !document.itsContentIsLocked {

								TouchModePicker(
									activePanel: $itsActivePanel,
									document: document,
									editorHelpShouldBeShown: $editorHelpShouldBeShown)
								.opacity(theToolbarOpacity)
							}
						}
					}
				}
			}
			.padding(geometryGamesControlInset)
			.onAppear() {
				
				if gMakeScreenshots {
					itsActivePanel = selectPanelForScreenshot(fileURL: fileURL)
					brushColorSelectionMode = .previous	//	used with brush color panel in "Cubic"
				} else {
					if quickStartHelpShouldBeShown
					&& document.itsTouchMode == .draw
					&& itsActivePanel == .noPanel {
					
						itsActivePanel = .helpQuickStart
					}
				}
				
				//	Put a "null change" onto the Undo stack,
				//	so that the drawing will get re-saved when the user
				//	closes it, even if the user has made only non-undoable
				//	changes like rotating, zooming, or locking the drawing.
				//	It's not foolproof:  if the user undoes this null change
				//	(and makes no other undoable changes) then the drawing
				//	won't get resaved and any non-undoable changes will be lost.
				//
				//		When running on iOS 18.4, SwiftUI creates
				//		the KaleidoPaintContentView twice, so tread
				//		carefully here.
				//
				if let theUndoManager = document.itsUndoManager,
					!theUndoManager.canUndo {
					
					document.changeNothing()
				}
			}
		}
		.onChange(of: itsActivePanel) { oldActivePanel, newActivePanel in

			if oldActivePanel == .helpQuickStart
			&& newActivePanel != .helpQuickStart {
				
				//	We've satisfied our possible obligation
				//	to show the helpQuickStart panel.
				quickStartHelpShouldBeShown = false
			}
			
			if oldActivePanel == .helpEditor
			&& newActivePanel != .helpEditor {
				
				//	We've satisfied our possible obligation
				//	to show the helpEditor panel.
				editorHelpShouldBeShown = false
			}
		}
	}
}


// MARK: -
// MARK: Screenshots

func selectPanelForScreenshot(
	fileURL: URL?
) -> PanelType {

	if let theFileURL = fileURL {
	
		let theDrawingName = theFileURL.deletingPathExtension().lastPathComponent
		switch theDrawingName {
		
			case "Paisley":
				return .helpQuickStart
				
			case "Cubic":
				return .brushColor
				
			case "Knitted":
				return .symmetry
			
			case "Lilylike":
				return .helpEditor
			
			case "Eagles":
				return .smoothingTolerance
		
			default:
				return .noPanel
		}
		
	} else {	//	should never occur
	
		return .noPanel
	}
}


// MARK: -
// MARK: Toolbars

struct BorderIfNeeded: ViewModifier {

	@Environment(\.colorScheme) var colorScheme

	let backgroundIntensity: Double
	let cornerRadius: Double
	
	init(
		over backgroundColor: LinearDisplayP3Color,
		cornerRadius: Double
	) {
		self.backgroundIntensity
			= (backgroundColor.r
			 + backgroundColor.g
			 + backgroundColor.b)
			/ 3.0
			
		self.cornerRadius = cornerRadius
	}
	
	func body(content: Content) -> some View {
	
		let theBorderIsNeeded = (
			colorScheme == .light ?
			(backgroundIntensity > 0.9375) :
			(backgroundIntensity < 0.0625)
		)
		
		return Group() {
		
			if theBorderIsNeeded {
			
				content
				.overlay(
					RoundedRectangle(cornerRadius: cornerRadius)
					.stroke(.gray, lineWidth: 1.0))

			} else {
			
				content
			}
		}
	}
}

struct ButtonsAtTop: View {

	var document: KaleidoPaintDocument
	let fileURL: URL?

	var body: some View {

		//	This ZStack lets the Undo and Redo buttons be centered.
		ZStack(alignment: .top) {

			if !document.itsContentIsLocked {
			
				HStack() {
					UndoButton(document: document)
					RedoButton(document: document)
				}
				.padding(toolbarPadding)
				.background(gSystemBackgroundColor)
				.cornerRadius(geometryGamesCornerRadius)
				.modifier(BorderIfNeeded(
					over: document.itsBackgroundColor,
					cornerRadius: geometryGamesCornerRadius))
			}

			LockButton(
				document: document,
				fileURL: fileURL)
			.frame(maxWidth: .infinity, alignment: .trailing)
		}
		.modifier(buttonStyleOnMacOS())
		.modifier(applyForegroundAccentColorOnMacOS())
	}
}

struct ButtonsAtBottomLeading: View {

	@Binding var activePanel: PanelType
	@Bindable var document: KaleidoPaintDocument

	var body: some View {

		//	The buttons already have their own tappable padding,
		//	so the AdaptiveStack doesn't need to provide any extra spacing.
		AdaptiveStack(spacing: 0) {

			BrushColorButton(
				activePanel: $activePanel,
				brushColor: $document.itsBrushColor)

			FillColorButton(
				activePanel: $activePanel,
				fillColor: $document.itsFillColor)

			BrushThicknessButton(
				activePanel: $activePanel)

			SmoothingToleranceButton(
				activePanel: $activePanel)
		}
		.modifier(buttonStyleOnMacOS())
		.modifier(applyForegroundAccentColorOnMacOS())
		.padding(toolbarPadding)
		.background(gSystemBackgroundColor)
		.cornerRadius(geometryGamesCornerRadius)
		.modifier(BorderIfNeeded(
			over: document.itsBackgroundColor,
			cornerRadius: geometryGamesCornerRadius))
	}
}

struct ButtonsAtBottomTrailing: View {

	@Binding var activePanel: PanelType
	@Bindable var document: KaleidoPaintDocument

	var body: some View {

		//	The buttons already have their own tappable padding,
		//	so the AdaptiveStack doesn't need to provide any extra spacing.
		AdaptiveStack(spacing: 0) {

			if document.itsTouchMode == .draw {
			
				if !document.itsContentIsLocked {
				
					BackgroundColorButton(
						activePanel: $activePanel,
						backgroundColor: $document.itsBackgroundColor)

					SymmetryButton(
						activePanel: $activePanel,
						wallpaperGroup: $document.itsWallpaperGroup)
				}

				ExportButton(activePanel: $activePanel)
			}

			HelpMenuButton(activePanel: $activePanel)
		}
		.modifier(buttonStyleOnMacOS())
		.modifier(applyForegroundAccentColorOnMacOS())
		.padding(toolbarPadding)
		.background(gSystemBackgroundColor)
		.cornerRadius(geometryGamesCornerRadius)
		.modifier(BorderIfNeeded(
			over: document.itsBackgroundColor,
			cornerRadius: geometryGamesCornerRadius))
	}
}


// MARK: -
// MARK: Buttons

struct UndoButton: View {

	var document: KaleidoPaintDocument
	
	@State var canUndo: Bool = false
	
	var body: some View {

		Button {

			document.itsUndoManager?.undo()

			document.itsUndoRedoCount += 1

		} label: {
		
			Image(systemName: "arrowshape.turn.up.backward.circle")
				.font(.title)
		}
		.disabled(!canUndo)
		.onChange(of: document.itsUndoRedoCount, initial: true) {
		
			canUndo = document.itsUndoManager?.canUndo ?? false
				   || gMakeScreenshots
		}
	}
}

struct RedoButton: View {

	var document: KaleidoPaintDocument

	@State var canRedo: Bool = false

	var body: some View {
	
		Button {
			
			document.itsUndoManager?.redo()
			
			document.itsUndoRedoCount += 1
			
		} label: {
		
			Image(systemName: "arrowshape.turn.up.forward.circle")
				.font(.title)
		}
		.disabled(!canRedo)
		.onChange(of: document.itsUndoRedoCount, initial: true) {
			canRedo = document.itsUndoManager?.canRedo ?? false
				   || gMakeScreenshots
		}
	}
}


struct LockButton: View {
	
	var document: KaleidoPaintDocument
	let fileURL: URL?

	@State var showLockView: Bool = false

	var body: some View {

		let theFileName = String(fileURL?.deletingPathExtension().lastPathComponent ?? "")

		Button() {
			showLockView.toggle()
		} label: {
			Image(systemName: document.itsContentIsLocked ?
					"lock.fill" : "lock.open.fill")
			.font(.title)
			.padding(toolbarPadding)
			.background(gSystemBackgroundColor)
			.cornerRadius(geometryGamesCornerRadius)
			.modifier(BorderIfNeeded(
				over: document.itsBackgroundColor,
				cornerRadius: geometryGamesCornerRadius))
		}
		.popover(isPresented: $showLockView) {
			LockView(
				document: document,
				fileName: theFileName)
		}
	}
}

struct LockView: View {

	var document: KaleidoPaintDocument
	let fileName: String

	@Environment(\.dismiss) var dismiss

	var body: some View {

		Button(role: document.itsContentIsLocked ? .destructive : nil ) {
						
			document.itsContentIsLocked.toggle()

			dismiss()
			
		} label: {
		
			Label(
				String(
					format: Bundle.main.localizedString(
								forKey: document.itsContentIsLocked ?
											"UnlockDrawing" : "LockDrawing",
								value: nil,
								table: nil),
					fileName),
				systemImage: document.itsContentIsLocked ?
								"lock.open.fill" : "lock.fill"
			)
			.padding(16.0)
		}
		.presentationCompactAdaptation(.popover)
	}
}

struct ShadowIfNeeded: ViewModifier {

	@Environment(\.colorScheme) var colorScheme
	
	@Binding var buttonColor: LinearDisplayP3Color
	
	func body(content: Content) -> some View {

		let thePerceivedIntensity
			= 0.299 * buttonColor.r
			+ 0.587 * buttonColor.g
			+ 0.114 * buttonColor.b

		let thePossibleShadowColor: Color?
		
		switch colorScheme {
		
		case .light:
			thePossibleShadowColor = (thePerceivedIntensity > 0.8750 ? Color.gray : nil)
			
		case .dark:
			thePossibleShadowColor = (thePerceivedIntensity < 0.0625 ? Color.white : nil)
			
		@unknown default:
			thePossibleShadowColor = nil
		}

		return Group() {

			if let theShadowColor = thePossibleShadowColor {

				content
				.shadow(color: theShadowColor, radius: 4.0)

			} else {

				content
			}
		}
	}
}

struct BrushColorButton: View {

	@Binding var activePanel: PanelType
	@Binding var brushColor: LinearDisplayP3Color

	var body: some View {

		Button {
			activePanel = (activePanel == .brushColor ? .noPanel : .brushColor)
		} label: {
			Image(systemName: "paintbrush.pointed")
				.font(.title)
				.foregroundStyle(brushColor.asSwiftUIColor())
				.modifier(ShadowIfNeeded(buttonColor: $brushColor))
				.padding(geometryGamesControlPadding)
				.background(activePanel == .brushColor ?
							selectedButtonBackgroundColor : nil)
				.cornerRadius(selectedButtonCornerRadius)
		}
	}
}

struct FillColorButton: View {

	@Binding var activePanel: PanelType
	@Binding var fillColor: LinearDisplayP3Color

	var body: some View {
	
		Button {
			activePanel = (activePanel == .fillColor ? .noPanel : .fillColor)
		} label: {
			Image("paint bucket")
				.font(.title)
				.foregroundStyle(fillColor.asSwiftUIColor())
				.modifier(ShadowIfNeeded(buttonColor: $fillColor))
				.padding(geometryGamesControlPadding)
				.background(activePanel == .fillColor ?
							selectedButtonBackgroundColor : nil)
				.cornerRadius(selectedButtonCornerRadius)
		}
	}
}

struct BackgroundColorButton: View {

	@Binding var activePanel: PanelType
	@Binding var backgroundColor: LinearDisplayP3Color
	
	var body: some View {
	
		Button {
			activePanel = (activePanel == .backgroundColor ? .noPanel : .backgroundColor)
		} label: {
			ZStack {
				Image(systemName: "square.fill")
					.imageScale(.large)
					.foregroundStyle(backgroundColor.asSwiftUIColor())
				Image(systemName: "square")
					.imageScale(.large)
					.foregroundStyle(.gray)
			}
			.font(.title.weight(.ultraLight))
			.padding(geometryGamesControlPadding)
			.background(activePanel == .backgroundColor ?
						selectedButtonBackgroundColor : nil)
			.cornerRadius(selectedButtonCornerRadius)
		}
	}
}

struct BrushThicknessButton: View {

	@Binding var activePanel: PanelType

	var body: some View {
	
		Button {
			activePanel = (activePanel == .brushThickness ? .noPanel : .brushThickness)
		} label: {
			Image(systemName: "lineweight")
				.font(.title)
				.padding(geometryGamesControlPadding)
				.background(activePanel == .brushThickness ?
							selectedButtonBackgroundColor : nil)
				.cornerRadius(selectedButtonCornerRadius)
		}
	}
}

struct SymmetryButton: View {

	@Binding var activePanel: PanelType
	@Binding var wallpaperGroup: WallpaperGroup

	var body: some View {

		Button {
			activePanel = (activePanel == .symmetry ? .noPanel : .symmetry)
		} label: {
			Image("wallpaper group toolbar buttons/" + wallpaperGroup.rawValue)
				.font(.title)
				.padding(geometryGamesControlPadding)
				.background(activePanel == .symmetry ?
							selectedButtonBackgroundColor : nil)
				.cornerRadius(selectedButtonCornerRadius)
		}
	}
}

struct SmoothingToleranceButton: View {

	@Binding var activePanel: PanelType

	var body: some View {
	
		Button {
			activePanel = (activePanel == .smoothingTolerance ? .noPanel : .smoothingTolerance)
		} label: {
			Image(systemName: "scribble")	//	or "alternatingcurrent"
				.font(.title)
				.padding(geometryGamesControlPadding)
				.background(activePanel == .smoothingTolerance ?
							selectedButtonBackgroundColor : nil)
				.cornerRadius(selectedButtonCornerRadius)
		}
	}
}

struct ExportButton: View {

	@Binding var activePanel: PanelType

	var body: some View {
	

		Button {
			activePanel = (activePanel == .export ? .noPanel : .export)
		} label: {
			Image(systemName: "square.and.arrow.up")
				.font(.title)
				.padding(geometryGamesControlPadding)
				.background(activePanel == .export ?
							selectedButtonBackgroundColor : nil)
				.cornerRadius(selectedButtonCornerRadius)
		}
	}
}

struct HelpMenuButton: View {

	@Binding var activePanel: PanelType

	var body: some View {

		Button {
			activePanel = activePanel == .helpMenuPanel ? .noPanel : .helpMenuPanel
		} label: {
			Image(systemName: "questionmark.circle")
			.font(.title)
			.padding(geometryGamesControlPadding)
			.background(geometryGamesTappableClearColor)
		}
	}
}

struct HelpMenuView: View {

	@Binding var activePanel: PanelType
	
	var body: some View {

		VStack(alignment: .leading, spacing: 8.0) {

			Button() {
				activePanel = .helpQuickStart
			} label: {
				Label("Quick Start", systemImage: "questionmark.circle")
			}
		
			Button() {
				activePanel = .helpEditor
			} label: {
				Label("Editor-HowTo-short", systemImage: "questionmark.circle")
			}
		
			Button() {
				activePanel = .helpTutorials
			} label: {
				Label("Tutorials", systemImage: "questionmark.circle")
			}
		
			Button() {
				activePanel = .helpImageGallery
			} label: {
				Label("Image Gallery", systemImage: "questionmark.circle")
			}
		
			Button() {
				activePanel = .helpContact
			} label: {
				GeometryGamesHelpMenuContactItemLabel()
			}
			
			Button() {
				activePanel = .translators
			} label: {
				GeometryGamesHelpMenuTranslatorsItemLabel()
			}
		}
		.modifier(helpMenuStyle())
	}
}

struct TouchModePicker: View {

	@Binding var activePanel: PanelType
	@Bindable var document: KaleidoPaintDocument
	@Binding var editorHelpShouldBeShown: Bool
	
	var body: some View {
	
		Picker("Touch Mode", selection: $document.itsTouchMode) {
		
			ForEach(TouchMode.allCases) { mode in
				Text(LocalizedStringKey(mode.localizedNameKey()))
			}
		}
		.pickerStyle(.segmented)
		.labelsHidden()
		.fixedSize()
		.padding(toolbarPadding)
		.background(gSystemBackgroundColor)
		.cornerRadius(geometryGamesCornerRadius)
		.modifier(BorderIfNeeded(
			over: document.itsBackgroundColor,
			cornerRadius: geometryGamesCornerRadius))
		.onChange(of: document.itsTouchMode) {

			document.itsControlHandleHit = nil

			document.itsBaseDrawingTextureFullRedrawRequestCount += 1
			document.changeCount += 1

			//	When entering edit mode...
			switch document.itsTouchMode {
			
			case .draw:

				//	If the helpEditor panel is up,
				//	replace it with the helpQuickStart panel.
				if activePanel == .helpEditor {
					activePanel = .helpQuickStart
				}

			case .edit:
			
				switch activePanel {
				
					//	If the helpEditor panel is up,
					//	leave it up.
					case .helpEditor:
						break
				
					//	If the helpQuickStart panel is up,
					//	replace it with the helpEditor panel.
					case .helpQuickStart:
						activePanel = .helpEditor
					
					//	Auto-show helpEditor once per session,
					//	when first switching to Edit mode.
					//	When switching to Edit mode for a second or later time,
					//	close all other panels.
					default:
						if editorHelpShouldBeShown {
							activePanel = .helpEditor
						} else {
							activePanel = .noPanel
						}
				}
				
				editorHelpShouldBeShown = false
			}
		}
	}
}


// MARK: -
// MARK: Control panels

struct PossibleControlPanel: View {

	@Environment(\.horizontalSizeClass) var horizontalSizeClass

	var document: KaleidoPaintDocument
	var renderer: KaleidoPaintRenderer?
	@Binding var activePanel: PanelType
	@Binding var brushColorSelectionMode: SelectionMode
	@Binding var brushThicknessSelectionMode: SelectionMode
	@Binding var fillColorSelectionMode: SelectionMode
	@Binding var backgroundColorSelectionMode: SelectionMode
	@Binding var quickStartHelpShouldBeShown: Bool
	@Binding var shapePanelIsShown: Bool
	let fileURL: URL?

	//	The brush color, fill color and brush thickness panels
	//	will ignore the changeAllOfSame… bindings that we pass them,
	//	but we have to pass something, and we can't make it a binding
	//	to a 'Bool?' because when the ColorPanel and ThicknessPanel
	//	appear in the EditorPanel, the checkboxes there will need
	//	to be able to toggle the bound values.  So let's define
	//	a dummy Bool value, which will never get used but at least
	//	lets the code compile correctly.
	@State private var dummyBool = false
	

	var body: some View {

		let theTranslatorThanks = [
			GeometryGamesTranslatorThanks(pre: "شكرا لـ", name: "حمزة خليف", post: nil, lang: "ar"),
			GeometryGamesTranslatorThanks(pre: "mit Dank an", name: "Frank Lutz", post: nil, lang: "de"),
			GeometryGamesTranslatorThanks(pre: "gracias a", name: "Joan Porti", post: nil, lang: "es"),
			GeometryGamesTranslatorThanks(pre: "merci à", name: "Roland Lehoucq", post: nil, lang: "fr"),
			GeometryGamesTranslatorThanks(pre: "grazie a", name: "Carlo Petronio", post: nil, lang: "it"),
			GeometryGamesTranslatorThanks(pre: nil, name: "竹内建氏と\n澤田智宏氏に", post: "感謝します", lang: "ja"),
			GeometryGamesTranslatorThanks(pre: "met dank aan", name: "Sebas Eliëns", post: nil, lang: "nl"),
			GeometryGamesTranslatorThanks(pre: "obrigado a", name: "Nuno Fernandes", post: nil, lang: "pt"),
			GeometryGamesTranslatorThanks(pre: "спасибо", name: "Алексею Пронину", post: nil, lang: "ru"),
			GeometryGamesTranslatorThanks(pre: "感谢", name: "马楚媛与邹燕清", post: nil, lang: "zh-Hans")
		]
		
		//	In a regular width layout (for example on an iPad)
		//		some of the panels get left-aligned, others right-aligned.
		//	In a compact width layout (for example on most iPhones)
		//		all the panels get centered.
		let maybeLeading:  Alignment = horizontalSizeClass == .regular ? .leading  : .center
		let maybeTrailing: Alignment = horizontalSizeClass == .regular ? .trailing : .center

		switch activePanel {
		
		case .noPanel:
		
			Spacer()
			.frame(maxWidth: .infinity, alignment: .center)
		
		case .brushColor:

			ColorPanel(
				document: document,
				colorTarget: .brush,
				colorSelectionMode: $brushColorSelectionMode,
				changeAllOfSameColor: $dummyBool)
			.cornerRadius(geometryGamesCornerRadius)
			.modifier(BorderIfNeeded(
				over: document.itsBackgroundColor,
				cornerRadius: geometryGamesCornerRadius))
			.fixedSize()
			.frame(maxWidth: .infinity, alignment: maybeLeading)
		
		case .fillColor:

			ColorPanel(
				document: document,
				colorTarget: .fill,
				colorSelectionMode: $fillColorSelectionMode,
				changeAllOfSameColor: $dummyBool)
			.cornerRadius(geometryGamesCornerRadius)
			.modifier(BorderIfNeeded(
				over: document.itsBackgroundColor,
				cornerRadius: geometryGamesCornerRadius))
			.fixedSize()
			.frame(maxWidth: .infinity, alignment: maybeLeading)
		
		case .brushThickness:
		
			ThicknessPanel(
				document: document,
				thicknessTarget: .brush,
				thicknessSelectionMode: $brushThicknessSelectionMode,
				changeAllOfSameThickness: $dummyBool)
			.frame(maxWidth: 320.0)
			.cornerRadius(geometryGamesCornerRadius)
			.modifier(BorderIfNeeded(
				over: document.itsBackgroundColor,
				cornerRadius: geometryGamesCornerRadius))
			.frame(maxWidth: .infinity, alignment: maybeLeading)
		
		case .smoothingTolerance:
			
			SmoothingTolerancePanel(document: document)
			.frame(maxWidth: .infinity, alignment: maybeLeading)
		
		case .backgroundColor:
		
			ColorPanel(
				document: document,
				colorTarget: .background,
				colorSelectionMode: $backgroundColorSelectionMode,
				changeAllOfSameColor: $dummyBool)
			.cornerRadius(geometryGamesCornerRadius)
			.modifier(BorderIfNeeded(
				over: document.itsBackgroundColor,
				cornerRadius: geometryGamesCornerRadius))
			.fixedSize()
			.frame(maxWidth: .infinity, alignment: maybeTrailing)

		case .symmetry:

			SymmetryPanel(
				document: document,
				shapePanelIsShown: $shapePanelIsShown)
			.frame(maxWidth: .infinity, alignment: maybeTrailing)

		case .export:

			//	It seems that
			//
			//	  On iOS
			//		fileURL is never nil, so we always have access
			//		to the drawing's name, which the GeometryGamesExportView's
			//		ShareLink uses as the subject line in an e-mail,
			//		a caption in an iMessage, etc.
			//
			//	  on macOS
			//		fileURL is nil for a new drawing,
			//		but the GeometryGamesExportView's ShareLink
			//		completely ignores the caption we pass to it.
			//
			//	So either way, the fallback value for theDrawingName
			//	never gets shown to the user.
			//
			let theDrawingName = fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
			//
			//	If the user sometimes saw the fallback value,
			//	we'd want to localize it, like this
			//
			//		?? Bundle.main.localizedString(
			//			forKey: "Untitled",
			//			value: nil,
			//			table: "GeometryGamesLocalizable" )
		
			if let theRenderer = renderer {

				GeometryGamesExportView(
					modelData: document,
					exportRenderer: theRenderer,
					caption: theDrawingName,
					
					//	KaleidoPaint passes these special-purpose parameters
					//	to support the option to export a (tileable) rectangle.
					exportTileableRectangleTitle:
						titleForExportTileableRectangle(shapeConstraints:
							document.itsWallpaperGroup.torusGroup.itsUnitCellShapeConstraints),
					prepareModelToRenderTileableRectangle: { availableWidthPx, availableHeightPx in
						document.prepareModelToExportTileableRectangle(
									availableWidthPx: availableWidthPx,
									availableHeightPx: availableHeightPx)
					},
					restoreModelAfterRenderingTileableRectangle: {
						document.restoreModelAfterExportingTileableRectangle()
					}
				)
				.modifier(BorderIfNeeded(
					over: document.itsBackgroundColor,
					cornerRadius: geometryGamesCornerRadius))
				.frame(maxWidth: .infinity, alignment: maybeTrailing)
			}
		
		case .helpMenuPanel:
			HelpMenuView(activePanel: $activePanel)
			.frame(maxWidth: .infinity, alignment: .trailing)
		
		case .helpQuickStart:
			
			KaleidoPaintHelpQuickStartView()
			.modifier(BorderIfNeeded(
				over: document.itsBackgroundColor,
				cornerRadius: geometryGamesCornerRadius))
			.frame(maxWidth: .infinity, alignment: maybeTrailing)
			
		case .helpEditor:
			
			KaleidoPaintHelpEditorView()
			.modifier(BorderIfNeeded(
				over: document.itsBackgroundColor,
				cornerRadius: geometryGamesCornerRadius))
			.frame(maxWidth: .infinity, alignment: maybeTrailing)
			
		case .helpTutorials:

			KaleidoPaintHelpTutorialsView()
			.modifier(BorderIfNeeded(
				over: document.itsBackgroundColor,
				cornerRadius: geometryGamesCornerRadius))
			.frame(maxWidth: .infinity, alignment: maybeTrailing)
			
		case .helpImageGallery:
			
			KaleidoPaintHelpImageGalleryView()
			.modifier(BorderIfNeeded(
				over: document.itsBackgroundColor,
				cornerRadius: geometryGamesCornerRadius))
			.frame(maxWidth: .infinity, alignment: maybeTrailing)
			
		case .helpContact:
			
			GeometryGamesContactView()
			.modifier(BorderIfNeeded(
				over: document.itsBackgroundColor,
				cornerRadius: geometryGamesCornerRadius))
			.frame(maxWidth: .infinity, alignment: maybeTrailing)
			
		case .translators:

			GeometryGamesTranslatorsView(theTranslatorThanks)
			.modifier(BorderIfNeeded(
				over: document.itsBackgroundColor,
				cornerRadius: geometryGamesCornerRadius))
			.frame(maxWidth: .infinity, alignment: maybeTrailing)

		}
	}
}

func titleForExportTileableRectangle(
	shapeConstraints: ShapeConstraints
) -> LocalizedStringKey {

	//	The unit torus is itself rectangular for wallpaper groups
	//	whose ShapeConstraints include .angle_2π_over_4, and
	//	a double cover of the unit torus is rectangular for groups
	//	whose ShapeConstraints include .rhombus.
	//
	//	There are only two groups that fall into neither of those categories,
	//	namely ○ and 2222.  We can export a rectangle even for them,
	//	but it will be tileable only with an offset.
	
	return
		( shapeConstraints.contains(.angle_2π_over_4)
	   || shapeConstraints.contains(.rhombus) )
	?
		"Tileable rectangle"
	:
		"Rectangle"
}


enum ColorTarget {
	case brush
	case fill
	case background
	case selectedObject
}

struct ColorPanel: View {

	@Bindable var document: KaleidoPaintDocument
	let colorTarget: ColorTarget
	@Binding var colorSelectionMode: SelectionMode
	@Binding var changeAllOfSameColor: Bool

	//	Work with LinearDisplayP3Colors as directly as possible,
	//	so that in-use colors may get reused exactly, without
	//	introducing the numerical errors that round-trip conversion
	//	to a SwiftUI Color and back might cause. This helps
	//	ensure that when the user asks to change all DrawingElements
	//	of a given color, none get missed because of tiny errors
	//	in their color components.

	//	SwiftUI's ColorPicker naturally insists on a Binding
	//	to a SwiftUI Color. When reading its value, our code in
	//
	//		onChange(of: colorPickerColorAsSwiftUIColor)
	//
	//	takes care to never copy a color that differs only
	//	trivially from the existing color.
	//
	@State var colorPickerColorAsSwiftUIColor: Color = .black	// updateColorPanelState sets this

	//	The currentColorAsLinearDisplayP3Color is relevant only when
	//	the colorTarget is .background or .selectedObject.
	@State private var currentColorAsLinearDisplayP3Color: LinearDisplayP3Color
		= LinearDisplayP3Color(r: 0.0, g: 0.0, b: 0.0, a: 0.0)	// updateColorPanelState sets this
	@State private var newColorAsLinearDisplayP3Color: LinearDisplayP3Color
		= LinearDisplayP3Color(r: 0.0, g: 0.0, b: 0.0, a: 0.0)	// updateColorPanelState sets this

	@State private var colorPickerLabel: LocalizedStringKey
														= "???" // updateColorPanelState sets this

	var body: some View {
	
		let updateColorPanelState = {
		
			switch colorTarget {
			
			case .brush:
			
				currentColorAsLinearDisplayP3Color = document.itsBrushColor
				colorPickerLabel = "Brush color"
				
			case .fill:
			
				currentColorAsLinearDisplayP3Color = document.itsFillColor
				colorPickerLabel = "Fill color"
				
			case .background:
			
				currentColorAsLinearDisplayP3Color = document.itsBackgroundColor
				colorPickerLabel = "New background color"
				
			case .selectedObject:
			
				if let theControlHandleHit = document.itsControlHandleHit {
				
					let theHitElement = theControlHandleHit.itsElement
					
					currentColorAsLinearDisplayP3Color = theHitElement.itsColor
					
					if theHitElement is Dot {
						colorPickerLabel = "New dot color"
					} else if theHitElement is Curve {
						colorPickerLabel = "New line color"
					} else if theHitElement is Fill {
						colorPickerLabel = "New fill color"
					} else {
						colorPickerLabel = "???"
					}
					
				} else {	//	should never occur
					currentColorAsLinearDisplayP3Color = LinearDisplayP3Color(r: 1.0, g: 0.0, b: 1.0, a: 1.0)
					colorPickerLabel = "???"
				}
			}
			
			newColorAsLinearDisplayP3Color = currentColorAsLinearDisplayP3Color
			colorPickerColorAsSwiftUIColor = newColorAsLinearDisplayP3Color.asSwiftUIColor()
		}

		let theSwatchCornerRadius = 4.0
		
		return VStack(alignment: .center) {
			
			Picker(
				"Color selection mode",	//	labelsHidden() hides this
				selection: $colorSelectionMode)
			{
				ForEach(SelectionMode.allCases) { mode in
					Image(systemName: mode.symbolSystemName())
				}
			}
			.pickerStyle(.segmented)
			.labelsHidden()
			.fixedSize()

			Group() {

				switch colorSelectionMode {
							
				case .new:
					ColorPicker(
						colorPickerLabel,
						selection: $colorPickerColorAsSwiftUIColor,
						supportsOpacity: false)

				case .previous:
					ColorPalette(
						document: document,
						colorAsLinearDisplayP3Color:
							$newColorAsLinearDisplayP3Color,
						colorTarget: colorTarget)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
						
			//	Changes to the brush and fill colors are handled
			//	in .onChange(of:) and don't need an Apply button.
			if colorTarget == .background
			|| colorTarget == .selectedObject {
			
				//	Why an "Apply" button?
				//
				//	As explained on the web page
				//
				//		https://stackoverflow.com/questions/66699101/swiftui-colorpicker-opened-and-closed-events
				//
				//	there's no way to know when the user dismisses
				//	the SwiftUI ColorPicker.  So the only way to put
				//	a color change onto the Undo stack is to insist
				//	that the user explicitly press an Apply button.
				//	This is not an ideal situation, but it's worth
				//	putting up with an Apply button in order to get
				//	the ColorPicker's many good features (custom color palette,
				//	several different selection modes, etc.).
				//
				Button() {

					//	Note:
					//	changeBackgroundColor(to:) and changeColor(of:to:)
					//	both increment itsUndoRedoCount. We'll respond to
					//	onChange(of: document.itsUndoRedoCount) to update
					//	our local State, so there's no need to explicitly
					//	update any colors here.
				
					switch colorTarget {
					
					case .brush, .fill:
						//	We've already restricted the Apply button
						//	to .background and .selectedObject.
						break
						
					case .background:
					
						document.changeBackgroundColor(
							to: newColorAsLinearDisplayP3Color)
						
					case .selectedObject:
					
						if let theControlHandleHit = document.itsControlHandleHit {
						
							let theElements = (changeAllOfSameColor ?
								document.itsElements.filter() { element in
									theControlHandleHit.itsElement.itsColor.isAlmostTheSameAs(element.itsColor)
								} :
								[theControlHandleHit.itsElement]
							)
							
							document.changeColor(
								of: theElements,
								to: newColorAsLinearDisplayP3Color)
						}
					}

				} label: {
					Text("Apply")
					.font(.system(size: 20))
					.modifier(applyForegroundAccentColorOnMacOS())
				}
				.disabled(newColorAsLinearDisplayP3Color == currentColorAsLinearDisplayP3Color)

				HStack(spacing: 0) {

					//	Swatch of new color
					Rectangle()
					.fill(newColorAsLinearDisplayP3Color.asSwiftUIColor())
					.frame(width: 64, height: 32, alignment: .center)

					//	Swatch of old color
					Rectangle()
					.fill(currentColorAsLinearDisplayP3Color.asSwiftUIColor())
					.frame(width: 64, height: 32, alignment: .center)
				}
				.cornerRadius(theSwatchCornerRadius)
				.modifier(BorderIfNeeded(
					over: LinearDisplayP3Color(fromSwiftUIColor: gSystemBackgroundColor) ??
							LinearDisplayP3Color(r: 1.0, g: 0.0, b: 1.0, a: 1.0),
					cornerRadius: theSwatchCornerRadius))
			}
				
			if colorTarget == .selectedObject {
				Toggle("Change everything of same color", isOn: $changeAllOfSameColor)
				.toggleStyle(.kaleidoPaintCheckbox)
			}
		}
		.modifier(buttonStyleOnMacOS())
		.font(.body)
		.padding(geometryGamesPanelPadding)
		.background(gSystemBackgroundColor)
		.onAppear() {
			//	On iOS, SwiftUI always calls onAppear() as expected,
			//	but on macOS, SwiftUI doesn't call onAppear() when
			//	the user taps from one DrawingElement to another,
			//	so in those cases we need to rely on the onChange(of:)
			//	call immediately below.
			updateColorPanelState()
		}
		.onChange(of: document.itsControlHandleHit?.itsElement, initial: false) {
			//	See comment in onAppear() immediately above.
			updateColorPanelState()
		}
		.onChange(of: document.itsUndoRedoCount) {
			//	If the user taps the Undo or Redo button
			//	while this ColorPanel is up, we'll need
			//	to refresh for that too.
			updateColorPanelState()
		}
		.onChange(of: colorSelectionMode) {
			//	Let's refresh the colors when changing the SelectionMode.
			updateColorPanelState()
		}
		.onChange(of: colorPickerColorAsSwiftUIColor) {
		
			//	Whenever the user intends different DrawingElements
			//	to have the same color, we want to make sure that
			//	they have *exactly* the same color, so that operations
			//	to change "all elements of the same color" will work
			//	reliably. In particular, we want to take care to avoid
			//	scenarios where we take a DrawingElement's LinearDisplayP3Color,
			//	convert it to a SwiftUI color for use in the SwiftUI ColorPicker,
			//	then convert it back again to a LinearDisplayP3Color
			//	with a tiny numerical error, and assign that ever-so-slightly
			//	different color back to the DrawingElement.
			//	Throughout this ColorPanel, we take the LinearDisplayP3Colors
			//	to be our reliable sources of truth, and consider
			//	the colorPickerColorAsSwiftUIColor to be only a rough approximation.
			
			if let theColorPickerColor = LinearDisplayP3Color(
											fromSwiftUIColor: colorPickerColorAsSwiftUIColor)
			{
				let ε = 0.01	//	allows for a small error with color components in 0-255
				if abs(theColorPickerColor.r - newColorAsLinearDisplayP3Color.r) > ε
				|| abs(theColorPickerColor.g - newColorAsLinearDisplayP3Color.g) > ε
				|| abs(theColorPickerColor.b - newColorAsLinearDisplayP3Color.b) > ε
				|| abs(theColorPickerColor.a - newColorAsLinearDisplayP3Color.a) > ε
				{
					newColorAsLinearDisplayP3Color = theColorPickerColor
				}
			}
		}
		.onChange(of: newColorAsLinearDisplayP3Color) {
						
			//	Change brush or fill colors immediately,
			//	without putting them onto the Undo stack.
			//
			switch colorTarget {
			
			case .brush:
				document.itsBrushColor = newColorAsLinearDisplayP3Color
				
			case .fill:
				document.itsFillColor = newColorAsLinearDisplayP3Color
				
			case .background, .selectedObject:
				//	Wait for the user to tap the Apply button.
				break
			}
		}
	}
}

struct ColorPalette: View {

	var document: KaleidoPaintDocument
	@Binding var colorAsLinearDisplayP3Color: LinearDisplayP3Color
	let colorTarget: ColorTarget

	@Environment(\.horizontalSizeClass) var horizontalSizeClass

	var body: some View {
	
		var theRedundantColors = document.itsElements.map{ element in element.itsColor }
		theRedundantColors.append(document.itsBackgroundColor)
		var theIncludedColors = Set<LinearDisplayP3Color>()
		let theUniqueColors = theRedundantColors.filter(){ color in
			theIncludedColors.insert(color).inserted
		}
				
		let theColorChipSize = 32.0
		let theColorChipSpacing: CGFloat? = 0.0
		let theBorderThickness = 2.0
		let theMaxColumnCount = horizontalSizeClass == .compact ? 5 : 6
		let theColumnCount = min(theMaxColumnCount, theUniqueColors.count)
		let theRowCount =
			theColumnCount > 0 ?		//	should never fail
			(theUniqueColors.count + (theColumnCount - 1)) / theColumnCount :
			1
		let theVisibleRowCount =
			colorTarget == .selectedObject ?
			(
				//	The Editor panel has less vertical space available
				//	than the other panels do.
				min(
				
					//	Show the 1 or 2 rows.
					Double(theRowCount),
					
					//	Show part but not all of the 3rd row, so the user
					//	sees that s/he may scroll to reach additional rows.
					2.375
				)
			) :
			(
				//	The panels for the pen, fill and background colors
				//	all have plenty of vertical space, so show all rows if possible.
				Double(theRowCount)
			)
		let theColumns = Array(
			repeating: GridItem(.fixed(theColorChipSize), spacing: theColorChipSpacing),
			count: theColumnCount)
		
		return ScrollView() {
		
			LazyVGrid(columns: theColumns, spacing: theColorChipSpacing) {
			
				//	If we let ForEach() act directly on theUniqueColors,
				//	then we'd need to make LinearDisplayP3Color Identifiable
				//	by adding a "var id: UUID".  That seems like unnecessary
				//	extra weight for what's otherwise a very lightweight struct,
				//	especially since this is the only place we'd need to use it.
				//	So let's let ForEach() act on the array indices instead.
				ForEach(0 ..< theUniqueColors.count, id: \.self) { i in
				
					let theColor = theUniqueColors[i]
					
					Rectangle()
					.fill(theColor.asSwiftUIColor())
					.stroke(.black, lineWidth: theBorderThickness)
						//	stroke gets centered on rectangle's perimeter
					.frame(width: theColorChipSize, height: theColorChipSize)
					.onTapGesture {
						colorAsLinearDisplayP3Color = theColor
					}
				}
			}
			.padding( // needed to avoid clipping "strokes" around the perimeter
				0.5 * theBorderThickness
			)
			.cornerRadius(4.0)
		}
		.frame(height: theVisibleRowCount * theColorChipSize  +  theBorderThickness)
	}
}


enum ThicknessTarget {
	case brush
	case selectedObject
}

struct ThicknessPanel: View {

	var document: KaleidoPaintDocument
	let thicknessTarget: ThicknessTarget
	@Binding var thicknessSelectionMode: SelectionMode
	@Binding var changeAllOfSameThickness: Bool

	//	WARNING!  Kludge alert: Dual "sources of truth" for the targeted thickness!
	//
	//	On the one hand, we want to work with the underlying thickness values
	//	as much as possible, so that in-use thicknesses may get reused exactly,
	//	without introducing the numerical errors that round-trip conversion
	//	to a log₂(thickness factor) and back would cause.
	//
	@State private var plainThickness = gDefaultThickness	//	overridden in .onAppear()
	//
	//	On the other hand, we want the Slider to display the thickness
	//	on a logarithmic scale, so we need to pass the Slider a binding
	//	to an explicit variable for log₂(thickness factor).
	//
	@State private var log2ThicknessFactor = 0.0			//	overridden in .onAppear()
	//
	//	Changes to the plainThickness get converted
	//	and passed along to the log2ThicknessFactor,
	//	except when the user is actively sliding
	//	the Slider, when the reverse is true.
	//
	@State private var userIsSlidingSlider: Bool = false
	

	@State private var startingThickness: Double?	//	Starting thickness for a thickness change
	@State private var endingThickness: Double?		//	 Ending  thickness for a thickness change

	@State private var affectedBrushstrokes: [Brushstroke] = []

	let theDefaultSampleLineThickness = 16.0	//	in points


	var body: some View {

		let theColor: Color
		let theTargetIsDot: Bool
		let theLabel: LocalizedStringKey
		switch thicknessTarget {
		
		case .brush:
		
			theColor = document.itsBrushColor.asSwiftUIColor()
			theLabel = "Brush thickness"
			theTargetIsDot = true
			
		case .selectedObject:
		
			if let theControlHandleHit = document.itsControlHandleHit {
			
				let theSelectedElement = theControlHandleHit.itsElement
				theColor = theSelectedElement.itsColor.asSwiftUIColor()
				theTargetIsDot = theSelectedElement is Dot
				theLabel = (theTargetIsDot ? "Dot size" : "Line thickness")
				
			} else {	//	should never occur
			
				theColor = Color(.displayP3, red: 0.0, green: 0.0, blue: 0.0, opacity: 1.0)
				theTargetIsDot = false
				theLabel = "???"
			}
		}

		let theSampleLineThickness = exp2(log2ThicknessFactor) * theDefaultSampleLineThickness
		let theSampleLineCornerRadius = 0.5 * theSampleLineThickness
	
		return VStack(alignment: .center) {
		
			Picker(
				"Thickness selection mode",	//	We'll set labelsHidden()
				selection: $thicknessSelectionMode)
			{
				ForEach(SelectionMode.allCases) { mode in
					Image(systemName: mode.symbolSystemName())
				}
			}
			.pickerStyle(.segmented)
			.labelsHidden()
			.fixedSize()

			HStack(alignment: .center) {

				Text(theLabel)
				.fixedSize()
				
				Spacer()
				
				//	The RoundedRectangle() itself has a height
				//	that's proportional to the line thickness.
				//	But it's enclosed in an extra frame of fixed height,
				//	so that the panel's total height stays constant
				//	even as the user varies the line thickness
				//	(well, except for the thickest thicknesses).
				//
				RoundedRectangle(cornerSize: CGSize(
									width: theSampleLineCornerRadius,
									height: theSampleLineCornerRadius))
				.frame(height: theSampleLineThickness)
				.frame(maxWidth: (theTargetIsDot ?
									theSampleLineThickness :
									128.0))
				.foregroundStyle(theColor)
				.frame(
					maxWidth: .infinity,
					alignment: (theTargetIsDot ? .center : .trailing))
			}

			switch thicknessSelectionMode {
			
			case .new:

				ThicknessSlider(
					plainThickness: $plainThickness,
					log2ThicknessFactor: $log2ThicknessFactor,
					userIsSlidingSlider: $userIsSlidingSlider,
					startingThickness: $startingThickness,
					endingThickness: $endingThickness)
				
			case .previous:
				
				ThicknessPalette(
					document: document,
					thicknessTarget: thicknessTarget,
					startingThickness: $startingThickness,
					endingThickness: $endingThickness)
			}

			if thicknessTarget == .selectedObject {
				Toggle("Change everything of same thickness", isOn: $changeAllOfSameThickness)
					.toggleStyle(.kaleidoPaintCheckbox)
			}
		}
		.font(.body)
		.padding(geometryGamesPanelPadding)
		.background(gSystemBackgroundColor)
		.onAppear{
			
			switch thicknessTarget {
			
			case .brush:
				plainThickness = document.itsBrushThickness
				
			case .selectedObject:
				if let theSelectedBrushstroke
					= document.itsControlHandleHit?.itsElement as? Brushstroke {
					
					plainThickness = theSelectedBrushstroke.itsThickness
					
				} else {	//	should never occur
				
					plainThickness = gDefaultThickness
				}
			}
			
			//	.onChange(of: plainThickness) will now
			//	set log2ThicknessFactor as well.
		}
		.onChange(of: plainThickness) {
		
			//	Copy the converted plainThickness to log2ThicknessFactor
			//	in response to .onAppear() and then whenever
			//	the user chooses a color from the ColorPalette.
			//	(When the user is actively sliding the Slider we'll copy
			//	the converted log2ThicknessFactor to the plainThickness.)
			//
			if !userIsSlidingSlider {
			
				log2ThicknessFactor = log2(plainThickness / gDefaultThickness)
			}

			//	Whether the user is using the slider or not, apply
			//	the new plainThickness to any affectedBrushstrokes.
			//
			if thicknessTarget == .selectedObject {

				for theAffectedBrushstroke in affectedBrushstrokes {

					//	Set theAffectedBrushstroke's thickness
					//	without putting it on the Undo/Redo stack
					//	and without recomputing flood fills.
					//	This will give the user a rough idea what
					//	the new thickness looks like in the drawing.
					
					theAffectedBrushstroke.itsThickness = plainThickness
				}
				
				if !affectedBrushstrokes.isEmpty {
				
					document.itsBaseDrawingTextureFullRedrawRequestCount += 1
					document.changeCount += 1
				}
			}
		}
		.onChange(of: log2ThicknessFactor) {

			//	Copy the converted log2ThicknessFactor to the plainThickness
			//	only while the user is actively sliding the Slider.
			//	(In response to .onAppear(), and then later whenever
			//	the user chooses a color from the ColorPalette we'll copy
			//	the converted plainThickness to the log2ThicknessFactor.)
			//
			if userIsSlidingSlider {
			
				plainThickness = exp2(log2ThicknessFactor) * gDefaultThickness
			}
		}
		.onChange(of: startingThickness) {
		
			if startingThickness != nil {
			
				switch thicknessTarget {
				
				case .brush:
				
					affectedBrushstrokes = []	//	empty array for brush thickness
				
				case .selectedObject:
				
					if let theSelectedBrushstroke	//	should never fail
						= document.itsControlHandleHit?.itsElement as? Brushstroke {
					
						if changeAllOfSameThickness {
						
							affectedBrushstrokes =
								document.itsElements
								.compactMap() { element in
									element as? Brushstroke
								}
								.filter() { brushstroke in
									brushstroke.itsThickness == theSelectedBrushstroke.itsThickness
								}
						
						} else {
						
							affectedBrushstrokes = [theSelectedBrushstroke]
						}
					
					} else {	//	should never occur
					
						affectedBrushstrokes = []
					}
				}
			}
		}
		.onChange(of: endingThickness) {
		
			if let theEndingThickness = endingThickness {
			
				switch thicknessTarget {
				
				case .brush:
				
					//	Set the brush thickness directly,
					//	without putting it on the Undo stack.
					document.itsBrushThickness = theEndingThickness
					
				case .selectedObject:

					if let theStartingThickness = startingThickness {
					
						//	Put the change from the theStartingThickness
						//	to theEndingThickness on the Undo stack.
						//
						//	changeThickness() will change
						//	the affectedBrushstrokes' thicknesses,
						//	and also call clearCachedRLERuns()
						//	to re-create any affected fills.
						
						document.changeThickness(
							of: affectedBrushstrokes,	//	listed in the same order they get drawn
							from: theStartingThickness,
							to: theEndingThickness)
					}
				}
				
				//	Clean up.
				startingThickness = nil
				endingThickness = nil
				affectedBrushstrokes = []	//	OK to clear before setting plainThickness,
											//	because document.changeThickness() will have
											//	taken care of the affectedBrushstrokes.

				//	If the user slid the ThicknessSlider, it will have kept
				//	the log2ThicknessFactor and thence also the plainThickness
				//	updated at all times.
				//
				//	But if the user selected theEndingThickness
				//	in the ThicknessSlider, we'll have to update
				//	the plainThickness and thence also the log2ThicknessFactor.
				//
				if thicknessSelectionMode == .previous {
				
					//	We've already cleared the array of affectedBrushstrokes,
					//	setting plainThickness won't have any side effects
					//	other than to (sometimes redundantly) set log2ThicknessFactor.
					plainThickness = theEndingThickness
				}
			}
		}
	}
}

struct ThicknessSlider: View {

	@Binding var plainThickness: Double
	@Binding var log2ThicknessFactor: Double
	@Binding var userIsSlidingSlider: Bool
	@Binding var startingThickness: Double?	//	Starting thickness for a thickness change
	@Binding var endingThickness: Double?	//	 Ending  thickness for a thickness change

	var body: some View {

		Slider(
			value: $log2ThicknessFactor,
			in: minLog2ThicknessFactor ... maxLog2ThicknessFactor,
			onEditingChanged: {isEditing in
			
				userIsSlidingSlider = isEditing
			
				if isEditing {

					//	The user began sliding the slider.
					//	.onChange(of: startingThickness) will compute the affectedBrushstrokes.
					//
					//		Note:  Apple's documentation says only that
					//
					//			"The slider calls onEditingChanged
					//			when editing begins and ends."
					//
					//		without explicitly say whether the "editing begins" call
					//		includes some small initial change or not.  Fortunately,
					//		in practice the value we get here for log2ThicknessFactor
					//		is the value from just before editing began.  That is,
					//		it doesn't include any small initial change.
					//
					
					startingThickness = plainThickness

				} else {

					//	The user finished sliding the slider.
					//	.onChange(of: endingThickness) will handle the change.
					
					endingThickness = plainThickness
				}
			}
		)
		.frame(width: thicknessSliderLength)
	}
}

//	The length of the SwiftUI Slider includes room
//	for the entire "thumb" at each end.
//	In other words, the usable track length
//	is two thumb radii less than the length
//	of the Slider as a whole.
//
let theExpectedThumbRadius = 13.0	//	an empiral observation -- not documented
let theTrackLength = thicknessSliderLength - 2.0 * theExpectedThumbRadius
let theTrackHeight = 4.0
let theInUseMarkerHeight = 20.0
let theInUseMarkerWidth = 4.0
let theCurrentMarkerHeight = 32.0
let theCurrentMarkerWidth = 2.0
let theButtonHeight = theCurrentMarkerHeight
let theTrackColor = Color(.displayP3, red: 0.875, green: 0.875, blue: 0.875, opacity: 0.875)

struct ThicknessPalette: View {

	var document: KaleidoPaintDocument
	let thicknessTarget: ThicknessTarget

	@Binding var startingThickness: Double?
	@Binding var endingThickness: Double?
	
	let inUseMarkerColor = Color(.displayP3, red: 0.00, green: 0.75, blue: 0.25, opacity: 1.0)
	let currentMarkerColor = Color(.displayP3, red: 0.00, green: 0.50, blue: 0.75, opacity: 1.0)

	var body: some View {
			
		//	Compute the positions where the in-use thickness markers
		//	should site on the track.  The positions are measured
		//	in points, on a scale from 0 to theTrackLength.
		let theBrushstrokes = document.itsElements.compactMap(){ element in
			element as? Brushstroke}
		let theRedundantThickesses = theBrushstrokes.map() {brushstroke in brushstroke.itsThickness}
		var theIncludedThickesses = Set<Double>()
		let theUniqueThicknesses = theRedundantThickesses.filter(){ thickness in
			theIncludedThickesses.insert(thickness).inserted
		}
		let theSortedThicknesses = theUniqueThicknesses.sorted()
		let thePlacements: [(Double, Double)]
				//	returns (thickness, x position in range (0.0, theTrackLength))
			= theSortedThicknesses.map() { thickness in
			(
				thickness,
				(
					(log2(thickness / gDefaultThickness) - minLog2ThicknessFactor)
				  / (      maxLog2ThicknessFactor        - minLog2ThicknessFactor)
				)
				* theTrackLength
			)
		}
		let theRanges: [(Double, Double, Double)] = makeTappableRanges(placements: thePlacements)
		
		let theCurrentThickness: Double = ( thicknessTarget == .brush ?
			
				//	.brush
				document.itsBrushThickness  :
				
				//	.selectedObject
				(document.itsControlHandleHit?.itsElement as? Brushstroke)?.itsThickness ?? gDefaultThickness
		)
			
		let theCurrentThicknessPosition =
			(
				(log2(theCurrentThickness / gDefaultThickness) - minLog2ThicknessFactor)
			  / (maxLog2ThicknessFactor - minLog2ThicknessFactor)
			)
			* theTrackLength
		
		ZStack() {

			Rectangle()
			.frame(width: theTrackLength, height: theTrackHeight)
			.foregroundStyle(theTrackColor)
			.cornerRadius(2.0)
			
			ForEach(thePlacements, id: \.1) { thickness, position in

				Rectangle()
				.frame(width: theInUseMarkerWidth, height: theInUseMarkerHeight)
				.foregroundStyle(inUseMarkerColor)
				.cornerRadius(2.0)
				.position(	//	places Rectangle's center
					x: theExpectedThumbRadius + position,
					y: 0.5 * theCurrentMarkerHeight)
			}
			
			Rectangle()
			.frame(width: theCurrentMarkerWidth, height: theCurrentMarkerHeight)
			.foregroundStyle(.blue)
			.position(	//	places Rectangle's center
				x: theExpectedThumbRadius + theCurrentThicknessPosition,
				y: 0.5 * theCurrentMarkerHeight)

			//	Invisible -- yet tappable -- rectangles provide
			//	nice wide targets for the user to tap.
			//	Each tappable rectangle includes a given thickness
			//	and extends halfway to the neighboring thickness
			//	on either side.
			//
			ForEach(theRanges, id: \.1) { thickness, leading, trailing in

				Rectangle()
				.frame(width: trailing - leading, height: theCurrentMarkerHeight)
				.foregroundStyle(.clear)	//	By default, transparent rectangles aren't tappable, but…
				.contentShape(Rectangle())	//	…this makes rectangle tappable in spite of transparency.
				.position(	//	places Rectangle's center
					x: theExpectedThumbRadius + 0.5 * (leading + trailing),
					y: 0.5 * theCurrentMarkerHeight)
				.onTapGesture() {
				
					//	The ThicknessPanel's onChange(of: startingThickness)
					//	will determine which Brushstrokes are affected.
					startingThickness = theCurrentThickness
					
					//	The ThicknessPanel's onChange(of: endingThickness)
					//	will make the change.
					endingThickness = thickness
				}
			}
		}
		.frame(
			width: thicknessSliderLength,
			height: theCurrentMarkerHeight)
	}

	func makeTappableRanges(
		placements: [(Double, Double)]
	) -> [(Double, Double, Double)] {	//	returns (thickness, leading x, trailing x)
	
		//	Let each range include the given thickness
		//	and extend halfway to the neighboring thickness
		//	on either side.
		
		let theIndices = 0 ..< placements.count
		let theTappableRanges = theIndices.map() {i in
		
			(
				//	thickness
				placements[i].0,
				
				//	leading x
				i > 0 ?
					0.5 * (placements[i-1].1 + placements[i].1) :
					0.0,
					
				//	trailing x
				i < theIndices.upperBound - 1 ?
					0.5 * (placements[i].1 + placements[i+1].1) :
					theTrackLength
			)
		}
		
		return theTappableRanges
	}
}


struct KaleidoPaintCheckboxToggleStyle: ToggleStyle {

	func makeBody(configuration: Configuration) -> some View {

		HStack() {

			configuration.label
			.font(.system(size: 10))
			//	.multilineTextAlignment(.leading)
			
			Spacer()
			
			Button() {
			
				configuration.isOn.toggle()
				
			} label: {
			
					Image(systemName:
						configuration.isOn ? "checkmark.square" : "square")
			}
			.buttonStyle(.borderless)
			.modifier(applyForegroundAccentColorOnMacOS())
		}
	}
}

extension ToggleStyle where Self == KaleidoPaintCheckboxToggleStyle {
	static var kaleidoPaintCheckbox: KaleidoPaintCheckboxToggleStyle { .init() }
}


enum WallpaperGroupNotation: String, CaseIterable, Identifiable {
	
	case noNotation
	case orbifold
	case crystallographic
	
	var id: String { self.rawValue }

	var localizedName: String {
	
		Bundle.main.localizedString(
			forKey: self.rawValue,
			value: nil,
			table: nil)
	}
}

struct SymmetryPanel: View {

	@Environment(\.horizontalSizeClass) var horizontalSizeClass
	@Environment(\.verticalSizeClass) var verticalSizeClass

	@Bindable var document: KaleidoPaintDocument

	@Binding var shapePanelIsShown: Bool

	@State var notation = WallpaperGroupNotation(rawValue:
		UserDefaults.standard.string(forKey: "wallpaper group notation") ?? "orbifold") ?? .orbifold

	let theButtonHSpacing = 8.0
	let theButtonVSpacing = 8.0

	var body: some View {

		let theDisplayIsLarge = (
			horizontalSizeClass == .regular
		 && verticalSizeClass   == .regular)
		 
		let theButtonOrderOnCompactDisplay: [WallpaperGroup] =
			[.wpg2222, .wpgS2222, .wpg2S22, .wpg333, .wpgS333, .wpg3S3, .wpg442, .wpgS442, .wpg4S2, .wpg632, .wpgS632, .wpg22S, .wpg22X, .wpgSS, .wpgSX, .wpgXX, .wpgO]
		
		return VStack(alignment: .leading) {

			if theDisplayIsLarge {
			
				Text("Symmetry pattern")
				.font(.title2)	//	use a larger font on large display
				.padding(EdgeInsets(top: 4.0, leading: 0.0, bottom: 8.0, trailing: 0.0))
				.frame(maxWidth: .infinity, alignment: .center)
		
				VStack(alignment: .center, spacing: theButtonVSpacing) {
				
					HStack(spacing: theButtonHSpacing) {
					
						WallpaperGroupButton(
							wallpaperGroup: .wpgS2222,
							document: document,
							notation: notation)
							
						WallpaperGroupButton(
							wallpaperGroup: .wpgS333,
							document: document,
							notation: notation)
						
						WallpaperGroupButton(
							wallpaperGroup: .wpgS442,
							document: document,
							notation: notation)
						
						WallpaperGroupButton(
							wallpaperGroup: .wpgS632,
							document: document,
							notation: notation)
					
						WallpaperGroupButton(
							wallpaperGroup: .wpgO,
							document: document,
							notation: notation)
						.hidden()
					
						WallpaperGroupButton(
							wallpaperGroup: .wpgO,
							document: document,
							notation: notation)
						.hidden()
					
						WallpaperGroupButton(
							wallpaperGroup: .wpgO,
							document: document,
							notation: notation)
					}
					
					HStack(spacing: theButtonHSpacing) {
					
						WallpaperGroupButton(
							wallpaperGroup: .wpg2222,
							document: document,
							notation: notation)
						
						WallpaperGroupButton(
							wallpaperGroup: .wpg333,
							document: document,
							notation: notation)
						
						WallpaperGroupButton(
							wallpaperGroup: .wpg442,
							document: document,
							notation: notation)
						
						WallpaperGroupButton(
							wallpaperGroup: .wpg632,
							document: document,
							notation: notation)
					
						WallpaperGroupButton(
							wallpaperGroup: .wpgO,
							document: document,
							notation: notation)
						.hidden()
						
						WallpaperGroupButton(
							wallpaperGroup: .wpg22S,
							document: document,
							notation: notation)
						
						WallpaperGroupButton(
							wallpaperGroup: .wpg22X,
							document: document,
							notation: notation)
					}
					
					HStack(spacing: theButtonHSpacing) {
						
						WallpaperGroupButton(
							wallpaperGroup: .wpg2S22,
							document: document,
							notation: notation)
						
						WallpaperGroupButton(
							wallpaperGroup: .wpg3S3,
							document: document,
							notation: notation)
						
						WallpaperGroupButton(
							wallpaperGroup: .wpg4S2,
							document: document,
							notation: notation)
					
						WallpaperGroupButton(
							wallpaperGroup: .wpgO,
							document: document,
							notation: notation)
						.hidden()
						
						WallpaperGroupButton(
							wallpaperGroup: .wpgSS,
							document: document,
							notation: notation)
						
						WallpaperGroupButton(
							wallpaperGroup: .wpgSX,
							document: document,
							notation: notation)
						
						WallpaperGroupButton(
							wallpaperGroup: .wpgXX,
							document: document,
							notation: notation)
					}
				}
			
			} else {	//	size class is compact
			
				//	On iOS 15 I couldn't find a way to cajole SwiftUI
				//	to reliably display the title "Symmetry Pattern Longer"
				//	(which simulates the longer title we might expect
				//	in some non-English languages) without truncation
				//	when theDisplayIsLarge == false.  Strangely enough,
				//	it would sometimes split the title into two lines
				//	and sometimes truncate it, depending on seemingly
				//	irrelevant factors.  So as a fallback plan,
				//	let's display a shorter title on small displays.
				//
				Text("Symmetry")
				.padding(EdgeInsets(top: 4.0, leading: 0.0, bottom: 8.0, trailing: 0.0))
				.frame(maxWidth: .infinity, alignment: .center)
		
				ScrollViewReader() { proxy in
				
					ScrollView(.horizontal) {
					
						HStack() {
						
							ForEach(theButtonOrderOnCompactDisplay) { wallpaperGroup in
							
								WallpaperGroupButton(
									wallpaperGroup: wallpaperGroup,
									document: document,
									notation: notation)
								.padding(2.0)	//	workaround for a clipping artifact in ScrollView
								.id(wallpaperGroup.id)
							}
						}
					}
					.onAppear() {
						proxy.scrollTo(document.itsWallpaperGroup.id,
						anchor: .center)
					}
				}
			}

			VStack() {

				NotationButton(notation: $notation)
				
				Toggle(isOn: $document.itsShowSingularitiesFlag) {
					Text("Grid")
				}
					
				Toggle(isOn: $document.itsColorBySymmetryFlag) {
					Text("Color by symmetry")
				}
				
				HStack() {
				
					RealignButton(document: document)
					
					Spacer()
					.frame(width: 16.0)
								
					ShapeButton(
						document: document,
						shapePanelIsShown: $shapePanelIsShown)
					.disabled(document.itsWallpaperGroup.torusGroup.itsRigidity == .rigid)
				}
			}
			.fixedSize(horizontal: true, vertical: false)
			.frame(maxWidth: .infinity, alignment: .center)
		}
		.modifier(buttonStyleOnMacOS())
		.frame(maxWidth: (theDisplayIsLarge ? .infinity : 304.0))
		.fixedSize()
		.padding(geometryGamesPanelPadding)
		.background(gSystemBackgroundColor)
		.cornerRadius(geometryGamesCornerRadius)
		.modifier(BorderIfNeeded(
			over: document.itsBackgroundColor,
			cornerRadius: geometryGamesCornerRadius))
		.onChange(of: notation) {

			UserDefaults.standard.set(
				notation.rawValue,
				forKey: "wallpaper group notation")
		}
		.onChange(of: document.itsShowSingularitiesFlag) {
		
			//	We don't need to redraw itsUnitCellSingularitiesTexture,
			//	because we keep it up date even when it's not visible,
			//	but we do need to refresh itsUnitCellComposedTexture
			//	to include it.
			
			document.itsCompositeTextureRedrawRequestCount += 1
			document.changeCount += 1
		}
		.onChange(of: document.itsColorBySymmetryFlag) {
		
			document.itsBaseDrawingTextureFullRedrawRequestCount += 1
			document.itsCurveInProgressTextureRedrawRequestCount += 1	//	unnecessary but safe
			document.changeCount += 1
		}
	}
}

struct WallpaperGroupButton: View {

	let wallpaperGroup: WallpaperGroup
	var document: KaleidoPaintDocument
	let notation: WallpaperGroupNotation
	
	var body: some View {
	
		let theOptionalLabel: String?
		switch notation {
		
		case .noNotation:
			theOptionalLabel = nil
			
		case .orbifold:
			theOptionalLabel = wallpaperGroup.orbifoldName
			
		case .crystallographic:
			theOptionalLabel = wallpaperGroup.IUCName
		}
	
		let theButtonSize =	64.0	//	size in points
		let theCornerRadius = 16.0
		let theBorderWidth = 1.0
		
		let theDefaultButtonBackgroundColor = Color.white
		let theSelectedButtonBackgroundColor = Color(.displayP3, red: 0.00, green: 0.25, blue: 1.00)
		let theBorderColor = Color(.displayP3, red: 0.50, green: 0.50, blue: 0.75)
	
		return Button() {
		
			if wallpaperGroup != document.itsWallpaperGroup {
			
				let theDefaultUnitCellPlacement = UnitCellPlacement(
					defaultForWallpaperGroup: wallpaperGroup)

				document.changeWallpaperGroup(
					to: wallpaperGroup,
					placement: theDefaultUnitCellPlacement)
			}
		
		} label: {
		
			VStack(spacing: 4.0) {
		
				Image("wallpaper group panel buttons/" + wallpaperGroup.rawValue)
					.resizable()
					.frame(width: theButtonSize, height: theButtonSize)
					.background(wallpaperGroup == document.itsWallpaperGroup ?
									theSelectedButtonBackgroundColor :
									theDefaultButtonBackgroundColor)
					.cornerRadius(theCornerRadius)
					.overlay(
						RoundedRectangle(cornerRadius: theCornerRadius)
							.stroke(theBorderColor, lineWidth: theBorderWidth)
					)
				
				if let theLabel = theOptionalLabel {
				
					Text(theLabel)
					.font(.body)
					.modifier(applyForegroundAccentColorOnMacOS())
				}
			}
		}
	}
}

struct NotationButton: View {

	@Binding var notation: WallpaperGroupNotation

	var body: some View {

		HStack(spacing: 0.0) {
		
			Text("Notation")
#if os(macOS)
			Text(":")
#endif
#if os(iOS)
			Spacer()
#endif
			Picker(
				"Notation",	//	label not shown
				selection: $notation
			) {
				ForEach(WallpaperGroupNotation.allCases, id: \.self) { notationName in
					Text(notationName.localizedName)
				//	.modifier(applyForegroundAccentColorOnMacOS())	//	has no effect (?!)
					.foregroundStyle(Color.accentColor)				//	works fine
					.tag(notationName)	//	.tag must come after .foregroundStyle
				}
			}
			.pickerStyle(MenuPickerStyle())
			.labelsHidden()	//	needed on macOS, but iOS hides the label no matter what
			.fixedSize()
		}
	}
}

struct RealignButton: View {

	var document: KaleidoPaintDocument

	var body: some View {

		Button() {
			
			//	Restore itsUnitCellPlacement's default position.
			//
			//		Note:  When the user uses two fingers
			//		to translate, rotate and/or zoom the drawing,
			//		we make the change directly, without putting it
			//		onto the Undo stack.  But when the user
			//		taps the Realign button, we *do* put the change
			//		onto the Undo stack, because it might alter
			//		the drawing's aspect ratio.
			//
			
			let theOldPlacement = document.itsUnitCellPlacement
			let theNewPlacement = UnitCellPlacement(
									defaultForWallpaperGroup: document.itsWallpaperGroup)
			
			document.changeUnitCellPlacement(
				oldPlacement: theOldPlacement,
				newPlacement: theNewPlacement)

		} label: {
			Text("Realign")
			.modifier(applyForegroundAccentColorOnMacOS())
		}
	}
}

struct ShapeButton: View {

	@Bindable var document: KaleidoPaintDocument
	@Binding var shapePanelIsShown: Bool

	@State var itsOldShape: UnitCellShape?

	var body: some View {

		Button() {
			
			shapePanelIsShown.toggle()

		} label: {
			Text("Aspect ratio")
			.modifier(applyForegroundAccentColorOnMacOS())
		}
		.popover(isPresented: $shapePanelIsShown) {
		
			//	The popover seems to be modal only with respect
			//	to taps in Views that don't at least potentially affect
			//	the presence of the ShapeButton or ShapePanel.
			//	By contrast, Views that might affect the presence
			//	of the ShapeButton or ShapePanel respond to the tap used to dismiss
			//	the popover and, when that happens, sometimes
			//	shapePanelIsShown doesn't get reset to false
			//	and thus document.changeUnitCellShape() doesn't get called.
			//	That happens, for example, when the user selects
			//	a reshapable group (for example ××), opens the ShapePanel
			//	and then taps on a Button for a non-reshapable group
			//	(for example *623) or on a toolbar Button.
			//
			//	To ensure that document.changeUnitCellShape() gets called,
			//	we may respond to .onAppear() and .onDisappear()
			//	and ignore .onChange(of: shapePanelIsShown).

			ShapePanel(document: document)
			.onAppear() {

				//	The panel is just now appearing.
				//	Remember the unit cell's shape.
				
				itsOldShape = document.getUnitCellShape()
			}
			.onDisappear() {

				//	The panel is just now disappearing.
				//	If unit cell's shape has changed,
				//	submit the change to the Undo stack.
				
				let theShape = document.getUnitCellShape()
				
				if theShape != itsOldShape {
			
					if let theOldShape = itsOldShape {
					
						document.changeUnitCellShape(
							oldShape: theOldShape,
							newShape: theShape)
						
						itsOldShape = nil	//	just to be tidy
					}
				}
			}
		}
	}
}


struct SmoothingTolerancePanel: View {

	@Bindable var document: KaleidoPaintDocument

	let theMinSmoothingTolerance = 0.001
	let theMaxSmoothingTolerance = 0.016
	
	let theLabelSize = 32.0
	let theLabelLineThickness = 4.0

	var body: some View {
		
		let theBrushColorAsSwiftUIColor = document.itsBrushColor.asSwiftUIColor()
		
		return VStack(alignment: .center) {
		
			Text("Line smoothing")
		
			Slider(
				value: $document.itsSmoothingTolerance,
				in: theMinSmoothingTolerance ... theMaxSmoothingTolerance,
				label: {
					Text("Smoothing Tolerance")	//	We'll set labelsHidden()
				},
				minimumValueLabel: {
					SmoothedLine(lineIsWiggly: true)
					.stroke(style: StrokeStyle(
									lineWidth: theLabelLineThickness,
									lineCap: .round))
					.foregroundStyle(theBrushColorAsSwiftUIColor)
					.frame(width: theLabelSize, height: theLabelSize)
				},
				maximumValueLabel: {
					SmoothedLine(lineIsWiggly: false)
					.stroke(style: StrokeStyle(
									lineWidth: theLabelLineThickness,
									lineCap: .round))
					.foregroundStyle(theBrushColorAsSwiftUIColor)
					.frame(width: theLabelSize, height: theLabelSize)
				}
			)
			.labelsHidden()
			.frame(maxWidth: 256.0)
			.padding(geometryGamesControlPadding)
		}
		.font(.body)
		.padding(geometryGamesPanelPadding)
		.background(gSystemBackgroundColor)
		.cornerRadius(geometryGamesCornerRadius)
		.modifier(BorderIfNeeded(
			over: document.itsBackgroundColor,
			cornerRadius: geometryGamesCornerRadius))
	}
}


struct SmoothedLine: Shape {

	let lineIsWiggly: Bool

	func path(in rect: CGRect) -> Path {
	
		//	Note:  A SwiftUI Path's origin sits at the upper left.
		
		//	Choose the control points.
		let c: [CGPoint]
		if lineIsWiggly {
			c = [
				CGPoint(x: 0.110, y: 0.865),
				CGPoint(x: 0.100, y: 0.605),
				CGPoint(x: 0.260, y: 0.510),
				CGPoint(x: 0.255, y: 0.245),
				CGPoint(x: 0.510, y: 0.260),
				CGPoint(x: 0.605, y: 0.085),
				CGPoint(x: 0.865, y: 0.110)
			]
		} else {
			c = [
				CGPoint(x: 0.25, y: 0.125)
			]
		}
		let theNumControlPoints = c.count
		
		//	Compute the points on the curve.
		var p: [CGPoint] = []
		p.reserveCapacity(theNumControlPoints + 1)
		p.append(CGPoint(x: 0.0, y: 1.0))
		for i in 0 ..< (theNumControlPoints - 1) {
			p.append(CGPoint(
				x: 0.5 * (c[i].x + c[i+1].x),
				y: 0.5 * (c[i].y + c[i+1].y)))
		}
		p.append(CGPoint(x: 1.0, y: 0.0))
		let theNumPoints = p.count
		precondition(
			theNumPoints == theNumControlPoints + 1,
			"Internal error: Bezier points and control points aren't consistent")
		
		//	Scale the control point and regular points
		//	to fit the given CGRect.
		let cc = c.map() { unscaledControlPoint in
		
			CGPoint(
				x: rect.origin.x  +  unscaledControlPoint.x * rect.size.width,
				y: rect.origin.y  +  unscaledControlPoint.y * rect.size.height)
		}
		let pp = p.map() { unscaledPoint in
		
			CGPoint(
				x: rect.origin.x  +  unscaledPoint.x * rect.size.width,
				y: rect.origin.y  +  unscaledPoint.y * rect.size.height)
		}
		
		//	Create thePath.
		
		var thePath = Path()
		
		thePath.move(to: pp[0])
		
		for i in 0 ..< (theNumPoints - 1) {
		
			thePath.addQuadCurve(to: pp[i+1], control: cc[i])
		}
		
		return thePath
	}
}


// MARK: -
// MARK: Shape panel

struct ShapePanel: View {

	var document: KaleidoPaintDocument
	
	@State var itsLog2AspectRatio = 0.0
	let itsMinLog2AspectRatio = -2.0	//	aspect ratio 1/4
	let itsMaxLog2AspectRatio = +2.0	//	aspect ratio  4
	
	@State var itsShear = 0.0
	let itsMinShear = -2.0
	let itsMaxShear = +2.0

	var body: some View {
	
		let theRigidity = document.itsWallpaperGroup.torusGroup.itsRigidity
		
		let theSnapTolerance = 0.125
		
		//	The code here modifies itsUnitCellPlacement directly.
		//	When the user dismisses this ShapePanel, the caller
		//	takes responsibility for putting the overall change
		//	onto the Undo stack.
		VStack() {
		
			//	When the user opens ShapePanel and then switches to a rigid group,
			//	The ShapePanel will be shown briefly for the rigid group
			//	before it disappears.  So we shouldn't display any sort
			//	of error message for a rigid group - just display an empty VStack.

			if theRigidity != .rigid {	//	group has some flexibility
			
				Slider(
					value: $itsLog2AspectRatio,
					in: itsMinLog2AspectRatio ... itsMaxLog2AspectRatio,
					onEditingChanged: {isEditing in
					
						//	When the user releases the slider...
						if !isEditing {
						
							//	...with a value close to zero...
							if abs(itsLog2AspectRatio) < theSnapTolerance {
							
								//	...snap exactly to zero
								itsLog2AspectRatio = 0.0
							}
						}
					}
				)
				.frame(width: 256.0)
				.onAppear() {

					let theShape = document.getUnitCellShape()
					
					itsLog2AspectRatio = log2(theShape.aspectRatio)
				}
				.onChange(of: itsLog2AspectRatio) {
									
					let theCurrentShape = document.getUnitCellShape()
					let theNewAspectRatio = exp2(itsLog2AspectRatio)
					let theNewShape = UnitCellShape(
										aspectRatio: theNewAspectRatio,
										shear: theCurrentShape.shear)
					
					document.setUnitCellShape(theNewShape)
										
					//	As the user drags the slider, we reshape
					//	the drawing using the existing unit cell textures,
					//	because that's a quick operation.
					//
					//	We won't redraw the unit cell textures
					//	until the user dismisses this ShapePanel,
					//	because that can be a slow operation
					//	if the drawing contain lots of filled regions.
					//
					document.changeCount += 1
				}
				
				Text("Aspect ratio")
				.font(.caption)
			}
			
			if theRigidity == .fullyFlexible {
			
				Slider(
					value: $itsShear,
					in: itsMinShear ... itsMaxShear,
					onEditingChanged: {isEditing in
					
						//	In order to support "half drop" patterns
						//	(as requested by Rebecca Elfast),
						//	when the user releases the slider...
						if !isEditing {
						
							//	...with a value close to an integer or half-integer...
							let theNearestSnapPoint = 0.5 * round(2.0 * itsShear)
							let theDifference = abs(itsShear - theNearestSnapPoint)
							if theDifference < theSnapTolerance {
							
								//	...snap exactly to theNearestSnapPoint.
								itsShear = theNearestSnapPoint
							}
						}
					})
				.frame(width: 256.0)
				.onAppear() {

					let theShape = document.getUnitCellShape()
					
					itsShear = theShape.shear
				}
				.onChange(of: itsShear) {
									
					let theCurrentShape = document.getUnitCellShape()
					let theNewShape = UnitCellShape(
										aspectRatio: theCurrentShape.aspectRatio,
										shear: itsShear)
					
					document.setUnitCellShape(theNewShape)
										
					//	As the user drags the slider, we reshape
					//	the drawing using the existing unit cell textures,
					//	because that's a quick operation.
					//
					//	We won't redraw the unit cell textures
					//	until the user dismisses this ShapePanel,
					//	because that can be a slow operation
					//	if the drawing contain lots of filled regions.
					//
					document.changeCount += 1
				}
			
				Text("Shear")
				.font(.caption)
			}
		}
		.padding(16.0)
	}
}


// MARK: -
// MARK: Editor panel

struct EditorSection: ViewModifier {
	func body(content: Content) -> some View {
		content
		.frame(maxWidth: .infinity, alignment: .center)
		.background(gSystemBackgroundColor)
		.cornerRadius(geometryGamesCornerRadius)
	}
}

struct EditorPanel: View {

	var document: KaleidoPaintDocument
	@Binding var colorSelectionMode: SelectionMode
	@Binding var changeAllOfSameColor: Bool
	@Binding var thicknessSelectionMode: SelectionMode
	@Binding var changeAllOfSameThickness: Bool
	@Binding var deleteAllOfSameColor: Bool

	@Binding var editorIsShown: Bool

	@State private var desiredNodeType: SplineNodeType = .smooth	//	overridden in .onAppear

	var body: some View {

		let thePaddingAndSpacing = 8.0

		var theDeleteButtonTitle: LocalizedStringKey = "Delete ???"
		if document.itsControlHandleHit?.itsElement is Dot {
			theDeleteButtonTitle = "Delete dot"
		}
		if document.itsControlHandleHit?.itsElement is Curve {
			theDeleteButtonTitle = "Delete line"
		}
		if document.itsControlHandleHit?.itsElement is Fill {
			theDeleteButtonTitle = "Delete fill"
		}

		return VStack(spacing: thePaddingAndSpacing) {
		
			ColorPanel(
				document: document,
				colorTarget: .selectedObject,
				colorSelectionMode: $colorSelectionMode,
				changeAllOfSameColor: $changeAllOfSameColor)
			.modifier(EditorSection())

			if document.itsControlHandleHit?.itsElement is Brushstroke {
			
				ThicknessPanel(
					document: document,
					thicknessTarget: .selectedObject,
					thicknessSelectionMode: $thicknessSelectionMode,
					changeAllOfSameThickness: $changeAllOfSameThickness)
				.modifier(EditorSection())
			}
			
			if let theSelectedCurve = document.itsControlHandleHit?.itsElement as? Curve,
			   let theSelectedNode = document.itsControlHandleHit?.itsNode {
			
				let theSpline = theSelectedCurve.itsSpline
				
				VStack(spacing: 12.0) {
				
					if theSelectedNode !== theSpline.itsNodes.first
					&& theSelectedNode !== theSpline.itsNodes.last {
					
						HStack() {
							
							Text("Control point style")
							
							Spacer()

							Picker(
								"Control point style",	//	unused
								selection: $desiredNodeType
							) {
								ForEach(SplineNodeType.allCases, id: \.id) { theNodeType in
									Text(theNodeType.localizedNameKey())
								//	.modifier(applyForegroundAccentColorOnMacOS())	//	has no effect (?!)
									.foregroundStyle(Color.accentColor)				//	works fine
									.tag(theNodeType)	//	.tag must come after .foregroundStyle
								}
							}
							.pickerStyle(MenuPickerStyle())
							.labelsHidden()	//	needed on macOS, but iOS hides the label no matter what
							.fixedSize()
							.onAppear() {

								desiredNodeType = theSelectedNode.itsNodeType
							}
							.onChange(of: desiredNodeType) {

								//	If theSelectedNode.itsNodeType's original value differs
								//	from the desiredNodeType's hard-coded default value,
								//	then onAppear() will set the correct value.
								//	But a side effect of that is that changeonChange(of:)
								//	may get called when the View first appears.
								//	So we must take care to put a SplineNodeType change
								//	onto the Undo stack only if theSelectedNode.itsNodeType
								//	itself has changed.
								
								let theOldNodeType = theSelectedNode.itsNodeType
								
								if desiredNodeType != theOldNodeType {
								
									document.changeSplineNodeType(
											curve: theSelectedCurve,
											node: theSelectedNode,
											from: theOldNodeType,
											to: desiredNodeType)
								}
							}
						}
					}
					
					if theSpline.itsNodes.count >= 3 {	//	must keep ≥ 2 nodes

						Button() {
						
							document.deleteSplineNode(
								curve: theSelectedCurve,
								node: theSelectedNode)

							editorIsShown = false
						
						} label: {
						
							HStack() {
								Text("Delete control point")
								Spacer()
								Image(systemName: "minus.circle")
							}
							.modifier(applyForegroundAccentColorOnMacOS())
						}
					}

					Button() {

						let (theNewNodeA, theNewNodeB)
							= theSelectedCurve.itsSpline.splitNode(theSelectedNode)
						
						document.splitSplineNode(
							curve: theSelectedCurve,
							oldNode: theSelectedNode,
							newNodeA: theNewNodeA,
							newNodeB: theNewNodeB)

						editorIsShown = false
					
					} label: {
					
						HStack() {
							Text("Split control point")
							Spacer()
							Image(systemName: "plus.circle")
						}
						.modifier(applyForegroundAccentColorOnMacOS())
					}
				}
				.padding(geometryGamesPanelPadding)
				.modifier(EditorSection())
			}
			
			VStack(spacing: 8.0) {
			
				Button() {

					if let theSelectedElement = document.itsControlHandleHit?.itsElement {
					
						let theDeletionPredicate = ( deleteAllOfSameColor ?
							{ (element: DrawingElement) in
								theSelectedElement.itsColor.isAlmostTheSameAs(element.itsColor) } :
							{ (element: DrawingElement) in
								element === theSelectedElement }
						)

						let theRemainingElements = document.itsElements.filter() { element in
														!theDeletionPredicate(element) }
						
						document.changeElementArray(
							from: document.itsElements,
							to: theRemainingElements)
						
						editorIsShown = false
					}
					
				} label: {
				
					HStack() {
						Text(theDeleteButtonTitle)
						Spacer()
						Image(systemName: "trash")
					}
					.foregroundStyle(Color.red)
				}

				Toggle("Delete everything of same color", isOn: $deleteAllOfSameColor)
					.toggleStyle(.kaleidoPaintCheckbox)
			}
			.padding(EdgeInsets(
				top: 8.0,
				leading: geometryGamesPanelPadding,
				bottom: 8.0,
				trailing: geometryGamesPanelPadding))
			.modifier(EditorSection())
		}
		.modifier(buttonStyleOnMacOS())
		.padding(thePaddingAndSpacing)
		.background(
			GeometryReader() { geometry in
		
				//	There's apparently no simple way to set
				//	the color of the little arrow that ties
				//	a popover to its anchor point.
				//	The following workaround (which I found
				//	on the internet) underlays a rectangle
				//	that's slightly larger than the popover's
				//	content area.  It's an ugly hack, but it works.
				
				let thePadding = 128.0
				
				Color(white: 0.875)
					.frame(
						width:  geometry.size.width  + thePadding,
						height: geometry.size.height + thePadding,
						alignment: .center)
					.frame(
						width:  geometry.size.width,
						height: geometry.size.height,
						alignment: .center)
			}
		)
	}
}

//struct KaleidoPaintContentView_Previews: PreviewProvider {
//	static var previews: some View {
//		KaleidoPaintContentView(document: .constant(KaleidoPaintDocument()))
//	}
//}
