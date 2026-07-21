import AppKit
import SwiftUI
import Combine

/// The base (1.0×) size of the widget content. The window and the scaled
/// content are both derived from this so they always stay in sync.
let baseWidgetSize = CGSize(width: 384, height: 516)

/// User-selectable widget sizes. Persisted so the choice becomes the default
/// on every launch (set from Settings while the widget is visible).
enum WidgetSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var scale: CGFloat {
        switch self {
        case .small: return 0.82
        case .medium: return 1.0
        case .large: return 1.22
        }
    }

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}

final class WidgetSizeManager: ObservableObject {
    private let storageKey = "widget.size"

    @Published var size: WidgetSize {
        didSet {
            guard oldValue != size else { return }
            UserDefaults.standard.set(size.rawValue, forKey: storageKey)
        }
    }

    var scale: CGFloat { size.scale }

    static let shared = WidgetSizeManager()

    init() {
        let raw = UserDefaults.standard.string(forKey: "widget.size")
        self.size = WidgetSize(rawValue: raw ?? "") ?? .medium
    }
}

/// Hosts the widget content and scales it uniformly to the chosen size.
/// Because every element of `ContentView` uses fixed point geometry, a single
/// centred scale keeps the body, platter, tonearm, and panels perfectly aligned.
struct ScaledWidgetView: View {
    @ObservedObject var animator: SongSwitchAnimator
    @ObservedObject var themeManager: WidgetThemeManager
    @ObservedObject var sizeManager: WidgetSizeManager

    var body: some View {
        VinylWidgetView(animator: animator, themeManager: themeManager)
            .scaleEffect(sizeManager.scale, anchor: .center)
            .frame(width: baseWidgetSize.width * sizeManager.scale,
                   height: baseWidgetSize.height * sizeManager.scale)
    }
}

/// Scales the song-switch animation overlay by the same factor so the flying
/// disk/sleeves stay aligned with the (also scaled) widget at any size.
struct ScaledOverlayView: View {
    @ObservedObject var animator: SongSwitchAnimator
    @ObservedObject var sizeManager: WidgetSizeManager

    var body: some View {
        AnimationOverlayView(animator: animator)
            .scaleEffect(sizeManager.scale, anchor: .center)
    }
}

class WidgetWindow: NSPanel {

    init() {
        super.init(
            contentRect: NSRect(x: 100, y: 300, width: 372, height: 404),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Transparent background — no visible window chrome
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // Float above the desktop but below normal windows
        level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

        // Appear on all Spaces and stay in place
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // Allow native drag from anywhere in the widget surface.
        isMovableByWindowBackground = true

        // Keep it visible even when the app is not "active"
        hidesOnDeactivate = false

        // Accept mouse events so we can click and drag later
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
    }
}
