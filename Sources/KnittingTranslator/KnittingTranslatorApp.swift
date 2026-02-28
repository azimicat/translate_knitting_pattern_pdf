import SwiftUI

@main
struct KnittingTranslatorApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 700)
        }
        .windowResizability(.contentMinSize)
    }
}
