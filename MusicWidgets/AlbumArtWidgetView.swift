import SwiftUI
import AppKit

// MARK: - Gallery model
//
// A different kind of widget from Vinyl/CD on purpose: no physical device,
// no disc, no skeuomorphism — just the cover art (VinylPod-style minimalism),
// rendered nicely. Each size is a genuinely different layout, not a scaled
// copy of the same design.

enum AlbumArtSize: String, CaseIterable, Identifiable {
    case compact, circle, mini, card
    var id: String { rawValue }

    var baseSize: CGSize {
        switch self {
        case .compact: return CGSize(width: 220, height: 220)
        case .circle:  return CGSize(width: 200, height: 200)
        case .mini:    return CGSize(width: 280, height: 84)
        case .card:    return CGSize(width: 280, height: 360)
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
        AlbumArtModel(id: "albumart-circle", name: "Circle", subtitle: "Round art with a live progress ring", size: .circle),
        AlbumArtModel(id: "albumart-mini", name: "Mini", subtitle: "A glanceable info strip", size: .mini),
        AlbumArtModel(id: "albumart-card", name: "Card", subtitle: "Full-bleed art with controls", size: .card)
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

    @StateObject private var detector = MusicDetector()
    @StateObject private var artFetcher = AlbumArtFetcher()

    @State private var displayedArt: NSImage?
    @State private var displayedInfo: NowPlayingInfo = .empty

    // MARK: - Progress-bar scrubbing (Card layout only) — same scheme as
    // VinylWidgetView/VinylHorizontalWidgetView, duplicated rather than
    // shared per this codebase's convention of keeping each widget
    // self-contained.
    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0
    @State private var seekHandoffUntil: Date?
    private let seekHandoffSuppressionDuration = 0.45

    private var np: NowPlayingInfo { isPreview ? (previewInfo ?? .empty) : displayedInfo }
    private var art: NSImage {
        (isPreview ? previewArt : displayedArt) ?? FallbackCoverArtGenerator.fallbackImage
    }
    private var trackKey: String { "\(np.trackName)|\(np.artistName)" }

    var body: some View {
        Group {
            switch model.size {
            case .compact: compactLayout
            case .circle: circleLayout
            case .mini: miniLayout
            case .card: cardLayout
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
            if live.trackName != displayedInfo.trackName || live.artistName != displayedInfo.artistName {
                seekHandoffUntil = nil
            }
            guard !shouldSuppressSeekHandoffUpdate(from: live) else { return }
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
            // Explicit frame right at the image, before clipping — every
            // layout in this file pins its own art frame here rather than
            // relying on the outer body-level frame. Without this, one track
            // whose fetched art reported an unusual intrinsic size (e.g. a
            // non-square source image) briefly rendered at that image's own
            // proportions before the outer frame ever got a say, clipping
            // the rounded corners against the wrong rectangle.
            .frame(width: model.size.baseSize.width, height: model.size.baseSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .onTapGesture { togglePlayback() }
    }

    // MARK: - Circle (200x200) — round art + a live progress ring

    private var circleLayout: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let fraction = progressFraction(at: context.date)
            ZStack {
                artImage
                    .id(trackKey)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: trackKey)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 168, height: 168)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))

                // The one widget in the family that shows playback position
                // as a ring instead of a bar — there's no room for one here,
                // and it reads naturally against the round art.
                Circle()
                    .trim(from: 0, to: hasProgressData ? fraction : 0)
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 188, height: 188)
                    .animation(.linear(duration: 0.4), value: fraction)

                Circle()
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    .frame(width: 188, height: 188)
            }
            .frame(width: model.size.baseSize.width, height: model.size.baseSize.height)
            .contentShape(Circle())
            .onTapGesture { togglePlayback() }
        }
    }

    // MARK: - Mini (280x84) — a glanceable horizontal strip

    private var miniLayout: some View {
        HStack(spacing: 14) {
            artImage
                .id(trackKey)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: trackKey)
                .aspectRatio(1, contentMode: .fill)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture { togglePlayback() }

            VStack(alignment: .leading, spacing: 2) {
                Text(np.trackName.isEmpty ? "Nothing Playing" : np.trackName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !np.artistName.isEmpty {
                    Text(np.artistName)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Play/pause only — no skip buttons — keeps this the smallest,
            // most glanceable member of the family, distinct from Card's
            // full transport row.
            transportButton(np.isPlaying ? "pause.fill" : "play.fill", size: 17, prominent: true) {
                togglePlayback()
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 18)
        .padding(.vertical, 12)
        .frame(width: model.size.baseSize.width, height: model.size.baseSize.height)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.62))
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Card (280x360) — full-bleed art + info + controls

    private var cardLayout: some View {
        ZStack(alignment: .bottom) {
            // The art itself IS the background now — full-bleed and sharp,
            // no blur — instead of a small inset square over a flat colour
            // gradient. Tapping anywhere on it toggles playback.
            artImage
                .id(trackKey)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: trackKey)
                .aspectRatio(contentMode: .fill)
                .frame(width: model.size.baseSize.width, height: model.size.baseSize.height)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { togglePlayback() }

            // Scrim only where the UI actually sits, fading to clear above
            // it — keeps the art readable up top instead of darkening the
            // whole card the way a full-frame overlay would.
            LinearGradient(
                colors: [.clear, .black.opacity(0.30), .black.opacity(0.74)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 190)
            .allowsHitTesting(false)

            VStack(spacing: 3) {
                Text(np.trackName.isEmpty ? "Nothing Playing" : np.trackName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.tail)
                if !np.artistName.isEmpty {
                    Text(np.artistName)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.tail)
                }

                // Preview cards show these purely for looks — cosmetic
                // only, never wired to real transport commands.
                HStack(spacing: 26) {
                    transportButton("backward.fill", size: 15) { if !isPreview { detector.previousTrack() } }
                    transportButton(np.isPlaying ? "pause.fill" : "play.fill", size: 20, prominent: true) { togglePlayback() }
                    transportButton("forward.fill", size: 15) { if !isPreview { detector.nextTrack() } }
                }
                .padding(.top, 10)

                cardScrubBar
                    .padding(.top, 12)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 20)
        }
        .frame(width: model.size.baseSize.width, height: model.size.baseSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    /// Small, minimal, and — unlike the plain ProgressStrip used elsewhere —
    /// interactive: drag anywhere on it to seek. Same NSView drag-capture
    /// scheme as the vinyl widgets' own scrub bars (the widget window is
    /// movable-by-background, so a plain SwiftUI DragGesture would drag the
    /// whole widget instead of seeking).
    private var cardScrubBar: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let fraction = isScrubbing ? scrubProgress : progressFraction(at: context.date)
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25)).frame(height: isScrubbing ? 5 : 3)
                    Capsule().fill(Color.white).frame(width: max(2, width * fraction), height: isScrubbing ? 5 : 3)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 9, height: 9)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .offset(x: min(width - 9, max(0, width * fraction - 4.5)))
                        .opacity(isScrubbing ? 1 : 0)
                }
                .frame(height: 16)
                .overlay {
                    if !isPreview {
                        AlbumArtScrubDragCaptureView(
                            onBegan: { handleScrubDrag(fraction: $0.x / width) },
                            onMoved: { handleScrubDrag(fraction: $0.x / width) },
                            onEnded: {
                                handleScrubDrag(fraction: $0.x / width)
                                commitScrub()
                            },
                            onCancelled: { endScrubSession() }
                        )
                    }
                }
            }
            .frame(height: 16)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isScrubbing)
        }
        .opacity(hasProgressData ? 1 : 0)
    }

    private var hasProgressData: Bool {
        !np.trackName.isEmpty && (np.durationMillis ?? 0) > 0
    }

    private var canSeek: Bool {
        !isPreview &&
            !displayedInfo.trackName.isEmpty &&
            displayedInfo.source != .none &&
            (displayedInfo.durationMillis ?? 0) > 0
    }

    private func progressFraction(at date: Date) -> Double {
        guard let dur = np.durationMillis, dur > 0, let pos = np.positionMillis else { return 0 }
        var elapsed = Double(pos)
        if np.isPlaying, let sampledAt = np.progressSampledAt {
            elapsed += date.timeIntervalSince(sampledAt) * 1000
        }
        return min(1, max(0, elapsed / Double(dur)))
    }

    private func handleScrubDrag(fraction: Double) {
        guard canSeek else { return }
        if !isScrubbing {
            setWidgetBackgroundDraggingEnabled(false)
            isScrubbing = true
        }
        scrubProgress = min(1, max(0, fraction))
    }

    private func commitScrub() {
        defer { endScrubSession() }
        guard isScrubbing else { return }
        commitSeek(toProgress: scrubProgress)
    }

    private func endScrubSession() {
        isScrubbing = false
        setWidgetBackgroundDraggingEnabled(true)
    }

    private func setWidgetBackgroundDraggingEnabled(_ enabled: Bool) {
        guard let window = NSApp.windows.first(where: { $0 is WidgetWindow }) else { return }
        window.isMovableByWindowBackground = enabled
    }

    /// Optimistically move the displayed position so the UI doesn't snap
    /// back while the player catches up, then tell the player.
    private func commitSeek(toProgress progress: Double) {
        guard canSeek, let durationMillis = displayedInfo.durationMillis else { return }

        let targetMillis = Int((progress * Double(durationMillis)).rounded())
        let sampledAt = displayedInfo.isPlaying ? Date() : nil
        seekHandoffUntil = Date().addingTimeInterval(seekHandoffSuppressionDuration)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            displayedInfo = NowPlayingInfo(
                trackName: displayedInfo.trackName,
                artistName: displayedInfo.artistName,
                albumName: displayedInfo.albumName,
                albumArtURL: displayedInfo.albumArtURL,
                isPlaying: displayedInfo.isPlaying,
                source: displayedInfo.source,
                positionMillis: targetMillis,
                durationMillis: displayedInfo.durationMillis,
                progressSampledAt: sampledAt
            )
        }
        detector.seek(toMillis: targetMillis)
    }

    /// Suppresses exactly one stale post-seek poll from snapping the
    /// optimistic position back down before the player's own seek lands.
    private func shouldSuppressSeekHandoffUpdate(from live: NowPlayingInfo) -> Bool {
        guard let seekHandoffUntil else { return false }
        let now = Date()
        guard now < seekHandoffUntil else {
            self.seekHandoffUntil = nil
            return false
        }
        if live.isPlaying != displayedInfo.isPlaying {
            self.seekHandoffUntil = nil
            return false
        }
        return true
    }

    // Bare glyphs, no button-cap background — matches Apple Music's own
    // mini-player exactly: play/pause reads bigger and fully opaque white,
    // skip buttons smaller and muted.
    private func transportButton(_ symbol: String, size: CGFloat, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : Color.white.opacity(0.65))
                .frame(width: prominent ? 46 : 36, height: prominent ? 46 : 36)
                .contentShape(Rectangle())
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

/// Raw AppKit drag surface backing the Card layout's scrub bar — duplicated
/// from the vinyl widgets' own (private, file-scoped) capture views rather
/// than shared, per this codebase's convention of keeping each widget
/// self-contained. The widget window is movable-by-background, and AppKit
/// decides that at mouse-down — too early for a SwiftUI gesture callback to
/// veto, so a plain DragGesture here would drag the whole widget instead.
private struct AlbumArtScrubDragCaptureView: NSViewRepresentable {
    var onBegan: (CGPoint) -> Void
    var onMoved: (CGPoint) -> Void
    var onEnded: (CGPoint) -> Void
    var onCancelled: () -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onBegan = onBegan
        view.onMoved = onMoved
        view.onEnded = onEnded
        view.onCancelled = onCancelled
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onBegan = onBegan
        nsView.onMoved = onMoved
        nsView.onEnded = onEnded
        nsView.onCancelled = onCancelled
    }

    final class CaptureView: NSView {
        var onBegan: ((CGPoint) -> Void)?
        var onMoved: ((CGPoint) -> Void)?
        var onEnded: ((CGPoint) -> Void)?
        var onCancelled: (() -> Void)?

        private var isTrackingPress = false

        override var isFlipped: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func mouseDown(with event: NSEvent) {
            isTrackingPress = true
            window?.isMovableByWindowBackground = false
            onBegan?(localPoint(from: event))
        }

        override func mouseDragged(with event: NSEvent) {
            guard isTrackingPress else { return }
            onMoved?(localPoint(from: event))
        }

        override func mouseUp(with event: NSEvent) {
            guard isTrackingPress else { return }
            isTrackingPress = false
            onEnded?(localPoint(from: event))
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil, isTrackingPress {
                isTrackingPress = false
                onCancelled?()
            }
            super.viewWillMove(toWindow: newWindow)
        }

        private func localPoint(from event: NSEvent) -> CGPoint {
            convert(event.locationInWindow, from: nil)
        }
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
                previewInfo: live.info, previewArt: live.art
            )
                .frame(width: base.width, height: base.height)
                .scaleEffect(s)
                .frame(width: base.width * s, height: base.height * s)
                .frame(width: geo.size.width, height: geo.size.height)
                .drawingGroup()   // static preview — flatten into one cached texture
        }
    }
}
