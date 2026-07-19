import SwiftUI
import AppKit

private let cdMargin: CGFloat = 16   // transparent room for a soft, non-square shadow

// MARK: - Material

struct CDMaterial {
    var housing: [Color]
    var ring: [Color]
    var accent: Color
    var lidTint: Color
    var lidOpacity: Double
    var well: [Color]
    var panel: [Color]
    var lcdBg: [Color]
    var lcd: Color
    var subtitle: Color
    var isLight: Bool
    var translucent: Bool = false
}

// MARK: - Archetype (device body)

enum CDArchetype: String {
    case discman, translucent, hifi, boombox

    var baseSize: CGSize {
        switch self {
        case .discman, .translucent: return CGSize(width: 360, height: 500)
        case .hifi:    return CGSize(width: 560, height: 300)
        case .boombox: return CGSize(width: 580, height: 432)
        }
    }
    var deckDiameter: CGFloat {
        switch self {
        case .discman, .translucent: return 220
        case .hifi:    return 196
        case .boombox: return 96
        }
    }
}

// MARK: - Gallery model

struct CDModel: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let archetype: CDArchetype
    let material: CDMaterial

    static let all: [CDModel] = [
        // ===== Discman (portable) — 10 colours =====
        CDModel(id: "discman-silver",     name: "Silver",    subtitle: "Brushed silver",      archetype: .discman,     material: .silver),
        CDModel(id: "discman-noir",       name: "Noir",      subtitle: "Stealth black",       archetype: .discman,     material: .noir),
        CDModel(id: "discman-cobalt",     name: "Cobalt",    subtitle: "Deep blue",           archetype: .discman,     material: .cobalt),
        CDModel(id: "discman-ruby",       name: "Ruby",      subtitle: "Glossy red",          archetype: .discman,     material: .ruby),
        CDModel(id: "discman-ivory",      name: "Ivory",     subtitle: "Warm cream",          archetype: .discman,     material: .ivory),
        CDModel(id: "discman-blush",      name: "Blush",     subtitle: "Soft pink",           archetype: .discman,     material: .blush),
        CDModel(id: "discman-sunflower",  name: "Sunflower", subtitle: "Warm yellow",         archetype: .discman,     material: .sunflower),
        CDModel(id: "translucent-bondi",  name: "Bondi",     subtitle: "Y2K clear blue",      archetype: .translucent, material: .bondi),
        CDModel(id: "translucent-tang",   name: "Tangerine", subtitle: "Y2K clear orange",    archetype: .translucent, material: .tangerine),
        CDModel(id: "translucent-grape",  name: "Grape",     subtitle: "Y2K clear purple",    archetype: .translucent, material: .grape),
        CDModel(id: "translucent-lime",   name: "Lime",      subtitle: "Y2K clear green",     archetype: .translucent, material: .lime),
        CDModel(id: "translucent-frost",  name: "Frost",     subtitle: "Y2K clear ice",       archetype: .translucent, material: .frost),

        // ===== Hi-Fi deck (component) — 7 colours =====
        CDModel(id: "hifi-aluminum",      name: "Aluminum",  subtitle: "Brushed aluminum",    archetype: .hifi,        material: .aluminum),
        CDModel(id: "hifi-onyx",          name: "Onyx",      subtitle: "Matte black",         archetype: .hifi,        material: .onyx),
        CDModel(id: "hifi-champagne",     name: "Champagne", subtitle: "Warm gold",           archetype: .hifi,        material: .champagne),
        CDModel(id: "hifi-graphite",      name: "Graphite",  subtitle: "Dark gunmetal",       archetype: .hifi,        material: .graphite),
        CDModel(id: "hifi-navy",          name: "Navy",      subtitle: "Deep blue steel",     archetype: .hifi,        material: .navy),
        CDModel(id: "hifi-burgundy",      name: "Burgundy",  subtitle: "Wine red & brass",    archetype: .hifi,        material: .burgundy),
        CDModel(id: "hifi-forest",        name: "Forest",    subtitle: "Deep green & silver", archetype: .hifi,        material: .forest),

        // ===== Boombox (twin-speaker) — 7 colours =====
        CDModel(id: "boombox-charcoal",   name: "Charcoal",  subtitle: "Twin-speaker grey",   archetype: .boombox,     material: .charcoal),
        CDModel(id: "boombox-cherry",     name: "Cherry",    subtitle: "Retro red & chrome",  archetype: .boombox,     material: .cherry),
        CDModel(id: "boombox-cream",      name: "Cream",     subtitle: "Retro beige",         archetype: .boombox,     material: .cream),
        CDModel(id: "boombox-teal",       name: "Teal",      subtitle: "Retro teal",          archetype: .boombox,     material: .teal),
        CDModel(id: "boombox-skyblue",    name: "Sky Blue",  subtitle: "Powder blue",         archetype: .boombox,     material: .skyblue),
        CDModel(id: "boombox-plum",       name: "Plum",      subtitle: "Deep purple",         archetype: .boombox,     material: .plum),
        CDModel(id: "boombox-sunset",     name: "Sunset",    subtitle: "Coral & cream",       archetype: .boombox,     material: .sunset)
    ]
}

// MARK: - CD form (groups colours by device body)

struct CDForm: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let icon: String
    let models: [CDModel]
}

extension CDModel {
    static let forms: [CDForm] = [
        CDForm(id: "discman", name: "Discman", subtitle: "Portable pocket player", icon: "opticaldisc",
               models: all.filter { $0.archetype == .discman || $0.archetype == .translucent }),
        CDForm(id: "hifi", name: "Hi-Fi Deck", subtitle: "Component shelf unit", icon: "hifispeaker",
               models: all.filter { $0.archetype == .hifi }),
        CDForm(id: "boombox", name: "Boombox", subtitle: "Twin-speaker portable", icon: "radio",
               models: all.filter { $0.archetype == .boombox })
    ]
}

extension CDMaterial {
    static let silver = CDMaterial(
        housing: [Color(hex: "262b33"), Color(hex: "171a20"), Color(hex: "0d0f13")],
        ring: [Color(hex: "eef2f8"), Color(hex: "9aa3b0"), Color(hex: "4a5058"), Color(hex: "c8d0da")],
        accent: Color(hex: "5fd8ff"), lidTint: Color(hex: "0a1018"), lidOpacity: 0.28,
        well: [Color(hex: "0a0c10"), Color(hex: "04050a")],
        panel: [Color(hex: "2a2f38"), Color(hex: "171b21")],
        lcdBg: [Color(hex: "0a2a30"), Color(hex: "061a1e")], lcd: Color(hex: "67f0d8"),
        subtitle: Color(hex: "8a94a2"), isLight: false)

    static let noir = CDMaterial(
        housing: [Color(hex: "1a1c20"), Color(hex: "101216"), Color(hex: "070809")],
        ring: [Color(hex: "c8ccd2"), Color(hex: "7a8088"), Color(hex: "3a3f46"), Color(hex: "a6acb4")],
        accent: Color(hex: "47c7e8"), lidTint: Color(hex: "05080c"), lidOpacity: 0.30,
        well: [Color(hex: "08090c"), Color(hex: "030405")],
        panel: [Color(hex: "222630"), Color(hex: "121519")],
        lcdBg: [Color(hex: "07262b"), Color(hex: "04161a")], lcd: Color(hex: "58e6cf"),
        subtitle: Color(hex: "7a828e"), isLight: false)

    static let bondi = CDMaterial(
        housing: [Color(hex: "4fb8d6"), Color(hex: "2e93b4"), Color(hex: "1d6f8c")],
        ring: [Color(hex: "f4fbff"), Color(hex: "b8dded"), Color(hex: "7fb4c8"), Color(hex: "e2f2f8")],
        accent: Color(hex: "ffffff"), lidTint: Color(hex: "bfeaf5"), lidOpacity: 0.30,
        well: [Color(hex: "12586e"), Color(hex: "0a3a4a")],
        panel: [Color(hex: "8fd4e6"), Color(hex: "5fb2cc")],
        lcdBg: [Color(hex: "0c3a44"), Color(hex: "082832")], lcd: Color(hex: "9af0ff"),
        subtitle: Color(hex: "e8fbff"), isLight: false, translucent: true)

    static let tangerine = CDMaterial(
        housing: [Color(hex: "f59a4a"), Color(hex: "e57826"), Color(hex: "c45a18")],
        ring: [Color(hex: "fff6ee"), Color(hex: "f0cbac"), Color(hex: "d49a72"), Color(hex: "f8e0cc")],
        accent: Color(hex: "fff4ea"), lidTint: Color(hex: "ffe0c4"), lidOpacity: 0.30,
        well: [Color(hex: "8a3e12"), Color(hex: "5e2a0c")],
        panel: [Color(hex: "f4b483"), Color(hex: "e08e52")],
        lcdBg: [Color(hex: "5a2810"), Color(hex: "3e1c0a")], lcd: Color(hex: "ffd9a8"),
        subtitle: Color(hex: "fff0e2"), isLight: false, translucent: true)

    static let aluminum = CDMaterial(
        housing: [Color(hex: "e8ebf0"), Color(hex: "d2d7df"), Color(hex: "b6bdc8")],
        ring: [Color(hex: "ffffff"), Color(hex: "c8d0dc"), Color(hex: "9aa4b4"), Color(hex: "e6ebf2")],
        accent: Color(hex: "3f9ad8"), lidTint: Color(hex: "dfe7f2"), lidOpacity: 0.22,
        well: [Color(hex: "aeb6c2"), Color(hex: "868e9c")],
        panel: [Color(hex: "f4f6fa"), Color(hex: "dce2ec")],
        lcdBg: [Color(hex: "9fc0c4"), Color(hex: "84a8ac")], lcd: Color(hex: "10302e"),
        subtitle: Color(hex: "6a7280"), isLight: true)

    static let onyx = CDMaterial(
        housing: [Color(hex: "26282c"), Color(hex: "17191c"), Color(hex: "0c0d0f")],
        ring: [Color(hex: "d8dce2"), Color(hex: "8c929a"), Color(hex: "42474e"), Color(hex: "b4bac2")],
        accent: Color(hex: "8affc8"), lidTint: Color(hex: "07080a"), lidOpacity: 0.28,
        well: [Color(hex: "0a0b0d"), Color(hex: "030405")],
        panel: [Color(hex: "2c2f34"), Color(hex: "16181b")],
        lcdBg: [Color(hex: "06241c"), Color(hex: "041510")], lcd: Color(hex: "7dffc4"),
        subtitle: Color(hex: "868d96"), isLight: false)

    static let cobalt = CDMaterial(
        housing: [Color(hex: "23406e"), Color(hex: "162a4e"), Color(hex: "0c1830")],
        ring: [Color(hex: "eaf2ff"), Color(hex: "a8c0e2"), Color(hex: "5a76a0"), Color(hex: "d2e0f4")],
        accent: Color(hex: "7fc4ff"), lidTint: Color(hex: "081226"), lidOpacity: 0.28,
        well: [Color(hex: "0e1d38"), Color(hex: "06101f")],
        panel: [Color(hex: "2c4576"), Color(hex: "182c52")],
        lcdBg: [Color(hex: "0a2244"), Color(hex: "06152c")], lcd: Color(hex: "a8d4ff"),
        subtitle: Color(hex: "9ab0d0"), isLight: false)

    static let cherry = CDMaterial(
        housing: [Color(hex: "8e2230"), Color(hex: "6c1622"), Color(hex: "4a0e16")],
        ring: [Color(hex: "f0f2f6"), Color(hex: "b0b6c0"), Color(hex: "5a606a"), Color(hex: "d6dce4")],
        accent: Color(hex: "ffcaa0"), lidTint: Color(hex: "1a0608"), lidOpacity: 0.30,
        well: [Color(hex: "2a0a0e"), Color(hex: "160508")],
        panel: [Color(hex: "7a1c28"), Color(hex: "4e1018")],
        lcdBg: [Color(hex: "2a0c08"), Color(hex: "180604")], lcd: Color(hex: "ffb27a"),
        subtitle: Color(hex: "d8a0a6"), isLight: false)

    static let charcoal = CDMaterial(
        housing: [Color(hex: "2e3138"), Color(hex: "1d2026"), Color(hex: "121419")],
        ring: [Color(hex: "e4e8ee"), Color(hex: "9aa2ac"), Color(hex: "474d55"), Color(hex: "c2c9d2")],
        accent: Color(hex: "ff7a4a"), lidTint: Color(hex: "0a0c10"), lidOpacity: 0.30,
        well: [Color(hex: "0c0e12"), Color(hex: "050608")],
        panel: [Color(hex: "33373f"), Color(hex: "1c1f25")],
        lcdBg: [Color(hex: "2a1408"), Color(hex: "1a0c04")], lcd: Color(hex: "ffb066"),
        subtitle: Color(hex: "8a929c"), isLight: false)

    // MARK: Added Discman colours (3 solid, 2 translucent)
    static let ruby = CDMaterial(
        housing: [Color(hex: "c0303a"), Color(hex: "94202a"), Color(hex: "6a141c")],
        ring: [Color(hex: "f4f0f0"), Color(hex: "c0b6b8"), Color(hex: "6a5e60"), Color(hex: "e0d6d8")],
        accent: Color(hex: "ffd0c0"), lidTint: Color(hex: "2a0808"), lidOpacity: 0.28,
        well: [Color(hex: "2a0a0c"), Color(hex: "160506")],
        panel: [Color(hex: "a83038"), Color(hex: "7a1c24")],
        lcdBg: [Color(hex: "2a0c0a"), Color(hex: "180604")], lcd: Color(hex: "ffb0a0"),
        subtitle: Color(hex: "e0b0b0"), isLight: false)

    static let ivory = CDMaterial(
        housing: [Color(hex: "f4f1ea"), Color(hex: "e6e1d6"), Color(hex: "d4cdbe")],
        ring: [Color(hex: "ffffff"), Color(hex: "d8d2c6"), Color(hex: "a89e8e"), Color(hex: "ece6da")],
        accent: Color(hex: "d8954f"), lidTint: Color(hex: "efe8da"), lidOpacity: 0.22,
        well: [Color(hex: "c0b8a8"), Color(hex: "9a9080")],
        panel: [Color(hex: "faf7f0"), Color(hex: "e8e2d6")],
        lcdBg: [Color(hex: "b8c4b0"), Color(hex: "9aa894")], lcd: Color(hex: "2a3420"),
        subtitle: Color(hex: "8a8070"), isLight: true)

    static let blush = CDMaterial(
        housing: [Color(hex: "f6dde4"), Color(hex: "f0c9d6"), Color(hex: "e6b3c6")],
        ring: [Color(hex: "ffffff"), Color(hex: "e8cdd6"), Color(hex: "c89aa8"), Color(hex: "f2dde4")],
        accent: Color(hex: "d86b8e"), lidTint: Color(hex: "f3d2dd"), lidOpacity: 0.26,
        well: [Color(hex: "caa0ae"), Color(hex: "a87e8c")],
        panel: [Color(hex: "fae3ea"), Color(hex: "f0cdda")],
        lcdBg: [Color(hex: "3a2230"), Color(hex: "281622")], lcd: Color(hex: "ffc0d4"),
        subtitle: Color(hex: "a87888"), isLight: true)

    static let grape = CDMaterial(
        housing: [Color(hex: "9a6fd0"), Color(hex: "7a4eb4"), Color(hex: "5a3494")],
        ring: [Color(hex: "f6f0ff"), Color(hex: "d6c2ee"), Color(hex: "a888c8"), Color(hex: "e8dcf6")],
        accent: Color(hex: "ffffff"), lidTint: Color(hex: "d8c4f0"), lidOpacity: 0.30,
        well: [Color(hex: "3e2068"), Color(hex: "2a1248")],
        panel: [Color(hex: "b491e0"), Color(hex: "8c63c8")],
        lcdBg: [Color(hex: "2c1450"), Color(hex: "1c0c38")], lcd: Color(hex: "e0c8ff"),
        subtitle: Color(hex: "f0e6ff"), isLight: false, translucent: true)

    static let lime = CDMaterial(
        housing: [Color(hex: "8cd05a"), Color(hex: "6cb43c"), Color(hex: "4e9426")],
        ring: [Color(hex: "f4ffe8"), Color(hex: "cfeeb6"), Color(hex: "a0c888"), Color(hex: "e6f6dc")],
        accent: Color(hex: "ffffff"), lidTint: Color(hex: "d4f0bc"), lidOpacity: 0.30,
        well: [Color(hex: "2e5818"), Color(hex: "1c3a0c")],
        panel: [Color(hex: "a4e07e"), Color(hex: "7cc452")],
        lcdBg: [Color(hex: "143a14"), Color(hex: "0c280c")], lcd: Color(hex: "d0ffb0"),
        subtitle: Color(hex: "eaffe0"), isLight: false, translucent: true)

    // MARK: Added Hi-Fi colours
    static let champagne = CDMaterial(
        housing: [Color(hex: "e8d6a8"), Color(hex: "d4be88"), Color(hex: "b89e64")],
        ring: [Color(hex: "fff8e8"), Color(hex: "e0cfa0"), Color(hex: "b0996a"), Color(hex: "f0e4c4")],
        accent: Color(hex: "a8762a"), lidTint: Color(hex: "efe2c0"), lidOpacity: 0.24,
        well: [Color(hex: "b0a078"), Color(hex: "8a7a54")],
        panel: [Color(hex: "f2e6c4"), Color(hex: "ddcda0")],
        lcdBg: [Color(hex: "b8b890"), Color(hex: "9a9a70")], lcd: Color(hex: "3a3414"),
        subtitle: Color(hex: "8a7a50"), isLight: true)

    static let graphite = CDMaterial(
        housing: [Color(hex: "3a3e44"), Color(hex: "282c31"), Color(hex: "16191d")],
        ring: [Color(hex: "d4d8de"), Color(hex: "8e949c"), Color(hex: "464b52"), Color(hex: "b6bcc4")],
        accent: Color(hex: "7fb0d8"), lidTint: Color(hex: "0a0c10"), lidOpacity: 0.28,
        well: [Color(hex: "0c0e12"), Color(hex: "050608")],
        panel: [Color(hex: "33373e"), Color(hex: "1d2025")],
        lcdBg: [Color(hex: "10242c"), Color(hex: "0a161c")], lcd: Color(hex: "9fd4e8"),
        subtitle: Color(hex: "868d96"), isLight: false)

    static let navy = CDMaterial(
        housing: [Color(hex: "1f3358"), Color(hex: "152544"), Color(hex: "0c1830")],
        ring: [Color(hex: "e6eeff"), Color(hex: "aac2e6"), Color(hex: "5e7aa4"), Color(hex: "cdddf4")],
        accent: Color(hex: "7fc0ff"), lidTint: Color(hex: "08122a"), lidOpacity: 0.28,
        well: [Color(hex: "0c1a36"), Color(hex: "06101f")],
        panel: [Color(hex: "28406e"), Color(hex: "17284c")],
        lcdBg: [Color(hex: "0a2040"), Color(hex: "06142c")], lcd: Color(hex: "a8d0ff"),
        subtitle: Color(hex: "9ab0d0"), isLight: false)

    // MARK: Added Boombox colours
    static let cream = CDMaterial(
        housing: [Color(hex: "e8dcc0"), Color(hex: "d8c8a4"), Color(hex: "c2ae84")],
        ring: [Color(hex: "fff8ea"), Color(hex: "ddcaa0"), Color(hex: "ab9870"), Color(hex: "efe2c6")],
        accent: Color(hex: "d8743a"), lidTint: Color(hex: "efe6cc"), lidOpacity: 0.24,
        well: [Color(hex: "b0a280"), Color(hex: "8a7c5a")],
        panel: [Color(hex: "f2e8ce"), Color(hex: "e0d2b0")],
        lcdBg: [Color(hex: "2a1808"), Color(hex: "1a0e04")], lcd: Color(hex: "ffb066"),
        subtitle: Color(hex: "8a7a58"), isLight: true)

    static let teal = CDMaterial(
        housing: [Color(hex: "2f9a92"), Color(hex: "1f7a72"), Color(hex: "124e48")],
        ring: [Color(hex: "ecfffb"), Color(hex: "b8e6de"), Color(hex: "7fb4ac"), Color(hex: "dcf4ee")],
        accent: Color(hex: "ffd76a"), lidTint: Color(hex: "0a2a28"), lidOpacity: 0.28,
        well: [Color(hex: "0e3a36"), Color(hex: "082624")],
        panel: [Color(hex: "2f8a82"), Color(hex: "1d6660")],
        lcdBg: [Color(hex: "0a2e2a"), Color(hex: "06201c")], lcd: Color(hex: "7af0d8"),
        subtitle: Color(hex: "bfeae2"), isLight: false)

    static let skyblue = CDMaterial(
        housing: [Color(hex: "6fb8d8"), Color(hex: "4e96b8"), Color(hex: "356f8c")],
        ring: [Color(hex: "f0fbff"), Color(hex: "c2e2ee"), Color(hex: "8fb4c4"), Color(hex: "def2f8")],
        accent: Color(hex: "ff9a4a"), lidTint: Color(hex: "0c2a36"), lidOpacity: 0.26,
        well: [Color(hex: "123e4e"), Color(hex: "0a2832")],
        panel: [Color(hex: "6cb0cc"), Color(hex: "4a8aa8")],
        lcdBg: [Color(hex: "0a2c38"), Color(hex: "061c26")], lcd: Color(hex: "a8e8ff"),
        subtitle: Color(hex: "cdeaf2"), isLight: false)

    // MARK: Second wave
    static let sunflower = CDMaterial(
        housing: [Color(hex: "f2c93e"), Color(hex: "e0ac1e"), Color(hex: "b88410")],
        ring: [Color(hex: "fffbe8"), Color(hex: "ecd490"), Color(hex: "b89a50"), Color(hex: "f6e8b8")],
        accent: Color(hex: "3a2c08"), lidTint: Color(hex: "f6e0a0"), lidOpacity: 0.24,
        well: [Color(hex: "8a660c"), Color(hex: "5e4408")],
        panel: [Color(hex: "f4d668"), Color(hex: "e0b430")],
        lcdBg: [Color(hex: "3e2e06"), Color(hex: "2a1e04")], lcd: Color(hex: "ffe08a"),
        subtitle: Color(hex: "6a5210"), isLight: true)

    static let frost = CDMaterial(
        housing: [Color(hex: "e4ecf2"), Color(hex: "cddae4"), Color(hex: "aebfcc")],
        ring: [Color(hex: "ffffff"), Color(hex: "dde8f0"), Color(hex: "a4b6c4"), Color(hex: "eef4f8")],
        accent: Color(hex: "3a8ac8"), lidTint: Color(hex: "f0f6fa"), lidOpacity: 0.34,
        well: [Color(hex: "8ea0ae"), Color(hex: "6a7e8c")],
        panel: [Color(hex: "eef4f8"), Color(hex: "d2dfe8")],
        lcdBg: [Color(hex: "1e3040"), Color(hex: "142230")], lcd: Color(hex: "a8dcff"),
        subtitle: Color(hex: "6a7e8e"), isLight: true, translucent: true)

    static let burgundy = CDMaterial(
        housing: [Color(hex: "5a1a28"), Color(hex: "42101c"), Color(hex: "2c0a12")],
        ring: [Color(hex: "f6e8c8"), Color(hex: "d8b878"), Color(hex: "9a7a3e"), Color(hex: "ecd8a8")],
        accent: Color(hex: "f0c060"), lidTint: Color(hex: "1c060c"), lidOpacity: 0.30,
        well: [Color(hex: "220810"), Color(hex: "140408")],
        panel: [Color(hex: "521826"), Color(hex: "360e18")],
        lcdBg: [Color(hex: "2a1206"), Color(hex: "1a0a04")], lcd: Color(hex: "ffcc7a"),
        subtitle: Color(hex: "cca0a8"), isLight: false)

    static let forest = CDMaterial(
        housing: [Color(hex: "1c3a2c"), Color(hex: "122a1e"), Color(hex: "0a1c14")],
        ring: [Color(hex: "eaf2ee"), Color(hex: "aec4b8"), Color(hex: "5a7468"), Color(hex: "d2e0d8")],
        accent: Color(hex: "6ae0a8"), lidTint: Color(hex: "061410"), lidOpacity: 0.28,
        well: [Color(hex: "0a1e16"), Color(hex: "05100c")],
        panel: [Color(hex: "1e4232"), Color(hex: "112a1e")],
        lcdBg: [Color(hex: "06241a"), Color(hex: "041610")], lcd: Color(hex: "7affc0"),
        subtitle: Color(hex: "8aa89a"), isLight: false)

    static let plum = CDMaterial(
        housing: [Color(hex: "3e2450"), Color(hex: "2c163c"), Color(hex: "1c0e28")],
        ring: [Color(hex: "f2eaf8"), Color(hex: "c8b0dc"), Color(hex: "7a5e94"), Color(hex: "e0d0ec")],
        accent: Color(hex: "ff9ae0"), lidTint: Color(hex: "160a20"), lidOpacity: 0.30,
        well: [Color(hex: "1e1028"), Color(hex: "120818")],
        panel: [Color(hex: "42285a"), Color(hex: "2a163a")],
        lcdBg: [Color(hex: "24102e"), Color(hex: "160a1e")], lcd: Color(hex: "f0b0ff"),
        subtitle: Color(hex: "b096c8"), isLight: false)

    static let sunset = CDMaterial(
        housing: [Color(hex: "e8703e"), Color(hex: "cc5426"), Color(hex: "a43c16")],
        ring: [Color(hex: "fff4e8"), Color(hex: "f2cca4"), Color(hex: "c89468"), Color(hex: "f8e2c8")],
        accent: Color(hex: "ffe8b0"), lidTint: Color(hex: "2a1006"), lidOpacity: 0.28,
        well: [Color(hex: "6e2c0e"), Color(hex: "4a1e08")],
        panel: [Color(hex: "e0824e"), Color(hex: "c05e2c")],
        lcdBg: [Color(hex: "3a1608"), Color(hex: "260e04")], lcd: Color(hex: "ffcf9a"),
        subtitle: Color(hex: "ffe2c8"), isLight: false)
}

// MARK: - Phase machine

enum CDPhase: Equatable { case idle, decelerate, liftOff, eject, gap, insert, seat, spinUp }

final class CDTransitionAnimator: ObservableObject {
    @Published private(set) var phase: CDPhase = .idle
    var onReveal: (() -> Void)?
    var onComplete: (() -> Void)?
    private var token: UUID?
    private var scheduled: [DispatchWorkItem] = []
    var isAnimating: Bool { phase != .idle }

    func start() { cancel(); let id = UUID(); token = id; advance(.decelerate, id: id) }
    func cancel() { scheduled.forEach { $0.cancel() }; scheduled.removeAll(); token = nil; phase = .idle }

    private func advance(_ next: CDPhase, id: UUID) {
        guard token == id else { return }
        if next == .gap { onReveal?() }
        withAnimation(animation(for: next)) { phase = next }
        if next == .idle { onComplete?(); token = nil; return }
        let following = phaseAfter(next)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.token == id else { return }
            self.advance(following, id: id)
        }
        scheduled.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration(for: next), execute: work)
    }
    private func phaseAfter(_ p: CDPhase) -> CDPhase {
        switch p {
        case .idle: return .idle
        case .decelerate: return .liftOff
        case .liftOff: return .eject
        case .eject: return .gap
        case .gap: return .insert
        case .insert: return .seat
        case .seat: return .spinUp
        case .spinUp: return .idle
        }
    }
    private func duration(for p: CDPhase) -> TimeInterval {
        switch p {
        case .idle: return 0
        case .decelerate: return 0.70
        case .liftOff: return 0.46
        case .eject: return 0.55
        case .gap: return 0.18
        case .insert: return 0.58
        case .seat: return 0.52
        case .spinUp: return 0.80
        }
    }
    private func animation(for p: CDPhase) -> Animation {
        switch p {
        case .idle: return .linear(duration: 0.01)
        case .decelerate: return .easeOut(duration: 0.70)
        case .liftOff: return .spring(response: 0.46, dampingFraction: 0.8)
        case .eject: return .timingCurve(0.4, 0.0, 0.5, 1.0, duration: 0.55)
        case .gap: return .linear(duration: 0.18)
        case .insert: return .timingCurve(0.35, 0.5, 0.3, 1.0, duration: 0.58)
        case .seat: return .spring(response: 0.5, dampingFraction: 0.6)
        case .spinUp: return .easeIn(duration: 0.80)
        }
    }
}

// MARK: - CD Widget (engine + archetype layouts)

struct CDWidgetView: View {
    let model: CDModel
    var isPreview: Bool = false
    var previewSpinning: Bool = false   // gallery hover: spin the disc without the detector

    @StateObject private var detector = MusicDetector()
    @StateObject private var artFetcher = AlbumArtFetcher()
    @StateObject private var transition = CDTransitionAnimator()

    @State private var displayedArt: NSImage? = nil
    @State private var incomingArt: NSImage? = nil
    @State private var lastTrackKey: String = ""
    @State private var optimisticPlaying: Bool? = nil

    @ObservedObject private var settings = WidgetSettings.shared

    private let maxSpinSpeed: Double = 2200   // real CDs spin fast — art blurs

    private var mat: CDMaterial { model.material }
    private var np: NowPlayingInfo { detector.nowPlaying }
    private var playing: Bool { optimisticPlaying ?? np.isPlaying }
    private var trackKey: String { "\(np.trackName)|\(np.artistName)|\(np.albumName)" }

    private var targetSpeed: Double {
        if isPreview { return previewSpinning ? 760 : 0 }
        switch transition.phase {
        case .spinUp, .idle: return playing ? maxSpinSpeed : 0
        default: return 0
        }
    }

    private var cardSize: CGSize {
        CGSize(width: model.archetype.baseSize.width - cdMargin * 2,
               height: model.archetype.baseSize.height - cdMargin * 2)
    }

    var body: some View {
        ZStack {
            archetypeBody.frame(width: cardSize.width, height: cardSize.height)
                .overlay(alignment: settings.notesSide == .left ? .topLeading : .topTrailing) {
                    if settings.notesEnabled && !isPreview {
                        MusicalNotesView(side: settings.notesSide, active: playing)
                            .padding(settings.notesSide == .left ? .leading : .trailing, 16)
                            .padding(.top, -8)
                    }
                }
        }
        .frame(width: model.archetype.baseSize.width, height: model.archetype.baseSize.height)
        .onAppear { if !isPreview { setup() } }
        .onChange(of: trackKey) { _, k in if !isPreview { handleTrackChange(k) } }
        .onChange(of: np.albumArtURL) { _, u in if !isPreview { fetchArt(u) } }
        .onChange(of: np.isPlaying) { _, _ in optimisticPlaying = nil }
    }

    @ViewBuilder private var archetypeBody: some View {
        switch model.archetype {
        case .discman, .translucent: portraitLayout
        case .hifi:    hifiLayout
        case .boombox: boomboxLayout
        }
    }

    // Shared deck
    private var deck: some View {
        CDDeck(material: mat, diameter: model.archetype.deckDiameter,
               phase: transition.phase, targetSpeed: targetSpeed,
               displayedArt: displayedArt, incomingArt: incomingArt,
               onTap: { togglePlayback() }, isStatic: isPreview && !previewSpinning)
    }

    private var lcd: some View {
        CDLcd(track: np.trackName, artist: np.artistName, playing: playing, material: mat)
    }

    private var isPortrait: Bool {
        model.archetype == .discman || model.archetype == .translucent
    }

    private var controls: some View {
        CDControls(playing: playing, material: mat, analog: isPortrait,
                   onPrev: { detector.previousTrack() },
                   onPlay: { togglePlayback() },
                   onNext: { detector.nextTrack() })
    }

    private func brandBar(wide: Bool = false) -> some View {
        HStack(alignment: .center) {
            // Our own stylized disc-audio mark (logo-inspired, legally distinct)
            HStack(spacing: 6) {
                ZStack {
                    Circle().strokeBorder(mat.subtitle.opacity(0.85), lineWidth: 1.6).frame(width: 15, height: 15)
                    Circle().strokeBorder(mat.subtitle.opacity(0.55), lineWidth: 1).frame(width: 8, height: 8)
                    Circle().fill(mat.subtitle.opacity(0.85)).frame(width: 2.5, height: 2.5)
                }
                VStack(alignment: .leading, spacing: -1) {
                    Text("DIGITAL DISC")
                        .font(.system(size: 9, weight: .black, design: .rounded)).tracking(0.2)
                    Text("STEREO · HI-FI AUDIO")
                        .font(.system(size: 5.5, weight: .bold)).tracking(1.0)
                }
                .foregroundStyle(mat.subtitle.opacity(0.9))
            }
            Spacer()
            HStack(spacing: 5) {
                Text("PWR").font(.system(size: 6.5, weight: .bold)).tracking(1)
                    .foregroundStyle(mat.subtitle.opacity(0.7))
                Circle().fill(playing ? mat.accent : mat.accent.opacity(0.3)).frame(width: 6, height: 6)
                    .shadow(color: playing ? mat.accent.opacity(0.9) : .clear, radius: 4)
            }
        }
    }

    // MARK: Portrait (Discman + Translucent)

    private var portraitLayout: some View {
        ZStack {
            housingShape(cornerRadius: 30)

            // translucent internals hint
            if mat.translucent {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.12))
                    .frame(width: 120, height: 30)
                    .blur(radius: 4)
                    .offset(y: cardSize.height * 0.34)
            }

            VStack(spacing: 0) {
                brandBar().padding(.top, 20).padding(.horizontal, 30)
                Spacer().frame(height: 16)
                deck
                HStack { lcd; Spacer(minLength: 0) }.padding(.top, 16).padding(.horizontal, 26)
                Spacer(minLength: 22)
                controls.padding(.bottom, 20).padding(.horizontal, 32)
            }
            .frame(width: cardSize.width, height: cardSize.height)
        }
    }

    // MARK: Hi-Fi (landscape)

    private var hifiLayout: some View {
        ZStack {
            housingShape(cornerRadius: 18)
            brushedLines.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 18) {
                deck
                VStack(alignment: .leading, spacing: 16) {
                    brandBar()
                    lcd
                    controls
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 26)
            .frame(width: cardSize.width, height: cardSize.height)
        }
    }

    // MARK: Boombox (landscape, twin speakers)

    private var boomboxLayout: some View {
        let topH: CGFloat = 46
        let innerH = cardSize.height - topH
        return VStack(spacing: 0) {
            // Handle + telescoping antenna
            ZStack {
                BoomboxAntenna(colors: mat.ring)
                    .frame(width: 86, height: topH + 12)
                    .offset(x: cardSize.width * 0.30, y: -4)
                BoomboxHandle(colors: mat.ring)
                    .frame(width: 180, height: topH)
            }
            .frame(width: cardSize.width, height: topH)

            ZStack {
                boomboxBody

                // Big bass woofers flanking, vertically centred (mid-point)
                HStack {
                    BoomboxWoofer(material: mat, active: playing && !isPreview, diameter: 152)
                    Spacer(minLength: 0)
                    BoomboxWoofer(material: mat, active: playing && !isPreview, diameter: 152)
                }
                .padding(.horizontal, 22)
                .frame(width: cardSize.width, height: innerH)

                // Centre column: control deck, disc, retro display
                VStack(spacing: 7) {
                    topControls
                    deck
                    boomboxLcd
                    Spacer(minLength: 0)
                }
                .padding(.top, 18)
                .frame(width: cardSize.width, height: innerH)
            }
            .frame(width: cardSize.width, height: innerH)
        }
        .frame(width: cardSize.width, height: cardSize.height)
    }

    // Control deck: knob · transport keys · knob
    private var topControls: some View {
        HStack(spacing: 12) {
            boomboxKnob
            boomboxButtons
            boomboxKnob
        }
    }

    private var boomboxKnob: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: "5a5f68"), Color(hex: "23262c"), Color(hex: "111316")],
                                     center: UnitPoint(x: 0.4, y: 0.34), startRadius: 0, endRadius: 13))
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 0.6))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6).padding(0.6))
                .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
            // pointer notch
            Capsule().fill(mat.accent.opacity(0.9))
                .frame(width: 2, height: 7)
                .offset(y: -6)
                .shadow(color: mat.accent.opacity(0.6), radius: 2)
        }
    }

    // 3D glossy plastic body with bevels, recessed baffle, feet and texture
    private var boomboxBody: some View {
        ZStack {
            // outer shell
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [mat.housing[0].adjustBrightness(0.06),
                                              mat.housing[1],
                                              mat.housing[2],
                                              mat.housing[1].adjustBrightness(0.03)],
                                     startPoint: .top, endPoint: .bottom))
            // glossy top sweep
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.16), .clear],
                                     startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.42)))
            // brushed texture
            BoomboxTexture().clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            // edge bevel (light top, dark bottom)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.0), Color.black.opacity(0.3)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1.4)
            // recessed front baffle
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [mat.housing[2].adjustBrightness(-0.02), mat.housing[2].adjustBrightness(0.02)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.45), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [Color.black.opacity(0.3), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.12)))
                )
                .padding(11)
            // rubber feet peeking at the bottom
            HStack {
                feet; Spacer(); feet
            }
            .padding(.horizontal, 46)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .offset(y: 7)
        }
    }

    private var feet: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(LinearGradient(colors: [Color(hex: "1a1c20"), Color(hex: "070809")], startPoint: .top, endPoint: .bottom))
            .frame(width: 46, height: 14)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5))
    }

    // Retro pixelated green LED display
    private var boomboxLcd: some View {
        let led = Color(hex: "74ff6b")
        return VStack(spacing: 1) {
            Text(np.trackName.isEmpty ? "NO DISC" : np.trackName.uppercased())
                .font(.system(size: 8.5, weight: .bold, design: .monospaced)).tracking(1.5)
                .foregroundStyle(led)
                .shadow(color: led.opacity(0.7), radius: 2)
                .lineLimit(1).truncationMode(.tail)
            Text(np.artistName.isEmpty ? "- - -" : np.artistName.uppercased())
                .font(.system(size: 6.5, weight: .semibold, design: .monospaced)).tracking(1.5)
                .foregroundStyle(led.opacity(0.55))
                .shadow(color: led.opacity(0.4), radius: 1.5)
                .lineLimit(1).truncationMode(.tail)
        }
        .frame(width: 140)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color(hex: "071006"))
                BoomboxLcdMatrix(color: led)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Color.black.opacity(0.55), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(led.opacity(0.12), lineWidth: 0.5).padding(1))
        )
    }

    private var boomboxButtons: some View {
        HStack(spacing: 7) {
            boomboxKey("backward.fill") { detector.previousTrack() }
            boomboxKey(playing ? "pause.fill" : "play.fill", primary: true) { togglePlayback() }
            boomboxKey("forward.fill") { detector.nextTrack() }
        }
    }

    private func boomboxKey(_ icon: String, primary: Bool = false, _ action: @escaping () -> Void) -> some View {
        let keyColors: [Color] = primary
            ? [mat.accent.adjustBrightness(0.10), mat.accent.adjustBrightness(-0.16)]
            : [Color(hex: "d2d6dd"), Color(hex: "9aa0a8")]
        let icColor: Color = primary ? Color(hex: "201006") : Color(hex: "2a2e34")
        return Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(LinearGradient(colors: keyColors, startPoint: .top, endPoint: .bottom))
                    .frame(width: 24, height: 17)
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5))
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5).padding(0.5))
                    .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                Image(systemName: icon).font(.system(size: 7.5, weight: .black)).foregroundStyle(icColor)
            }
        }
        .buttonStyle(CDButtonStyle())
    }

    // MARK: Housing helpers

    private func housingShape(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(colors: mat.housing, startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(mat.isLight ? 0.9 : 0.2), .clear],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(mat.translucent ? 0.5 : (mat.isLight ? 0.4 : 0.05)), .clear],
                                         startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
            )
    }

    private var brushedLines: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                let path = Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }
                ctx.stroke(path, with: .color(.white.opacity(0.04)), lineWidth: 0.5)
                y += 3
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Logic

    private func togglePlayback() { optimisticPlaying = !playing; detector.togglePlayback() }

    private func setup() {
        detector.start()
        lastTrackKey = trackKey
        fetchArt(np.albumArtURL, commitImmediately: true)
    }

    private func handleTrackChange(_ newKey: String) {
        guard newKey != lastTrackKey else { return }
        lastTrackKey = newKey
        if let url = np.albumArtURL {
            artFetcher.fetchArt(from: url, trackKey: newKey, forceRefresh: true) { image in self.incomingArt = image }
        } else { incomingArt = nil }
        if displayedArt != nil || !np.trackName.isEmpty {
            transition.onReveal = { self.displayedArt = self.incomingArt }
            transition.onComplete = { self.displayedArt = self.incomingArt ?? self.displayedArt }
            transition.start()
        } else { displayedArt = incomingArt }
    }

    private func fetchArt(_ url: String?, commitImmediately: Bool = false) {
        guard let url, !url.isEmpty else { return }
        artFetcher.fetchArt(from: url, trackKey: trackKey, forceRefresh: false) { image in
            if commitImmediately || !transition.isAnimating { self.displayedArt = image }
            else { self.incomingArt = image }
        }
    }
}

// MARK: - Size wrapper (scales the CD widget by the shared size setting)

struct CDSizedRoot: View {
    let model: CDModel
    @ObservedObject private var sizeM = WidgetSizeManager.shared

    var body: some View {
        let s = sizeM.scale
        let base = model.archetype.baseSize
        CDWidgetView(model: model)
            .scaleEffect(s)
            .frame(width: base.width * s, height: base.height * s)
    }
}

// MARK: - Shared deck (the disc mechanism)

struct CDDeck: View {
    let material: CDMaterial
    let diameter: CGFloat
    let phase: CDPhase
    let targetSpeed: Double
    let displayedArt: NSImage?
    let incomingArt: NSImage?
    var onTap: () -> Void = {}
    var isStatic: Bool = false   // gallery previews: no spin engine / TimelineView

    @State private var angle: Double = 0
    @State private var spinSpeed: Double = 0
    @State private var lastTick: Date? = nil

    private var dock: CGFloat { diameter + 32 }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: material.well, center: .center, startRadius: 0, endRadius: dock / 2))
                .frame(width: dock, height: dock)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.55), lineWidth: 2).blur(radius: 0.5))
                .shadow(color: .black.opacity(0.6), radius: 6, y: 2)

            clampHub

            Group {
                if isStatic {
                    discLayer.frame(width: dock, height: dock).clipShape(Circle())
                } else {
                    discLayer
                        .frame(width: dock, height: dock)
                        .clipShape(Circle())
                        .modifier(SpinIntegrator(angle: $angle, spinSpeed: $spinSpeed, lastTick: $lastTick, target: targetSpeed))
                }
            }

            Circle()
                .strokeBorder(AngularGradient(colors: material.ring + [material.ring.first ?? .gray], center: .center), lineWidth: diameter * 0.027)
                .frame(width: dock + 4, height: dock + 4)
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)

            flipLid
            hinge.offset(y: -dock / 2 - 3)
        }
        .frame(width: dock + 16, height: dock + 20)
        .contentShape(Circle())
        .onTapGesture { onTap() }
    }

    private var discLayer: some View {
        let lift = dock * 0.66
        let isOutgoing = [.decelerate, .liftOff, .eject].contains(phase)
        let art = isOutgoing ? displayedArt : (incomingArt ?? displayedArt)
        let offsetY: CGFloat = {
            switch phase {
            case .liftOff: return -14
            case .eject, .gap: return -lift
            default: return 0
            }
        }()
        let scale: CGFloat = {
            switch phase {
            case .liftOff, .eject, .gap, .insert: return 1.10
            default: return 1.0
            }
        }()
        let lifted = [.liftOff, .eject, .gap, .insert].contains(phase)
        return CDDiscView(albumArt: art, accent: material.accent, diameter: diameter)
            .rotationEffect(.degrees(angle))
            .scaleEffect(scale)
            .offset(y: offsetY)
            .shadow(color: .black.opacity(lifted ? 0.5 : 0.0), radius: lifted ? 16 : 0, y: lifted ? 14 : 0)
    }

    private var clampHub: some View {
        let hub = diameter * 0.13
        return ZStack {
            Circle().fill(AngularGradient(colors: [Color(hex: "f0f4fa"), Color(hex: "8a93a0"),
                                                   Color(hex: "e4e9f0"), Color(hex: "7e8794"),
                                                   Color(hex: "f0f4fa")], center: .center))
                .frame(width: hub, height: hub)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
            Circle().fill(RadialGradient(colors: [Color(hex: "fdfefe"), Color(hex: "9aa2ad")],
                                         center: UnitPoint(x: 0.4, y: 0.32), startRadius: 0, endRadius: hub * 0.36))
                .frame(width: hub * 0.62, height: hub * 0.62)
                .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
        }
    }

    private var flipLid: some View {
        let lidSize = dock + 10
        return ZStack {
            Circle().fill(material.lidTint.opacity(material.lidOpacity))
            Ellipse().fill(LinearGradient(colors: [Color.white.opacity(0.55), .clear], startPoint: .topLeading, endPoint: .center))
                .frame(width: lidSize * 0.82, height: lidSize * 0.46)
                .offset(x: -lidSize * 0.1, y: -lidSize * 0.18).blur(radius: 7)
            Ellipse().fill(LinearGradient(colors: [.clear, Color.white.opacity(0.18)], startPoint: .center, endPoint: .bottomTrailing))
                .frame(width: lidSize * 0.6, height: lidSize * 0.4)
                .offset(x: lidSize * 0.15, y: lidSize * 0.18).blur(radius: 8)
            Circle().strokeBorder(AngularGradient(colors: material.ring + [material.ring.first ?? .gray], center: .center), lineWidth: diameter * 0.032)
            Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 1).padding(diameter * 0.04)
        }
        .frame(width: lidSize, height: lidSize)
        .clipShape(Circle())
        .rotation3DEffect(.degrees(lidOpenAngle), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.65)
        .shadow(color: .black.opacity(phase != .idle ? 0.4 : 0.12), radius: 10, y: 8)
        .allowsHitTesting(false)
    }

    private var lidOpenAngle: Double {
        switch phase {
        case .liftOff, .eject, .gap, .insert: return -108
        default: return 0
        }
    }

    private var hinge: some View {
        HStack(spacing: diameter * 0.12) {
            ForEach(0..<2, id: \.self) { _ in
                Capsule().fill(LinearGradient(colors: material.ring, startPoint: .top, endPoint: .bottom))
                    .frame(width: diameter * 0.082, height: diameter * 0.045)
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.3), lineWidth: 0.5))
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }
}

// MARK: - Shared LCD

struct CDLcd: View {
    let track: String
    let artist: String
    let playing: Bool
    let material: CDMaterial
    var width: CGFloat = 176

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.isEmpty ? "NO DISC" : track.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(0.5)
                .foregroundStyle(material.lcd)
                .shadow(color: material.lcd.opacity(material.isLight ? 0 : 0.6), radius: 3)
                .lineLimit(1).truncationMode(.tail)
            Text(artist.isEmpty ? (playing ? "▶ PLAY" : "❚❚ PAUSE") : artist.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(0.5)
                .foregroundStyle(material.lcd.opacity(0.7))
                .lineLimit(1).truncationMode(.tail)
        }
        .frame(width: width, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: material.lcdBg, startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.black.opacity(0.5), lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(material.lcd.opacity(0.12), lineWidth: 0.5).padding(1))
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        )
    }
}

// MARK: - Shared controls

struct CDControls: View {
    let playing: Bool
    let material: CDMaterial
    var analog: Bool = false
    var onPrev: () -> Void
    var onPlay: () -> Void
    var onNext: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onPrev) { CDPhysicalButton(icon: "backward.fill", material: material, analog: analog) }.buttonStyle(CDButtonStyle())
            Spacer()
            Button(action: onPlay) { CDPhysicalButton(icon: playing ? "pause.fill" : "play.fill", material: material, primary: true, analog: analog) }.buttonStyle(CDButtonStyle())
            Spacer()
            Button(action: onNext) { CDPhysicalButton(icon: "forward.fill", material: material, analog: analog) }.buttonStyle(CDButtonStyle())
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(
            Capsule().fill(LinearGradient(colors: material.panel, startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(Color.white.opacity(material.isLight ? 0.7 : 0.10), lineWidth: 1))
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.35), lineWidth: 1).padding(1))
                .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
        )
    }
}

// MARK: - Retro LED dot-matrix substrate (the "pixels")

struct BoomboxLcdMatrix: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 3
            var y: CGFloat = 1.5
            while y < size.height {
                var x: CGFloat = 1.5
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.1, height: 1.1)),
                             with: .color(color.opacity(0.10)))
                    x += step
                }
                y += step
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Boombox bass woofer (pulses while playing)

struct BoomboxWoofer: View {
    let material: CDMaterial
    let active: Bool
    var diameter: CGFloat = 150

    var body: some View {
        TimelineView(.animation(paused: !active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let pulse = active ? (sin(t * 5.5) * 0.5 + sin(t * 8.9) * 0.3 + sin(t * 13.7) * 0.2) : 0
            let coneScale = 1.0 + 0.05 * pulse
            woofer(coneScale: coneScale)
        }
    }

    private func woofer(coneScale: CGFloat) -> some View {
        ZStack {
            // outer chrome trim ring (raised, catches light)
            Circle()
                .fill(AngularGradient(colors: material.ring + material.ring + [material.ring.first ?? .gray], center: .center))
                .frame(width: diameter, height: diameter)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 4, y: 3)

            // black basket recess
            Circle()
                .fill(RadialGradient(colors: [Color(hex: "3a3e44"), Color(hex: "121417"), Color(hex: "070809")],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: diameter * 0.44))
                .frame(width: diameter * 0.88, height: diameter * 0.88)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1).frame(width: diameter * 0.88, height: diameter * 0.88))

            // mounting bolts around the chrome ring
            ForEach(0..<8, id: \.self) { i in
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: "eef2f8"), Color(hex: "5a606a"), Color(hex: "23262c")],
                                         center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: diameter * 0.02))
                    .frame(width: diameter * 0.038, height: diameter * 0.038)
                    .offset(y: -diameter * 0.46)
                    .rotationEffect(.degrees(Double(i) / 8.0 * 360))
            }

            // rubber surround (glossy torus)
            Circle()
                .fill(RadialGradient(colors: [.clear, Color(hex: "242424"), Color(hex: "3a3a3a"), Color(hex: "141414"), .clear],
                                     center: .center, startRadius: diameter * 0.28, endRadius: diameter * 0.42))
                .frame(width: diameter * 0.82, height: diameter * 0.82)

            // cone with concentric grooves
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: "44484f"), Color(hex: "1c1e22"), Color(hex: "090a0c")],
                                         center: UnitPoint(x: 0.42, y: 0.38), startRadius: 0, endRadius: diameter * 0.3))
                    .frame(width: diameter * 0.6, height: diameter * 0.6)
                ForEach(1..<5, id: \.self) { i in
                    Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.6)
                        .frame(width: diameter * 0.6 * (CGFloat(i) / 5.0), height: diameter * 0.6 * (CGFloat(i) / 5.0))
                    Circle().strokeBorder(Color.white.opacity(0.05), lineWidth: 0.5)
                        .frame(width: diameter * 0.6 * (CGFloat(i) / 5.0) + 1, height: diameter * 0.6 * (CGFloat(i) / 5.0) + 1)
                }
            }
            .scaleEffect(coneScale)

            // domed dust cap with specular highlight
            Circle()
                .fill(RadialGradient(colors: [Color(hex: "6a6e78"), Color(hex: "262a30"), Color(hex: "0a0b0d")],
                                     center: UnitPoint(x: 0.38, y: 0.32), startRadius: 0, endRadius: diameter * 0.12))
                .frame(width: diameter * 0.22, height: diameter * 0.22)
                .overlay(
                    Ellipse().fill(LinearGradient(colors: [Color.white.opacity(0.45), .clear], startPoint: .topLeading, endPoint: .center))
                        .frame(width: diameter * 0.13, height: diameter * 0.08)
                        .offset(x: -diameter * 0.02, y: -diameter * 0.035)
                )
                .overlay(Circle().strokeBorder(material.accent.opacity(0.3), lineWidth: 1))
                .scaleEffect(coneScale)
                .shadow(color: .black.opacity(0.55), radius: 2, y: 1.5)
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Boombox antenna

struct BoomboxAntenna: View {
    let colors: [Color]
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                // collar
                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: 10, height: 7)
                    .position(x: 8, y: h - 4)
                // telescoping rod
                Path { p in
                    p.move(to: CGPoint(x: 8, y: h - 4))
                    p.addLine(to: CGPoint(x: w - 6, y: 6))
                }
                .stroke(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                // tip ball
                Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 8, height: 8)
                    .position(x: w - 6, y: 6)
                    .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
            }
        }
    }
}

// MARK: - Subtle brushed plastic texture

struct BoomboxTexture: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                }
                ctx.stroke(path, with: .color(.white.opacity(0.018)), lineWidth: 0.5)
                y += 3
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Boombox carry handle

struct BoomboxHandle: View {
    let colors: [Color]
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            Path { p in
                p.move(to: CGPoint(x: 8, y: h))
                p.addLine(to: CGPoint(x: 8, y: h * 0.55))
                p.addQuadCurve(to: CGPoint(x: w - 8, y: h * 0.55), control: CGPoint(x: w / 2, y: -h * 0.25))
                p.addLine(to: CGPoint(x: w - 8, y: h))
            }
            .stroke(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Physical button

struct CDPhysicalButton: View {
    let icon: String
    let material: CDMaterial
    var primary: Bool = false
    var analog: Bool = false

    var body: some View {
        if analog { analogButton } else { digitalButton }
    }

    // Glossy domed button (used by the special devices for now)
    private var digitalButton: some View {
        let d: CGFloat = primary ? 42 : 33
        let capColors: [Color] = primary
            ? [material.accent.adjustBrightness(0.18), material.accent, material.accent.adjustBrightness(-0.22)]
            : (material.isLight ? [Color(hex: "ffffff"), Color(hex: "e2e7ef"), Color(hex: "b6bfcc")]
                                : [Color(hex: "4a525d"), Color(hex: "333a43"), Color(hex: "1a1e24")])
        let iconColor: Color = primary ? Color(hex: "07171c") : (material.isLight ? Color(hex: "3a414b") : Color(hex: "eef3f8"))

        return ZStack {
            Circle().fill(Color.black.opacity(0.45)).frame(width: d + 8, height: d + 8).blur(radius: 1.5)
            Circle().fill(LinearGradient(colors: [Color.black.opacity(0.5), Color.white.opacity(material.isLight ? 0.3 : 0.05)], startPoint: .bottom, endPoint: .top))
                .frame(width: d + 5, height: d + 5)
            Circle().fill(LinearGradient(colors: capColors, startPoint: .top, endPoint: .bottom))
                .frame(width: d, height: d)
                .overlay(Ellipse().fill(LinearGradient(colors: [Color.white.opacity(0.7), .clear], startPoint: .top, endPoint: .center))
                    .frame(width: d * 0.7, height: d * 0.45).offset(y: -d * 0.16).blur(radius: 0.5))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 0.6).padding(0.5))
                .shadow(color: .black.opacity(0.5), radius: 2, y: 2)
            Image(systemName: icon).font(.system(size: primary ? 14 : 11, weight: .black))
                .foregroundStyle(iconColor)
                .shadow(color: .white.opacity(primary ? 0.2 : 0.12), radius: 0.5, y: 0.6)
        }
        .frame(width: d + 8, height: d + 8)
    }

    // Analog: matte rounded-rect transport key, beveled edge, engraved icon
    private var analogButton: some View {
        let w: CGFloat = primary ? 42 : 34
        let h: CGFloat = (primary ? 42 : 34) * 0.82
        let r: CGFloat = w * 0.30
        let capColors: [Color] = primary
            ? [material.accent.adjustBrightness(0.06), material.accent.adjustBrightness(-0.16)]
            : (material.isLight ? [Color(hex: "eef1f6"), Color(hex: "c4ccd7")]
                                : [Color(hex: "464d57"), Color(hex: "262b32")])
        let iconColor: Color = primary
            ? Color(hex: "201006")
            : (material.isLight ? Color(hex: "434a54") : Color(hex: "d0d7df"))
        let debossLight: Color = material.isLight ? Color.white.opacity(0.85) : Color.white.opacity(0.14)

        return ZStack {
            // recessed slot
            RoundedRectangle(cornerRadius: r + 2, style: .continuous)
                .fill(Color.black.opacity(0.42))
                .frame(width: w + 6, height: h + 6)
                .blur(radius: 1.2)
            RoundedRectangle(cornerRadius: r + 1, style: .continuous)
                .fill(LinearGradient(colors: [Color.black.opacity(0.55), Color.white.opacity(material.isLight ? 0.45 : 0.06)],
                                     startPoint: .bottom, endPoint: .top))
                .frame(width: w + 3, height: h + 3)

            // matte key cap
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(LinearGradient(colors: capColors, startPoint: .top, endPoint: .bottom))
                .frame(width: w, height: h)
                // top chamfer highlight (beveled edge catching light)
                .overlay(
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [Color.white.opacity(material.isLight ? 0.9 : 0.4), .clear],
                                                     startPoint: .top, endPoint: .center), lineWidth: 1)
                )
                .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(Color.black.opacity(0.32), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: 1.5)

            // engraved (debossed) icon
            Image(systemName: icon)
                .font(.system(size: primary ? 12.5 : 10, weight: .heavy))
                .foregroundStyle(iconColor)
                .shadow(color: debossLight, radius: 0, x: 0, y: 0.8)
        }
        .frame(width: w + 6, height: h + 6)
    }
}

extension Color {
    func adjustBrightness(_ delta: Double) -> Color {
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let r = min(1, max(0, ns.redComponent + delta))
        let g = min(1, max(0, ns.greenComponent + delta))
        let b = min(1, max(0, ns.blueComponent + delta))
        return Color(red: Double(r), green: Double(g), blue: Double(b))
    }
}

private struct CDButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .offset(y: configuration.isPressed ? 1.5 : 0)
            .brightness(configuration.isPressed ? -0.1 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct SpinIntegrator: ViewModifier {
    @Binding var angle: Double
    @Binding var spinSpeed: Double
    @Binding var lastTick: Date?
    let target: Double
    func body(content: Content) -> some View {
        TimelineView(.animation(paused: target == 0 && spinSpeed < 0.5)) { context in
            content.onChange(of: context.date) { _, now in
                let dt = min(0.05, now.timeIntervalSince(lastTick ?? now))
                lastTick = now
                if spinSpeed < target {
                    // Accelerating ramp: gentle off the line, up to full in ~2s (like a real CD).
                    let accel = 150 + spinSpeed * 1.8
                    spinSpeed = min(target, spinSpeed + accel * dt)
                } else if spinSpeed > target {
                    // Spin-down for the swap.
                    spinSpeed = max(target, spinSpeed - (spinSpeed * 2.4 + 160) * dt)
                }
                angle = (angle + spinSpeed * dt).truncatingRemainder(dividingBy: 360)
            }
        }
    }
}

// MARK: - The disc (full-face printed art + hole)

struct CDDiscView: View {
    let albumArt: NSImage?
    let accent: Color
    var diameter: CGFloat = 220

    var body: some View {
        let hole = diameter * 0.10
        ZStack {
            Group {
                if let art = albumArt {
                    Image(nsImage: art).resizable().scaledToFill()
                } else {
                    Circle().fill(AngularGradient(stops: [
                        .init(color: Color(hex: "f4f8ff"), location: 0.0),
                        .init(color: Color(hex: "aab4c2"), location: 0.25),
                        .init(color: Color(hex: "eef3fa"), location: 0.5),
                        .init(color: Color(hex: "aab4c2"), location: 0.75),
                        .init(color: Color(hex: "f4f8ff"), location: 1.0)
                    ], center: .center))
                }
            }
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())

            Circle().fill(AngularGradient(stops: [
                .init(color: .white.opacity(0.0), location: 0.0),
                .init(color: .white.opacity(0.22), location: 0.10),
                .init(color: .white.opacity(0.0), location: 0.22),
                .init(color: .white.opacity(0.12), location: 0.5),
                .init(color: .white.opacity(0.0), location: 0.62),
                .init(color: .white.opacity(0.18), location: 0.85),
                .init(color: .white.opacity(0.0), location: 1.0)
            ], center: .center)).blendMode(.screen)

            Circle().fill(RadialGradient(colors: [Color.white.opacity(0.08), .clear, Color.black.opacity(0.20)],
                                         center: UnitPoint(x: 0.42, y: 0.36), startRadius: diameter * 0.05, endRadius: diameter * 0.55))

            clampArea

            Circle().strokeBorder(AngularGradient(colors: [Color(hex: "59f0d0").opacity(0.0), Color(hex: "59f0d0").opacity(0.10),
                                                           Color(hex: "ff7ad9").opacity(0.10), Color(hex: "ffd86a").opacity(0.08),
                                                           Color(hex: "59f0d0").opacity(0.0)], center: .center), lineWidth: 3)
                .blendMode(.screen).padding(2)
        }
        .frame(width: diameter, height: diameter)
        .mask(Circle().overlay(Circle().frame(width: hole, height: hole).blendMode(.destinationOut)).compositingGroup())
        .overlay(Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.7), Color.black.opacity(0.35)],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
        .overlay(Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 1).frame(width: hole + 1.5, height: hole + 1.5))
    }

    private var clampArea: some View {
        let ring = diameter * 0.22
        return ZStack {
            Circle().fill(RadialGradient(colors: [Color(hex: "d8dde6"), Color(hex: "b4bcc8")],
                                         center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: ring * 0.5))
                .frame(width: ring, height: ring)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.18), lineWidth: 0.8))
            Circle().strokeBorder(Color.black.opacity(0.16), lineWidth: 1).frame(width: ring * 0.7, height: ring * 0.7)
        }
    }
}
