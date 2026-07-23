import SwiftUI
import AppKit

// MARK: - Gallery model
//
// The bare mechanism and nothing else — just the spinning disc and its
// centre spindle, no housing/body/tonearm/track panel around it. Floats
// directly on the desktop with a fully transparent frame. Reuses the exact
// same disc renderer (SpinningVinylView) as every other vinyl style — only
// what's built around it differs (here, nothing).
//
// No Custom colour option (unlike Vinyl v1/Horizontal) — kept to Adaptive
// plus the three named colourways for now, since this is scoped to the
// bare-mechanism look itself, not a full re-run of the custom-colour-picker
// plumbing. Easy to add later if wanted.

struct VinylSpindleModel: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let themeID: WidgetThemeID

    static let all: [VinylSpindleModel] = [
        VinylSpindleModel(id: "spindle-adaptive", name: "Adaptive", subtitle: "Matches the album art, live", themeID: .adaptive),
        VinylSpindleModel(id: "spindle-classic", name: "Classic", subtitle: "Warm wood & gold", themeID: .default),
        VinylSpindleModel(id: "spindle-obsidian", name: "Obsidian", subtitle: "Jet black & chrome", themeID: .obsidian),
        VinylSpindleModel(id: "spindle-pearl", name: "Pearl", subtitle: "Cream & terracotta", themeID: .pearl)
    ]
}

let spindleDiscDiameter: CGFloat = 272
/// Margin all round the disc for its own drop shadow — the window itself is
/// fully transparent outside the disc, same idea as cdMargin/Vinyl v1's own
/// outer frame.
private let spindleMargin: CGFloat = 20
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
