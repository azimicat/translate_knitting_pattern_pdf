import SwiftUI
import AppKit

// swift run で起動した場合でもキーボード入力を受け取れるようにするため、
// AppDelegate で明示的にアクティベーションポリシーを設定する
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct KnittingTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
