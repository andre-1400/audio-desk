import Combine
import ServiceManagement

@MainActor
final class LaunchOnStartupManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var isUpdating = false

    init() {
        refresh()
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            statusMessage = "\"name\" will open automatically when you log in."
        case .notRegistered:
            isEnabled = false
            statusMessage = "\"name\" will not open automatically when you log in."
        case .requiresApproval:
            isEnabled = false
            statusMessage = "Approve \"name\" in System Settings to enable startup."
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
