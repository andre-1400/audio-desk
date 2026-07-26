import SwiftUI
import AppKit

// MARK: - Window
//
// Originally sat at true desktop-picture level (CGWindowLevelForKey(.desktopWindow),
// below the Finder desktop icons) — but windows at or below icon level
// generally don't receive mouse clicks at all: the WindowServer routes
// clicks at that layer to Finder's own desktop interactions (icon
// selection, empty-space gestures), not through to us, which is exactly
// why transport buttons/the close button read as clicks on empty desktop
// instead.
//
// Raised further still, above the Dock's own window level (not just
// WidgetWindow's icon-level+1) — NSApp.presentationOptions'
// .autoHideDock only actually hides the Dock while the requesting app is
// the active/frontmost app, which this one deliberately never becomes
// (.nonactivatingPanel, so it never steals focus from whatever you were
// using). Since that route can't work here, sitting above the Dock's
// level instead means our opaque full-screen window simply covers it —
// same visual/interaction result (nothing shows through, clicks near the
// bottom go to us, not the Dock) without needing the app to activate.
// Being full-screen and opaque, it likewise still fully covers the
// desktop icons underneath. Not draggable — there's nowhere to drag a
// background to.
final class DesktopWidgetWindow: NSPanel {
    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        level = NSWindow.Level(Int(CGWindowLevelForKey(.dockWindow)) + 1)
        // No .canJoinAllSpaces — that made the window follow you into
        // every Space, including another app's own full-screen Space
        // (e.g. a full-screen Claude Code window), which isn't "the
        // desktop" in any meaningful sense. Without it, the window stays
        // put on whichever Space/desktop it was opened on, like a normal
        // window would.
        collectionBehavior = [.stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        // Off, unlike WidgetWindow — this flag makes AppKit deliver a
        // mouseMoved event for every pixel of cursor travel even with no
        // button down, which WidgetWindow wants for its small draggable
        // panels. Desktop's window is the entire screen with a much
        // heavier view tree (full disc + tonearm + shadows), so hit-testing
        // that on every single mouse-moved event at full pointer frequency
        // is real, sustained main-thread work — the likely cause of the
        // spinning-cursor "not responding" state while hovering it. None of
        // this window's own interactions need it: SwiftUI's .onHover close
        // button uses AppKit tracking areas, which fire on cursor
        // enter/exit regardless of this flag, not on continuous movement.
        acceptsMouseMovedEvents = false
        ignoresMouseEvents = false
    }
}

// MARK: - Gallery model
//
// A different kind of widget from every other family: full-screen, sitting
// at desktop-picture level (below the Finder icons, above the actual
// wallpaper) instead of floating as a small panel. Only one instance can
// exist, same exclusivity rule every other widget family already follows.
//
// Adaptive + Custom only — no fixed named colourways. Two silhouettes:
// Vinyl (disc + tonearm, reusing the exact same disc renderer as every
// other vinyl style) and Cover (a big centred piece of album art, the way
// iOS's own lock-screen Now Playing expands the art when you tap it).

enum DesktopWidgetStyle: String {
    case vinyl, cover
}

struct DesktopWidgetModel: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let style: DesktopWidgetStyle
    let themeID: WidgetThemeID   // .adaptive or .custom only for this family

    var isCustom: Bool { themeID == .custom }
}

struct DesktopWidgetForm: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let icon: String
    let models: [DesktopWidgetModel]
}

extension DesktopWidgetModel {
    static let forms: [DesktopWidgetForm] = [
        DesktopWidgetForm(id: "desktop-vinyl", name: "Vinyl", subtitle: "Disc + tonearm, full screen",
                           icon: "record.circle",
                           models: [
                            DesktopWidgetModel(id: "desktop-vinyl-adaptive", name: "Adaptive", subtitle: "Matches the album art, live", style: .vinyl, themeID: .adaptive),
                            DesktopWidgetModel(id: "desktop-vinyl-custom", name: "Custom", subtitle: "Pick your own exact colour", style: .vinyl, themeID: .custom)
                           ]),
        DesktopWidgetForm(id: "desktop-cover", name: "Cover", subtitle: "Full-screen album art",
                           icon: "photo",
                           models: [
                            DesktopWidgetModel(id: "desktop-cover-adaptive", name: "Adaptive", subtitle: "Matches the album art, live", style: .cover, themeID: .adaptive),
                            DesktopWidgetModel(id: "desktop-cover-custom", name: "Custom", subtitle: "Pick your own exact colour", style: .cover, themeID: .custom)
                           ])
    ]
    static let all: [DesktopWidgetModel] = forms.flatMap { $0.models }
}

// MARK: - Widget

struct DesktopWidgetView: View {
    let model: DesktopWidgetModel
    var isPreview: Bool = false
    var previewSpinning: Bool = false
    var previewInfo: NowPlayingInfo? = nil
    var previewArt: NSImage? = nil
    var previewColours: ExtractedColours? = nil
    var previewBlurredArt: NSImage? = nil
    var onClose: (() -> Void)? = nil

    @StateObject private var detector = MusicDetector()
    @StateObject private var artFetcher = AlbumArtFetcher()

    @State private var displayedArt: NSImage?
    @State private var displayedInfo: NowPlayingInfo = .empty
    @State private var lastTrackKey: String = ""
    @State private var extractedColours: ExtractedColours = .adaptivePreviewPlaceholder
    @State private var blurredBodyArt: NSImage?
    @State private var closeHovered = false

    // Progress-bar scrubbing — plain DragGesture, not the NSView capture
    // trick every other widget needs: this window is never movable-by-
    // background (there's nowhere to drag a full-screen backdrop to), so
    // there's no window-drag hijack risk to guard against here.
    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0
    @State private var seekHandoffUntil: Date?
    private let seekHandoffSuppressionDuration = 0.45

    @ObservedObject private var customColors = CustomColorManager.shared

    private var isCustom: Bool { model.isCustom }
    private var effectiveColours: ExtractedColours {
        if isCustom {
            return model.style == .vinyl ? customColors.desktopVinyl.extractedColours : customColors.desktopCover.extractedColours
        }
        return isPreview ? (previewColours ?? .adaptivePreviewPlaceholder) : extractedColours
    }
    private var effectiveArt: NSImage? { isPreview ? previewArt : displayedArt }
    private var effectiveBlurredArt: NSImage? { isPreview ? previewBlurredArt : blurredBodyArt }
    private var theme: WidgetThemePalette { WidgetThemeID.adaptivePalette(from: effectiveColours) }
    private var np: NowPlayingInfo { isPreview ? (previewInfo ?? .empty) : displayedInfo }
    private var trackKey: String {
        "\(detector.nowPlaying.trackName)|\(detector.nowPlaying.artistName)|\(detector.nowPlaying.albumName)"
    }

    private var fgPrimary: Color { AdaptiveBody.primary(effectiveColours.dominant) }
    private var fgSecondary: Color { AdaptiveBody.secondary(effectiveColours.dominant) }

    private func togglePlayback() {
        guard !isPreview else { return }
        detector.togglePlayback()
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                backdrop(in: geo.size)

                switch model.style {
                case .vinyl: vinylLayout(in: geo.size)
                case .cover: coverLayout(in: geo.size)
                }

                if !isPreview {
                    closeButton
                        .padding(.leading, 24)
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .opacity(closeHovered ? 1 : 0)
                        .onHover { closeHovered = $0 }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !isPreview else { return }
            detector.start()
            displayedInfo = detector.nowPlaying
            lastTrackKey = trackKey
            if !detector.nowPlaying.trackName.isEmpty {
                refreshArt(forceRefresh: false)
            }
        }
        .onDisappear {
            guard !isPreview else { return }
            detector.stop()
        }
        .onChange(of: trackKey) { oldValue, newValue in
            guard !isPreview else { return }
            guard oldValue != newValue, lastTrackKey != newValue else { return }
            lastTrackKey = newValue
            seekHandoffUntil = nil
            let live = detector.nowPlaying
            guard !live.trackName.isEmpty else {
                withAnimation(.easeInOut(duration: 0.3)) { displayedArt = nil }
                return
            }
            withAnimation(.easeInOut(duration: 0.3)) { displayedInfo = live }
            refreshArt(forceRefresh: true)
        }
        .onChange(of: detector.nowPlaying) { _, live in
            guard !isPreview else { return }
            guard !shouldSuppressSeekHandoffUpdate(from: live) else { return }
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

    // MARK: - Backdrop (shared by both styles)

    private func backdrop(in size: CGSize) -> some View {
        ZStack {
            Color.black
            if let art = effectiveArt {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .blur(radius: 60)
                    .scaleEffect(1.15)
                    .overlay(Color.black.opacity(0.55))
            } else {
                LinearGradient(colors: theme.widgetBodyGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .ignoresSafeArea()
    }

    private var closeButton: some View {
        Button(action: { onClose?() }) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.45))
                .shadow(color: .black.opacity(0.4), radius: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Vinyl layout — title/artist upper-left, huge disc + tonearm

    private func vinylLayout(in size: CGSize) -> some View {
        // Proportional to the available canvas throughout, rather than
        // fixed point sizes — the same layout code has to read sensibly at
        // both a real display's size and the gallery preview's much
        // smaller card, not just avoid literally clipping at each.
        // Smaller and pushed toward the right edge, leaving the whole left
        // half of the screen clear for the text/transport column instead of
        // the two competing for the same centre ground.
        let discDiameter = min(size.height * 0.58, size.width * 0.3)
        let discScale = discDiameter / 272
        let leadingPad = size.width * 0.045
        let titleSize = size.height * 0.05
        let subtitleSize = size.height * 0.024
        let eyebrowSize = size.height * 0.016
        // Transport icon size, proportional like everything else here — at
        // fixed point sizes these read fine on a real display but badly
        // oversized on the much smaller gallery-preview canvas.
        let iconSize = min(48, size.height * 0.048)

        return ZStack {
            VStack(alignment: .leading, spacing: size.height * 0.012) {
                Text("NOW PLAYING")
                    .font(.system(size: eyebrowSize, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(fgSecondary.opacity(0.8))
                    .shadow(color: .black.opacity(0.4), radius: 6)
                Text(np.trackName.isEmpty ? "Nothing Playing" : np.trackName)
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(fgPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.4), radius: 10)
                if !np.artistName.isEmpty {
                    Text(albumLine)
                        .font(.system(size: subtitleSize, weight: .medium))
                        .foregroundStyle(fgSecondary)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.4), radius: 8)
                }
            }
            .frame(maxWidth: size.width * 0.5, alignment: .leading)
            .padding(.leading, leadingPad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, size.height * 0.07)

            ZStack {
                SpinningVinylView(
                    isPlaying: isPreview ? previewSpinning : np.isPlaying,
                    albumArt: effectiveArt,
                    vinylTint: theme.albumArtLabelGradient.first ?? Color(hex: "9B5523"),
                    albumArtLabelGradient: theme.albumArtLabelGradient,
                    albumArtRingColor: theme.albumArtRingColor,
                    labelDiameter: 125
                )
                .scaleEffect(discScale)
                .frame(width: discDiameter, height: discDiameter)

                desktopTonearm
                    .scaleEffect(discScale)
                    .frame(width: 90 * discScale, height: 180 * discScale)
                    .offset(x: discDiameter / 2 * 0.731, y: -discDiameter / 2 * 0.206)
            }
            .contentShape(Rectangle())
            .onTapGesture { togglePlayback() }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, size.width * 0.13)

            // True vertical centre — same as the disc's own frame — so the
            // two line up level with each other instead of the row sitting
            // below the disc's centre.
            transportRow(iconSize: iconSize)
                .padding(.leading, leadingPad + size.width * 0.1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            // Its own full-width row spanning almost the entire screen,
            // independent of the disc/button column widths above it,
            // rather than matching the transport row's narrower measure.
            scrubBar
                .frame(width: size.width * 0.88)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, size.height * 0.08)
        }
    }

    /// Same geometry as every other vinyl style's tonearm (90x180 frame,
    /// pivot at 68,16, headshell attached directly at the rod's own 20°
    /// angle — duplicated per this codebase's established convention) plus
    /// a grounding cast shadow and a highlight streak down the rod so it
    /// reads as metal rather than a flat cutout at the size a desktop
    /// widget renders it at. The independently-tilted headshell tried
    /// earlier made it look like a separate piece floating off the rod's
    /// end, so this keeps the original single, consistent angle instead.
    /// Purely decorative: no progress tracking, no track-change
    /// choreography — the disc always just rests here, spinning or not.
    private var desktopTonearm: some View {
        ZStack {
            // Cast shadow onto the record — grounds the assembly as
            // something physically resting on the disc.
            Ellipse()
                .fill(Color.black.opacity(0.4))
                .frame(width: 74, height: 24)
                .blur(radius: 8)
                .position(x: 40, y: 158)

            // Arm rod — a brighter centre streak on top of the base
            // gradient reads as a specular highlight along a round metal
            // tube, plus a third, much softer/wider shadow layer under the
            // existing two so it doesn't look pasted flat onto the disc.
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [Color(hex: "1c1c1e"), Color(hex: "7c7c80"), Color(hex: "1c1c1e")],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 8, height: 132)
                .overlay(
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 1.4, height: 122)
                )
                .rotationEffect(.degrees(20))
                .position(x: 46, y: 85)
                .shadow(color: .black.opacity(0.6), radius: 1.5, x: 1, y: 2)
                .shadow(color: .black.opacity(0.35), radius: 5, x: 2, y: 5)
                .shadow(color: .black.opacity(0.2), radius: 13, x: 3, y: 11)

            // Pivot mount
            Circle()
                .fill(LinearGradient(colors: [Color(hex: "38383c"), Color(hex: "222224"), Color(hex: "0e0e10")],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                .position(x: 68, y: 16)

            Circle()
                .fill(RadialGradient(colors: [Color(hex: "f2f2f4"), Color(hex: "c2c2c6"), Color(hex: "78787c")],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 8))
                .frame(width: 15, height: 15)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.28), lineWidth: 0.5))
                .position(x: 68, y: 16)

            // Headshell + stylus
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Color(hex: "666666"), Color(hex: "222222")],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 18, height: 16)
                .position(x: 24, y: 152)
                .shadow(color: .black.opacity(0.4), radius: 1.5, x: 1, y: 1)

            Rectangle()
                .fill(LinearGradient(colors: [Color(hex: "bbbbbb"), Color(hex: "666666")], startPoint: .top, endPoint: .bottom))
                .frame(width: 2, height: 8)
                .position(x: 28, y: 164)
        }
        .frame(width: 90, height: 180)
    }

    /// "Artist — Album", collapsing gracefully when either is missing.
    private var albumLine: String {
        let artist = np.artistName
        let album = np.albumName
        if artist.isEmpty { return album }
        if album.isEmpty { return artist }
        return "\(artist) — \(album)"
    }

    // MARK: - Cover layout — big centred art, iOS-lock-screen style

    private func coverLayout(in size: CGSize) -> some View {
        let artSide = min(size.height * 0.5, size.width * 0.34)

        return VStack(spacing: 22) {
            Spacer(minLength: 0)

            Group {
                if let art = effectiveArt {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: theme.widgetBodyGradient, startPoint: .top, endPoint: .bottom))
                }
            }
            .frame(width: artSide, height: artSide)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 40, x: 0, y: 20)
            .contentShape(Rectangle())
            .onTapGesture { togglePlayback() }

            VStack(spacing: 6) {
                Text(np.trackName.isEmpty ? "Nothing Playing" : np.trackName)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(fgPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.4), radius: 8)
                if !np.artistName.isEmpty {
                    Text(np.artistName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(fgSecondary)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.4), radius: 6)
                }
            }
            .frame(maxWidth: min(560, size.width * 0.6))

            VStack(spacing: 18) {
                scrubBar
                transportRow(iconSize: min(28, size.height * 0.028))
            }
            .frame(width: min(420, size.width * 0.3))
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Shared transport + scrub bar

    /// `iconSize` scales the whole row (skip icons, play icon, spacing, hit
    /// target) together so it reads the same proportion on the small
    /// gallery-preview canvas as on a real full screen, instead of using
    /// fixed point sizes that only look right at one size.
    private func transportRow(iconSize: CGFloat) -> some View {
        HStack(spacing: iconSize * 2) {
            transportButton("backward.fill", size: iconSize, color: fgSecondary) { if !isPreview { detector.previousTrack() } }
            transportButton(np.isPlaying ? "pause.fill" : "play.fill", size: iconSize * 1.5, color: fgPrimary) { togglePlayback() }
            transportButton("forward.fill", size: iconSize, color: fgSecondary) { if !isPreview { detector.nextTrack() } }
        }
    }

    private func transportButton(_ symbol: String, size: CGFloat, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
                .shadow(color: .black.opacity(0.4), radius: size * 0.2)
                .frame(width: size * 1.7, height: size * 1.7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPreview)
    }

    private var scrubBar: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = np.durationMillis ?? 0
            let fraction = isScrubbing ? scrubProgress : progressFraction(at: context.date)
            let elapsed = isScrubbing ? Int(scrubProgress * Double(duration)) : elapsedMillis(at: context.date)
            let remaining = max(0, duration - elapsed)
            VStack(spacing: 6) {
                GeometryReader { geo in
                    let width = geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(fgSecondary.opacity(0.3)).frame(height: isScrubbing ? 6 : 4)
                        Capsule().fill(fgPrimary).frame(width: max(2, width * fraction), height: isScrubbing ? 6 : 4)
                        Circle()
                            .fill(fgPrimary)
                            .frame(width: 12, height: 12)
                            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                            .offset(x: min(width - 12, max(0, width * fraction - 6)))
                            .opacity(isScrubbing ? 1 : 0)
                    }
                    .frame(height: 22)
                    .contentShape(Rectangle())
                    .gesture(
                        isPreview ? nil : DragGesture(minimumDistance: 0)
                            .onChanged { drag in handleScrubDrag(fraction: drag.location.x / width) }
                            .onEnded { drag in
                                handleScrubDrag(fraction: drag.location.x / width)
                                commitScrub()
                            }
                    )
                }
                .frame(height: 22)
                .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isScrubbing)

                HStack {
                    Text(formatTime(elapsed))
                    Spacer()
                    Text("-" + formatTime(remaining))
                }
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(fgSecondary)
            }
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

    private func elapsedMillis(at date: Date) -> Int {
        guard let pos = np.positionMillis else { return 0 }
        var elapsed = Double(pos)
        if np.isPlaying, let sampledAt = np.progressSampledAt {
            elapsed += date.timeIntervalSince(sampledAt) * 1000
        }
        if let dur = np.durationMillis { elapsed = min(elapsed, Double(dur)) }
        return max(0, Int(elapsed))
    }

    private func progressFraction(at date: Date) -> Double {
        guard let dur = np.durationMillis, dur > 0 else { return 0 }
        return min(1, max(0, Double(elapsedMillis(at: date)) / Double(dur)))
    }

    private func formatTime(_ millis: Int) -> String {
        let totalSeconds = millis / 1000
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func handleScrubDrag(fraction: Double) {
        guard canSeek else { return }
        isScrubbing = true
        scrubProgress = min(1, max(0, fraction))
    }

    private func commitScrub() {
        defer { isScrubbing = false }
        guard isScrubbing else { return }
        commitSeek(toProgress: scrubProgress)
    }

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

    // MARK: - Art fetching

    private func refreshArt(forceRefresh: Bool) {
        let artURL = detector.nowPlaying.albumArtURL ?? ""
        artFetcher.fetchArt(from: artURL, trackKey: trackKey, forceRefresh: forceRefresh) { image in
            guard let image else { return }
            withAnimation(.easeInOut(duration: 0.3)) { displayedArt = image }
            if !isCustom {
                extractedColours = ColourExtractor.extract(from: image)
            }
        }
    }
}

// MARK: - Gallery preview (fit-scaled, flattened)

struct DesktopWidgetModelPreview: View {
    let model: DesktopWidgetModel
    var animated: Bool = false
    @ObservedObject var live: GalleryLiveTrack = GalleryLiveTrack()

    /// The preview card is much smaller than a real screen, so it uses its
    /// own compact base size rather than trying to fake an actual display's
    /// aspect ratio — this is a stand-in to show the look, not a literal
    /// screen simulation.
    private let previewBaseSize = CGSize(width: 480, height: 300)

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / previewBaseSize.width, geo.size.height / previewBaseSize.height)
            let view = DesktopWidgetView(
                model: model, isPreview: true, previewSpinning: animated,
                previewInfo: live.info, previewArt: live.art,
                previewColours: model.themeID == .adaptive ? live.colours : nil
            )
                .frame(width: previewBaseSize.width, height: previewBaseSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .scaleEffect(s)
                .frame(width: previewBaseSize.width * s, height: previewBaseSize.height * s)
                .frame(width: geo.size.width, height: geo.size.height)
            // drawingGroup() flattens into a static cached texture — fine
            // (cheap) for the resting state, but it was applied
            // unconditionally here, which silently killed the hover-spin
            // animation outright: every other preview in the app only
            // flattens when NOT animated, exactly to avoid this.
            if animated {
                view
            } else {
                view.drawingGroup()
            }
        }
    }
}
