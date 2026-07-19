import SwiftUI

@main
struct MusicWidgetsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main WindowGroup — the gallery window is created and shown by the
        // AppDelegate and toggled from the menu-bar item. This keeps the app out
        // of the Dock (LSUIElement) and accessible only from the menu bar.
        Settings { EmptyView() }
    }
}
