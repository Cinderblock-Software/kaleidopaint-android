//	KaleidoPaintApp.swift
//
//	© 2026 by Jeff Weeks
//	See TermsOfUse.txt

import SwiftUI

@main
struct KaleidoPaintApp: App {

	@Environment(\.scenePhase) var scenePhase

	@State var quickStartHelpShouldBeShown: Bool = true
	@State var editorHelpShouldBeShown: Bool = true
	
	init() {

		UserDefaults.standard.register(
			defaults: [
				//	With what initial symmetry group should we create new drawings?
				"default symmetry group" : "632"
			]
		)

#if targetEnvironment(simulator)
		//	When creating screenshots in the simulator,
		//	we'll need to know where to put source files
		//	for the desired drawings.
		PrintDocumentDirectoryPathToConsole()
#endif
	}
	
	var body: some Scene {

		DocumentGroup(newDocument: { KaleidoPaintDocument() }) { file in

			KaleidoPaintContentView(
				document: file.document,
				fileURL: file.fileURL,
				quickStartHelpShouldBeShown: $quickStartHelpShouldBeShown,
				editorHelpShouldBeShown: $editorHelpShouldBeShown)
		}
		.defaultSize(
			width:  gMakeScreenshots ? 1280.0 : 1024.0,
			height: gMakeScreenshots ?  800.0 :  768.0)
	}
}
