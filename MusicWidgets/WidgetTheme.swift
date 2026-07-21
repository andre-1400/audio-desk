import SwiftUI
import Foundation
import Combine

enum WidgetThemeID: String, CaseIterable {
    case `default` = "default"
    case modern = "modern"
    case minimalIvory = "minimalIvory"
    case minimalRose = "minimalRose"
    case pearl = "pearl"
    case obsidian = "obsidian"
    // New styles
    case walnut = "walnut"
    case rosegold = "rosegold"
    case mint = "mint"
    case midnight = "midnight"
    case crimson = "crimson"
    case emerald = "emerald"
    case sandstone = "sandstone"
    case slate = "slate"
    case bubblegum = "bubblegum"
    // Retro models (with transport buttons)
    case jukebox = "jukebox"
    case diner = "diner"
    case boombox = "boombox"
    case tweed = "tweed"
    case mustard = "mustard"
    // Second wave
    case synthwave = "synthwave"
    case glacier = "glacier"
    case carbon = "carbon"
    case honey = "honey"
    case lavender = "lavender"
    case copper = "copper"
    case minimalSage = "minimalSage"
    // Live — colours track whatever's currently playing instead of a fixed palette
    case adaptive = "adaptive"

    static func fromPersisted(_ value: String?) -> WidgetThemeID {
        guard let value,
              let parsed = WidgetThemeID(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .default
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

        // MARK: Modern (floating disc, no body)
        case .modern:
            return WidgetThemePalette(
                showBody: false,
                showBodyTexture: false,
                widgetBodyGradient: [.clear, .clear, .clear, .clear],
                widgetBorder: .clear,
                widgetTopSheen: .clear,
                albumArtLabelGradient: [Color(hex: "1a1a1a"), Color(hex: "0d0d0d"), Color(hex: "080808")],
                albumArtRingColor: Color.white.opacity(0.18),
                trackPlayingDot: Color(hex: "ffffff"),
                trackPausedDot: Color(hex: "888888"),
                trackTitle: Color(hex: "ffffff"),
                trackArtist: Color(hex: "aaaaaa"),
                trackIdle: Color(hex: "666666"),
                screwGradient: [.clear, .clear, .clear],
                shelfButtonBackground: .clear,
                shelfButtonRing: .clear,
                shelfButtonIcon: .clear,
                shelfPanelGradient: [.clear, .clear, .clear],
                shelfOutline: .clear,
                queueBarText: Color(hex: "ffffff"),
                queueBarBackground: Color(hex: "111111"),
                queueBarBorder: Color(hex: "ffffff").opacity(0.1),
                connectOverlayIcon: Color(hex: "888888"),
                connectOverlayTitle: Color(hex: "ffffff"),
                connectOverlaySubtitle: Color(hex: "aaaaaa"),
                connectOverlayBackground: Color(hex: "111111"),
                connectOverlayBorder: Color(hex: "ffffff").opacity(0.1),
                sleeveCardGradient: [Color(hex: "222222"), Color(hex: "111111"), Color(hex: "0a0a0a")],
                sleeveCardBorder: Color(hex: "ffffff").opacity(0.10),
                sleeveNowText: Color(hex: "ffffff"),
                sleeveNowBackground: Color(hex: "111111"),
                sleevePlaceholderOuter: Color(hex: "222222"),
                sleevePlaceholderMiddle: Color(hex: "111111"),
                sleevePlaceholderInner: Color(hex: "1a1a1a"),
                sleevePlaceholderLetter: Color(hex: "aaaaaa")
            )

        // MARK: Minimal floating-disc colour variants (no body)
        case .minimalIvory:
            return makeVinylPalette(
                texture: false,
                body: ["000000", "000000", "000000", "000000"],
                border: "ffffff", borderOpacity: 0, sheen: "ffffff", sheenOpacity: 0,
                label: ["f2ead6", "ddcfae", "b89c78"], ring: "f4e8cc",
                accent: "ffffff", paused: "999999",
                title: "ffffff", artist: "cfcfcf", idle: "808080",
                screw: ["000000", "000000", "000000"], dark: true, showBody: false
            )

        case .minimalRose:
            return makeVinylPalette(
                texture: false,
                body: ["000000", "000000", "000000", "000000"],
                border: "ffffff", borderOpacity: 0, sheen: "ffffff", sheenOpacity: 0,
                label: ["e8aebb", "c87f90", "9a5868"], ring: "f3c8d2",
                accent: "ffffff", paused: "999999",
                title: "ffffff", artist: "cfcfcf", idle: "808080",
                screw: ["000000", "000000", "000000"], dark: true, showBody: false
            )

        // MARK: New styles (built via factory for consistency)
        case .walnut:
            return makeVinylPalette(
                texture: true,
                body: ["3d2817", "2a1a0e", "1f130a", "2a1a0e"],
                border: "c9a24b", borderOpacity: 0.18, sheen: "e8c878", sheenOpacity: 0.12,
                label: ["8a5a2a", "5c3a18", "2e1c0a"], ring: "d4a85a",
                accent: "e0a84a", paused: "a88a55",
                title: "f0d8a0", artist: "b89a68", idle: "7a6040",
                screw: ["d8bc78", "9a7838", "4a3015"], dark: true
            )

        case .rosegold:
            return makeVinylPalette(
                texture: false,
                body: ["f5e0e0", "f0d5d5", "e8c8c8", "f0d5d5"],
                border: "d8a8a0", borderOpacity: 0.40, sheen: "ffffff", sheenOpacity: 0.50,
                label: ["c08878", "9a6458", "6a4038"], ring: "d89888",
                accent: "d4887a", paused: "c0a098",
                title: "5a3530", artist: "8a6058", idle: "c0a8a0",
                screw: ["e8c0b0", "d09888", "a87868"], dark: false
            )

        case .mint:
            return makeVinylPalette(
                texture: false,
                body: ["d8ede0", "c8e5d5", "b8ddc8", "c8e5d5"],
                border: "8ab89a", borderOpacity: 0.40, sheen: "ffffff", sheenOpacity: 0.50,
                label: ["5a8a6a", "3e6a4a", "244530"], ring: "6aa87a",
                accent: "4aa86a", paused: "8ab09a",
                title: "20402e", artist: "508060", idle: "90b8a0",
                screw: ["c0d8c8", "90b89a", "6a9070"], dark: false
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

        case .crimson:
            return makeVinylPalette(
                texture: true,
                body: ["3a0e12", "2a080c", "1e0608", "2a080c"],
                border: "d0a050", borderOpacity: 0.20, sheen: "f0c860", sheenOpacity: 0.10,
                label: ["7a2a2a", "5a1818", "3a0e0e"], ring: "d0a85a",
                accent: "e0b04a", paused: "a07858",
                title: "f0d8a0", artist: "c09878", idle: "8a5a4a",
                screw: ["e0c078", "a07838", "4a2818"], dark: true
            )

        case .emerald:
            return makeVinylPalette(
                texture: true,
                body: ["0e3020", "082418", "051a10", "082418"],
                border: "d0b060", borderOpacity: 0.22, sheen: "f0d878", sheenOpacity: 0.10,
                label: ["1a5a3a", "0e3a24", "082414"], ring: "d0b85a",
                accent: "e0c050", paused: "8aa080",
                title: "f0e8c0", artist: "a0c0a0", idle: "608060",
                screw: ["e0d088", "a08840", "4a4018"], dark: true
            )

        case .sandstone:
            return makeVinylPalette(
                texture: false,
                body: ["e8dcc4", "e0d2b4", "d8c8a4", "e0d2b4"],
                border: "b09868", borderOpacity: 0.40, sheen: "ffffff", sheenOpacity: 0.45,
                label: ["a07840", "705228", "443014"], ring: "b89060",
                accent: "c08840", paused: "b0a080",
                title: "4a3818", artist: "806840", idle: "b8a880",
                screw: ["d8c498", "b09858", "8a7038"], dark: false
            )

        case .slate:
            return makeVinylPalette(
                texture: true,
                body: ["3a3e44", "2c3034", "222528", "2c3034"],
                border: "9098a0", borderOpacity: 0.22, sheen: "ffffff", sheenOpacity: 0.08,
                label: ["48505a", "343a42", "24282e"], ring: "a0a8b0",
                accent: "90a0b0", paused: "6a727a",
                title: "e8ecf0", artist: "9aa2aa", idle: "555a60",
                screw: ["c8ccd0", "888e96", "3a3e44"], dark: true
            )

        case .bubblegum:
            return makeVinylPalette(
                texture: false,
                body: ["fdd8e8", "fcc8de", "fab8d4", "fcc8de"],
                border: "e89ab8", borderOpacity: 0.40, sheen: "ffffff", sheenOpacity: 0.55,
                label: ["d8688a", "b84868", "902c48"], ring: "e87aa0",
                accent: "f060a0", paused: "d8a0b8",
                title: "7a2848", artist: "b05878", idle: "e0a8c0",
                screw: ["fcc8de", "f090b0", "d86890"], dark: false
            )

        // MARK: Retro models (warm vintage, chrome/brass hardware + buttons)
        case .jukebox:
            return makeVinylPalette(
                texture: false,
                body: ["6e1a18", "521210", "3e0e0c", "521210"],
                border: "d8d8d8", borderOpacity: 0.25, sheen: "ffffff", sheenOpacity: 0.10,
                label: ["d8c8a0", "b09060", "8a6840"], ring: "e8d8b0",
                accent: "f0d070", paused: "b09878",
                title: "f5e6c0", artist: "d0b890", idle: "9a7858",
                screw: ["ececec", "a8a8a8", "585858"], dark: true
            )

        case .diner:
            return makeVinylPalette(
                texture: false,
                body: ["1f6e6a", "145450", "0e3e3c", "145450"],
                border: "d8d8d8", borderOpacity: 0.25, sheen: "ffffff", sheenOpacity: 0.12,
                label: ["e0d8c0", "b8a888", "8a7858"], ring: "f0e8d0",
                accent: "f0c050", paused: "90b0a8",
                title: "eef5ee", artist: "b8d0c8", idle: "6a9088",
                screw: ["ececec", "a8a8a8", "585858"], dark: true
            )

        case .boombox:
            return makeVinylPalette(
                texture: false,
                body: ["2c2c30", "202024", "18181a", "202024"],
                border: "ff8a3a", borderOpacity: 0.30, sheen: "ffffff", sheenOpacity: 0.08,
                label: ["3a3a3e", "262628", "18181a"], ring: "ff8a3a",
                accent: "ff8a3a", paused: "808088",
                title: "f0f0f2", artist: "b0b0b8", idle: "606068",
                screw: ["d0d0d4", "8a8a90", "3a3a40"], dark: true
            )

        case .tweed:
            return makeVinylPalette(
                texture: false,
                body: ["5a4630", "463420", "342614", "463420"],
                border: "c8a24b", borderOpacity: 0.25, sheen: "e8c878", sheenOpacity: 0.10,
                label: ["c8a868", "9a7840", "6a5028"], ring: "d4b070",
                accent: "e0b050", paused: "b09870",
                title: "f0dca8", artist: "c8b088", idle: "8a7048",
                screw: ["e0c078", "a88838", "52401a"], dark: true
            )

        case .mustard:
            return makeVinylPalette(
                texture: false,
                body: ["c89030", "a8741e", "8a5e14", "a8741e"],
                border: "5a3e18", borderOpacity: 0.40, sheen: "ffffff", sheenOpacity: 0.22,
                label: ["7a5020", "5a3a14", "3e280c"], ring: "8a6028",
                accent: "8a4e18", paused: "b09850",
                title: "3e2810", artist: "6a4e20", idle: "b09040",
                screw: ["e0c068", "b89038", "7a5a20"], dark: false
            )

        // MARK: Second wave

        case .synthwave:
            return makeVinylPalette(
                texture: true,
                body: ["1a1030", "120a24", "0c061a", "120a24"],
                border: "ff4fd8", borderOpacity: 0.28, sheen: "9a6bff", sheenOpacity: 0.12,
                label: ["ff4fd8", "b025a8", "5c1470"], ring: "5df0ff",
                accent: "5df0ff", paused: "8a6aa8",
                title: "f0e0ff", artist: "b090d8", idle: "584878",
                screw: ["d0b0ff", "8a5fd0", "3a2060"], dark: true
            )

        case .glacier:
            return makeVinylPalette(
                texture: false,
                body: ["e8f2f8", "dcebf4", "cee0ec", "dcebf4"],
                border: "8ab4cc", borderOpacity: 0.40, sheen: "ffffff", sheenOpacity: 0.55,
                label: ["5a8aa8", "3a6a88", "224a62"], ring: "6aa8c8",
                accent: "3a9ad8", paused: "90b0c4",
                title: "1e3a4e", artist: "50788e", idle: "a0c0d0",
                screw: ["d0e4ee", "9ec0d4", "6a94ac"], dark: false
            )

        case .carbon:
            return makeVinylPalette(
                texture: true,
                body: ["232326", "18181b", "0f0f11", "18181b"],
                border: "e03a3a", borderOpacity: 0.30, sheen: "ffffff", sheenOpacity: 0.06,
                label: ["3a3a3e", "242428", "141416"], ring: "e03a3a",
                accent: "ff4545", paused: "78787e",
                title: "f2f2f4", artist: "a8a8b0", idle: "58585e",
                screw: ["c8c8cc", "808086", "323236"], dark: true
            )

        case .honey:
            return makeVinylPalette(
                texture: false,
                body: ["f4e4c0", "eed8a8", "e4c890", "eed8a8"],
                border: "b8862a", borderOpacity: 0.40, sheen: "ffffff", sheenOpacity: 0.50,
                label: ["c89030", "9a6a1e", "6a4410"], ring: "c89838",
                accent: "d89a28", paused: "b8a070",
                title: "4a3410", artist: "846018", idle: "c0a86a",
                screw: ["e8d098", "c0983f", "8a6a24"], dark: false
            )

        case .lavender:
            return makeVinylPalette(
                texture: false,
                body: ["e6dcf4", "dccef0", "cebce6", "dccef0"],
                border: "9a7cc8", borderOpacity: 0.40, sheen: "ffffff", sheenOpacity: 0.52,
                label: ["8a68b8", "664a92", "44306a"], ring: "9a78cc",
                accent: "8a5ad8", paused: "a898c0",
                title: "3a2858", artist: "6a548e", idle: "b0a0cc",
                screw: ["dcd0f0", "b09cd8", "8068a8"], dark: false
            )

        case .copper:
            return makeVinylPalette(
                texture: true,
                body: ["4a2a18", "38200f", "2a160a", "38200f"],
                border: "e8945a", borderOpacity: 0.24, sheen: "ffb87a", sheenOpacity: 0.12,
                label: ["b06a35", "84481e", "542c10"], ring: "e89a5e",
                accent: "ff9a50", paused: "b08868",
                title: "ffd8b8", artist: "cc9a74", idle: "84603f",
                screw: ["f0c090", "c07a40", "6a3c1a"], dark: true
            )

        case .minimalSage:
            return makeVinylPalette(
                texture: false,
                body: ["000000", "000000", "000000", "000000"],
                border: "ffffff", borderOpacity: 0, sheen: "ffffff", sheenOpacity: 0,
                label: ["b8ccae", "94ac88", "68805e"], ring: "c4d8ba",
                accent: "ffffff", paused: "999999",
                title: "ffffff", artist: "cfcfcf", idle: "808080",
                screw: ["000000", "000000", "000000"], dark: true, showBody: false
            )

        // MARK: Adaptive — body colour tracks the currently playing album's
        // art instead of a fixed palette. This static branch (fallback
        // colours) only fires for contexts with no live data, e.g. the
        // gallery preview card; the live widget gets its colours from
        // WidgetThemeID.adaptivePalette(from:) via WidgetThemeManager instead.
        case .adaptive:
            return WidgetThemeID.adaptivePalette(from: .fallback)

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
