import SwiftUI
import AppKit

// MARK: - Native macOS design foundation
//
// The shared primitives that replace the old neumorphic system (raised
// double-shadow cards, custom pill controls) with the materials, vibrancy,
// and continuous-corner surfaces macOS system apps (Music, Finder, Settings)
// actually use. Everything here is chrome-only — no widget rendering touches
// this file.

/// A live `NSVisualEffectView` bridged into SwiftUI — the real native blur /
/// vibrancy that flat SwiftUI fills can't produce. Used for the window base
/// and the sidebar so the app reads as a native macOS window, not an opaque
/// card on a flat page.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .followsWindowActiveState

    init(_ material: NSVisualEffectView.Material = .underWindowBackground,
         blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
         state: NSVisualEffectView.State = .followsWindowActiveState) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
    }
}

// MARK: - Surfaces

/// A material card — the native replacement for `neuRaised`. A translucent
/// material fill with continuous corners and a single soft shadow; no hard
/// border. `elevated` slightly deepens the shadow (used on hover).
private struct AppCard: ViewModifier {
    var corner: CGFloat = 16
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                // A whisper-thin top highlight for the "glass" edge — far
                // softer than the old opaque hairline border.
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(elevated ? 0.18 : 0.10),
                    radius: elevated ? 18 : 10, x: 0, y: elevated ? 8 : 4)
    }
}

extension View {
    /// Native material card surface. Replaces `neuRaised` on chrome surfaces.
    func appCard(corner: CGFloat = 16, elevated: Bool = false) -> some View {
        modifier(AppCard(corner: corner, elevated: elevated))
    }

    /// A flat inset well (search fields, small insets) — a thin material with
    /// continuous corners, no drop shadow. Native replacement for `neuInset`
    /// where a recessed look is wanted.
    func appWell(corner: CGFloat = 10) -> some View {
        background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

// MARK: - Typography ramp
//
// A small subset of Apple's HIG type ramp so chrome text uses consistent,
// system-native sizes/weights instead of ad-hoc point sizes. SF Pro (the
// default design) rather than SF Rounded, matching Music/Finder/Settings.

extension Font {
    /// Big screen title (e.g. the gallery category header).
    static let appLargeTitle = Font.system(size: 26, weight: .bold)
    /// Section / group title.
    static let appTitle = Font.system(size: 15, weight: .semibold)
    /// Emphasised row/card title.
    static let appHeadline = Font.system(size: 14, weight: .semibold)
    /// Standard body text.
    static let appBody = Font.system(size: 13, weight: .regular)
    /// Secondary / supporting text.
    static let appSubheadline = Font.system(size: 12, weight: .regular)
    /// Small captions, counts, footers.
    static let appCaption = Font.system(size: 11, weight: .regular)
}
