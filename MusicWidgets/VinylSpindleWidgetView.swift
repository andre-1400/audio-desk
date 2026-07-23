import SwiftUI
import AppKit

// MARK: - Gallery model
//
// The bare mechanism and nothing else — just the spinning disc, its centre
// spindle, and a tonearm that tracks playback position, no housing/body/
// track panel around any of it. Floats directly on the desktop with a
// fully transparent frame. Reuses the exact same disc renderer
// (SpinningVinylView) as every other vinyl style — only what's built
// around it differs (here, almost nothing).
//
// Only one model, deliberately: there's no housing left to give a colour
// to, so the Classic/Obsidian/Pearl device-body colourways this family's
// other forms offer don't mean anything here — the disc always just shows
// whatever's playing, live. That single option is presented with the same
// "LIVE" special-card treatment Adaptive gets everywhere else, since it's
// effectively a permanent Adaptive style with no alternative to contrast
// against.

struct VinylSpindleModel: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let themeID: WidgetThemeID

    static let all: [VinylSpindleModel] = [
        VinylSpindleModel(id: "spindle-live", name: "Spindle", subtitle: "Just the disc, floating free", themeID: .adaptive)
    ]
}

let spindleDiscDiameter: CGFloat = 272
/// Margin all round the disc for its own drop shadow AND the tonearm's
/// swing — the window itself is fully transparent outside the disc, same
/// idea as cdMargin/Vinyl v1's own outer frame. Wider than a plain shadow
/// margin would need on its own: the tonearm's pivot sits outside the
/// disc's edge, and its far end (the needle) sweeps a real arc around that
/// pivot as it tracks playback progress — a tight margin tuned only for
/// the disc's own shadow would clip it against the actual window edge.
let spindleMargin: CGFloat = 60
let spindleBaseSize = CGSize(width: spindleDiscDiameter + spindleMargin * 2,
                              height: spindleDiscDiameter + spindleMargin * 2)

// MARK: - Widget

struct VinylSpindleWidgetView: View {
    let model: VinylSpindleModel
    var isPreview: Bool = false
    var previewSpinning: Bool = false   // gallery hover: spin the disc without the detector
    // Real playing-track data for the gallery preview, threaded down from
    // GalleryLiveTrack. Only ever read when isPreview.
    var previewInfo: NowPlayingInfo? = nil
    var previewArt: NSImage? = nil
    var previewColours: ExtractedColours? = nil

    @StateObject private var detector = MusicDetector()
    @StateObject private var artFetcher = AlbumArtFetcher()

    @State private var displayedArt: NSImage?
    @State private var displayedInfo: NowPlayingInfo = .empty
    @State private var lastTrackKey: String = ""
    // Only ever read for Adaptive; neutral grey/white rather than the
    // generic extraction-failure fallback, so the gallery/initial look
    // reads as "becomes whatever's playing," not "this one is brown."
    @State private var extractedColours: ExtractedColours = .adaptivePreviewPlaceholder

    private var isAdaptive: Bool { model.themeID == .adaptive }
    private var effectiveColours: ExtractedColours {
        isPreview ? (previewColours ?? .adaptivePreviewPlaceholder) : extractedColours
    }
    private var effectiveArt: NSImage? { isPreview ? previewArt : displayedArt }
    private var theme: WidgetThemePalette {
        isAdaptive ? WidgetThemeID.adaptivePalette(from: effectiveColours) : model.themeID.palette
    }
    private var np: NowPlayingInfo { isPreview ? (previewInfo ?? .empty) : displayedInfo }
    private var trackKey: String {
        "\(detector.nowPlaying.trackName)|\(detector.nowPlaying.artistName)|\(detector.nowPlaying.albumName)"
    }

    private func togglePlayback() {
        guard !isPreview else { return }
        detector.togglePlayback()
    }

    // MARK: - Tonearm angles
    //
    // Same idea as Vinyl v1's tonearm (angle tracks playback progress), but
    // with its own tuning: this one has no housing to visually anchor it,
    // so paused = swung further out and away from the disc entirely (not
    // just resting at its edge), and the sweep toward the label at 100%
    // progress goes further in, since there's no track-info panel below to
    // compete with for reading as "the needle is nearly at the centre now."

    private let tonearmRestAngle = -14.0
    private let tonearmStartAngle = 0.0
    private let tonearmEndAngle = 20.0
    private let tonearmMaxProgress = 0.98

    private func tonearmAngle(at date: Date) -> Double {
        guard !np.trackName.isEmpty, np.isPlaying else { return tonearmRestAngle }
        guard let progress = playbackProgress(at: date) else { return tonearmStartAngle }
        return tonearmAngle(forProgress: progress)
    }

    private func playbackProgress(at date: Date) -> Double? {
        guard let dur = np.durationMillis, dur > 0, let pos = np.positionMillis else { return nil }
        var elapsed = Double(pos)
        if np.isPlaying, let sampledAt = np.progressSampledAt {
            elapsed += date.timeIntervalSince(sampledAt) * 1000
        }
        return min(tonearmMaxProgress, max(0, elapsed / Double(dur)))
    }

    private func tonearmAngle(forProgress progress: Double) -> Double {
        let clamped = min(tonearmMaxProgress, max(0, progress))
        return tonearmStartAngle + (tonearmEndAngle - tonearmStartAngle) * clamped
    }

    var body: some View {
        ZStack {
            SpinningVinylView(
                isPlaying: isPreview ? previewSpinning : np.isPlaying,
                albumArt: effectiveArt,
                vinylTint: theme.albumArtLabelGradient.first ?? Color(hex: "9B5523"),
                albumArtLabelGradient: theme.albumArtLabelGradient,
                albumArtRingColor: theme.albumArtRingColor,
                labelDiameter: 125
            )
            .frame(width: spindleDiscDiameter, height: spindleDiscDiameter)

            spindleHub

            // Purely visual: swings toward the label as the song progresses,
            // swings out and away when paused/stopped. Preview cards never
            // animate this — previewSpinning only drives the disc spin, and
            // there's no real position data for a preview to track anyway.
            if !isPreview {
                TimelineView(.animation) { context in
                    tonearm
                        .rotationEffect(
                            .degrees(tonearmAngle(at: context.date)),
                            anchor: UnitPoint(x: 68.0 / 90.0, y: 16.0 / 180.0)
                        )
                }
                .animation(.spring(response: 1.0, dampingFraction: 0.7), value: np.isPlaying)
                .offset(x: spindleDiscDiameter / 2 * 0.731, y: -spindleDiscDiameter / 2 * 0.206)
            }
        }
        .frame(width: spindleDiscDiameter, height: spindleDiscDiameter)
        .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
        .contentShape(Circle())
        .onTapGesture { togglePlayback() }
        .frame(width: spindleBaseSize.width, height: spindleBaseSize.height)
        .onAppear {
            guard !isPreview else { return }
            detector.start()
            displayedInfo = detector.nowPlaying
            lastTrackKey = trackKey
            if !detector.nowPlaying.trackName.isEmpty {
                refreshArt(forceRefresh: false)
            }
        }
        .onDisappear {
            guard !isPreview else { return }
            detector.stop()
        }
        .onChange(of: trackKey) { oldValue, newValue in
            guard !isPreview else { return }
            guard oldValue != newValue, lastTrackKey != newValue else { return }
            lastTrackKey = newValue
            let live = detector.nowPlaying
            guard !live.trackName.isEmpty else {
                withAnimation(.easeInOut(duration: 0.3)) { displayedArt = nil }
                return
            }
            refreshArt(forceRefresh: true)
        }
        .onChange(of: detector.nowPlaying) { _, live in
            guard !isPreview else { return }
            displayedInfo = live
        }
        .onChange(of: detector.nowPlaying.albumArtURL) { _, newURL in
            guard !isPreview else { return }
            if newURL != nil {
                refreshArt(forceRefresh: false)
            } else if detector.nowPlaying.trackName.isEmpty {
                artFetcher.fetchArt(from: "", trackKey: "", forceRefresh: true) { _ in
                    displayedArt = nil
                }
            }
        }
    }

    /// A small chrome dot at the disc's true centre — the "spindle" this
    /// style is named for. Every housed vinyl style relies on the turntable
    /// body around it to read as a record player; with nothing else here,
    /// the spindle is what actually says "this is a record," not just a
    /// circular album-art sticker.
    private var spindleHub: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [Color(hex: "f4f4f4"), Color(hex: "8c8c8c"),
                                 Color(hex: "eeeeee"), Color(hex: "747474"),
                                 Color(hex: "f4f4f4")],
                        center: .center
                    )
                )
                .frame(width: 13, height: 13)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: "2a2a2a"), Color(hex: "0a0a0a")],
                                     center: .center, startRadius: 0, endRadius: 3))
                .frame(width: 5, height: 5)
        }
    }

    /// Identical geometry to Vinyl v1's/Horizontal's own tonearm —
    /// duplicated rather than shared, per this codebase's existing
    /// convention of hand-copying this exact assembly between widgets. No
    /// counterweight here: that's a per-style trait this bare-mechanism
    /// widget has no trait system for, and it isn't missed at this size.
    private var tonearm: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "1c1c1e"), Color(hex: "606064"), Color(hex: "1c1c1e")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 8, height: 132)
                .rotationEffect(.degrees(20))
                .position(x: 46, y: 85)
                .shadow(color: .black.opacity(0.55), radius: 1.5, x: 1, y: 2)
                .shadow(color: .black.opacity(0.32), radius: 5, x: 2, y: 5)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "38383c"), Color(hex: "222224"), Color(hex: "0e0e10")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                .position(x: 68, y: 16)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "f2f2f4"), Color(hex: "c2c2c6"), Color(hex: "78787c")],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: 8
                    )
                )
                .frame(width: 15, height: 15)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.28), lineWidth: 0.5))
                .position(x: 68, y: 16)

            // Headshell/needle mount at the far end of the rod.
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "666666"), Color(hex: "222222")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 18, height: 16)
                .position(x: 24, y: 152)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "bbbbbb"), Color(hex: "666666")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2, height: 8)
                .position(x: 28, y: 164)
        }
        .frame(width: 90, height: 180)
    }

    private func refreshArt(forceRefresh: Bool) {
        let artURL = detector.nowPlaying.albumArtURL ?? ""
        artFetcher.fetchArt(from: artURL, trackKey: trackKey, forceRefresh: forceRefresh) { image in
            guard let image else { return }
            withAnimation(.easeInOut(duration: 0.3)) { displayedArt = image }
            if isAdaptive {
                extractedColours = ColourExtractor.extract(from: image)
            }
        }
    }
}

// MARK: - Sized root (applies the global small/medium/large scale)

struct VinylSpindleSizedRoot: View {
    let model: VinylSpindleModel
    @ObservedObject private var sizeM = WidgetSizeManager.shared

    var body: some View {
        let s = sizeM.scale
        VinylSpindleWidgetView(model: model)
            .scaleEffect(s)
            .frame(width: spindleBaseSize.width * s, height: spindleBaseSize.height * s)
    }
}

// MARK: - Gallery preview (fit-scaled, flattened)

struct VinylSpindleModelPreview: View {
    let model: VinylSpindleModel
    var animated: Bool = false
    @ObservedObject var live: GalleryLiveTrack = GalleryLiveTrack()

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / spindleBaseSize.width, geo.size.height / spindleBaseSize.height)
            VinylSpindleWidgetView(
                model: model, isPreview: true, previewSpinning: animated,
                previewInfo: live.info, previewArt: live.art,
                previewColours: model.themeID == .adaptive ? live.colours : nil
            )
                .frame(width: spindleBaseSize.width, height: spindleBaseSize.height)
                .scaleEffect(s)
                .frame(width: spindleBaseSize.width * s, height: spindleBaseSize.height * s)
                .frame(width: geo.size.width, height: geo.size.height)
                .drawingGroup()
        }
    }
}
