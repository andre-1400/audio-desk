import SwiftUI
import AppKit

// MARK: - On/off state
//
// Single source of truth for whether the notch widget is enabled — the
// gallery toggle reads/writes this directly (no AppDelegate round-trip
// needed), and AppDelegate observes it to create/destroy the actual window,
// the same way WidgetSettings/CustomColorManager drive their own effects
// elsewhere in this app.
final class NotchWidgetState: ObservableObject {
    static let shared = NotchWidgetState()
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "notchWidget.enabled") }
    }
    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "notchWidget.enabled")
    }
}

// MARK: - Notch detection
//
// auxiliaryTopLeftArea/auxiliaryTopRightArea are the public API Apple added
// specifically so apps can find the safe regions on either side of the
// camera-housing notch (2021+ MacBook Pro, 2022+ MacBook Air) — a screen
// only has them, and a non-zero safeAreaInsets.top, when it actually has a
// notch. No private API involved.

enum NotchDetector {
    static var hasNotch: Bool { notchedScreen != nil }

    static var notchedScreen: NSScreen? {
        NSScreen.screens.first {
            $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil
        }
    }

    /// The physical notch's own rect, in AppKit's bottom-left-origin screen
    /// coordinate space. This is an actual cutout in the display panel — no
    /// pixels exist there at all — so nothing rendered inside this rect can
    /// ever be seen; every layout in this file keeps drawn content below it
    /// rather than beside it (see NotchLayoutMetrics/NotchWidgetView).
    ///
    /// Width comes from the widely-used BoringNotch project's own formula
    /// (screen width minus both auxiliary areas' widths, +4) rather than
    /// `right.minX - left.maxX`, which is what this used originally — that
    /// version produced a gap spanning most of the screen. The two should
    /// be equivalent if both auxiliary rects sit flush against their
    /// respective screen edges, so evidently that assumption doesn't hold
    /// here; this is the field-tested version instead of another guess.
    static func notchFrame(on screen: NSScreen) -> CGRect? {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
              screen.safeAreaInsets.top > 0 else { return nil }
        let width = screen.frame.width - left.width - right.width + 4
        let height = screen.safeAreaInsets.top
        guard width > 0 else { return nil }
        return CGRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }
}

// MARK: - Layout metrics
//
// Modelled on how BoringNotch actually does this (a single fixed window,
// sized to the maximum/expanded footprint, created once and never moved or
// resized — see NotchWidgetWindow below) rather than the earlier approach
// here of animating the real NSWindow frame on hover, which is what made
// hover detection unreliable: a window's own frame changing size mid-
// animation is a much flakier hit-test target than a plain SwiftUI view
// whose drawn size animates within an already-large, static window.
struct NotchLayoutMetrics {
    let notch: CGRect
    let leftWidth: CGFloat = 90
    let rightWidth: CGFloat = 260
    let expandedHeight: CGFloat = 96

    var expandedWidth: CGFloat { leftWidth + notch.width + rightWidth }

    /// Idle's own, narrower flanking columns — using the full expanded
    /// width made the idle pill read as too long; this keeps the same
    /// "art left of the notch, bars right of the notch, explicit gap over
    /// it" structure but with much tighter columns, closer to how much
    /// room the reference actually gives the idle state.
    // Locked in at commit 9d27cba was 48/64/+14 — scaled down ~0.8x here
    // (proportionally, not independently) per feedback that it read as too
    // bulky overall.
    // Width reverted to 38/51 per feedback — that dimension read fine, it
    // was the *height* that was still cutting into other windows' UI in
    // that safe area (a browser tab strip). Cutting height further instead
    // of width this time.
    let idleLeftWidth: CGFloat = 38
    let idleRightWidth: CGFloat = 51
    var idleWidth: CGFloat { idleLeftWidth + notch.width + idleRightWidth }
    /// Only a little taller than the notch itself — this content sits
    /// beside the notch, not underneath it, so it doesn't need extra
    /// height to escape the cutout, just enough for a comfortably-sized
    /// icon.
    var idleHeight: CGFloat { notch.height }

    /// The one fixed window frame — big enough for the expanded state,
    /// centred on the notch, top edge flush with the screen's own top edge.
    var windowFrame: CGRect {
        CGRect(x: notch.midX - expandedWidth / 2, y: notch.maxY - expandedHeight,
               width: expandedWidth, height: expandedHeight)
    }
}

// MARK: - Window
//
// Independent of every other widget's window management — this one isn't
// part of the one-at-a-time exclusivity group (it's tiny, lives only at the
// very top of one specific screen, and is meant to run alongside whatever
// else is placed).
//
// Styling/behaviour here (style mask, window level, collection behaviour)
// mirrors the BoringNotch project's own window setup, since that's a
// widely-used, field-tested configuration for exactly this kind of
// always-on-every-space, above-the-menu-bar utility panel.
final class NotchWidgetWindow: NSPanel {
    init(metrics: NotchLayoutMetrics) {
        super.init(
            contentRect: metrics.windowFrame,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        // Above the menu bar — the expanded state needs to visually sit on
        // top of it, the same way iPhone's Dynamic Island covers the
        // status bar.
        level = NSWindow.Level(Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        hidesOnDeactivate = false
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Widget

struct NotchWidgetView: View {
    let metrics: NotchLayoutMetrics
    var isPreview: Bool = false
    var previewExpanded: Bool = false
    var previewInfo: NowPlayingInfo? = nil
    var previewArt: NSImage? = nil
    var previewColours: ExtractedColours? = nil

    @StateObject private var detector = MusicDetector()
    @StateObject private var artFetcher = AlbumArtFetcher()
    @State private var displayedInfo: NowPlayingInfo = .empty
    @State private var displayedArt: NSImage?
    @State private var extractedColours: ExtractedColours = .adaptivePreviewPlaceholder
    @State private var lastTrackKey = ""
    @State private var hovering = false

    private var np: NowPlayingInfo { isPreview ? (previewInfo ?? .empty) : displayedInfo }
    private var art: NSImage? { isPreview ? previewArt : displayedArt }
    private var colours: ExtractedColours { isPreview ? (previewColours ?? .adaptivePreviewPlaceholder) : extractedColours }
    private var waveColour: Color { colours.dominant }
    private var expanded: Bool { isPreview ? previewExpanded : hovering }
    private var isActive: Bool { !np.trackName.isEmpty }

    // Idle + nothing playing: literally nothing drawn or hit-testable, a
    // zero-size frame matching the real notch's own footprint exactly —
    // the background shape was previously drawn unconditionally regardless
    // of playback state, which made the notch look permanently, visibly
    // taller than it really is even with nothing playing.
    private var isVisible: Bool { expanded || isActive }

    var body: some View {
        ZStack {
            if isVisible {
                let shape = UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: expanded ? 18 : 10,
                    bottomTrailingRadius: expanded ? 18 : 10,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                // Idle stays plain black — small and meant to blend with
                // the real notch, not draw attention. Expanded tints
                // toward the playing track's own colours (dominant +
                // secondary) instead of flat black, the same "adaptive"
                // language every other widget in this app already uses,
                // rather than a fixed brand colour lifted from a reference.
                if expanded {
                    shape.fill(
                        LinearGradient(
                            colors: [colours.dominant.opacity(0.5), colours.secondary.opacity(0.35), Color.black.opacity(0.94)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .background(shape.fill(Color.black))
                } else {
                    shape.fill(Color.black)
                }
            }

            if expanded {
                // No top padding here: the art column and the info column
                // both sit entirely to the left/right of the notch's own
                // x-range (see expandedContent's layout), never underneath
                // it, so unlike the idle pill neither needs pushing down —
                // doing that anyway was eating into the vertical space
                // needed for title/artist/progress/transport, which is what
                // was clipping the transport row at the bottom.
                expandedContent
            } else if isActive {
                // Same reasoning as expandedContent now: art and the
                // equalizer bars sit in their own columns to the left/right
                // of an explicit notch-width gap, so neither is ever
                // actually under the cutout — no padding needed to dodge
                // it, and they can sit at the same height as the notch
                // itself instead of hanging in an overhang below it.
                idleContent
            }
        }
        .frame(
            width: expanded ? metrics.expandedWidth : (isActive ? metrics.idleWidth : 0),
            height: expanded ? metrics.expandedHeight : (isActive ? metrics.idleHeight : 0)
        )
        .contentShape(Rectangle())
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: expanded)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isActive)
        .onHover { isHovering in
            guard !isPreview else { return }
            hovering = isHovering
        }
        // maxHeight was missing here — without it, this view's actual
        // height stayed whatever the previous .frame(width:,height:) call
        // set (idleHeight, ~40-50pt), and since the window itself is
        // ALWAYS a fixed expandedHeight (96pt, never resized — see
        // NotchWidgetWindow's own doc comment), SwiftUI centred that
        // shorter content vertically within the full window instead of
        // anchoring it to the top. No amount of alignment tweaking inside
        // idleContent itself could have fixed that: the content was
        // correctly top-aligned within its own box, but that whole box
        // was floating in the middle of a much taller, unrelated canvas.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            guard !isPreview else { return }
            detector.start()
            displayedInfo = detector.nowPlaying
        }
        .onDisappear {
            guard !isPreview else { return }
            detector.stop()
        }
        .onChange(of: detector.nowPlaying) { _, live in
            guard !isPreview else { return }
            displayedInfo = live
            let key = "\(live.trackName)|\(live.artistName)|\(live.albumName)"
            guard key != lastTrackKey else { return }
            lastTrackKey = key
            guard let url = live.albumArtURL, !url.isEmpty else {
                displayedArt = nil
                extractedColours = .adaptivePreviewPlaceholder
                return
            }
            artFetcher.fetchArt(from: url, trackKey: key, forceRefresh: false) { image in
                displayedArt = image
                guard let image else { return }
                extractedColours = ColourExtractor.extract(from: image)
            }
        }
    }

    // MARK: - Idle: album art to the left of the notch, equalizer bars to
    // the right — flanking it at the same height, the way the reference
    // does, rather than both crammed together underneath it. Shown only
    // while something's actually playing — same restraint as iPhone's
    // Dynamic Island, no indicator at all when nothing's playing. Same
    // notch-width gap technique as expandedContent: the art and bars sit
    // in their own columns outside the notch's x-range entirely, so
    // neither needs padding to dodge the cutout.
    private var idleContent: some View {
        HStack(spacing: 0) {
            Group {
                if let art {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.15))
                }
            }
            // Filling the full idleHeight edge to edge, rather than a small
            // fixed 16pt icon floating in the middle of the available
            // height — makes the art actually read as art instead of a
            // tiny thumbnail, and it's the natural size ceiling here since
            // idleHeight is the tighter of the two dimensions to work with.
            .frame(width: metrics.idleHeight * 0.8, height: metrics.idleHeight * 0.8)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.leading, 6)
            .frame(width: metrics.idleLeftWidth)

            Color.clear.frame(width: metrics.notch.width)

            EqualizerBars(animating: isPreview ? true : np.isPlaying, color: waveColour)
                .frame(width: metrics.idleRightWidth)
        }
        // Explicitly top-aligned, rather than left to this HStack's default
        // vertical centring within idleHeight — centring is what was
        // still reading as "not raised up": if idleHeight ends up taller
        // than the content itself for any reason, centring drops it toward
        // the middle of that space instead of hugging the top edge, which
        // is where it needs to sit to actually read as flanking the notch.
        .frame(height: metrics.idleHeight, alignment: .top)
    }

    // MARK: - Expanded: art on the left, title/artist/progress/transport
    // stacked on the right.
    private var expandedContent: some View {
        HStack(spacing: 0) {
            Group {
                if let art {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.15))
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(width: metrics.leftWidth)

            Color.clear.frame(width: metrics.notch.width)

            HStack(spacing: 8) {
                VStack(spacing: 5) {
                    VStack(spacing: 1) {
                        Text(np.trackName.isEmpty ? "Nothing Playing" : np.trackName)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if !np.artistName.isEmpty {
                            Text(np.artistName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }

                    progressRow

                    HStack(spacing: 22) {
                        transportButton("backward.fill", size: 12) { if !isPreview { detector.previousTrack() } }
                        transportButton(np.isPlaying ? "pause.fill" : "play.fill", size: 15) { if !isPreview { detector.togglePlayback() } }
                        transportButton("forward.fill", size: 12) { if !isPreview { detector.nextTrack() } }
                    }
                }

                // Same decorative equalizer accent as the idle pill, tinted
                // the same way — a small visual echo on the expanded state
                // instead of the two looking unrelated.
                EqualizerBars(animating: isPreview ? true : np.isPlaying, color: waveColour)
            }
            .padding(.horizontal, 14)
            .frame(width: metrics.rightWidth)
        }
    }

    private var progressRow: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = np.durationMillis ?? 0
            let elapsed = elapsedMillis(at: context.date)
            let remaining = max(0, duration - elapsed)
            let fraction = duration > 0 ? min(1, max(0, Double(elapsed) / Double(duration))) : 0

            VStack(spacing: 2) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25)).frame(height: 3)
                        Capsule().fill(Color.white).frame(width: max(2, geo.size.width * fraction), height: 3)
                    }
                }
                .frame(height: 3)

                HStack {
                    Text(formatTime(elapsed))
                    Spacer()
                    Text("-" + formatTime(remaining))
                }
                .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
            }
        }
        .opacity((np.durationMillis ?? 0) > 0 ? 1 : 0)
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

    private func formatTime(_ millis: Int) -> String {
        let totalSeconds = millis / 1000
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func transportButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size + 12, height: size + 12)
                // A soft circular chip behind each icon instead of a bare
                // glyph floating on the background — reads as an actual
                // button, not just decoration.
                .background(Circle().fill(Color.white.opacity(0.12)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPreview)
    }
}

// MARK: - Idle equalizer glyph — a few bars bouncing at staggered, offset
// speeds while playing (frozen flat when paused), the "sound wave" look
// next to the small album art in the idle pill.
// Two attempts at this via SwiftUI's implicit .animation(_:value:) both
// still showed residual movement while paused — a repeatForever animation
// already in flight on the layer isn't reliably fully superseded just by
// changing what curve a later value change requests, no matter how that
// curve is spelled (a different one-shot curve, or even nil). Rebuilt
// without SwiftUI's animation system at all: TimelineView recomputes each
// bar's height directly from wall-clock time every tick while playing, and
// is literally `paused` (stops ticking) plus falls back to a hardcoded
// constant the instant `animating` is false — a plain conditional
// expression evaluated fresh each render, nothing left implicitly running
// that could keep nudging the value afterward.
private struct EqualizerBars: View {
    var animating: Bool = true
    var color: Color = .white

    private let barHeights: [CGFloat] = [5, 12, 8, 10]
    private let minHeight: CGFloat = 3
    // Paused: all bars drop to this same small height — motionless,
    // uniform, just barely there rather than invisible.
    private let pausedHeight: CGFloat = 2

    var body: some View {
        TimelineView(.animation(paused: !animating)) { context in
            // Bottom-aligned rather than centred — bars should read as
            // growing up from a shared baseline while playing, not
            // floating around a shared centre line, and it's what makes
            // the paused state actually look "low down" rather than
            // centred in the available height.
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(barHeights.indices, id: \.self) { i in
                    Capsule()
                        .fill(color.opacity(animating ? 0.85 : 0.4))
                        .frame(width: 2.6, height: animating ? height(for: i, at: context.date) : pausedHeight)
                }
            }
        }
        .frame(height: 14, alignment: .bottom)
    }

    /// A per-bar sine wave, each at its own speed/phase offset so they
    /// don't move in lockstep — sampled fresh from wall-clock time, no
    /// stored animation state to leave running.
    private func height(for index: Int, at date: Date) -> CGFloat {
        let speed = 3.4 + Double(index) * 0.7
        let phaseOffset = Double(index) * 1.4
        let wave = (sin(date.timeIntervalSinceReferenceDate * speed + phaseOffset) + 1) / 2
        return minHeight + wave * (barHeights[index] - minHeight)
    }
}

// MARK: - Gallery preview (fit-scaled, always shown expanded — a card too
// small to usefully hover, so it just shows what expanding looks like)
//
// Uses a stand-in notch width/position (no real notch involved in a
// preview thumbnail) purely so the shared NotchLayoutMetrics math has
// something to compute against.

struct NotchWidgetModelPreview: View {
    var animated: Bool = false
    @ObservedObject var live: GalleryLiveTrack = GalleryLiveTrack()

    private let previewMetrics = NotchLayoutMetrics(notch: CGRect(x: 0, y: 0, width: 180, height: 32))
    private let previewBaseSize = CGSize(width: 340, height: 90)

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / previewBaseSize.width, geo.size.height / previewBaseSize.height)
            NotchWidgetView(metrics: previewMetrics, isPreview: true, previewExpanded: animated,
                             previewInfo: live.info, previewArt: live.art, previewColours: live.colours)
                .frame(width: previewMetrics.expandedWidth, height: previewMetrics.expandedHeight)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .frame(width: previewBaseSize.width, height: previewBaseSize.height)
                .scaleEffect(s)
                .frame(width: previewBaseSize.width * s, height: previewBaseSize.height * s)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
