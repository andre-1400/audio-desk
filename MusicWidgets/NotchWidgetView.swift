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
    /// pixels exist there at all, not just an area macOS avoids drawing
    /// into — so nothing rendered inside this rect can ever be seen. Every
    /// layout in this file treats it as a hard gap, never as drawable space.
    /// nil if this screen has no notch.
    static func notchFrame(on screen: NSScreen) -> CGRect? {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
              screen.safeAreaInsets.top > 0, right.minX > left.maxX else { return nil }
        let width = right.minX - left.maxX
        let height = screen.safeAreaInsets.top
        return CGRect(x: left.maxX, y: screen.frame.maxY - height, width: width, height: height)
    }
}

// MARK: - Layout metrics
//
// One shared source for both the window's frames and the SwiftUI content's
// piece widths, so they can never disagree about where the notch's dead
// zone actually is.
struct NotchLayoutMetrics {
    let notch: CGRect
    let leftWidth: CGFloat = 74
    let rightWidth: CGFloat = 250
    /// Width of the *visible* idle pill, drawn only in the sliver right of
    /// the notch — separate from the idle window's actual (much larger)
    /// hit-testable frame below.
    let idleVisibleWidth: CGFloat = 26
    let expandedHeight: CGFloat = 78

    /// Idle window spans the notch's *entire* width plus the visible
    /// sliver to its right — a window occupying that geometry still gets
    /// mouse/hover events perfectly normally even though nothing drawn
    /// over the notch itself is visible, so this makes "hover anywhere
    /// near/over the notch" reliably trigger expansion instead of only a
    /// thin strip off to one side, which was too small a target to hit
    /// consistently at normal cursor speed.
    var idleFrame: CGRect {
        CGRect(x: notch.minX, y: notch.maxY - notch.height,
               width: notch.width + idleVisibleWidth, height: notch.height)
    }

    /// Expanded: spans from the left safe area, across the notch's own dead
    /// zone, into the right safe area — the content drawn inside (see
    /// NotchWidgetView) leaves an exact `notch.width`-wide gap in the
    /// middle to match, so nothing ever renders where it can't be seen.
    var expandedFrame: CGRect {
        CGRect(x: notch.minX - leftWidth, y: notch.maxY - expandedHeight,
               width: leftWidth + notch.width + rightWidth, height: expandedHeight)
    }
}

// MARK: - Window
//
// Independent of every other widget's window management — this one isn't
// part of the one-at-a-time exclusivity group (it's tiny, lives only at the
// very top of one specific screen, and is meant to run alongside whatever
// else is placed).
//
// The window's own frame IS the interactive region at all times, rather
// than sizing it to the maximum expanded size up front and hit-testing an
// irregular shape within that. Idle, that frame is the small pill next to
// the notch — space nothing else was using — so menu bar icons further out
// are never blocked; only on hover does the frame grow to the full
// expanded span, the same way iPhone's Dynamic Island expands over the
// status bar, and shrinks back the moment the mouse leaves it.
final class NotchWidgetWindow: NSPanel {
    let metrics: NotchLayoutMetrics

    init(metrics: NotchLayoutMetrics) {
        self.metrics = metrics
        super.init(
            contentRect: metrics.idleFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Above the menu bar — expanding needs to visually sit on top of it.
        level = NSWindow.Level(Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        collectionBehavior = [.stationary, .ignoresCycle, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
    }

    func setExpanded(_ expanded: Bool) {
        animator().setFrame(expanded ? metrics.expandedFrame : metrics.idleFrame, display: true)
    }
}

// MARK: - Widget

struct NotchWidgetView: View {
    let metrics: NotchLayoutMetrics
    var isPreview: Bool = false
    var previewExpanded: Bool = false
    var previewInfo: NowPlayingInfo? = nil
    var previewArt: NSImage? = nil
    var onExpandedChange: ((Bool) -> Void)? = nil

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

    var body: some View {
        Group {
            if expanded {
                expandedContent
            } else {
                idleContent
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: expanded)
        .onHover { isHovering in
            guard !isPreview else { return }
            hovering = isHovering
            onExpandedChange?(isHovering)
        }
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

    // MARK: - Idle
    //
    // The window's own frame spans the whole notch (see idleFrame) so
    // hovering anywhere near it reliably triggers expansion — but nothing
    // can actually be SEEN over the notch itself, so only the trailing
    // idleVisibleWidth-wide sliver ever draws anything: a small pill,
    // shown only while something's actually playing (same restraint as
    // iPhone's Dynamic Island — no indicator at all when nothing's
    // playing), flat on the edge touching the notch and rounded on the
    // outer edge so it reads as a small extension growing out of it.
    private var idleContent: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: metrics.notch.width)

            ZStack {
                if isActive {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0, bottomLeadingRadius: 0,
                        bottomTrailingRadius: 12, topTrailingRadius: 0,
                        style: .continuous
                    )
                    .fill(Color.black)
                    Image(systemName: "waveform")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: metrics.idleVisibleWidth)
        }
    }

    // MARK: - Expanded: art on the left of the notch, title/artist/
    // progress/transport stacked on the right — an explicit
    // `notch.width`-wide gap sits between them with nothing drawn in it at
    // all, since that space is a real cutout in the display and nothing
    // rendered there is visible.
    private var expandedContent: some View {
        HStack(spacing: 0) {
            ZStack {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 18,
                    bottomTrailingRadius: 0, topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(Color.black)

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
            }
            .frame(width: metrics.leftWidth)

            Color.clear
                .frame(width: metrics.notch.width)
                .allowsHitTesting(false)

            ZStack {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 18, topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(Color.black)

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
                .padding(.vertical, 8)
            }
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
                .frame(width: previewMetrics.expandedFrame.width, height: previewMetrics.expandedHeight)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .frame(width: previewBaseSize.width, height: previewBaseSize.height)
                .scaleEffect(s)
                .frame(width: previewBaseSize.width * s, height: previewBaseSize.height * s)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
