import SwiftUI
import Combine

// MARK: - Global widget settings (size lives in WidgetSizeManager.shared)

enum NotesSide: String, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var title: String { self == .left ? "Left" : "Right" }
}

/// Shared, persisted settings for the active desktop widget.
final class WidgetSettings: ObservableObject {
    static let shared = WidgetSettings()

    @Published var notesEnabled: Bool {
        didSet { UserDefaults.standard.set(notesEnabled, forKey: "widget.notes.enabled") }
    }
    @Published var notesSide: NotesSide {
        didSet { UserDefaults.standard.set(notesSide.rawValue, forKey: "widget.notes.side") }
    }

    /// Widget window opacity (0.5–1.0).
    @Published var widgetOpacity: Double {
        didSet { UserDefaults.standard.set(widgetOpacity, forKey: "widget.opacity") }
    }
    /// Widget floats above all windows instead of sitting just over the desktop.
    @Published var alwaysOnTop: Bool {
        didSet { UserDefaults.standard.set(alwaysOnTop, forKey: "widget.alwaysOnTop") }
    }
    /// Mouse clicks pass straight through the widget to whatever is behind it.
    @Published var clickThrough: Bool {
        didSet { UserDefaults.standard.set(clickThrough, forKey: "widget.clickThrough") }
    }
    /// Fade the widget out when nothing is playing, back in when music resumes.
    @Published var hideWhenPaused: Bool {
        didSet { UserDefaults.standard.set(hideWhenPaused, forKey: "widget.hideWhenPaused") }
    }

    private init() {
        notesEnabled = UserDefaults.standard.bool(forKey: "widget.notes.enabled")
        notesSide = NotesSide(rawValue: UserDefaults.standard.string(forKey: "widget.notes.side") ?? "") ?? .left
        let storedOpacity = UserDefaults.standard.object(forKey: "widget.opacity") as? Double
        widgetOpacity = min(1.0, max(0.5, storedOpacity ?? 1.0))
        alwaysOnTop = UserDefaults.standard.bool(forKey: "widget.alwaysOnTop")
        clickThrough = UserDefaults.standard.bool(forKey: "widget.clickThrough")
        hideWhenPaused = UserDefaults.standard.bool(forKey: "widget.hideWhenPaused")
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

// MARK: - Musical notes emitter (🎵 🎶 drifting out + fading while playing)

private struct FloatingNote: Identifiable {
    let id = UUID()
    let birth = Date()
    let isDouble: Bool = Bool.random()
    let size: CGFloat = .random(in: 26...40)
    let life: Double = .random(in: 2.6...3.9)
    let rise: CGFloat = .random(in: 66...98)
    let driftX: CGFloat
    let startX: CGFloat = .random(in: -18...22)
    let startY: CGFloat = .random(in: -20...16)
    let baseAngle: Double = .random(in: -30...30)   // tilted, never upside down / sideways
    let sway: Double = .random(in: 4...9)
    let phase: Double = .random(in: 0...6.28)

    init(side: NotesSide) {
        driftX = side == .left ? .random(in: -64 ... -16) : .random(in: 16...64)
    }
}

struct MusicalNotesView: View {
    let side: NotesSide
    let active: Bool

    @State private var notes: [FloatingNote] = []
    @State private var lastSpawn: Date = .distantPast

    var body: some View {
        TimelineView(.animation(paused: !active && notes.isEmpty)) { ctx in
            let now = ctx.date
            let t = now.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(notes) { note in
                    let p = min(1.0, now.timeIntervalSince(note.birth) / note.life)
                    let angle = note.baseAngle + note.sway * sin(t * 1.5 + note.phase)
                    NoteGlyph(isDouble: note.isDouble)
                        .frame(width: note.size, height: note.size * 1.4)
                        .rotationEffect(.degrees(angle))
                        .opacity(opacity(p))
                        .offset(x: note.startX + note.driftX * CGFloat(p),
                                y: note.startY - CGFloat(p) * note.rise)
                }
            }
            .frame(width: 130, height: 120, alignment: side == .left ? .topLeading : .topTrailing)
            .onChange(of: now) { _, d in tick(d) }
        }
        .allowsHitTesting(false)
    }

    private func opacity(_ p: Double) -> Double {
        if p >= 1 { return 0 }
        if p < 0.18 { return p / 0.18 }
        return 1 - (p - 0.18) / 0.82
    }

    private func tick(_ now: Date) {
        notes.removeAll { now.timeIntervalSince($0.birth) > $0.life }
        if active, now.timeIntervalSince(lastSpawn) > 0.7 {
            lastSpawn = now
            notes.append(FloatingNote(side: side))
        }
    }
}

// MARK: - Hand-drawn musical note glyphs (black)

struct NoteGlyph: View {
    let isDouble: Bool
    var body: some View {
        if isDouble { NoteDouble() } else { NoteSingle() }
    }
}

/// Eighth note (♪): tilted notehead + stem + flag.
struct NoteSingle: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                // stem
                RoundedRectangle(cornerRadius: w * 0.05)
                    .fill(.black)
                    .frame(width: w * 0.11, height: h * 0.66)
                    .position(x: w * 0.60, y: h * 0.39)
                // flag
                Path { p in
                    p.move(to: CGPoint(x: w * 0.655, y: h * 0.08))
                    p.addQuadCurve(to: CGPoint(x: w * 0.92, y: h * 0.46),
                                   control: CGPoint(x: w * 1.08, y: h * 0.16))
                    p.addQuadCurve(to: CGPoint(x: w * 0.655, y: h * 0.34),
                                   control: CGPoint(x: w * 0.84, y: h * 0.34))
                    p.closeSubpath()
                }.fill(.black)
                // notehead
                Ellipse()
                    .fill(.black)
                    .frame(width: w * 0.48, height: w * 0.36)
                    .rotationEffect(.degrees(-22))
                    .position(x: w * 0.38, y: h * 0.76)
            }
        }
    }
}

/// Beamed pair (♫): two noteheads + stems joined by a slanted beam.
struct NoteDouble: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                // beam connecting the two stem tops
                Path { p in
                    p.move(to: CGPoint(x: w * 0.30, y: h * 0.05))
                    p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.17))
                    p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.31))
                    p.addLine(to: CGPoint(x: w * 0.30, y: h * 0.19))
                    p.closeSubpath()
                }.fill(.black)
                // left stem
                RoundedRectangle(cornerRadius: w * 0.04).fill(.black)
                    .frame(width: w * 0.09, height: h * 0.62)
                    .position(x: w * 0.345, y: h * 0.42)
                // right stem
                RoundedRectangle(cornerRadius: w * 0.04).fill(.black)
                    .frame(width: w * 0.09, height: h * 0.54)
                    .position(x: w * 0.835, y: h * 0.50)
                // left notehead
                Ellipse().fill(.black)
                    .frame(width: w * 0.40, height: w * 0.30)
                    .rotationEffect(.degrees(-20))
                    .position(x: w * 0.22, y: h * 0.74)
                // right notehead
                Ellipse().fill(.black)
                    .frame(width: w * 0.40, height: w * 0.30)
                    .rotationEffect(.degrees(-20))
                    .position(x: w * 0.71, y: h * 0.80)
            }
        }
    }
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
                var y: CGFloat = 0
                while y < size.height {
                    let op = (Int(y) % 3 == 0) ? 0.055 : 0.02
                    ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) },
                               with: .color(.white.opacity(op)), lineWidth: 0.5)
                    y += 2.5
                }
            case .wood:
                var x: CGFloat = 4
                var seed = 1
                while x < size.width {
                    let wob = CGFloat((seed * 37) % 9) - 4
                    let op = (seed % 2 == 0) ? 0.13 : 0.06
                    ctx.stroke(Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addQuadCurve(to: CGPoint(x: x + wob, y: size.height),
                                       control: CGPoint(x: x + wob * 2, y: size.height / 2))
                    }, with: .color(.black.opacity(op)), lineWidth: 1)
                    x += CGFloat(5 + (seed * 13) % 7)
                    seed += 1
                }
            case .fabric:
                let step: CGFloat = 5
                var i: CGFloat = -size.height
                while i < size.width {
                    ctx.stroke(Path { p in p.move(to: CGPoint(x: i, y: 0)); p.addLine(to: CGPoint(x: i + size.height, y: size.height)) },
                               with: .color(.white.opacity(0.028)), lineWidth: 0.6)
                    ctx.stroke(Path { p in p.move(to: CGPoint(x: i, y: size.height)); p.addLine(to: CGPoint(x: i + size.height, y: 0)) },
                               with: .color(.black.opacity(0.045)), lineWidth: 0.6)
                    i += step
                }
            }
        }
        .allowsHitTesting(false)
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
    var traits: VinylModelTraits {
        switch self {
        case .jukebox:   // Retro — cherry wood cabinet
            return VinylModelTraits(hasTransportControls: true, spindle: .retro45, pattern: .wood)
        case .diner:     // Retro — teal diner console
            return VinylModelTraits(hasTransportControls: true, spindle: .retro45, pattern: .none)
        case .tweed:     // Retro — tweed-covered radiogram
            return VinylModelTraits(hasTransportControls: true, spindle: .retro45, pattern: .fabric)
        case .boombox:   // Retro — black & orange street deck
            return VinylModelTraits(hasTransportControls: true, spindle: .retro45, pattern: .brushed)
        case .mustard:   // Retro — 70s mustard console
            return VinylModelTraits(hasTransportControls: true, spindle: .retro45, pattern: .none)
        case .slate:     // Studio deck — brushed metal
            return VinylModelTraits(spindle: .retro45, hasPitchSlider: true, hasPowerLED: true, pattern: .brushed)
        case .walnut:    // Audiophile — walnut grain
            return VinylModelTraits(spindle: .retro45, hasCounterweight: true, hasPlatterRing: true, pattern: .wood)
        case .sandstone: // Suitcase — canvas weave
            return VinylModelTraits(hasPowerLED: true, caseBorder: true, pattern: .fabric)
        case .synthwave: // Studio deck — neon night build
            return VinylModelTraits(spindle: .retro45, hasPitchSlider: true, hasPowerLED: true, pattern: .brushed)
        case .carbon:    // Track-day build — brushed black metal
            return VinylModelTraits(pattern: .brushed)
        case .copper:    // Heirloom — warm grain
            return VinylModelTraits(spindle: .retro45, hasCounterweight: true, pattern: .wood)
        default:
            return VinylModelTraits()
        }
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

