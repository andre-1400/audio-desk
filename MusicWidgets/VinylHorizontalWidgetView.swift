import SwiftUI
import AppKit

// MARK: - Gallery model
//
// A new Vinyl form: a horizontal "bar" layout (small spinning disc on the
// left, track info + transport controls on the right) instead of the
// vertical turntable body. Reuses the existing WidgetThemeID palette system
// so it stays consistent with every other vinyl colourway, and reuses the
// EXACT disc renderer (SpinningVinylView) and the exact tonearm geometry
// from the main widget — both just scaled down uniformly — rather than a
// hand-approximated mini version. It does not modify VinylWidgetView.swift.
//
// Track-change transition is intentionally simple here: a quick disc-shrink
// pulse, not the full sleeve-flying animation. That system is tuned for the
// main widget's much larger disc (hardcoded ~258pt elements/travel
// distances) and reusing it at this size didn't read well — kept this
// widget on its own simple, self-contained transition instead.

struct VinylHorizontalModel: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let themeID: WidgetThemeID

    static let all: [VinylHorizontalModel] = [
        VinylHorizontalModel(id: "hbar-adaptive", name: "Adaptive", subtitle: "Matches the album art, live", themeID: .adaptive),
        VinylHorizontalModel(id: "hbar-classic", name: "Classic", subtitle: "Warm wood & gold", themeID: .default),
        VinylHorizontalModel(id: "hbar-obsidian", name: "Obsidian", subtitle: "Jet black & chrome", themeID: .obsidian),
        VinylHorizontalModel(id: "hbar-pearl", name: "Pearl", subtitle: "Cream & terracotta", themeID: .pearl)
    ]
}

let horizontalBaseSize = CGSize(width: 400, height: 136)

/// Everything here is derived from one factor so the disc and tonearm scale
/// down together, uniformly, from their native size in the main widget
/// (disc 272pt, tonearm frame 90x180pt) — never resized independently.
private let hDiscScale: CGFloat = 0.44
private let hDiscContainerSize: CGFloat = 130

// MARK: - Widget

struct VinylHorizontalWidgetView: View {
    let model: VinylHorizontalModel
    var isPreview: Bool = false
    // Real playing-track data for the gallery preview, threaded down from
    // GalleryLiveTrack. Only ever read when isPreview.
    var previewInfo: NowPlayingInfo? = nil
    var previewArt: NSImage? = nil
    var previewColours: ExtractedColours? = nil
    var previewBlurredArt: NSImage? = nil

    @StateObject private var detector = MusicDetector()
    @StateObject private var artFetcher = AlbumArtFetcher()

    @State private var displayedInfo: NowPlayingInfo = .empty
    @State private var displayedArt: NSImage?
    @State private var lastObservedTrackIdentity: String = ""
    @State private var hasSeenInitialTrackIdentity = false
    @State private var discPulseScale: Double = 1.0
    // Only ever read for the Adaptive model (see `theme` below), so this
    // initial value only matters for Adaptive: neutral grey/white rather
    // than the generic extraction-failure fallback, so the gallery/initial
    // look reads as "becomes whatever's playing," not "this one is brown."
    @State private var extractedColours: ExtractedColours = .adaptivePreviewPlaceholder
    /// Adaptive only: current album art, heavily blurred, used as the body.
    /// Cached per track — never recomputed per frame.
    @State private var blurredBodyArt: NSImage?

    private var effectiveColours: ExtractedColours {
        isPreview ? (previewColours ?? .adaptivePreviewPlaceholder) : extractedColours
    }
    private var effectiveArt: NSImage? { isPreview ? previewArt : displayedArt }
    private var effectiveBlurredBodyArt: NSImage? { isPreview ? previewBlurredArt : blurredBodyArt }

    private var theme: WidgetThemePalette {
        model.themeID == .adaptive ? WidgetThemeID.adaptivePalette(from: effectiveColours) : model.themeID.palette
    }

    /// Foreground colours picked for contrast against the body as drawn.
    private var isAdaptive: Bool { model.themeID == .adaptive }
    private var fgPrimary: Color {
        isAdaptive ? AdaptiveBody.primary(effectiveColours.dominant) : theme.trackTitle
    }
    private var fgSecondary: Color {
        isAdaptive ? AdaptiveBody.secondary(effectiveColours.dominant) : theme.trackArtist
    }
    private var np: NowPlayingInfo { isPreview ? (previewInfo ?? .empty) : displayedInfo }

    private var trackIdentityKey: String {
        "\(detector.nowPlaying.trackName)|\(detector.nowPlaying.artistName)|\(detector.nowPlaying.albumName)"
    }

    var body: some View {
        HStack(spacing: 14) {
            discArea
            VStack(alignment: .leading, spacing: 8) {
                trackText
                Spacer(minLength: 2)
                transportRow
                progressRow
            }
            .padding(.vertical, 14)
            .padding(.trailing, 18)
        }
        .padding(.leading, 12)
        .frame(width: horizontalBaseSize.width, height: horizontalBaseSize.height, alignment: .leading)
        .background(
            ZStack {
                LinearGradient(colors: theme.widgetBodyGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                // Adaptive: same treatment as every other adaptive style —
                // the body is the blurred album art, not an averaged colour.
                AdaptiveBodyFill(blurredArt: effectiveBlurredBodyArt, size: horizontalBaseSize)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(theme.widgetBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.32), radius: 16, x: 0, y: 9)
        .onAppear {
            guard !isPreview else { return }
            detector.start()
            displayedInfo = detector.nowPlaying
            lastObservedTrackIdentity = trackIdentityKey
            hasSeenInitialTrackIdentity = true
            if !detector.nowPlaying.trackName.isEmpty {
                refreshArt(forceRefresh: false)
            }
        }
        .onDisappear {
            guard !isPreview else { return }
            detector.stop()
        }
        .onChange(of: trackIdentityKey) { oldValue, newValue in
            guard !isPreview else { return }
            handleTrackIdentityChange(oldValue: oldValue, newValue: newValue)
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

    // MARK: - Track transition — simple crossfade + a quick disc-shrink pulse

    private func handleTrackIdentityChange(oldValue: String, newValue: String) {
        if !hasSeenInitialTrackIdentity {
            hasSeenInitialTrackIdentity = true
            lastObservedTrackIdentity = newValue
            return
        }
        if oldValue == newValue || lastObservedTrackIdentity == newValue { return }
        lastObservedTrackIdentity = newValue

        let live = detector.nowPlaying
        guard !live.trackName.isEmpty else {
            withAnimation(.easeInOut(duration: 0.3)) {
                displayedInfo = live
                displayedArt = nil
            }
            return
        }

        let isInitialTrack = oldValue.isEmpty || displayedInfo.trackName.isEmpty
        withAnimation(.easeInOut(duration: 0.3)) {
            displayedInfo = live
        }
        refreshArt(forceRefresh: true)

        guard !isInitialTrack else { return }

        // Quick "disc dips" pulse to mark the change, instead of a full
        // sleeve-flying transition.
        withAnimation(.easeOut(duration: 0.16)) {
            discPulseScale = 0.82
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                discPulseScale = 1.0
            }
        }
    }

    private func refreshArt(forceRefresh: Bool) {
        let artURL = detector.nowPlaying.albumArtURL ?? ""
        artFetcher.fetchArt(from: artURL, trackKey: trackIdentityKey, forceRefresh: forceRefresh) { image in
            guard let image else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                displayedArt = image
            }
            if model.themeID == .adaptive {
                extractedColours = ColourExtractor.extract(from: image)
                DispatchQueue.global(qos: .userInitiated).async {
                    let blurred = ArtBlurrer.blurredBody(from: image)
                    DispatchQueue.main.async { blurredBodyArt = blurred }
                }
            }
        }
    }

    private func togglePlayback() {
        guard !isPreview else { return }
        detector.togglePlayback()
    }

    // MARK: - Disc + tonearm (left side) — exact reuse, uniformly scaled

    private var discArea: some View {
        let discSize = 272 * hDiscScale
        let discRadius = discSize / 2
        return ZStack {
            SpinningVinylView(
                // Preview cards never spin the disc — no hover-spin gate
                // exists for this widget type, so if a real track happens
                // to be playing this would otherwise animate every visible
                // card continuously, all at once.
                isPlaying: isPreview ? false : displayedInfo.isPlaying,
                albumArt: effectiveArt,
                vinylTint: theme.albumArtLabelGradient.first ?? Color(hex: "9B5523"),
                albumArtLabelGradient: theme.albumArtLabelGradient,
                albumArtRingColor: theme.albumArtRingColor
            )
            .scaleEffect(hDiscScale)
            .frame(width: discSize, height: discSize)
            .scaleEffect(discPulseScale)

            hTonearm
                .scaleEffect(hDiscScale)
                .frame(width: 90 * hDiscScale, height: 180 * hDiscScale)
                // Computed, not eyeballed: ZStack centres hTonearm's own
                // frame-centre on the disc centre before this offset runs,
                // which puts the joint (local 68,16) at (0.169,-0.544)*R
                // from disc-centre for free. Solving offset = target - that
                // inherent position puts the joint just outside the disc's
                // edge (0.9R, -0.75R) with the needle landing ~2/3 of the
                // way out — resting near the edge, not swept to the middle.
                // No extra rotation here: the assembly's internal angles are
                // already self-consistent (copied whole from the real
                // widget) — rotating it around an off-centre anchor on top
                // of that is what made it look detached/broken last time.
                .offset(x: discRadius * 0.731, y: -discRadius * 0.206)
        }
        .frame(width: hDiscContainerSize, height: hDiscContainerSize)
        .contentShape(Rectangle())
        .onTapGesture { togglePlayback() }
    }

    /// Identical shapes/colours/shadows to VinylWidgetView's tonearmView —
    /// duplicated (not shared) per this codebase's existing convention of
    /// hand-copying this exact geometry between the live widget and its
    /// gallery-preview replica. No counterweight/traits: this widget has
    /// no per-style trait system, and no seek interactivity (decorative).
    private var hTonearm: some View {
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

            // Headshell/needle mount at the far end of the rod — this was
            // missing entirely before, which is why the tip looked bare.
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

    // MARK: - Track info + controls (right side)

    private var trackText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(np.trackName.isEmpty ? "Nothing Playing" : np.trackName)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(fgPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if !np.artistName.isEmpty {
                Text(np.artistName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(fgSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transportRow: some View {
        // Preview cards show these purely for looks — cosmetic only, never
        // wired to real transport commands.
        HStack(spacing: 18) {
            transportButton("backward.fill", size: 13) { if !isPreview { detector.previousTrack() } }
            transportButton(np.isPlaying ? "pause.fill" : "play.fill", size: 15) { togglePlayback() }
            transportButton("forward.fill", size: 13) { if !isPreview { detector.nextTrack() } }
        }
    }

    private func transportButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(fgPrimary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPreview)
    }

    private var progressRow: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let fraction = progressFraction(at: context.date)
            HStack(spacing: 8) {
                Text(formatTime(elapsedMillis(at: context.date)))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(fgSecondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(fgSecondary.opacity(0.25))
                        Capsule().fill(fgPrimary)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 3)
                Text("-" + formatTime(remainingMillis(at: context.date)))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(fgSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func elapsedMillis(at date: Date) -> Int {
        guard let pos = np.positionMillis else { return 0 }
        var elapsed = Double(pos)
        if np.isPlaying, let sampledAt = np.progressSampledAt {
            elapsed += date.timeIntervalSince(sampledAt) * 1000
        }
        if let dur = np.durationMillis { elapsed = min(elapsed, Double(dur)) }
        return max(0, Int(elapsed))
    }

    private func remainingMillis(at date: Date) -> Int {
        guard let dur = np.durationMillis else { return 0 }
        return max(0, dur - elapsedMillis(at: date))
    }

    private func progressFraction(at date: Date) -> Double {
        guard let dur = np.durationMillis, dur > 0 else { return 0 }
        return min(1, max(0, Double(elapsedMillis(at: date)) / Double(dur)))
    }

    private func formatTime(_ millis: Int) -> String {
        let totalSeconds = millis / 1000
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

// MARK: - Sized root (applies the global small/medium/large scale)

struct VinylHorizontalSizedRoot: View {
    let model: VinylHorizontalModel
    @ObservedObject private var sizeM = WidgetSizeManager.shared

    var body: some View {
        let s = sizeM.scale
        VinylHorizontalWidgetView(model: model)
            .scaleEffect(s)
            .frame(width: horizontalBaseSize.width * s, height: horizontalBaseSize.height * s)
    }
}

// MARK: - Gallery preview (fit-scaled, flattened)

struct VinylHorizontalModelPreview: View {
    let model: VinylHorizontalModel
    @ObservedObject var live: GalleryLiveTrack = GalleryLiveTrack()

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / horizontalBaseSize.width, geo.size.height / horizontalBaseSize.height)
            VinylHorizontalWidgetView(
                model: model, isPreview: true,
                previewInfo: live.info, previewArt: live.art,
                previewColours: live.colours, previewBlurredArt: live.blurredArt
            )
                .frame(width: horizontalBaseSize.width, height: horizontalBaseSize.height)
                .scaleEffect(s)
                .frame(width: horizontalBaseSize.width * s, height: horizontalBaseSize.height * s)
                .frame(width: geo.size.width, height: geo.size.height)
                .drawingGroup()
        }
    }
}
