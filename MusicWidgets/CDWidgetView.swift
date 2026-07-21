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
    case discman, hifi

    var baseSize: CGSize {
        switch self {
        case .discman: return CGSize(width: 360, height: 500)
        case .hifi:    return CGSize(width: 560, height: 300)
        }
    }
    var deckDiameter: CGFloat {
        switch self {
        case .discman: return 220
        case .hifi:    return 196
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
    /// When true, CDWidgetView ignores `material` and derives colours live
    /// from the currently playing album's art instead.
    var isAdaptive: Bool = false

    static let all: [CDModel] = [
        // ===== Discman (portable) — Adaptive first, then a few basics =====
        CDModel(id: "discman-adaptive", name: "Adaptive", subtitle: "Matches the album art, live",
                archetype: .discman, material: .adaptivePlaceholder, isAdaptive: true),
        CDModel(id: "discman-silver", name: "Silver", subtitle: "Brushed silver", archetype: .discman, material: .silver),
        CDModel(id: "discman-noir",   name: "Noir",   subtitle: "Stealth black",  archetype: .discman, material: .noir),
        CDModel(id: "discman-ruby",   name: "Ruby",   subtitle: "Glossy red",     archetype: .discman, material: .ruby),
        CDModel(id: "discman-ivory",  name: "Ivory",  subtitle: "Warm cream",     archetype: .discman, material: .ivory),

        // ===== Hi-Fi deck (component) — Adaptive first, then a few basics =====
        CDModel(id: "hifi-adaptive", name: "Adaptive", subtitle: "Matches the album art, live",
                archetype: .hifi, material: .adaptivePlaceholder, isAdaptive: true),
        CDModel(id: "hifi-aluminum", name: "Aluminum", subtitle: "Brushed aluminum", archetype: .hifi, material: .aluminum),
        CDModel(id: "hifi-onyx",     name: "Onyx",     subtitle: "Matte black",     archetype: .hifi, material: .onyx),
        CDModel(id: "hifi-navy",     name: "Navy",     subtitle: "Deep blue steel", archetype: .hifi, material: .navy)
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
               models: all.filter { $0.archetype == .discman }),
        CDForm(id: "hifi", name: "Hi-Fi Deck", subtitle: "Component shelf unit", icon: "hifispeaker",
               models: all.filter { $0.archetype == .hifi })
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

    static let navy = CDMaterial(
        housing: [Color(hex: "1f3358"), Color(hex: "152544"), Color(hex: "0c1830")],
        ring: [Color(hex: "e6eeff"), Color(hex: "aac2e6"), Color(hex: "5e7aa4"), Color(hex: "cdddf4")],
        accent: Color(hex: "7fc0ff"), lidTint: Color(hex: "08122a"), lidOpacity: 0.28,
        well: [Color(hex: "0c1a36"), Color(hex: "06101f")],
        panel: [Color(hex: "28406e"), Color(hex: "17284c")],
        lcdBg: [Color(hex: "0a2040"), Color(hex: "06142c")], lcd: Color(hex: "a8d0ff"),
        subtitle: Color(hex: "9ab0d0"), isLight: false)

    // MARK: Adaptive — colour tracks the currently playing album's art.
    // Neutral chrome ring, same as every other material (a real CD's clamp
    // ring doesn't change colour with the disc), everything else derived.

    /// Static stand-in the model needs a `material` value for; never actually
    /// rendered — CDWidgetView swaps to `.adaptive(from:)` whenever
    /// `model.isAdaptive` is true. This exists only for gallery previews /
    /// contexts with no live playback data.
    static let adaptivePlaceholder = adaptive(from: .adaptivePreviewPlaceholder)

    static func adaptive(from colours: ExtractedColours) -> CDMaterial {
        let dominant = colours.dominant
        let secondary = colours.secondary
        let darkest = secondary.adjustBrightness(-0.12)
        let isLight = dominant.isPerceivedLight
        return CDMaterial(
            housing: [dominant, secondary, darkest],
            ring: [Color(hex: "f0f2f6"), Color(hex: "b0b6c0"), Color(hex: "5a606a"), Color(hex: "d6dce4")],
            accent: dominant,
            lidTint: darkest,
            lidOpacity: 0.28,
            well: [darkest, darkest.adjustBrightness(-0.08)],
            panel: [secondary, darkest],
            lcdBg: [darkest, darkest.adjustBrightness(-0.06)],
            lcd: dominant,
            subtitle: isLight ? secondary : dominant.adjustBrightness(0.28),
            isLight: isLight
        )
    }
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
    // Only ever read when model.isAdaptive; neutral grey/white rather than
    // the generic extraction-failure fallback so it reads as "will become
    // whatever's playing," not a fixed brown.
    @State private var extractedColours: ExtractedColours = .adaptivePreviewPlaceholder

    @ObservedObject private var settings = WidgetSettings.shared

    private let maxSpinSpeed: Double = 2200   // real CDs spin fast — art blurs

    private var mat: CDMaterial { model.isAdaptive ? .adaptive(from: extractedColours) : model.material }
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
        case .discman: portraitLayout
        case .hifi:    hifiLayout
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
        model.archetype == .discman
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
            transition.onReveal = { self.displayedArt = self.incomingArt; self.updateAdaptiveColoursIfNeeded() }
            transition.onComplete = { self.displayedArt = self.incomingArt ?? self.displayedArt; self.updateAdaptiveColoursIfNeeded() }
            transition.start()
        } else { displayedArt = incomingArt; updateAdaptiveColoursIfNeeded() }
    }

    private func fetchArt(_ url: String?, commitImmediately: Bool = false) {
        guard let url, !url.isEmpty else { return }
        artFetcher.fetchArt(from: url, trackKey: trackKey, forceRefresh: false) { image in
            if commitImmediately || !transition.isAnimating {
                self.displayedArt = image
                self.updateAdaptiveColoursIfNeeded()
            } else { self.incomingArt = image }
        }
    }

    /// Adaptive material: derive live colours whenever the resting disc's
    /// art changes. No-op unless model.isAdaptive.
    private func updateAdaptiveColoursIfNeeded() {
        guard model.isAdaptive, let art = displayedArt else { return }
        extractedColours = ColourExtractor.extract(from: art)
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
