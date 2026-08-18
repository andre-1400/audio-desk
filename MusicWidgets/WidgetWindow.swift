import AppKit
import SwiftUI
import Combine

/// The base (1.0×) size of the widget content. The window and the scaled
/// content are both derived from this so they always stay in sync.
let baseWidgetSize = CGSize(width: 384, height: 516)

/// Continuous widget scale, replacing the old small/medium/large presets with
/// a slider so the size can be dialled anywhere between "desktop icon" and
/// "over half the screen." Persisted so it becomes the default on every launch.
final class WidgetSizeManager: ObservableObject {
    private let storageKey = "widget.scale"
    private let legacyKey = "widget.size"   // old small/medium/large string

    /// Narrowed from the original 0.22-2.6 range — that let the slider go
    /// all the way down to an ~85x114 desktop-icon-sized sliver and up to
    /// a ~1456pt-wide CD Hi-Fi, both of which read as unpolished/extreme
    /// rather than a considered size choice. baseWidgetSize (384x516,
    /// vinyl's own base) at minScale is ~192x258 — still a small, compact
    /// widget, not an icon. Every other widget family's own base size
    /// scales by the same factor, so a wider family (e.g. CD Hi-Fi at
    /// 560pt) reads larger still at the same slider position, which is
    /// expected — the slider dials relative size, not an absolute pixel
    /// target shared across every widget shape.
    static let minScale: CGFloat = 0.5
    /// At maxScale, vinyl (384pt base) is ~614pt wide, and CD Hi-Fi
    /// (560pt base) reaches ~896pt — sizeable but well short of dominating
    /// the screen the old 2.6 max allowed.
    static let maxScale: CGFloat = 1.6
    static let defaultScale: CGFloat = 1.0

    @Published var scale: CGFloat {
        didSet {
            guard oldValue != scale else { return }
            UserDefaults.standard.set(Double(scale), forKey: storageKey)
        }
    }

    static let shared = WidgetSizeManager()

    init() {
        if UserDefaults.standard.object(forKey: storageKey) != nil {
            let stored = CGFloat(UserDefaults.standard.double(forKey: storageKey))
            self.scale = min(Self.maxScale, max(Self.minScale, stored))
        } else if let legacy = UserDefaults.standard.string(forKey: legacyKey) {
            // One-time migration from the old discrete small/medium/large
            // setting, matching its previous fixed scale values, then drop
            // the legacy key so this branch never runs again.
            let migrated: CGFloat
            switch legacy {
            case "small": migrated = 0.82
            case "large": migrated = 1.22
            default: migrated = 1.0
            }
            self.scale = migrated
            UserDefaults.standard.set(Double(migrated), forKey: storageKey)
            UserDefaults.standard.removeObject(forKey: legacyKey)
        } else {
            self.scale = Self.defaultScale
        }
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

    // isMovableByWindowBackground above is not enough on its own here.
    // AppKit only starts a background drag when the view under the cursor
    // reports mouseDownCanMoveWindow, and SwiftUI's NSHostingView — which
    // covers this window's entire surface — reports false. The gallery
    // window never hits this because it's a .titled window and drags via
    // its (transparent) titlebar instead; this panel is .borderless, so
    // there's no titlebar to fall back on and the widget ends up pinned
    // in place.
    //
    // A window only receives mouseDown for events that no view in the
    // responder chain consumed, which makes this the right place to
    // handle it: the transport buttons, the scrub bar's NSView capture,
    // and the disc's own tap-to-pause gesture all swallow their own
    // clicks, so a press anywhere *else* on the widget falls through to
    // here and drags the window — "draggable everywhere except the
    // controls", without having to enumerate where the controls are.
    override func mouseDown(with event: NSEvent) {
        performDrag(with: event)
    }
}
