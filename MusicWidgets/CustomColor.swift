import SwiftUI
import AppKit

/// A user-picked colour, expressed as HSV (matching the picker UI) plus an
/// "intensity" knob that blends toward neutral grey — this is what feeds the
/// Custom style, the same way ExtractedColours feeds Adaptive.
struct HSVColor: Equatable, Codable {
    /// 0...1, maps to 0...360° around the hue wheel.
    var hue: Double = 0.58
    /// 0...1. 0 = grey, 1 = fully saturated.
    var saturation: Double = 0.55
    /// 0...1 ("value" in HSV). 0 = black, 1 = brightest.
    var brightness: Double = 0.62
    /// 0...1. How strongly the picked colour reads versus a neutral mid-grey
    /// — 1.0 is the colour exactly as picked, lower values mute it toward
    /// grey without changing its hue/saturation/brightness.
    var intensity: Double = 1.0

    static let `default` = HSVColor()

    /// The colour at full saturation/brightness for this hue, ignoring
    /// intensity — used to render the SV square and the hue swatch, which
    /// should never be muted by the intensity slider.
    var pureHue: Color { Color(hue: hue, saturation: 1, brightness: 1) }

    /// The colour exactly as the H/S/V sliders specify, before intensity.
    var rawColor: Color { Color(hue: hue, saturation: saturation, brightness: brightness) }

    /// rawColor blended toward neutral mid-grey by intensity — this is the
    /// colour that actually gets used everywhere (widget body, previews).
    var color: Color {
        guard intensity < 1 else { return rawColor }
        let ns = NSColor(rawColor).usingColorSpace(.deviceRGB) ?? NSColor(rawColor)
        let neutral = 0.5
        let r = Double(ns.redComponent) * intensity + neutral * (1 - intensity)
        let g = Double(ns.greenComponent) * intensity + neutral * (1 - intensity)
        let b = Double(ns.blueComponent) * intensity + neutral * (1 - intensity)
        return Color(red: r, green: g, blue: b)
    }

    /// Feeds directly into WidgetThemeID.adaptivePalette(from:)/
    /// CDMaterial.adaptive(from:) — the same functions Adaptive already
    /// uses, just fed a deliberately-chosen colour instead of one sampled
    /// from album art. secondary mirrors ColourExtractor's own convention
    /// (darken the dominant by 40%).
    var extractedColours: ExtractedColours {
        let dominant = color
        let ns = NSColor(dominant).usingColorSpace(.deviceRGB) ?? NSColor(dominant)
        let secondary = Color(red: Double(ns.redComponent) * 0.6,
                               green: Double(ns.greenComponent) * 0.6,
                               blue: Double(ns.blueComponent) * 0.6)
        return ExtractedColours(dominant: dominant, secondary: secondary)
    }
}

/// Persists one user-picked HSVColor per widget family that has a "Custom"
/// style — Vinyl v1, Vinyl Horizontal, CD Discman, CD Hi-Fi. A single shared
/// instance so every place that reads a Custom colour (a live desktop
/// widget, a gallery card's preview, the picker sheet's own mini preview)
/// observes the same source and stays in sync.
final class CustomColorManager: ObservableObject {
    static let shared = CustomColorManager()

    @Published var vinyl: HSVColor { didSet { Self.save(vinyl, key: "customColor.vinyl") } }
    @Published var vinylHorizontal: HSVColor { didSet { Self.save(vinylHorizontal, key: "customColor.vinylHorizontal") } }
    @Published var cdDiscman: HSVColor { didSet { Self.save(cdDiscman, key: "customColor.cdDiscman") } }
    @Published var cdHifi: HSVColor { didSet { Self.save(cdHifi, key: "customColor.cdHifi") } }

    private init() {
        vinyl = Self.load("customColor.vinyl")
        vinylHorizontal = Self.load("customColor.vinylHorizontal")
        cdDiscman = Self.load("customColor.cdDiscman")
        cdHifi = Self.load("customColor.cdHifi")
    }

    private static func save(_ value: HSVColor, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load(_ key: String) -> HSVColor {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(HSVColor.self, from: data)
        else { return .default }
        return value
    }
}
