//	KaleidoPaintHelp.swift
//
//	© 2026 by Jeff Weeks
//	See TermsOfUse.txt

import SwiftUI

struct KaleidoPaintHelpQuickStartView: View {

	@Environment(\.horizontalSizeClass) var horizontalSizeClass

	var body: some View {
	
		//	In Draw mode on an iPhone, we'll need to allow space
		//	for the button bars on each side.
		let theExtraPadding = horizontalSizeClass == .compact ? 80.0 : 0.0

		VStack(alignment: .center, spacing: 16.0) {
		
			Text("Quick Start")
			.font(.title3)
			
			VStack(alignment: .leading, spacing: 8.0) {
			
				Text("OneFinger-tip")
				Text("TwoFingers-tip")
				Text("DoubleTap-tip")
			}

			Text("HideGrid-tip")
			.font(.caption)
			.italic()
		}
		.padding(geometryGamesPanelPadding)
		.background(gSystemBackgroundColor)
		.cornerRadius(geometryGamesCornerRadius)
		.padding(EdgeInsets(
					top: 0.0,
					leading: theExtraPadding,
					bottom: 0.0,
					trailing: theExtraPadding))
	}
}

struct KaleidoPaintHelpEditorView: View {

	var body: some View {

		ScrollView() {
			
			VStack(alignment: .leading, spacing: 16.0) {
			
				Text("Editor-HowTo-long")
				.font(.title)
				.multilineTextAlignment(.center)
				.frame(maxWidth: .infinity, alignment: .center)
				
				VStack(alignment: .leading, spacing: 8.0) {
					Text("Control-Points")
					Image("Editor help/control points")
					.frame(maxWidth: .infinity, alignment: .center)
				}
				
				VStack(alignment: .leading, spacing: 8.0) {
					Text("Control-Points-Drag")
					Image("Editor help/control points drag")
					.frame(maxWidth: .infinity, alignment: .center)
				}
				
				VStack(alignment: .leading, spacing: 8.0) {
					Text("Control-Points-Tap")
					Image("Editor help/control points tap")
					.frame(maxWidth: .infinity, alignment: .center)
				}
				
				Text("No-Arc-Taps")
				
				VStack(alignment: .leading, spacing: 4.0) {
				
					Text("Performance-Tip")
				
					HStack(spacing: 0.0) {
					
						//	We want to allot exactly half the frame
						//	width to each of the two image names.
						//	The modifier
						//
						//		.frame(maxWidth: .infinity, alignment: .center)
						//
						//	does exactly that, because it makes each View "greedy"
						//	and willing to accept as much space as it's offered.
					
						Text("Caption-Bad")
							.font(.caption)
							.foregroundStyle(.red)
							.multilineTextAlignment(.center)
							.padding(EdgeInsets(top: 0.0, leading: 8.0, bottom: 0.0, trailing: 8.0))
							.frame(maxWidth: .infinity, alignment: .center)
					
						Text("Caption-Good")
							.font(.caption)
							.foregroundStyle(.green)
							.multilineTextAlignment(.center)
							.padding(EdgeInsets(top: 0.0, leading: 8.0, bottom: 0.0, trailing: 8.0))
							.frame(maxWidth: .infinity, alignment: .center)
					}
					
					HStack(spacing: 0.0) {
					
						//	See comments above regarding allotting exactly half the frame.
					
						Text("Subcaption-Bad")
							.font(.caption)
							.multilineTextAlignment(.center)
							.padding(EdgeInsets(top: 0.0, leading: 8.0, bottom: 0.0, trailing: 8.0))
							.frame(maxWidth: .infinity, alignment: .center)
					
						Text("Subcaption-Good")
							.font(.caption)
							.multilineTextAlignment(.center)
							.padding(EdgeInsets(top: 0.0, leading: 8.0, bottom: 0.0, trailing: 8.0))
							.frame(maxWidth: .infinity, alignment: .center)
					}
					
					HStack(spacing: 0.0) {
					
						//	See comments above regarding allotting exactly half the frame.
					
						Image("Editor help/1 region 2 fill points")
							.frame(width: 128.0, height: 135.0)
							.padding(EdgeInsets(top: 0.0, leading: 2.0, bottom: 0.0, trailing: 2.0))
							.frame(maxWidth: .infinity, alignment: .center)
					
						Image("Editor help/1 region 1 fill point")
							.frame(width: 128.0, height: 135.0)
							.padding(EdgeInsets(top: 0.0, leading: 2.0, bottom: 0.0, trailing: 2.0))
							.frame(maxWidth: .infinity, alignment: .center)
					}
				}
			}
		}
		.frame(maxWidth: 320.0)
		.padding(geometryGamesPanelPadding)
		.background(gSystemBackgroundColor)
		.cornerRadius(geometryGamesCornerRadius)
	}
}

struct KaleidoPaintHelpTutorialsView: View {

	var body: some View {
		
		VStack(alignment: .center, spacing: 8.0) {
		
			Text("Tutorials")
			.font(.title3)
			
			Text("[Francine's KaleidoPaint tutorials](https://tessellations.ca/2022/08/26/kaleidopaint-ipad-app-help/) provide guidance for novices as well as for more experience users.")
		}
		.frame(maxWidth: 320.0)
		.padding(geometryGamesPanelPadding)
		.background(gSystemBackgroundColor)
		.cornerRadius(geometryGamesCornerRadius)
	}
}

struct KaleidoPaintHelpImageGalleryView: View {

	var body: some View {
		
		VStack(alignment: .center, spacing: 8.0) {
		
			Text("Image Gallery")
			.font(.title3)
			
			Text("Image-Gallery-text")
		}
		.frame(maxWidth: 320.0)
		.padding(geometryGamesPanelPadding)
		.background(gSystemBackgroundColor)
		.cornerRadius(geometryGamesCornerRadius)
	}
}
