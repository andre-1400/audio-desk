import SwiftUI
import Combine

// MARK: - Window layer (replaces the old plain alwaysOnTop bool)
//
// A user asked for "always on top and on the bottom and all that" — a
// third option beyond the previous on/off. Normal keeps the existing
// default placement (just above desktop icons); alwaysOnBottom drops the
// widget to true desktop-picture level, *below* the icons. That's a real
// tradeoff, not just a cosmetic choice: DesktopWidgetView.swift's own
// window-level history documents that windows at or below icon level
// don't receive mouse clicks at all (WindowServer routes them to Finder's
// desktop interactions instead) — so a widget set to alwaysOnBottom
// becomes purely decorative, its transport buttons unclickable. Surfaced
// as a subtitle in Settings rather than silently discovered.
enum WidgetWindowLayer: String, CaseIterable {
    case alwaysOnBottom, normal, alwaysOnTop

    var title: String {
        switch self {
        case .alwaysOnBottom: return "Bottom"
        case .normal: return "Normal"
        case .alwaysOnTop: return "Top"
        }
    }
}

// MARK: - Global widget settings (size lives in WidgetSizeManager.shared)

/// Shared, persisted settings for the active desktop widget.
final class WidgetSettings: ObservableObject {
    static let shared = WidgetSettings()

    /// Widget window opacity (0.5–1.0).
    @Published var widgetOpacity: Double {
        didSet { UserDefaults.standard.set(widgetOpacity, forKey: "widget.opacity") }
    }
    /// Where the widget sits relative to other windows and the desktop
    /// icons — Normal (default), Always on Top, or Always on Bottom.
    @Published var windowLayer: WidgetWindowLayer {
        didSet { UserDefaults.standard.set(windowLayer.rawValue, forKey: "widget.windowLayer") }
    }
    /// Mouse clicks pass straight through the widget to whatever is behind it.
    @Published var clickThrough: Bool {
        didSet { UserDefaults.standard.set(clickThrough, forKey: "widget.clickThrough") }
    }
    /// Fade the widget out when nothing is playing, back in when music resumes.
    @Published var hideWhenPaused: Bool {
        didSet { UserDefaults.standard.set(hideWhenPaused, forKey: "widget.hideWhenPaused") }
    }
    /// Vinyl v1's disc-lift/sleeve-eject and Horizontal's quick disc-dip
    /// pulse. When off, both snap straight to the next track/colour instead.
    /// CD's own eject/insert is exempt on purpose — short enough that
    /// turning it off isn't worth it, unlike Vinyl v1's longer choreography.
    /// Album Art's plain crossfade isn't gated by this either — that's
    /// ordinary "don't pop" UI polish, not a track-change set piece.
    @Published var vinylTransitionAnimationEnabled: Bool {
        didSet { UserDefaults.standard.set(vinylTransitionAnimationEnabled, forKey: "widget.vinylTransitionAnimation") }
    }

    private init() {
        let storedOpacity = UserDefaults.standard.object(forKey: "widget.opacity") as? Double
        widgetOpacity = min(1.0, max(0.5, storedOpacity ?? 1.0))
        if let storedLayer = UserDefaults.standard.string(forKey: "widget.windowLayer"),
           let layer = WidgetWindowLayer(rawValue: storedLayer) {
            windowLayer = layer
        } else {
            // One-time migration from the old alwaysOnTop bool, then the
            // legacy key is simply never read again.
            windowLayer = UserDefaults.standard.bool(forKey: "widget.alwaysOnTop") ? .alwaysOnTop : .normal
        }
        clickThrough = UserDefaults.standard.bool(forKey: "widget.clickThrough")
        hideWhenPaused = UserDefaults.standard.bool(forKey: "widget.hideWhenPaused")
        vinylTransitionAnimationEnabled = UserDefaults.standard.object(forKey: "widget.vinylTransitionAnimation") as? Bool ?? true
    }
}

// MARK: - Recently used styles (powers the menu-bar quick switcher)

/// Persisted identifiers of the last few placed widgets, most recent first.
/// Encoded as "vinyl:<themeID>" or "cd:<modelID>".
enum RecentWidgets {
    private static let key = "widget.recent.v1"
    private static let lastKey = "widget.last.v1"
    private static let maxCount = 3

    static func note(vinyl themeID: WidgetThemeID) { note("vinyl:\(themeID.rawValue)") }
    static func note(cd model: CDModel) { note("cd:\(model.id)") }
    static func note(albumArt model: AlbumArtModel) { note("albumart:\(model.id)") }
    static func note(vinylHorizontal model: VinylHorizontalModel) { note("vinylh:\(model.id)") }
    static func note(desktop model: DesktopWidgetModel) { note("desktop:\(model.id)") }

    private static func note(_ entry: String) {
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        list.removeAll { $0 == entry }
        list.insert(entry, at: 0)
        UserDefaults.standard.set(Array(list.prefix(maxCount)), forKey: key)
        UserDefaults.standard.set(entry, forKey: lastKey)
    }

    static var entries: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    static var last: String? { UserDefaults.standard.string(forKey: lastKey) }
}

// MARK: - Model traits (per-style hardware, independent of color palette)

enum SpindleStyle {
    case standard   // small chrome dot
    case retro45    // 45-rpm adapter look (chrome ring + pin)
}

enum VinylBodyPattern {
    case none, brushed, wood, fabric
}

/// Subtle body texture overlay that gives the special vinyl styles their own
/// material character. Drawn with Canvas, clipped to the body by the caller.
struct VinylBodyTexture: View {
    let pattern: VinylBodyPattern

    var body: some View {
        Canvas { ctx, size in
            switch pattern {
            case .none:
                break
            case .brushed:
                Self.drawBrushed(in: &ctx, size: size)
            case .wood:
                Self.drawWood(in: &ctx, size: size)
            case .fabric:
                Self.drawFabric(in: &ctx, size: size)
            }
        }
        .allowsHitTesting(false)
    }

    // Each pattern draws from its own method rather than inline in the
    // Canvas closure. Inline, the switch's mixed CGFloat/Int arithmetic
    // and inline Path builders made this one expression slow enough to
    // type-check (~90ms on a current compiler) to risk exceeding the
    // limit on the older Swift the oldest supported Xcode ships. Same
    // drawing calls in the same order with the same values — only the
    // type-checking is split up.

    private static func drawBrushed(in ctx: inout GraphicsContext, size: CGSize) {
        var y: CGFloat = 0
        while y < size.height {
            let op: Double = (Int(y) % 3 == 0) ? 0.055 : 0.02
            let line = Path { p in
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(line, with: .color(.white.opacity(op)), lineWidth: 0.5)
            y += 2.5
        }
    }

    private static func drawWood(in ctx: inout GraphicsContext, size: CGSize) {
        var x: CGFloat = 4
        var seed: Int = 1
        while x < size.width {
            let wob: CGFloat = CGFloat((seed * 37) % 9) - 4
            let op: Double = (seed % 2 == 0) ? 0.13 : 0.06
            let grain = Path { p in
                p.move(to: CGPoint(x: x, y: 0))
                p.addQuadCurve(to: CGPoint(x: x + wob, y: size.height),
                               control: CGPoint(x: x + wob * 2, y: size.height / 2))
            }
            ctx.stroke(grain, with: .color(.black.opacity(op)), lineWidth: 1)
            x += CGFloat(5 + (seed * 13) % 7)
            seed += 1
        }
    }

    private static func drawFabric(in ctx: inout GraphicsContext, size: CGSize) {
        let step: CGFloat = 5
        var i: CGFloat = -size.height
        while i < size.width {
            let down = Path { p in
                p.move(to: CGPoint(x: i, y: 0))
                p.addLine(to: CGPoint(x: i + size.height, y: size.height))
            }
            ctx.stroke(down, with: .color(.white.opacity(0.028)), lineWidth: 0.6)
            let up = Path { p in
                p.move(to: CGPoint(x: i, y: size.height))
                p.addLine(to: CGPoint(x: i + size.height, y: 0))
            }
            ctx.stroke(up, with: .color(.black.opacity(0.045)), lineWidth: 0.6)
            i += step
        }
    }
}

/// Non-color traits of a vinyl model. Kept separate from WidgetThemePalette so
/// the color system stays untouched. Looked up by theme ID at render time.
struct VinylModelTraits {
    var hasTransportControls: Bool = false
    var spindle: SpindleStyle = .standard
    var hasPitchSlider: Bool = false
    var hasPowerLED: Bool = false
    var hasCounterweight: Bool = false
    var hasPlatterRing: Bool = false
    var caseBorder: Bool = false
    var pattern: VinylBodyPattern = .none
}

extension WidgetThemeID {
    // Every remaining style (Adaptive/Custom/Ghost) uses the plain default
    // traits — the retro/studio-specific trait combos, and later every
    // fixed prebuilt colourway, were removed. Ghost's "no housing" look
    // comes from WidgetThemePalette.showBody, not from a trait.
    var traits: VinylModelTraits {
        VinylModelTraits()
    }
}

// MARK: - Retro VFD display (old blocky green hi-fi readout)

/// A vintage vacuum-fluorescent-style display: blocky monospaced green glowing
/// text on a near-black inset panel. Shows track + artist on retro models.
struct RetroVFDDisplay: View {
    let title: String
    let subtitle: String

    private let green = Color(hex: "5dff86")

    var body: some View {
        VStack(spacing: 2) {
            Text(title.isEmpty ? "— — —" : title.uppercased())
                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(green)
                .shadow(color: green.opacity(0.75), radius: 3)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(subtitle.isEmpty ? "—" : subtitle.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(green.opacity(0.65))
                .shadow(color: green.opacity(0.4), radius: 2)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: 232)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(hex: "06110a"))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(green.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        )
    }
}

// MARK: - Retro square transport button

/// A chunky, square vintage push-button cap sitting in a recessed frame.
/// Shared by the live widget (wrapped in a Button) and the gallery preview.
struct RetroTransportButtonFace: View {
    let palette: WidgetThemePalette
    let icon: String
    var size: CGFloat = 34

    var body: some View {
        let r = size * 0.16
        ZStack {
            // Recessed frame
            RoundedRectangle(cornerRadius: r + 2)
                .fill(Color.black.opacity(0.38))
                .frame(width: size + 6, height: size + 6)

            // Button cap (metal/plastic)
            RoundedRectangle(cornerRadius: r)
                .fill(LinearGradient(colors: palette.screwGradient,
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: r)
                        .strokeBorder(
                            LinearGradient(colors: [Color.white.opacity(0.6), Color.black.opacity(0.28)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.5), radius: 1.5, x: 0, y: 1.5)

            Image(systemName: icon)
                .font(.system(size: size * 0.36, weight: .black))
                .foregroundStyle(Color(hex: "222222"))
        }
        .frame(width: size + 6, height: size + 6)
    }
}

