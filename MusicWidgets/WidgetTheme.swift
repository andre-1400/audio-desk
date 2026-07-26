import SwiftUI
import Foundation
import Combine

enum WidgetThemeID: String, CaseIterable {
    // Not a user-facing gallery choice anymore (every fixed prebuilt
    // colourway was removed) — kept only as the neutral base palette
    // GeneratedThemeSpec.toWidgetThemePalette derives its fallback colours
    // from.
    case `default` = "default"
    // Live — colours track whatever's currently playing instead of a fixed palette
    case adaptive = "adaptive"
    // Fixed — colour picked once by the user via HSVColorPickerView, not tied
    // to any playback state.
    case custom = "custom"
    // Live, same as Adaptive, but with showBody: false — no housing shell,
    // no button/scrubber chrome, just the disc and the title/artist text.
    case ghost = "ghost"

    static func fromPersisted(_ value: String?) -> WidgetThemeID {
        guard let value,
              let parsed = WidgetThemeID(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .adaptive
        }
        return parsed
    }
}

struct WidgetThemePalette {
    // Body
    let showBody: Bool
    let showBodyTexture: Bool
    let widgetBodyGradient: [Color]
    let widgetBorder: Color
    let widgetTopSheen: Color

    // Album art label (center of disc)
    let albumArtLabelGradient: [Color]
    let albumArtRingColor: Color

    // Track info
    let trackPlayingDot: Color
    let trackPausedDot: Color
    let trackTitle: Color
    let trackArtist: Color
    let trackIdle: Color

    // Screws
    let screwGradient: [Color]

    // Shelf / queue (kept for palette completeness, currently unused)
    let shelfButtonBackground: Color
    let shelfButtonRing: Color
    let shelfButtonIcon: Color
    let shelfPanelGradient: [Color]
    let shelfOutline: Color
    let queueBarText: Color
    let queueBarBackground: Color
    let queueBarBorder: Color

    // Connect overlay (unused but kept for forward compat)
    let connectOverlayIcon: Color
    let connectOverlayTitle: Color
    let connectOverlaySubtitle: Color
    let connectOverlayBackground: Color
    let connectOverlayBorder: Color

    // Sleeve card (animation overlay)
    let sleeveCardGradient: [Color]
    let sleeveCardBorder: Color
    let sleeveNowText: Color
    let sleeveNowBackground: Color
    let sleevePlaceholderOuter: Color
    let sleevePlaceholderMiddle: Color
    let sleevePlaceholderInner: Color
    let sleevePlaceholderLetter: Color
}

extension WidgetThemeID {
    var palette: WidgetThemePalette {
        switch self {

        // MARK: Classic Vinyl (warm dark wood + gold)
        case .default:
            return WidgetThemePalette(
                showBody: true,
                showBodyTexture: true,
                widgetBodyGradient: [Color(hex: "2a1a0a"), Color(hex: "1e1208"), Color(hex: "170e06"), Color(hex: "1e1208")],
                widgetBorder: Color(hex: "ffc864").opacity(0.14),
                widgetTopSheen: Color(hex: "ffc864").opacity(0.11),
                albumArtLabelGradient: [Color(hex: "9B5523"), Color(hex: "6C3E1A"), Color(hex: "3a1a06")],
                albumArtRingColor: Color(hex: "ffbe50").opacity(0.30),
                trackPlayingDot: Color(hex: "f0a030"),
                trackPausedDot: Color(hex: "b89a60"),
                trackTitle: Color(hex: "f0d890"),
                trackArtist: Color(hex: "b89a60"),
                trackIdle: Color(hex: "7a6040"),
                screwGradient: [Color(hex: "c8a860"), Color(hex: "7a5a28"), Color(hex: "3a2010")],
                shelfButtonBackground: Color(hex: "170e06"),
                shelfButtonRing: Color(hex: "ffc864"),
                shelfButtonIcon: Color(hex: "ffc864"),
                shelfPanelGradient: [Color(hex: "2a1a0a"), Color(hex: "1e1208"), Color(hex: "170e06")],
                shelfOutline: Color(hex: "ffc864").opacity(0.14),
                queueBarText: Color(hex: "f0d890"),
                queueBarBackground: Color(hex: "170e06"),
                queueBarBorder: Color(hex: "ffc864").opacity(0.1),
                connectOverlayIcon: Color(hex: "b89a60"),
                connectOverlayTitle: Color(hex: "f0d890"),
                connectOverlaySubtitle: Color(hex: "b89a60"),
                connectOverlayBackground: Color(hex: "1e1208"),
                connectOverlayBorder: Color(hex: "ffc864").opacity(0.15),
                sleeveCardGradient: [Color(hex: "3a2a1a"), Color(hex: "2a1a0a"), Color(hex: "221508")],
                sleeveCardBorder: Color(hex: "ffc864").opacity(0.12),
                sleeveNowText: Color(hex: "f0d890"),
                sleeveNowBackground: Color(hex: "170e06"),
                sleevePlaceholderOuter: Color(hex: "2a2020"),
                sleevePlaceholderMiddle: Color(hex: "1e1208"),
                sleevePlaceholderInner: Color(hex: "3a2a1a"),
                sleevePlaceholderLetter: Color(hex: "b89a60")
            )

        // MARK: Adaptive — body colour tracks the currently playing album's
        // art instead of a fixed palette. This static branch (fallback
        // colours) only fires for contexts with no live data, e.g. the
        // gallery preview card; the live widget gets its colours from
        // WidgetThemeID.adaptivePalette(from:) via WidgetThemeManager instead.
        case .adaptive:
            return WidgetThemeID.adaptivePalette(from: .adaptivePreviewPlaceholder)

        // MARK: Custom — body colour is whatever the user picked in
        // HSVColorPickerView. This static branch is only the gallery's
        // pre-selection placeholder; the live widget and the selected
        // preview card read WidgetThemeManager.palette / CustomColorManager
        // directly (see below), same split as Adaptive.
        case .custom:
            return WidgetThemeID.adaptivePalette(from: CustomColorManager.shared.vinyl.extractedColours)

        // MARK: Ghost — same live colours as Adaptive, no housing. This
        // static branch (fallback colours) only fires for contexts with no
        // live data, e.g. the gallery preview card; the live widget gets
        // its colours from WidgetThemeID.adaptivePalette(from:showBody:) via
        // WidgetThemeManager instead, same split as Adaptive/Custom.
        case .ghost:
            return WidgetThemeID.adaptivePalette(from: .adaptivePreviewPlaceholder, showBody: false)

        }
    }
}

// MARK: - Rainbow preview palette (gallery-grid Custom tile only)
//
// The Custom tile used to just render whatever colour the user had already
// saved, which looked identical to any other single-colour style and gave
// no visual hint that the whole point of it is "pick your own." This is a
// fixed multi-hue spectrum standing in for that — never used by the live
// widget or by the colour-picker sheet's own preview, only the gallery
// grid's Custom card, so it never fights with actually seeing your pick.
extension WidgetThemeID {
    static func rainbowPreviewPalette(showBody: Bool = true) -> WidgetThemePalette {
        let spectrum: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .red]
        let title = Color.white
        let subtitle = Color.white.opacity(0.75)
        return WidgetThemePalette(
            showBody: showBody,
            showBodyTexture: false,
            widgetBodyGradient: spectrum,
            widgetBorder: Color.white.opacity(0.2),
            widgetTopSheen: Color.white.opacity(0.13),
            albumArtLabelGradient: spectrum,
            albumArtRingColor: Color.white.opacity(0.34),
            trackPlayingDot: .white,
            trackPausedDot: subtitle,
            trackTitle: title,
            trackArtist: subtitle,
            trackIdle: Color.white.opacity(0.45),
            screwGradient: spectrum,
            shelfButtonBackground: Color.black.opacity(0.4),
            shelfButtonRing: .white,
            shelfButtonIcon: .white,
            shelfPanelGradient: spectrum,
            shelfOutline: Color.white.opacity(0.11),
            queueBarText: title,
            queueBarBackground: Color.black.opacity(0.4),
            queueBarBorder: Color.white.opacity(0.09),
            connectOverlayIcon: subtitle,
            connectOverlayTitle: title,
            connectOverlaySubtitle: subtitle,
            connectOverlayBackground: Color.black.opacity(0.4),
            connectOverlayBorder: Color.white.opacity(0.11),
            sleeveCardGradient: spectrum,
            sleeveCardBorder: Color.white.opacity(0.11),
            sleeveNowText: title,
            sleeveNowBackground: Color.black.opacity(0.4),
            sleevePlaceholderOuter: Color.blue,
            sleevePlaceholderMiddle: Color.black.opacity(0.4),
            sleevePlaceholderInner: Color.purple,
            sleevePlaceholderLetter: subtitle
        )
    }
}

// MARK: - Adaptive palette (live, built from the playing album's colours)

extension WidgetThemeID {
    static func adaptivePalette(from colours: ExtractedColours, showBody: Bool = true) -> WidgetThemePalette {
        let dominant = colours.dominant
        let secondary = colours.secondary
        let darkest = secondary.adjustBrightness(-0.12)
        // Judged against the body as actually drawn (blurred art + darkening
        // scrim), not the raw artwork — see AdaptiveBody.
        let isLight = AdaptiveBody.isLight(dominant)

        let title: Color = AdaptiveBody.primary(dominant)
        let artist: Color = AdaptiveBody.secondary(dominant)
        let idle: Color = isLight ? Color.black.opacity(0.38) : Color.white.opacity(0.45)

        let bodyColors = [dominant, secondary, darkest, secondary]
        let labelColors = [dominant, secondary, darkest]

        return WidgetThemePalette(
            showBody: showBody,
            showBodyTexture: false,
            widgetBodyGradient: bodyColors,
            widgetBorder: dominant.opacity(0.20),
            widgetTopSheen: dominant.opacity(0.13),
            albumArtLabelGradient: labelColors,
            albumArtRingColor: dominant.opacity(0.34),
            trackPlayingDot: dominant,
            trackPausedDot: secondary,
            trackTitle: title,
            trackArtist: artist,
            trackIdle: idle,
            screwGradient: [dominant.opacity(0.9), secondary, darkest],
            shelfButtonBackground: darkest,
            shelfButtonRing: dominant,
            shelfButtonIcon: dominant,
            shelfPanelGradient: [dominant, secondary, darkest],
            shelfOutline: dominant.opacity(0.11),
            queueBarText: title,
            queueBarBackground: darkest,
            queueBarBorder: dominant.opacity(0.09),
            connectOverlayIcon: secondary,
            connectOverlayTitle: title,
            connectOverlaySubtitle: artist,
            connectOverlayBackground: secondary,
            connectOverlayBorder: dominant.opacity(0.11),
            sleeveCardGradient: [dominant, secondary, darkest],
            sleeveCardBorder: dominant.opacity(0.11),
            sleeveNowText: title,
            sleeveNowBackground: darkest,
            sleevePlaceholderOuter: secondary,
            sleevePlaceholderMiddle: darkest,
            sleevePlaceholderInner: dominant,
            sleevePlaceholderLetter: artist
        )
    }
}

final class WidgetThemeManager: ObservableObject {
    private let storageKey = "onboarding.theme"
    @Published private(set) var themeID: WidgetThemeID
    @Published private(set) var customTheme: WidgetThemePalette?
    @Published private(set) var customThemeName: String?
    /// Pushed live by VinylWidgetView whenever the displayed album art
    /// changes; only consulted when themeID == .adaptive.
    @Published var adaptiveColours: ExtractedColours = .fallback

    var palette: WidgetThemePalette {
        if themeID == .adaptive { return WidgetThemeID.adaptivePalette(from: adaptiveColours) }
        if themeID == .custom { return WidgetThemeID.adaptivePalette(from: CustomColorManager.shared.vinyl.extractedColours) }
        return customTheme ?? themeID.palette
    }
    var isUsingCustomTheme: Bool { customTheme != nil }

    init(initialThemeID: String? = UserDefaults.standard.string(forKey: "onboarding.theme")) {
        self.themeID = WidgetThemeID.fromPersisted(initialThemeID)
    }

    func setThemeID(_ rawValue: String) {
        setTheme(WidgetThemeID.fromPersisted(rawValue))
    }

    func setTheme(_ newThemeID: WidgetThemeID) {
        themeID = newThemeID
        customTheme = nil
        customThemeName = nil
        UserDefaults.standard.set(newThemeID.rawValue, forKey: storageKey)
        UserDefaults.standard.set("preset", forKey: "theme.selection.mode")
    }

    func applyCustomTheme(_ palette: WidgetThemePalette, name: String, spec: GeneratedThemeSpec, showBody: Bool = true) {
        customTheme = palette
        customThemeName = name
        if let data = try? JSONEncoder().encode(spec) {
            UserDefaults.standard.set(data, forKey: "theme.generated.active.spec")
            UserDefaults.standard.set(name, forKey: "theme.generated.active.name")
            UserDefaults.standard.set(showBody, forKey: "theme.generated.active.showBody")
            UserDefaults.standard.set("generated", forKey: "theme.selection.mode")
        }
    }

    func clearCustomTheme() {
        customTheme = nil
        customThemeName = nil
        UserDefaults.standard.removeObject(forKey: "theme.generated.active.spec")
        UserDefaults.standard.removeObject(forKey: "theme.generated.active.name")
        UserDefaults.standard.removeObject(forKey: "theme.generated.active.showBody")
        UserDefaults.standard.set("preset", forKey: "theme.selection.mode")
    }

    func restoreGeneratedThemeIfNeeded() {
        guard UserDefaults.standard.string(forKey: "theme.selection.mode") == "generated",
              let data = UserDefaults.standard.data(forKey: "theme.generated.active.spec"),
              let spec = try? JSONDecoder().decode(GeneratedThemeSpec.self, from: data)
        else { return }
        let showBody = UserDefaults.standard.object(forKey: "theme.generated.active.showBody") as? Bool ?? true
        customTheme = spec.toWidgetThemePalette(showBody: showBody)
        customThemeName = UserDefaults.standard.string(forKey: "theme.generated.active.name") ?? spec.name
    }
}

// MARK: - GeneratedThemeSpec

struct GeneratedThemeSpec: Codable {
    // Identity
    var name: String
    var mood: String?

    // Widget body
    var widgetBodyGradient: [String]
    var widgetBorder: String
    var widgetTopSheen: String

    // Album art label (disc centre)
    var albumArtLabelGradient: [String]
    var albumArtRingColor: String

    // Track info
    var trackPlayingDot: String
    var trackPausedDot: String
    var trackTitle: String
    var trackArtist: String
    var trackIdle: String

    // Screws
    var screwGradient: [String]

    // Shelf / queue
    var shelfButtonBackground: String
    var shelfButtonRing: String
    var shelfButtonIcon: String
    var shelfPanelGradient: [String]
    var shelfOutline: String
    var queueBarText: String
    var queueBarBackground: String
    var queueBarBorder: String

    // Connect overlay
    var connectOverlayIcon: String
    var connectOverlayTitle: String
    var connectOverlaySubtitle: String
    var connectOverlayBackground: String
    var connectOverlayBorder: String

    // Sleeve card
    var sleeveCardGradient: [String]
    var sleeveCardBorder: String
    var sleeveNowText: String
    var sleeveNowBackground: String
    var sleevePlaceholderOuter: String
    var sleevePlaceholderMiddle: String
    var sleevePlaceholderInner: String
    var sleevePlaceholderLetter: String

    // Optional tuning
    var shelfOpacity: Double?
    var shadowStrength: Double?
}

// MARK: - Conversion: GeneratedThemeSpec -> WidgetThemePalette

extension GeneratedThemeSpec {

    func toWidgetThemePalette(showBody: Bool = true) -> WidgetThemePalette {
        let base = WidgetThemeID.default.palette

        func color(_ hex: String?, fallback: Color) -> Color {
            guard let hex else { return fallback }
            let stripped = hex.trimmingCharacters(in: .whitespacesAndNewlines)
                              .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard stripped.count == 6,
                  stripped.allSatisfy({ $0.isHexDigit }) else { return fallback }
            return Color(hex: stripped)
        }

        func colors(_ arr: [String]?, count: Int, fallback: [Color]) -> [Color] {
            let raw = arr ?? []
            var result = raw.enumerated().map { i, hex in
                color(hex, fallback: fallback[min(i, fallback.count - 1)])
            }
            while result.count < count {
                result.append(result.last ?? fallback[min(result.count, fallback.count - 1)])
            }
            return Array(result.prefix(count))
        }

        let clearArr4: [Color] = [.clear, .clear, .clear, .clear]
        let clearArr3: [Color] = [.clear, .clear, .clear]

        return WidgetThemePalette(
            showBody: showBody,
            showBodyTexture: showBody,
            widgetBodyGradient: showBody
                ? colors(widgetBodyGradient, count: 4, fallback: base.widgetBodyGradient)
                : clearArr4,
            widgetBorder:   showBody ? color(widgetBorder,   fallback: base.widgetBorder)   : .clear,
            widgetTopSheen: showBody ? color(widgetTopSheen, fallback: base.widgetTopSheen) : .clear,
            albumArtLabelGradient: colors(albumArtLabelGradient, count: 3,
                                          fallback: base.albumArtLabelGradient),
            albumArtRingColor: color(albumArtRingColor, fallback: base.albumArtRingColor),
            trackPlayingDot: color(trackPlayingDot, fallback: base.trackPlayingDot),
            trackPausedDot:  color(trackPausedDot,  fallback: base.trackPausedDot),
            trackTitle:      color(trackTitle,      fallback: base.trackTitle),
            trackArtist:     color(trackArtist,     fallback: base.trackArtist),
            trackIdle:       color(trackIdle,       fallback: base.trackIdle),
            screwGradient: showBody
                ? colors(screwGradient, count: 3, fallback: base.screwGradient)
                : clearArr3,
            shelfButtonBackground: color(shelfButtonBackground, fallback: base.shelfButtonBackground),
            shelfButtonRing:       color(shelfButtonRing,       fallback: base.shelfButtonRing),
            shelfButtonIcon:       color(shelfButtonIcon,       fallback: base.shelfButtonIcon),
            shelfPanelGradient: colors(shelfPanelGradient, count: 3,
                                       fallback: base.shelfPanelGradient),
            shelfOutline:        color(shelfOutline,        fallback: base.shelfOutline),
            queueBarText:        color(queueBarText,        fallback: base.queueBarText),
            queueBarBackground:  color(queueBarBackground,  fallback: base.queueBarBackground),
            queueBarBorder:      color(queueBarBorder,      fallback: base.queueBarBorder),
            connectOverlayIcon:       color(connectOverlayIcon,       fallback: base.connectOverlayIcon),
            connectOverlayTitle:      color(connectOverlayTitle,      fallback: base.connectOverlayTitle),
            connectOverlaySubtitle:   color(connectOverlaySubtitle,   fallback: base.connectOverlaySubtitle),
            connectOverlayBackground: color(connectOverlayBackground, fallback: base.connectOverlayBackground),
            connectOverlayBorder:     color(connectOverlayBorder,     fallback: base.connectOverlayBorder),
            sleeveCardGradient: colors(sleeveCardGradient, count: 3,
                                       fallback: base.sleeveCardGradient),
            sleeveCardBorder:        color(sleeveCardBorder,        fallback: base.sleeveCardBorder),
            sleeveNowText:           color(sleeveNowText,           fallback: base.sleeveNowText),
            sleeveNowBackground:     color(sleeveNowBackground,     fallback: base.sleeveNowBackground),
            sleevePlaceholderOuter:  color(sleevePlaceholderOuter,  fallback: base.sleevePlaceholderOuter),
            sleevePlaceholderMiddle: color(sleevePlaceholderMiddle, fallback: base.sleevePlaceholderMiddle),
            sleevePlaceholderInner:  color(sleevePlaceholderInner,  fallback: base.sleevePlaceholderInner),
            sleevePlaceholderLetter: color(sleevePlaceholderLetter, fallback: base.sleevePlaceholderLetter)
        )
    }
}
