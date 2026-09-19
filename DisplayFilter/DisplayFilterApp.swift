import SwiftUI

@main
struct DisplayFilterApp: App {
    // Created eagerly (not @StateObject): the menu bar window content is lazy, and the schedule must run before it is ever opened.
    private let appState = AppState.shared

    var body: some Scene {
        MenuBarExtra("Display Filter", systemImage: "moonphase.first.quarter") {
            ContentView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }

    #if DEBUG
    init() {
        guard CommandLine.arguments.contains("--debug-window") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let window = NSWindow(contentViewController: NSHostingController(rootView: ContentView().environmentObject(AppState.shared)))
            window.title = "DisplayFilter (debug)"
            window.setFrameOrigin(NSPoint(x: 60, y: 120))
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
        }
    }
    #endif
}
