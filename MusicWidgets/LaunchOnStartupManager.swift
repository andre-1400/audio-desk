import Combine
import ServiceManagement

@MainActor
final class LaunchOnStartupManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var isUpdating = false

    // Deliberately does NOT call refresh() here. SMAppService.mainApp.status
    // is backed by an XPC call to smd, which can be slow on a machine that
    // has never launched this app before (e.g. first run on a reviewer's
    // clean install) — synchronous inside init() would block SwiftUI's
    // first render pass for the whole Settings sheet, which can show up as
    // a blank window rather than a brief delay. Callers refresh explicitly
    // from .onAppear once the view is already on screen.
    init() {}

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            statusMessage = "Audio Desk will open automatically when you log in."
        case .notRegistered:
            isEnabled = false
            statusMessage = "Audio Desk will not open automatically when you log in."
        case .requiresApproval:
            isEnabled = false
            statusMessage = "Approve Audio Desk in System Settings to enable startup."
        case .notFound:
            isEnabled = false
            statusMessage = "Launch On Startup is unavailable for this build."
        @unknown default:
            isEnabled = false
            statusMessage = "Launch On Startup status is unavailable."
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard !isUpdating else { return }

        let service = SMAppService.mainApp
        if enabled, service.status == .enabled {
            refresh()
            return
        }
        if !enabled, service.status == .notRegistered || service.status == .notFound {
            refresh()
            return
        }

        isUpdating = true
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            refresh()
        } catch {
            refresh()
            statusMessage = "Could not update Launch On Startup: \(error.localizedDescription)"
        }
        isUpdating = false
    }
}
