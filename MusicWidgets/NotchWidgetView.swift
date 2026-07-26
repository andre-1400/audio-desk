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
    /// coordinate space. nil if this screen has no notch.
    static func notchFrame(on screen: NSScreen) -> CGRect? {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
              screen.safeAreaInsets.top > 0, right.minX > left.maxX else { return nil }
        let width = right.minX - left.maxX
        let height = screen.safeAreaInsets.top
        return CGRect(x: left.maxX, y: screen.frame.maxY - height, width: width, height: height)
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
// irregular shape within that. Idle, the frame matches the physical notch
// exactly — space the system already treats as dead, so nothing nearby
// (menu bar icons included) is ever blocked. Only on hover does the frame
// itself grow wider/taller, the same way iPhone's Dynamic Island expands
// over the status bar — and shrinks back the moment the mouse leaves it.
final class NotchWidgetWindow: NSPanel {
    static let expandedSize = CGSize(width: 300, height: 52)

    private let notchFrame: CGRect

    init(notchFrame: CGRect) {
        self.notchFrame = notchFrame
        super.init(
            contentRect: notchFrame,
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
        let size = expanded ? Self.expandedSize : notchFrame.size
        let topY = notchFrame.maxY
        let target = CGRect(x: notchFrame.midX - size.width / 2, y: topY - size.height,
                             width: size.width, height: size.height)
        animator().setFrame(target, display: true)
    }
}

// MARK: - Widget

struct NotchWidgetView: View {
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
        ZStack {
            // Rounded-bottom black shape, matching the physical notch's own
            // silhouette — idle, this is visually indistinguishable from
            // the unmodified notch.
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: expanded ? 20 : 10,
                bottomTrailingRadius: expanded ? 20 : 10,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color.black)

            if expanded {
                expandedContent.transition(.opacity)
            } else if isActive {
                idleIndicator
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

    // MARK: - Idle: a small equalizer glyph, and only while something's
    // actually playing — same as iPhone's Dynamic Island, no indicator at
    // all when nothing's playing.
    private var idleIndicator: some View {
        HStack {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.trailing, 6)
        }
    }

    // MARK: - Expanded: art + title/artist + transport, Dynamic-Island style

    private var expandedContent: some View {
        HStack(spacing: 10) {
            Group {
                if let art {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.15))
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

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
            .frame(maxWidth: 110, alignment: .leading)

            Spacer(minLength: 4)

            HStack(spacing: 12) {
                transportButton("backward.fill", size: 11) { if !isPreview { detector.previousTrack() } }
                transportButton(np.isPlaying ? "pause.fill" : "play.fill", size: 13) { if !isPreview { detector.togglePlayback() } }
                transportButton("forward.fill", size: 11) { if !isPreview { detector.nextTrack() } }
            }
        }
        .padding(.horizontal, 14)
    }

    private func transportButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size + 14, height: size + 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPreview)
    }
}

// MARK: - Gallery preview (fit-scaled, always shown expanded — a card too
// small to usefully hover, so it just shows what expanding looks like)

struct NotchWidgetModelPreview: View {
    var animated: Bool = false
    @ObservedObject var live: GalleryLiveTrack = GalleryLiveTrack()

    private let previewBaseSize = CGSize(width: 320, height: 90)

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / previewBaseSize.width, geo.size.height / previewBaseSize.height)
            NotchWidgetView(isPreview: true, previewExpanded: animated, previewInfo: live.info, previewArt: live.art)
                .frame(width: NotchWidgetWindow.expandedSize.width, height: NotchWidgetWindow.expandedSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(width: previewBaseSize.width, height: previewBaseSize.height)
                .scaleEffect(s)
                .frame(width: previewBaseSize.width * s, height: previewBaseSize.height * s)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
