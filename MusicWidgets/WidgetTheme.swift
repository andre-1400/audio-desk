import SwiftUI
import Foundation
import Combine

enum WidgetThemeID: String, CaseIterable {
    case `default` = "default"
    case pearl = "pearl"
    case obsidian = "obsidian"
    case midnight = "midnight"
    // Live — colours track whatever's currently playing instead of a fixed palette
    case adaptive = "adaptive"

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

        // MARK: Pearl (cream/ivory enclosure, warm terra cotta accents)
        case .pearl:
            return WidgetThemePalette(
                showBody: true,
                showBodyTexture: false,
                widgetBodyGradient: [Color(hex: "f8f4ee"), Color(hex: "f0ebe0"), Color(hex: "e8e0d0"), Color(hex: "f0ebe0")],
                widgetBorder: Color(hex: "c8a878").opacity(0.40),
                widgetTopSheen: Color(hex: "ffffff").opacity(0.50),
                albumArtLabelGradient: [Color(hex: "9B5523"), Color(hex: "6C3E1A"), Color(hex: "3a1a06")],
                albumArtRingColor: Color(hex: "c8855a").opacity(0.40),
                trackPlayingDot: Color(hex: "c8855a"),
                trackPausedDot: Color(hex: "b09070"),
                trackTitle: Color(hex: "3a2010"),
                trackArtist: Color(hex: "7a5a40"),
                trackIdle: Color(hex: "c0a888"),
                screwGradient: [Color(hex: "d4b890"), Color(hex: "b09060"), Color(hex: "8a7050")],
                shelfButtonBackground: Color(hex: "f0ebe0"),
                shelfButtonRing: Color(hex: "c8a878"),
                shelfButtonIcon: Color(hex: "8B5030"),
                shelfPanelGradient: [Color(hex: "f8f4ee"), Color(hex: "f0ebe0"), Color(hex: "e8e0d0")],
                shelfOutline: Color(hex: "c8a878").opacity(0.20),
                queueBarText: Color(hex: "3a2010"),
                queueBarBackground: Color(hex: "f0ebe0"),
                queueBarBorder: Color(hex: "c8a878").opacity(0.15),
                connectOverlayIcon: Color(hex: "b09070"),
                connectOverlayTitle: Color(hex: "3a2010"),
                connectOverlaySubtitle: Color(hex: "7a5a40"),
                connectOverlayBackground: Color(hex: "f8f4ee"),
                connectOverlayBorder: Color(hex: "c8a878").opacity(0.20),
                sleeveCardGradient: [Color(hex: "f0ebe0"), Color(hex: "e8e0d0"), Color(hex: "e0d8c8")],
                sleeveCardBorder: Color(hex: "c8a878").opacity(0.15),
                sleeveNowText: Color(hex: "3a2010"),
                sleeveNowBackground: Color(hex: "f0ebe0"),
                sleevePlaceholderOuter: Color(hex: "e8e0d0"),
                sleevePlaceholderMiddle: Color(hex: "f0ebe0"),
                sleevePlaceholderInner: Color(hex: "e8ddd0"),
                sleevePlaceholderLetter: Color(hex: "b09070")
            )

        // MARK: Obsidian (jet black enclosure, chrome/silver accents)
        case .obsidian:
            return WidgetThemePalette(
                showBody: true,
                showBodyTexture: true,
                widgetBodyGradient: [Color(hex: "050505"), Color(hex: "020202"), Color(hex: "080808"), Color(hex: "020202")],
                widgetBorder: Color(hex: "a0a0a0").opacity(0.22),
                widgetTopSheen: Color(hex: "ffffff").opacity(0.06),
                albumArtLabelGradient: [Color(hex: "1a1a1a"), Color(hex: "0d0d0d"), Color(hex: "050505")],
                albumArtRingColor: Color(hex: "c0c0c0").opacity(0.22),
                trackPlayingDot: Color(hex: "e0e0e0"),
                trackPausedDot: Color(hex: "606060"),
                trackTitle: Color(hex: "f0f0f0"),
                trackArtist: Color(hex: "909090"),
                trackIdle: Color(hex: "404040"),
                screwGradient: [Color(hex: "d0d0d0"), Color(hex: "808080"), Color(hex: "303030")],
                shelfButtonBackground: Color(hex: "080808"),
                shelfButtonRing: Color(hex: "a0a0a0"),
                shelfButtonIcon: Color(hex: "c0c0c0"),
                shelfPanelGradient: [Color(hex: "050505"), Color(hex: "020202"), Color(hex: "080808")],
                shelfOutline: Color(hex: "a0a0a0").opacity(0.12),
                queueBarText: Color(hex: "f0f0f0"),
                queueBarBackground: Color(hex: "080808"),
                queueBarBorder: Color(hex: "a0a0a0").opacity(0.10),
                connectOverlayIcon: Color(hex: "808080"),
                connectOverlayTitle: Color(hex: "f0f0f0"),
                connectOverlaySubtitle: Color(hex: "909090"),
                connectOverlayBackground: Color(hex: "0e0e0e"),
                connectOverlayBorder: Color(hex: "a0a0a0").opacity(0.12),
                sleeveCardGradient: [Color(hex: "121212"), Color(hex: "080808"), Color(hex: "050505")],
                sleeveCardBorder: Color(hex: "a0a0a0").opacity(0.10),
                sleeveNowText: Color(hex: "f0f0f0"),
                sleeveNowBackground: Color(hex: "080808"),
                sleevePlaceholderOuter: Color(hex: "121212"),
                sleevePlaceholderMiddle: Color(hex: "080808"),
                sleevePlaceholderInner: Color(hex: "101010"),
                sleevePlaceholderLetter: Color(hex: "909090")
            )

        case .midnight:
            return makeVinylPalette(
                texture: true,
                body: ["12203a", "0c1828", "08101e", "0c1828"],
                border: "8090b0", borderOpacity: 0.22, sheen: "ffffff", sheenOpacity: 0.06,
                label: ["1a2840", "0e1828", "080f1c"], ring: "a0b0d0",
                accent: "6a90d0", paused: "5a6a85",
                title: "e0e8f5", artist: "8a98b5", idle: "405068",
                screw: ["c0c8d8", "7888a0", "303a4a"], dark: true
            )

        // MARK: Adaptive — body colour tracks the currently playing album's
        // art instead of a fixed palette. This static branch (fallback
        // colours) only fires for contexts with no live data, e.g. the
        // gallery preview card; the live widget gets its colours from
        // WidgetThemeID.adaptivePalette(from:) via WidgetThemeManager instead.
        case .adaptive:
            return WidgetThemeID.adaptivePalette(from: .adaptivePreviewPlaceholder)

        }
    }
}

// MARK: - Adaptive palette (live, built from the playing album's colours)

extension WidgetThemeID {
    static func adaptivePalette(from colours: ExtractedColours) -> WidgetThemePalette {
        let dominant = colours.dominant
        let secondary = colours.secondary
        let darkest = secondary.adjustBrightness(-0.12)
        let isLight = dominant.isPerceivedLight

        let title: Color = isLight ? Color.black.opacity(0.86) : .white
        let artist: Color = isLight ? Color.black.opacity(0.58) : Color.white.opacity(0.7)
        let idle: Color = isLight ? Color.black.opacity(0.38) : Color.white.opacity(0.45)

        let bodyColors = [dominant, secondary, darkest, secondary]
        let labelColors = [dominant, secondary, darkest]

        return WidgetThemePalette(
            showBody: true,
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

// MARK: - Vinyl palette factory
// Builds a full WidgetThemePalette from a small set of key colors so new
// styles stay concise and consistent. Functionality is identical — this only
// supplies color data to the existing renderer.
private func makeVinylPalette(
    texture: Bool,
    body: [String],
    border: String, borderOpacity: Double,
    sheen: String, sheenOpacity: Double,
    label: [String], ring: String,
    accent: String, paused: String,
    title: String, artist: String, idle: String,
    screw: [String], dark: Bool,
    showBody: Bool = true
) -> WidgetThemePalette {
    let bodyColors = body.map { Color(hex: $0) }
    let labelColors = label.map { Color(hex: $0) }
    let screwColors = screw.map { Color(hex: $0) }
    let darkest = bodyColors.last ?? Color(hex: body[0])

    return WidgetThemePalette(
        showBody: showBody,
        showBodyTexture: showBody && texture,
        widgetBodyGradient: bodyColors,
        widgetBorder: Color(hex: border).opacity(borderOpacity),
        widgetTopSheen: Color(hex: sheen).opacity(sheenOpacity),
        albumArtLabelGradient: labelColors,
        albumArtRingColor: Color(hex: ring).opacity(0.32),
        trackPlayingDot: Color(hex: accent),
        trackPausedDot: Color(hex: paused),
        trackTitle: Color(hex: title),
        trackArtist: Color(hex: artist),
        trackIdle: Color(hex: idle),
        screwGradient: screwColors,
        shelfButtonBackground: darkest,
        shelfButtonRing: Color(hex: accent),
        shelfButtonIcon: Color(hex: accent),
        shelfPanelGradient: Array(bodyColors.prefix(3)),
        shelfOutline: Color(hex: border).opacity(borderOpacity * 0.6),
        queueBarText: Color(hex: title),
        queueBarBackground: darkest,
        queueBarBorder: Color(hex: border).opacity(borderOpacity * 0.5),
        connectOverlayIcon: Color(hex: paused),
        connectOverlayTitle: Color(hex: title),
        connectOverlaySubtitle: Color(hex: artist),
        connectOverlayBackground: bodyColors.count > 1 ? bodyColors[1] : darkest,
        connectOverlayBorder: Color(hex: border).opacity(borderOpacity * 0.6),
        sleeveCardGradient: Array(bodyColors.prefix(3)),
        sleeveCardBorder: Color(hex: border).opacity(borderOpacity * 0.6),
        sleeveNowText: Color(hex: title),
        sleeveNowBackground: darkest,
        sleevePlaceholderOuter: bodyColors.count > 1 ? bodyColors[1] : darkest,
        sleevePlaceholderMiddle: bodyColors.count > 2 ? bodyColors[2] : darkest,
        sleevePlaceholderInner: bodyColors[0],
        sleevePlaceholderLetter: Color(hex: artist)
    )
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
