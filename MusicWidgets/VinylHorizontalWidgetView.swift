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

struct VinylHorizontalModel: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let themeID: WidgetThemeID

    static let all: [VinylHorizontalModel] = [
        VinylHorizontalModel(id: "hbar-classic", name: "Classic", subtitle: "Warm wood & gold", themeID: .default),
        VinylHorizontalModel(id: "hbar-obsidian", name: "Obsidian", subtitle: "Jet black & chrome", themeID: .obsidian),
        VinylHorizontalModel(id: "hbar-walnut", name: "Walnut", subtitle: "Audiophile wood deck", themeID: .walnut)
    ]
}

let horizontalBaseSize = CGSize(width: 400, height: 136)

/// Everything here is derived from one factor so the disc and tonearm scale
/// down together, uniformly, from their native size in the main widget
/// (disc 272pt, tonearm frame 90x180pt) — never resized independently.
private let hDiscScale: CGFloat = 0.36
private let hDiscContainerSize: CGFloat = 118

// MARK: - Widget

struct VinylHorizontalWidgetView: View {
    let model: VinylHorizontalModel
    var isPreview: Bool = false
    /// Injected so the live widget can share a dedicated animator/overlay
    /// with AppDelegate; gallery previews just get a throwaway instance.
    @ObservedObject var animator: SongSwitchAnimator = SongSwitchAnimator()

    @StateObject private var detector = MusicDetector()
    @StateObject private var artFetcher = AlbumArtFetcher()

    @State private var displayedInfo: NowPlayingInfo = .empty
    @State private var displayedArt: NSImage?
    @State private var bufferedIncomingArt: NSImage?
    @State private var lastObservedTrackIdentity: String = ""
    @State private var hasSeenInitialTrackIdentity = false

    private var theme: WidgetThemePalette { model.themeID.palette }
    private var np: NowPlayingInfo { displayedInfo }

    private var trackIdentityKey: String {
        "\(detector.nowPlaying.trackName)|\(detector.nowPlaying.artistName)|\(detector.nowPlaying.albumName)"
    }
    private var animatorTrackIdentityKey: String {
        [detector.nowPlaying.trackName, detector.nowPlaying.artistName, detector.nowPlaying.albumName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "|")
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
            LinearGradient(colors: theme.widgetBodyGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
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
                refreshArt(forceRefresh: false, updateDisplayed: true)
            }
        }
        .onDisappear {
            guard !isPreview else { return }
            detector.stop()
            animator.cancelAndReset()
        }
        .onChange(of: trackIdentityKey) { oldValue, newValue in
            guard !isPreview else { return }
            handleTrackIdentityChange(oldValue: oldValue, newValue: newValue)
        }
        .onChange(of: detector.nowPlaying) { _, live in
            guard !isPreview else { return }
            updateDisplayedPlaybackState(from: live)
        }
        .onChange(of: detector.nowPlaying.albumArtURL) { _, newURL in
            guard !isPreview else { return }
            if let url = newURL {
                artFetcher.fetchArt(from: url, trackKey: trackIdentityKey, forceRefresh: false) { image in
                    guard let image else { return }
                    bufferedIncomingArt = image
                    if animator.isAnimating {
                        animator.updateIncomingAlbumArtIfPossible(image, identityKey: animatorTrackIdentityKey)
                    } else {
                        displayedArt = image
                    }
                }
            } else if detector.nowPlaying.trackName.isEmpty {
                artFetcher.fetchArt(from: "", trackKey: "", forceRefresh: true) { _ in
                    bufferedIncomingArt = nil
                    displayedArt = nil
                }
            }
        }
        .onChange(of: animator.revealEventID) { _, eventID in
            guard eventID != nil, let snapshot = animator.revealedIncomingSnapshot else { return }
            displayedInfo = NowPlayingInfo(
                trackName: snapshot.trackName,
                artistName: snapshot.artistName,
                albumName: snapshot.albumName,
                albumArtURL: detector.nowPlaying.albumArtURL,
                isPlaying: detector.nowPlaying.isPlaying,
                source: detector.nowPlaying.source,
                positionMillis: detector.nowPlaying.positionMillis,
                durationMillis: detector.nowPlaying.durationMillis,
                progressSampledAt: detector.nowPlaying.progressSampledAt
            )
            displayedArt = snapshot.albumArt ?? bufferedIncomingArt ?? artFetcher.albumArt
        }
    }

    // MARK: - Track transition (drives the same SongSwitchAnimator the main widget uses)

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
            animator.cancelAndReset()
            displayedInfo = live
            displayedArt = nil
            bufferedIncomingArt = nil
            return
        }

        let isInitialTrack = oldValue.isEmpty || displayedInfo.trackName.isEmpty
        if isInitialTrack {
            displayedInfo = live
            refreshArt(forceRefresh: true, updateDisplayed: true)
            return
        }

        guard live.isPlaying else {
            displayedInfo = live
            return
        }

        let outgoingSnapshot = SongSwitchAnimator.TrackSnapshot(
            trackName: displayedInfo.trackName,
            artistName: displayedInfo.artistName,
            albumName: displayedInfo.albumName,
            albumArt: displayedArt
        )
        let incomingSnapshot = SongSwitchAnimator.TrackSnapshot(
            trackName: live.trackName,
            artistName: live.artistName,
            albumName: live.albumName,
            albumArt: bufferedIncomingArt ?? artFetcher.albumArt
        )
        let request = SongSwitchAnimator.TransitionRequest(
            outgoing: outgoingSnapshot,
            incoming: incomingSnapshot,
            widgetFrameInScreen: widgetFrameInScreen(),
            platterCenterInScreen: platterCenterInScreen()
        )
        animator.startTransition(request)
        refreshArt(forceRefresh: true, updateDisplayed: false)
    }

    private func updateDisplayedPlaybackState(from live: NowPlayingInfo) {
        guard !animator.isAnimating else { return }
        displayedInfo = live
    }

    private func refreshArt(forceRefresh: Bool, updateDisplayed: Bool) {
        let artURL = detector.nowPlaying.albumArtURL ?? ""
        artFetcher.fetchArt(from: artURL, trackKey: trackIdentityKey, forceRefresh: forceRefresh) { image in
            guard let image else { return }
            bufferedIncomingArt = image
            if updateDisplayed {
                displayedArt = image
            } else if animator.isAnimating {
                animator.updateIncomingAlbumArtIfPossible(image, identityKey: animatorTrackIdentityKey)
            }
        }
    }

    private func togglePlayback() {
        guard !isPreview else { return }
        detector.togglePlayback()
    }

    // MARK: - Screen geometry (feeds the shared song-switch animator)

    /// Only one WidgetWindow exists at a time (one-widget-at-a-time is
    /// enforced by AppDelegate), so this is unambiguous even though the
    /// vertical widget uses the same window class.
    private func widgetFrameInScreen() -> CGRect {
        if let frame = NSApp.windows.first(where: { $0 is WidgetWindow })?.frame {
            return frame
        }
        return CGRect(x: 0, y: 0, width: horizontalBaseSize.width, height: horizontalBaseSize.height)
    }

    /// Unlike the vertical widget (disc centered in the window), the disc
    /// here sits in the left column, so this is computed from the actual
    /// layout instead of just frame.mid. leftInset/discCenterLocal mirror
    /// the constants used in `discArea` below.
    private func platterCenterInScreen() -> CGPoint {
        let frame = widgetFrameInScreen()
        let scale = frame.width / horizontalBaseSize.width
        let discCenterLocal = CGPoint(x: 12 + hDiscContainerSize / 2, y: horizontalBaseSize.height / 2)
        return CGPoint(
            x: frame.minX + discCenterLocal.x * scale,
            y: frame.maxY - discCenterLocal.y * scale
        )
    }

    // MARK: - Disc + tonearm (left side) — exact reuse, uniformly scaled

    private var discArea: some View {
        ZStack {
            SpinningVinylView(
                isPlaying: displayedInfo.isPlaying,
                albumArt: displayedArt,
                vinylTint: theme.albumArtLabelGradient.first ?? Color(hex: "9B5523"),
                isVisible: true,
                diskOpacity: animator.widgetDiskOpacity,
                freezeRotation: animator.platterRotationFrozen,
                overrideAlbumArt: animator.diskArtMode == .incoming
                    ? (animator.incomingAlbumArt ?? bufferedIncomingArt)
                    : nil,
                albumArtLabelGradient: theme.albumArtLabelGradient,
                albumArtRingColor: theme.albumArtRingColor
            )
            .scaleEffect(hDiscScale)
            .frame(width: 272 * hDiscScale, height: 272 * hDiscScale)

            hTonearm
                .scaleEffect(hDiscScale)
                .frame(width: 90 * hDiscScale, height: 180 * hDiscScale)
                // Same proportional placement as the main widget's tonearm
                // relative to its disc (offset 115,-84 on a 272pt disc),
                // just carried over at this scale rather than eyeballed fresh.
                .offset(x: 272 * hDiscScale * 0.42, y: -272 * hDiscScale * 0.31)
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
        }
        .frame(width: 90, height: 180)
    }

    // MARK: - Track info + controls (right side)

    private var trackText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(np.trackName.isEmpty ? "Nothing Playing" : np.trackName)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(theme.trackTitle)
                .lineLimit(1)
                .truncationMode(.tail)
            if !np.artistName.isEmpty {
                Text(np.artistName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.trackArtist)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transportRow: some View {
        HStack(spacing: 18) {
            transportButton("backward.fill", size: 13) { detector.previousTrack() }
            transportButton(np.isPlaying ? "pause.fill" : "play.fill", size: 15) { togglePlayback() }
            transportButton("forward.fill", size: 13) { detector.nextTrack() }
        }
    }

    private func transportButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(theme.trackTitle)
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
                    .foregroundStyle(theme.trackArtist)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.trackArtist.opacity(0.25))
                        Capsule().fill(theme.trackTitle)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 3)
                Text("-" + formatTime(remainingMillis(at: context.date)))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.trackArtist)
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

// MARK: - Scaled overlay (song-switch animation), matching ScaledOverlayView's
// pattern for the vertical widget — combines the disc-scale factor (this
// widget's disc is uniformly smaller than the main widget's) with the
// global small/medium/large size setting, so the flying sleeve/disk render
// at the same visual size as this widget's own resting disc.

struct HorizontalScaledOverlayView: View {
    @ObservedObject var animator: SongSwitchAnimator
    @ObservedObject var sizeManager: WidgetSizeManager

    var body: some View {
        AnimationOverlayView(animator: animator)
            .scaleEffect(hDiscScale * sizeManager.scale, anchor: .center)
    }
}

// MARK: - Sized root (applies the global small/medium/large scale)

struct VinylHorizontalSizedRoot: View {
    let model: VinylHorizontalModel
    @ObservedObject var animator: SongSwitchAnimator
    @ObservedObject private var sizeM = WidgetSizeManager.shared

    var body: some View {
        let s = sizeM.scale
        VinylHorizontalWidgetView(model: model, animator: animator)
            .scaleEffect(s)
            .frame(width: horizontalBaseSize.width * s, height: horizontalBaseSize.height * s)
    }
}

// MARK: - Gallery preview (fit-scaled, flattened)

struct VinylHorizontalModelPreview: View {
    let model: VinylHorizontalModel

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / horizontalBaseSize.width, geo.size.height / horizontalBaseSize.height)
            VinylHorizontalWidgetView(model: model, isPreview: true)
                .frame(width: horizontalBaseSize.width, height: horizontalBaseSize.height)
                .scaleEffect(s)
                .frame(width: horizontalBaseSize.width * s, height: horizontalBaseSize.height * s)
                .frame(width: geo.size.width, height: geo.size.height)
                .drawingGroup()
        }
    }
}
