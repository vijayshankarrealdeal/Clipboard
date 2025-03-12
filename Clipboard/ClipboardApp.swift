import SwiftUI

@main
struct ClipboardHistoryApp: App {
    // Use an AppDelegate to handle hotkeys, background mode, and startup registration.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 400)
        }
    }
}

