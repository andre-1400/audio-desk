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
    let leftWidth: CGFloat = 64
    let rightWidth: CGFloat = 210
    let idleWidth: CGFloat = 26
    let expandedHeight: CGFloat = 48

    /// Idle: a small standalone pill flush against the notch's right edge —
    /// deliberately NOT centred on/overlapping the notch itself (which
    /// would be invisible), and small enough that it only ever occupies
    /// space that's otherwise unused right next to the cutout.
    var idleFrame: CGRect {
        CGRect(x: notch.maxX, y: notch.maxY - notch.height, width: idleWidth, height: notch.height)
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

    // MARK: - Idle: a small pill flush against the notch's right edge,
    // shown only while something's actually playing — same restraint as
    // iPhone's Dynamic Island, no indicator at all when nothing's playing.
    // Flat on the leading edge (butts against the notch), rounded on the
    // trailing edge, so it reads as a small extension growing out of the
    // notch rather than a separate floating chip.
    private var idleContent: some View {
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
    }

    // MARK: - Expanded: art on the left of the notch, title/artist/
    // transport on the right — an explicit `notch.width`-wide gap sits
    // between them with nothing drawn in it at all, since that space is a
    // real cutout in the display and nothing rendered there is visible.
    private var expandedContent: some View {
        HStack(spacing: 0) {
            ZStack {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 16,
                    bottomTrailingRadius: 0, topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(Color.black)

                Group {
                    if let art {
                        Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.15))
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(width: metrics.leftWidth)

            Color.clear
                .frame(width: metrics.notch.width)
                .allowsHitTesting(false)

            ZStack(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 16, topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(Color.black)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(np.trackName.isEmpty ? "Nothing Playing" : np.trackName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if !np.artistName.isEmpty {
                            Text(np.artistName)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: 78, alignment: .leading)

                    Spacer(minLength: 4)

                    HStack(spacing: 10) {
                        transportButton("backward.fill", size: 11) { if !isPreview { detector.previousTrack() } }
                        transportButton(np.isPlaying ? "pause.fill" : "play.fill", size: 13) { if !isPreview { detector.togglePlayback() } }
                        transportButton("forward.fill", size: 11) { if !isPreview { detector.nextTrack() } }
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(width: metrics.rightWidth)
        }
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
