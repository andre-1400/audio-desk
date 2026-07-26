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
    /// How far the closed pill hangs below the real notch — the only part
    /// of it that's actually visible, since its top (matching the notch's
    /// own row) sits over the display cutout and can't be seen regardless
    /// of what's drawn there.
    let closedOverhang: CGFloat = 36

    var closedHeight: CGFloat { notch.height + closedOverhang }
    var expandedWidth: CGFloat { leftWidth + notch.width + rightWidth }

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

    @StateObject private var detector = MusicDetector()
    @StateObject private var artFetcher = AlbumArtFetcher()
    @State private var displayedInfo: NowPlayingInfo = .empty
    @State private var displayedArt: NSImage?
    @State private var lastTrackKey = ""
    @State private var hovering = false

    private var np: NowPlayingInfo { isPreview ? (previewInfo ?? .empty) : displayedInfo }
    private var art: NSImage? { isPreview ? previewArt : displayedArt }
    private var expanded: Bool { isPreview ? previewExpanded : hovering }
    private var isActive: Bool { !np.trackName.isEmpty }

    // Idle + nothing playing: literally nothing drawn or hit-testable, a
    // zero-size frame matching the real notch's own footprint exactly —
    // the background shape was previously drawn unconditionally at
    // closedHeight (notch height + overhang) regardless of playback state,
    // which is what made the notch look permanently, visibly taller than
    // it really is even with nothing playing.
    private var isVisible: Bool { expanded || isActive }

    var body: some View {
        ZStack {
            if isVisible {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: expanded ? 18 : 10,
                    bottomTrailingRadius: expanded ? 18 : 10,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(Color.black)
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
                // The closed pill's width matches the notch exactly, so
                // anything drawn in it genuinely does sit under the cutout
                // at the top — this one does need the padding. Explicitly
                // framed to just the overhang band (rather than left to
                // ZStack's default centring against the whole closedHeight,
                // which was sitting lower than necessary) and top-aligned
                // within it, so the art/bars sit as high as they safely can
                // — right at the edge of the invisible line, not centred
                // deeper into the visible strip below it.
                idleContent
                    .frame(width: metrics.notch.width, height: metrics.closedOverhang, alignment: .top)
                    .padding(.top, metrics.notch.height)
            }
        }
        .frame(
            width: expanded ? metrics.expandedWidth : (isActive ? metrics.notch.width : 0),
            height: expanded ? metrics.expandedHeight : (isActive ? metrics.closedHeight : 0)
        )
        .contentShape(Rectangle())
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: expanded)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isActive)
        .onHover { isHovering in
            guard !isPreview else { return }
            hovering = isHovering
        }
        .frame(maxWidth: .infinity, alignment: .top)
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
                return
            }
            artFetcher.fetchArt(from: url, trackKey: key, forceRefresh: false) { image in
                displayedArt = image
            }
        }
    }

    // MARK: - Idle: a small waveform glyph in the overhang below the
    // notch, shown only while something's actually playing — same
    // restraint as iPhone's Dynamic Island, no indicator at all when
    // nothing's playing.
    private var idleContent: some View {
        HStack(spacing: 4) {
            Group {
                if let art {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.15))
                }
            }
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            Spacer(minLength: 8)

            EqualizerBars(animating: isPreview ? true : np.isPlaying)
        }
        // A previous pass here made this proportional to notch.width
        // instead of a fixed inset, on the theory that padding was
        // constraining the gap — it wasn't (the Spacer already expands to
        // fill whatever's left regardless), so that change was invisible.
        // Cut to a small fixed inset instead, freeing up as much width as
        // possible for the Spacer to actually use.
        .padding(.horizontal, 4)
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPreview)
    }
}

// MARK: - Idle equalizer glyph — a few bars bouncing at staggered, offset
// speeds while playing (frozen flat when paused), the "sound wave" look
// next to the small album art in the idle pill.
private struct EqualizerBars: View {
    var animating: Bool = true

    @State private var phase = false

    private let barHeights: [CGFloat] = [7, 16, 10, 13]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(barHeights.indices, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 2.2, height: animating && phase ? barHeights[i] : 3)
                    .animation(
                        .easeInOut(duration: 0.42 + Double(i) * 0.08)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.11),
                        value: phase
                    )
            }
        }
        .frame(height: 18)
        .onAppear { phase = animating }
        .onChange(of: animating) { _, isAnimating in phase = isAnimating }
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
                             previewInfo: live.info, previewArt: live.art)
                .frame(width: previewMetrics.expandedWidth, height: previewMetrics.expandedHeight)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .frame(width: previewBaseSize.width, height: previewBaseSize.height)
                .scaleEffect(s)
                .frame(width: previewBaseSize.width * s, height: previewBaseSize.height * s)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
