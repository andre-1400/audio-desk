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
        case .mini:    return CGSize(width: 360, height: 84)
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
    var previewExtracted: ExtractedColours? = nil

    @StateObject private var detector = MusicDetector()
    @StateObject private var artFetcher = AlbumArtFetcher()

    @State private var displayedArt: NSImage?
    @State private var displayedInfo: NowPlayingInfo = .empty
    // Card/Circle sit text and controls directly on top of the album art,
    // so — same as every adaptive vinyl/CD style — the art's own dominant
    // colour decides whether they read as light or dark text.
    @State private var extracted: ExtractedColours = .fallback

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
    private var effectiveExtracted: ExtractedColours {
        isPreview ? (previewExtracted ?? .fallback) : extracted
    }
    private var trackKey: String { "\(np.trackName)|\(np.artistName)" }

    // MARK: - Adaptive text/control colour (Card + Circle)
    //
    // Same formula AdaptiveBody.isLight uses (perceived brightness against a
    // 0.48 threshold — already checked against WCAG contrast across a
    // spread of cover colours), but parametrised per layout's own scrim
    // strength instead of that shared helper's fixed 0.40 darkening, which
    // matches neither of these: Circle sits directly on raw art with no
    // scrim at all, and Card's bottom scrim is considerably stronger.

    private func isLightSurface(darkening: Double) -> Bool {
        effectiveExtracted.dominant.perceivedBrightness * (1 - darkening) > 0.48
    }

    /// Card's scrim ranges 0 -> 0.74 top-to-bottom. 0.55 here was a bug, not
    /// just an over-estimate: perceived brightness tops out at 1.0, so
    /// `1.0 * (1 - 0.55) = 0.45` could never clear the 0.48 threshold — dark
    /// text was mathematically unreachable no matter how white the art was,
    /// which is exactly what got reported. 0.15 is a real, achievable
    /// darkening estimate for the (much lighter, gradient-fading) band the
    /// text/controls actually sit in.
    private var cardIsLight: Bool { isLightSurface(darkening: 0.15) }
    private var cardPrimary: Color { cardIsLight ? Color.black.opacity(0.88) : .white }
    private var cardSecondary: Color { cardIsLight ? Color.black.opacity(0.58) : Color.white.opacity(0.72) }
    /// The scrim itself flips too — a black scrim under dark text would
    /// fight the very contrast it's meant to protect.
    private var cardScrimColor: Color { cardIsLight ? .white : .black }

    /// No scrim at all under Circle's ring — it sits right on the raw art.
    private var circleIsLight: Bool { isLightSurface(darkening: 0) }
    private var circlePrimary: Color { circleIsLight ? Color.black.opacity(0.85) : Color.white.opacity(0.9) }
    private var circleSecondary: Color { circleIsLight ? Color.black.opacity(0.35) : Color.white.opacity(0.10) }

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

    /// Radius of the art disc — also the inner edge of the drag-to-seek
    /// ring band, so a tap on the art (play/pause) and a drag on the ring
    /// (seek) never fight over the same pixels.
    private let circleArtRadius: CGFloat = 84
    /// Outer edge of the drag-to-seek band — a little past the visible ring
    /// (188pt diameter / 94pt radius) so it stays easy to grab.
    private let circleDragOuterRadius: CGFloat = 100

    private var circleLayout: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let fraction = isScrubbing ? scrubProgress : progressFraction(at: context.date)
            ZStack {
                artImage
                    .id(trackKey)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: trackKey)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: circleArtRadius * 2, height: circleArtRadius * 2)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(circleSecondary.opacity(0.6), lineWidth: 1))
                    .contentShape(Circle())
                    .onTapGesture { togglePlayback() }

                // The one widget in the family that shows playback position
                // as a ring instead of a bar — there's no room for one here,
                // and it reads naturally against the round art. Drag
                // anywhere on the ring band to seek.
                Circle()
                    .trim(from: 0, to: hasProgressData ? fraction : 0)
                    .stroke(circlePrimary, style: StrokeStyle(lineWidth: isScrubbing ? 4 : 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 188, height: 188)
                    .animation(isScrubbing ? nil : .linear(duration: 0.4), value: fraction)

                Circle()
                    .strokeBorder(circleSecondary, lineWidth: 1)
                    .frame(width: 188, height: 188)

                if isScrubbing {
                    let angle = fraction * 2 * .pi - .pi / 2
                    Circle()
                        .fill(circlePrimary)
                        .frame(width: 11, height: 11)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .offset(x: cos(angle) * 94, y: sin(angle) * 94)
                }
            }
            .frame(width: model.size.baseSize.width, height: model.size.baseSize.height)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isScrubbing)
            .overlay {
                if !isPreview {
                    AlbumArtRingDragCaptureView(
                        innerRadius: circleArtRadius,
                        outerRadius: circleDragOuterRadius,
                        onBegan: { handleCircularScrubDrag($0, canvasSize: model.size.baseSize.width) },
                        onMoved: { handleCircularScrubDrag($0, canvasSize: model.size.baseSize.width) },
                        onEnded: {
                            handleCircularScrubDrag($0, canvasSize: model.size.baseSize.width)
                            commitScrub()
                        },
                        onCancelled: { endScrubSession() }
                    )
                }
            }
        }
    }

    // MARK: - Mini (280x84) — a glanceable horizontal strip

    private var miniLayout: some View {
        HStack(spacing: 12) {
            artImage
                .id(trackKey)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: trackKey)
                .aspectRatio(1, contentMode: .fill)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture { togglePlayback() }

            // Was truncating to 2-3 characters on most real track names —
            // the transport buttons' tap targets (46/36pt, sized for the
            // much bigger Card) were eating most of the width on a strip
            // this compact. Given real room here instead of a smaller font,
            // which would've just made the same truncation harder to read.
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

            // Full back/play-pause/skip trio, same Apple Music hierarchy as
            // everywhere else in the app — play/pause bigger and fully
            // opaque, skips smaller and muted — but with tap targets sized
            // for this strip instead of Card's much bigger ones. Preview
            // cards show these purely for looks — cosmetic only, never
            // wired to real transport commands.
            HStack(spacing: 6) {
                transportButton("backward.fill", size: 12, tapTarget: 24) { if !isPreview { detector.previousTrack() } }
                transportButton(np.isPlaying ? "pause.fill" : "play.fill", size: 16, prominent: true, tapTarget: 32) { togglePlayback() }
                transportButton("forward.fill", size: 12, tapTarget: 24) { if !isPreview { detector.nextTrack() } }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
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
            // whole card the way a full-frame overlay would. Lightens
            // instead of darkens on light art, so dark text still gets a
            // scrim working *for* it instead of a black one fighting it.
            LinearGradient(
                colors: [.clear, cardScrimColor.opacity(0.30), cardScrimColor.opacity(0.74)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 190)
            .allowsHitTesting(false)

            VStack(spacing: 3) {
                Text(np.trackName.isEmpty ? "Nothing Playing" : np.trackName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(cardPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.tail)
                if !np.artistName.isEmpty {
                    Text(np.artistName)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(cardSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.tail)
                }

                // Preview cards show these purely for looks — cosmetic
                // only, never wired to real transport commands.
                HStack(spacing: 26) {
                    transportButton("backward.fill", size: 15, primaryColor: cardPrimary, secondaryColor: cardSecondary) {
                        if !isPreview { detector.previousTrack() }
                    }
                    transportButton(np.isPlaying ? "pause.fill" : "play.fill", size: 20, prominent: true,
                                     primaryColor: cardPrimary, secondaryColor: cardSecondary) { togglePlayback() }
                    transportButton("forward.fill", size: 15, primaryColor: cardPrimary, secondaryColor: cardSecondary) {
                        if !isPreview { detector.nextTrack() }
                    }
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
                    Capsule().fill(cardSecondary.opacity(0.4)).frame(height: isScrubbing ? 5 : 3)
                    Capsule().fill(cardPrimary).frame(width: max(2, width * fraction), height: isScrubbing ? 5 : 3)
                    Circle()
                        .fill(cardPrimary)
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

    /// Same scrub session as handleScrubDrag, just fed by an angle around
    /// the circle's centre (measured clockwise from 12 o'clock) instead of
    /// an x-position — Circle has no straight bar to drag along.
    private func handleCircularScrubDrag(_ point: CGPoint, canvasSize: CGFloat) {
        guard canSeek else { return }
        if !isScrubbing {
            setWidgetBackgroundDraggingEnabled(false)
            isScrubbing = true
        }
        let center = CGPoint(x: canvasSize / 2, y: canvasSize / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }
        scrubProgress = min(1, max(0, angle / (2 * .pi)))
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
    // mini-player exactly: play/pause reads bigger and fully opaque, skip
    // buttons smaller and muted. Defaults to white/white-muted for layouts
    // with a fixed dark background (Mini); Card passes its own adaptive
    // colours since it sits directly on the art.
    private func transportButton(
        _ symbol: String, size: CGFloat, prominent: Bool = false,
        primaryColor: Color = .white, secondaryColor: Color = .white.opacity(0.65),
        tapTarget: CGFloat? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let target = tapTarget ?? (prominent ? 46 : 36)
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(prominent ? primaryColor : secondaryColor)
                .frame(width: target, height: target)
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

/// Drag surface for Circle's ring: only claims an annular band (between
/// innerRadius and outerRadius from centre) instead of its whole bounds, so
/// taps on the inner art disc fall through to the SwiftUI tap gesture below
/// instead of being swallowed by this view — the ring (seek) and the art
/// (play/pause) sit on top of each other but need to stay independently
/// tappable/draggable.
private struct AlbumArtRingDragCaptureView: NSViewRepresentable {
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    var onBegan: (CGPoint) -> Void
    var onMoved: (CGPoint) -> Void
    var onEnded: (CGPoint) -> Void
    var onCancelled: () -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: CaptureView) {
        view.innerRadius = innerRadius
        view.outerRadius = outerRadius
        view.onBegan = onBegan
        view.onMoved = onMoved
        view.onEnded = onEnded
        view.onCancelled = onCancelled
    }

    final class CaptureView: NSView {
        var innerRadius: CGFloat = 0
        var outerRadius: CGFloat = 0
        var onBegan: ((CGPoint) -> Void)?
        var onMoved: ((CGPoint) -> Void)?
        var onEnded: ((CGPoint) -> Void)?
        var onCancelled: (() -> Void)?

        private var isTrackingPress = false

        override var isFlipped: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point) else { return nil }
            // Once a drag is underway, keep capturing even if the pointer
            // drifts inside the inner radius — a fast drag toward centre
            // shouldn't drop the gesture mid-scrub.
            if isTrackingPress { return self }
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let distance = hypot(point.x - center.x, point.y - center.y)
            return (distance >= innerRadius && distance <= outerRadius) ? self : nil
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
