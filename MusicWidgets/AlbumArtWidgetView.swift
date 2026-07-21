import SwiftUI
import AppKit

// MARK: - Gallery model
//
// A different kind of widget from Vinyl/CD on purpose: no physical device,
// no disc, no skeuomorphism — just the cover art (VinylPod-style minimalism),
// rendered nicely. Each size is a genuinely different layout, not a scaled
// copy of the same design.

enum AlbumArtSize: String, CaseIterable, Identifiable {
    case compact, card, hero
    var id: String { rawValue }

    var baseSize: CGSize {
        switch self {
        case .compact: return CGSize(width: 220, height: 220)
        case .card:    return CGSize(width: 280, height: 360)
        case .hero:    return CGSize(width: 380, height: 460)
        }
    }
}

struct AlbumArtModel: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let size: AlbumArtSize

    static let all: [AlbumArtModel] = [
        AlbumArtModel(id: "albumart-compact", name: "Compact", subtitle: "Just the cover art", size: .compact),
        AlbumArtModel(id: "albumart-card", name: "Card", subtitle: "Art with track info", size: .card),
        AlbumArtModel(id: "albumart-hero", name: "Hero", subtitle: "Full-bleed backdrop + controls", size: .hero)
    ]
}

// MARK: - Widget

struct AlbumArtWidgetView: View {
    let model: AlbumArtModel
    var isPreview: Bool = false
    // Real playing-track data for the gallery preview, threaded down from
    // GalleryLiveTrack. Only ever read when isPreview.
    var previewInfo: NowPlayingInfo? = nil
    var previewArt: NSImage? = nil
    var previewExtracted: ExtractedColours? = nil

    @StateObject private var detector = MusicDetector()
    @StateObject private var artFetcher = AlbumArtFetcher()

    @State private var displayedArt: NSImage?
    @State private var displayedInfo: NowPlayingInfo = .empty
    @State private var extracted: ExtractedColours = .fallback

    private var np: NowPlayingInfo { isPreview ? (previewInfo ?? .empty) : displayedInfo }
    private var art: NSImage {
        (isPreview ? previewArt : displayedArt) ?? FallbackCoverArtGenerator.fallbackImage
    }
    private var effectiveExtracted: ExtractedColours {
        isPreview ? (previewExtracted ?? .fallback) : extracted
    }
    private var trackKey: String { "\(np.trackName)|\(np.artistName)" }

    var body: some View {
        Group {
            switch model.size {
            case .compact: compactLayout
            case .card: cardLayout
            case .hero: heroLayout
            }
        }
        .frame(width: model.size.baseSize.width, height: model.size.baseSize.height)
        .onAppear {
            guard !isPreview else { return }
            detector.start()
            displayedInfo = detector.nowPlaying
            refreshArt(forceRefresh: false)
        }
        .onDisappear {
            guard !isPreview else { return }
            detector.stop()
        }
        .onChange(of: detector.nowPlaying) { _, live in
            guard !isPreview else { return }
            displayedInfo = live
        }
        .onChange(of: np.albumArtURL) { _, _ in
            guard !isPreview else { return }
            refreshArt(forceRefresh: false)
        }
    }

    private func refreshArt(forceRefresh: Bool) {
        artFetcher.fetchArt(from: np.albumArtURL ?? "", trackKey: trackKey, forceRefresh: forceRefresh) { image in
            withAnimation(.easeInOut(duration: 0.35)) {
                displayedArt = image
            }
            extracted = image.map(ColourExtractor.extract) ?? .fallback
        }
    }

    private func togglePlayback() {
        guard !isPreview else { return }
        detector.togglePlayback()
    }

    // MARK: - Compact (220x220) — literally just the art

    private var compactLayout: some View {
        artImage
            .id(trackKey)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: trackKey)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.38), radius: 18, x: 0, y: 10)
            .overlay(alignment: .topTrailing) {
                if !np.trackName.isEmpty {
                    PlaybackDot(isPlaying: np.isPlaying)
                        .padding(10)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .onTapGesture { togglePlayback() }
    }

    // MARK: - Card (280x360) — art + track info + progress

    private var cardLayout: some View {
        VStack(spacing: 14) {
            artImage
                .id(trackKey)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: trackKey)
                .aspectRatio(1, contentMode: .fill)
                .frame(width: 248, height: 248)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.30), radius: 14, x: 0, y: 8)
                .contentShape(Rectangle())
                .onTapGesture { togglePlayback() }

            VStack(spacing: 6) {
                Text(np.trackName.isEmpty ? "NOTHING PLAYING" : np.trackName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .tracking(np.trackName.isEmpty ? 1.4 : 0)
                if !np.artistName.isEmpty {
                    Text(np.artistName.uppercased())
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .tracking(0.6)
                }
                ProgressStrip(info: np, tint: .white)
                    .frame(width: 220)
                    .padding(.top, 4)
            }
        }
        .padding(.top, 24)
        .frame(width: model.size.baseSize.width, height: model.size.baseSize.height)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.34), radius: 20, x: 0, y: 12)
    }

    private var cardBackground: some View {
        LinearGradient(
            colors: [effectiveExtracted.dominant, effectiveExtracted.secondary],
            startPoint: .top, endPoint: .bottom
        )
        .animation(.easeInOut(duration: 0.5), value: effectiveExtracted.dominant)
    }

    // MARK: - Hero (380x460) — full-bleed backdrop + transport controls

    private var heroLayout: some View {
        ZStack {
            // Blurred, darkened backdrop from the same art — the "Apple Music
            // now playing" full-bleed look, no physical device at all.
            artImage
                .id(trackKey)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: trackKey)
                .aspectRatio(contentMode: .fill)
                .frame(width: model.size.baseSize.width, height: model.size.baseSize.height)
                .clipped()
                .blur(radius: 34)
                .overlay(Color.black.opacity(0.44))

            VStack(spacing: 18) {
                Spacer(minLength: 8)

                artImage
                    .id(trackKey)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: trackKey)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 210, height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 22, x: 0, y: 12)
                    .contentShape(Rectangle())
                    .onTapGesture { togglePlayback() }

                VStack(spacing: 5) {
                    Text(np.trackName.isEmpty ? "NOTHING PLAYING" : np.trackName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .tracking(np.trackName.isEmpty ? 1.6 : 0)
                    if !np.artistName.isEmpty {
                        Text(np.artistName.uppercased())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                            .tracking(0.8)
                    }
                }
                .padding(.horizontal, 24)

                ProgressStrip(info: np, tint: .white)
                    .frame(width: 260)

                // Preview cards show these purely for looks — cosmetic
                // only, never wired to real transport commands.
                HStack(spacing: 28) {
                    transportButton("backward.fill", size: 15) { if !isPreview { detector.previousTrack() } }
                    transportButton(np.isPlaying ? "pause.fill" : "play.fill", size: 20, prominent: true) { togglePlayback() }
                    transportButton("forward.fill", size: 15) { if !isPreview { detector.nextTrack() } }
                }
                .padding(.top, 2)

                Spacer(minLength: 18)
            }
        }
        .frame(width: model.size.baseSize.width, height: model.size.baseSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 14)
    }

    private func transportButton(_ symbol: String, size: CGFloat, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(prominent ? Color.white.opacity(0.94) : Color.white.opacity(0.14))
                .frame(width: prominent ? 46 : 36, height: prominent ? 46 : 36)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: size, weight: .semibold))
                        .foregroundStyle(prominent ? Color.black : Color.white.opacity(0.9))
                )
        }
        .buttonStyle(.plain)
        .disabled(isPreview)
    }

    private var artImage: some View {
        Image(nsImage: art)
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
}

// MARK: - Shared small pieces

/// A minimal playing/paused indicator — no skeuomorphism, just a soft dot.
private struct PlaybackDot: View {
    let isPlaying: Bool
    var body: some View {
        Circle()
            .fill(isPlaying ? Color(hex: "3ddc73") : Color.white.opacity(0.55))
            .frame(width: 9, height: 9)
            .shadow(color: (isPlaying ? Color(hex: "3ddc73") : .clear).opacity(0.7), radius: 4)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
    }
}

/// A thin, ticking progress bar — cheap TimelineView tick rather than a timer.
private struct ProgressStrip: View {
    let info: NowPlayingInfo
    let tint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.22))
                    Capsule().fill(tint.opacity(0.9))
                        .frame(width: geo.size.width * fraction(at: context.date))
                }
            }
        }
        .frame(height: 3)
    }

    private func fraction(at date: Date) -> Double {
        guard let pos = info.positionMillis, let dur = info.durationMillis, dur > 0 else { return 0 }
        var elapsedMillis = Double(pos)
        if info.isPlaying, let sampledAt = info.progressSampledAt {
            elapsedMillis += date.timeIntervalSince(sampledAt) * 1000
        }
        return min(1, max(0, elapsedMillis / Double(dur)))
    }
}

// MARK: - Sized root (applies the global small/medium/large scale, like CD/Vinyl)

struct AlbumArtSizedRoot: View {
    let model: AlbumArtModel
    @ObservedObject private var sizeM = WidgetSizeManager.shared

    var body: some View {
        let s = sizeM.scale
        let base = model.size.baseSize
        AlbumArtWidgetView(model: model)
            .scaleEffect(s)
            .frame(width: base.width * s, height: base.height * s)
    }
}

// MARK: - Gallery preview (fit-scaled, flattened like CD/Vinyl previews)

struct AlbumArtModelPreview: View {
    let model: AlbumArtModel
    @ObservedObject var live: GalleryLiveTrack = GalleryLiveTrack()

    var body: some View {
        GeometryReader { geo in
            let base = model.size.baseSize
            let s = min(geo.size.width / base.width, geo.size.height / base.height)
            AlbumArtWidgetView(
                model: model, isPreview: true,
                previewInfo: live.info, previewArt: live.art, previewExtracted: live.colours
            )
                .frame(width: base.width, height: base.height)
                .scaleEffect(s)
                .frame(width: base.width * s, height: base.height * s)
                .frame(width: geo.size.width, height: geo.size.height)
                .drawingGroup()   // static preview — flatten into one cached texture
        }
    }
}
