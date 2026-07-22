//
//  ContentView.swift
//  VinylWidget
//
//  Created by Andre Bytkin on 14/03/2026.
//

import SwiftUI
import AppKit

// MARK: - Helper Extensions

extension Color {
    /// Initialize Color from hex string (e.g., "2a1a0a")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

enum FallbackCoverArtGenerator {
    static let fallbackImage: NSImage = {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size)
        let colors = [
            NSColor(calibratedRed: 0.18, green: 0.18, blue: 0.18, alpha: 1.0),
            NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.09, alpha: 1.0),
            NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.05, alpha: 1.0)
        ]
        NSGradient(colors: colors)?
            .draw(in: rect, angle: 315)

        NSColor.white.withAlphaComponent(0.08).setStroke()
        let stripePath = NSBezierPath()
        stripePath.lineWidth = 1
        stride(from: 0.0, through: size.height, by: 10.0).forEach { y in
            stripePath.move(to: NSPoint(x: 0, y: y))
            stripePath.line(to: NSPoint(x: size.width, y: y))
        }
        stripePath.stroke()

        NSColor.white.withAlphaComponent(0.2).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(
            x: size.width * 0.36,
            y: size.height * 0.36,
            width: size.width * 0.28,
            height: size.height * 0.28
        ))
        ring.lineWidth = 2
        ring.stroke()

        NSColor.white.withAlphaComponent(0.18).setFill()
        let spindle = NSBezierPath(ovalIn: NSRect(
            x: size.width * 0.48,
            y: size.height * 0.48,
            width: size.width * 0.04,
            height: size.height * 0.04
        ))
        spindle.fill()

        return image
    }()
}

private struct TonearmPlaybackTransition {
    let startedAt: Date
    let duration: TimeInterval
    let fromAngle: Double
    let toAngle: Double

    func angle(at date: Date) -> Double? {
        let elapsed = date.timeIntervalSince(startedAt)
        guard elapsed < duration else { return nil }
        let progress = max(0, min(1, elapsed / duration))
        let inverse = 1 - progress
        let easedProgress = 1 - (inverse * inverse * inverse)
        return fromAngle + ((toAngle - fromAngle) * easedProgress)
    }
}

// MARK: - ContentView (Main UI Container)
/// The root view containing:
/// - Wooden player body (320×380) with wood grain texture, corner screws
/// - Platter area with spinning vinyl + album art label + spindle
/// - Track info display (song name, artist, status dot)
/// - Tonearm follows playback progress when timing data is available
/// - Drag gesture for repositioning (screen-coordinate based for jitter-free movement)
/// - Tap gesture to toggle playback

struct VinylWidgetView: View {
    // MARK: - State Objects
    @StateObject private var detector = MusicDetector()
    @StateObject private var artFetcher = AlbumArtFetcher()

    // MARK: - Injected from AppDelegate
    @ObservedObject var animator: SongSwitchAnimator
    @ObservedObject var themeManager: WidgetThemeManager

    // MARK: - Global settings (musical notes)
    @ObservedObject private var widgetSettings = WidgetSettings.shared


    // MARK: - State
    @State private var extractedColours: ExtractedColours = .fallback
    @State private var displayedNowPlaying: NowPlayingInfo = .empty
    @State private var displayedAlbumArt: NSImage?
    @State private var bufferedIncomingAlbumArt: NSImage?
    @State private var lastObservedTrackIdentity: String = ""
    @State private var hasSeenInitialTrackIdentity: Bool = false
    @State private var tonearmPlaybackTransition: TonearmPlaybackTransition?
    @State private var seekHandoffUntil: Date?
    @State private var trackProgressClampUntil: Date?
    /// Adaptive theme only: the current album art, heavily blurred, used as the
    /// widget body. Cached per track — never recomputed per frame.
    @State private var blurredBodyArt: NSImage?
    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0

    private let tonearmRestAngle = -22.0
    private let tonearmStartAngle = -8.0
    private let tonearmEndAngle = 14.0
    private let tonearmMaxSeekProgress = 0.98
    private let tonearmPlaybackTransitionDuration: TimeInterval = 0.42
    private let seekHandoffSuppressionDuration = 0.45
    private let trackStartProgressClampDuration = 1.2

    // MARK: - Computed Properties
    /// Map music source to string key for caching
    private var sourceKey: String {
        switch detector.nowPlaying.source {
        case .spotify:
            return "spotify"
        case .appleMusic:
            return "appleMusic"
        case .none:
            return "none"
        }
    }

    /// Unique key for current track (source + track/artist/album)
    /// Used to detect when song changes (triggers album art refresh)
    private var trackIdentityKey: String {
        "\(sourceKey)|\(detector.nowPlaying.trackName)|\(detector.nowPlaying.artistName)|\(detector.nowPlaying.albumName)"
    }

    /// Animator identity key must match SongSwitchAnimator normalization (no source prefix).
    private var animatorTrackIdentityKey: String {
        [
            normalizedIdentity(detector.nowPlaying.trackName),
            normalizedIdentity(detector.nowPlaying.artistName),
            normalizedIdentity(detector.nowPlaying.albumName)
        ].joined(separator: "|")
    }

    /// Tonearm angle — overridden during song switch animation
    private func tonearmAngle(at date: Date) -> Double {
        if animator.tonearmShouldRest {
            return tonearmRestAngle
        }

        guard !displayedNowPlaying.trackName.isEmpty else {
            return tonearmRestAngle
        }

        // Scrub bar drags: the arm tracks the bar, read-only.
        if isScrubbing {
            return tonearmAngle(forProgress: scrubProgress)
        }

        if let transitionAngle = tonearmPlaybackTransition?.angle(at: date) {
            return transitionAngle
        }

        guard displayedNowPlaying.isPlaying else {
            return tonearmRestAngle
        }

        guard let progress = playbackProgress(at: date) else {
            return tonearmStartAngle
        }

        return tonearmAngle(forProgress: progress)
    }

    private func playbackProgress(at date: Date) -> Double? {
        playbackProgress(for: displayedNowPlaying, at: date, applyingStartClamp: true)
    }

    private func playbackProgress(for info: NowPlayingInfo, at date: Date, applyingStartClamp: Bool) -> Double? {
        guard
            let durationMillis = info.durationMillis,
            let positionMillis = info.positionMillis,
            durationMillis > 0
        else { return nil }

        let estimatedPositionMillis: Double
        if info.isPlaying, let sampledAt = info.progressSampledAt {
            estimatedPositionMillis = Double(positionMillis) + (date.timeIntervalSince(sampledAt) * 1000)
        } else {
            estimatedPositionMillis = Double(positionMillis)
        }
        let rawProgress = min(tonearmMaxSeekProgress, max(0.0, estimatedPositionMillis / Double(durationMillis)))

        guard applyingStartClamp, info.isPlaying else { return rawProgress }
        guard let clampUntil = trackProgressClampUntil else { return rawProgress }
        if date >= clampUntil {
            return rawProgress
        }
        return min(rawProgress, 0.08)
    }

    private func tonearmAngle(forProgress progress: Double) -> Double {
        let clampedProgress = min(tonearmMaxSeekProgress, max(0.0, progress))
        return tonearmStartAngle + ((tonearmEndAngle - tonearmStartAngle) * clampedProgress)
    }

    private var theme: WidgetThemePalette { themeManager.palette }
    private var traits: VinylModelTraits { themeManager.themeID.traits }

    private let bodySize = CGSize(width: 344, height: 476)

    /// Perceived lightness of whatever the body actually is right now — the
    /// blurred album art under Adaptive, otherwise the theme's body gradient.
    /// Everything drawn on top keys off this so a near-white album can't leave
    /// white text on a white body (or vice versa).
    /// Perceived lightness of the body as actually drawn — see AdaptiveBody.
    /// Non-adaptive themes have no artwork, so they average their own gradient.
    private var bodyIsLight: Bool {
        if themeManager.themeID == .adaptive {
            return AdaptiveBody.isLight(extractedColours.dominant)
        }
        let colours = theme.widgetBodyGradient
        guard !colours.isEmpty else { return false }
        let mean = colours.map(\.perceivedBrightness).reduce(0, +) / Double(colours.count)
        return mean > 0.50
    }

    private var panelPrimary: Color {
        bodyIsLight ? Color.black.opacity(0.88) : .white
    }

    private var panelSecondary: Color {
        bodyIsLight ? Color.black.opacity(0.58) : Color.white.opacity(0.72)
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            // === Body shell (theme-conditional) ===
            if theme.showBody {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: theme.widgetBodyGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .black.opacity(0.7), radius: 30, x: 0, y: 20)

                    // Adaptive: the body IS the album art, blurred until it
                    // reads as almost one colour, rather than a flat average.
                    AdaptiveBodyFill(blurredArt: blurredBodyArt, size: bodySize)

                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(theme.widgetBorder, lineWidth: 1)

                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [theme.widgetTopSheen, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )

                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.06), .clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.28)
                            )
                        )

                    VinylBodyTexture(pattern: traits.pattern)
                }
                .frame(width: 344, height: 476)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }

            // Body surface details (case border, pitch fader, power LED)
            if theme.showBody { vinylBodyDetails }

            // === Content (always shown) ===
            VStack(spacing: 0) {
                platterArea
                    .padding(.top, theme.showBody ? 20 : 8)

                if traits.hasTransportControls {
                    VStack(spacing: 9) {
                        RetroVFDDisplay(
                            title: displayedNowPlaying.trackName.isEmpty ? "NO SIGNAL" : displayedNowPlaying.trackName,
                            subtitle: displayedNowPlaying.artistName
                        )
                        transportControls
                    }
                    .padding(.top, 10)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)
                } else {
                    modernTrackPanel
                        .padding(.top, 16)
                        .padding(.horizontal, 38)
                        .padding(.bottom, 20)
                }
            }

            // === Tonearm ===
            // Purely visual: its angle tracks playback progress (swings from
            // the edge toward the centre as the song plays) via
            // tonearmAngle(at:). No longer draggable/interactive — grabbing
            // it always dragged the whole widget instead of seeking (the
            // capture zone could never fully cover the head's swing without
            // also covering draggable background around it), so the seek
            // gesture was removed. Seeking is still available via the
            // scrub bar in the track panel below.
            TimelineView(.animation) { context in
                tonearmView
                    .rotationEffect(
                        .degrees(tonearmAngle(at: context.date)),
                        anchor: UnitPoint(x: 68.0 / 90.0, y: 16.0 / 180.0)
                    )
            }
            .animation(.spring(response: 1.2, dampingFraction: 0.7), value: animator.tonearmShouldRest)
            .offset(x: 115, y: -137)
        }
        .frame(width: 384, height: 516)
        .coordinateSpace(name: "widget")
        .overlay(alignment: widgetSettings.notesSide == .left ? .topLeading : .topTrailing) {
            if widgetSettings.notesEnabled {
                MusicalNotesView(side: widgetSettings.notesSide, active: displayedNowPlaying.isPlaying)
                    .padding(widgetSettings.notesSide == .left ? .leading : .trailing, 18)
                    .padding(.top, -8)
            }
        }
        .onAppear {
            detector.start()
            displayedNowPlaying = detector.nowPlaying
            displayedAlbumArt = artFetcher.albumArt
            bufferedIncomingAlbumArt = artFetcher.albumArt
            lastObservedTrackIdentity = trackIdentityKey
            hasSeenInitialTrackIdentity = true
            if !detector.nowPlaying.trackName.isEmpty {
                refreshAlbumArt(forceRefresh: false, updateDisplayedArt: true)
            }
        }
        .onDisappear {
            detector.stop()
            animator.cancelAndReset()
        }
        .onChange(of: trackIdentityKey) { oldValue, newValue in
            handleTrackIdentityChange(oldValue: oldValue, newValue: newValue)
        }
        .onChange(of: themeManager.themeID) { _, _ in
            if let art = displayedAlbumArt { updateBlurredBodyArt(from: art) }
        }
        .onChange(of: detector.nowPlaying) { _, live in
            updateDisplayedPlaybackState(from: live)
        }
        .onChange(of: detector.nowPlaying.albumArtURL) { _, newURL in
            if let url = newURL {
                artFetcher.fetchArt(from: url, trackKey: trackIdentityKey, forceRefresh: false) { image in
                    guard let image else { return }
                    extractedColours = ColourExtractor.extract(from: image)
                    bufferedIncomingAlbumArt = image
                    if animator.isAnimating {
                        animator.updateIncomingAlbumArtIfPossible(image, identityKey: animatorTrackIdentityKey)
                    } else {
                        // Not mid-transition: this is art arriving for the
                        // track we're already sitting on — most importantly
                        // the async first poll right after launch, where
                        // onAppear saw an empty detector and couldn't seed
                        // the colour. Push the adaptive colour/blur now, or
                        // the body stays fallback-brown until the next skip.
                        displayedAlbumArt = image
                        themeManager.adaptiveColours = extractedColours
                        updateBlurredBodyArt(from: image)
                    }
                }
            } else if detector.nowPlaying.trackName.isEmpty {
                // Only clear art when nothing is playing at all
                artFetcher.fetchArt(from: "", trackKey: "", forceRefresh: true) { _ in
                    extractedColours = .fallback
                    bufferedIncomingAlbumArt = nil
                    displayedAlbumArt = nil
                }
            }
        }
        .onChange(of: animator.revealEventID) { _, eventID in
            guard eventID != nil, let snapshot = animator.revealedIncomingSnapshot else { return }
            displayedNowPlaying = NowPlayingInfo(
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
            displayedAlbumArt = snapshot.albumArt ?? bufferedIncomingAlbumArt ?? artFetcher.albumArt
            // Adaptive theme changes here, at reveal — when the new disc
            // actually lands — not earlier when the new art first arrives
            // (that's mid lift-off, still showing the outgoing disc).
            if let art = displayedAlbumArt {
                themeManager.adaptiveColours = ColourExtractor.extract(from: art)
                updateBlurredBodyArt(from: art)
            }
        }
    }

    // MARK: - Helper Methods

    /// Enough info to draw a progress bar — independent of whether a seek
    /// gesture is currently permitted.
    private var hasProgressData: Bool {
        !displayedNowPlaying.trackName.isEmpty && (displayedNowPlaying.durationMillis ?? 0) > 0
    }

    /// Enough info, and a permissible state, to seek — gates the scrub bar.
    private var canSeek: Bool {
        !animator.isAnimating &&
            !displayedNowPlaying.trackName.isEmpty &&
            displayedNowPlaying.source != .none &&
            (displayedNowPlaying.durationMillis ?? 0) > 0
    }

    /// Commits a scrub-bar drag: optimistically move the displayed position
    /// so the UI doesn't snap back while the player catches up, then tell
    /// the player.
    private func commitSeek(toProgress progress: Double) {
        guard
            canSeek,
            let durationMillis = displayedNowPlaying.durationMillis
        else { return }

        let targetMillis = Int((progress * Double(durationMillis)).rounded())
        let sampledAt = displayedNowPlaying.isPlaying ? Date() : nil
        seekHandoffUntil = Date().addingTimeInterval(seekHandoffSuppressionDuration)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            displayedNowPlaying = NowPlayingInfo(
                trackName: displayedNowPlaying.trackName,
                artistName: displayedNowPlaying.artistName,
                albumName: displayedNowPlaying.albumName,
                albumArtURL: displayedNowPlaying.albumArtURL,
                isPlaying: displayedNowPlaying.isPlaying,
                source: displayedNowPlaying.source,
                positionMillis: targetMillis,
                durationMillis: displayedNowPlaying.durationMillis,
                progressSampledAt: sampledAt
            )
        }
        detector.seek(toMillis: targetMillis)
    }

    /// Adaptive only, and only once per track — the blur itself is done off the
    /// main thread since it's a Core Image render, not a cheap sample.
    private func updateBlurredBodyArt(from art: NSImage) {
        guard themeManager.themeID == .adaptive else {
            if blurredBodyArt != nil { blurredBodyArt = nil }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let blurred = ArtBlurrer.blurredBody(from: art)
            DispatchQueue.main.async { blurredBodyArt = blurred }
        }
    }

    private func setWidgetBackgroundDraggingEnabled(_ enabled: Bool) {
        guard let window = NSApp.windows.first(where: { $0 is WidgetWindow }) else { return }
        window.isMovableByWindowBackground = enabled
    }

    // MARK: - Progress bar scrubbing
    //
    // The only remaining way to seek, now that tonearm dragging is gone —
    // it always dragged the whole widget instead. The tonearm still
    // visually *follows* a scrub (see tonearmAngle), it just isn't itself
    // interactive.

    private func handleScrubDrag(fraction: Double) {
        guard canSeek else { return }
        if !isScrubbing {
            setWidgetBackgroundDraggingEnabled(false)
            isScrubbing = true
        }
        scrubProgress = min(tonearmMaxSeekProgress, max(0, fraction))
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

    private func updateDisplayedPlaybackState(from live: NowPlayingInfo) {
        guard !animator.isAnimating else { return }

        if live.trackName.isEmpty {
            seekHandoffUntil = nil
            trackProgressClampUntil = nil
            tonearmPlaybackTransition = nil
            displayedNowPlaying = live
            return
        }

        let isStrictSameTrack = isSameTrack(displayedNowPlaying, live)
        let isLooseSameTrack =
            displayedNowPlaying.source == live.source &&
            normalizedIdentity(displayedNowPlaying.trackName) == normalizedIdentity(live.trackName) &&
            normalizedIdentity(displayedNowPlaying.artistName) == normalizedIdentity(live.artistName)

        if !isStrictSameTrack {
            guard isLooseSameTrack else { return }
            applyDisplayedPlaybackUpdate(NowPlayingInfo(
                trackName: displayedNowPlaying.trackName,
                artistName: displayedNowPlaying.artistName,
                albumName: displayedNowPlaying.albumName,
                albumArtURL: displayedNowPlaying.albumArtURL,
                isPlaying: live.isPlaying,
                source: displayedNowPlaying.source,
                positionMillis: live.positionMillis,
                durationMillis: live.durationMillis,
                progressSampledAt: live.progressSampledAt
            ))
            return
        }

        guard !shouldSuppressSeekHandoffUpdate(from: live) else { return }
        applyDisplayedPlaybackUpdate(live)
    }

    private func applyDisplayedPlaybackUpdate(_ info: NowPlayingInfo) {
        if shouldAnimateTonearmPlaybackTransition(to: info) {
            startTonearmPlaybackTransition(to: info)
        }
        displayedNowPlaying = info
    }

    private func shouldAnimateTonearmPlaybackTransition(to info: NowPlayingInfo) -> Bool {
        !isScrubbing &&
            isSameTrack(displayedNowPlaying, info) &&
            displayedNowPlaying.isPlaying != info.isPlaying
    }

    private func startTonearmPlaybackTransition(to info: NowPlayingInfo) {
        let now = Date()
        let fromAngle = tonearmPlaybackTransition?.angle(at: now) ??
            tonearmTargetAngle(for: displayedNowPlaying, at: now)
        let toAngle = tonearmTargetAngle(for: info, at: now)
        guard abs(fromAngle - toAngle) > 0.1 else {
            tonearmPlaybackTransition = nil
            return
        }
        tonearmPlaybackTransition = TonearmPlaybackTransition(
            startedAt: now,
            duration: tonearmPlaybackTransitionDuration,
            fromAngle: fromAngle,
            toAngle: toAngle
        )
    }

    private func tonearmTargetAngle(for info: NowPlayingInfo, at date: Date) -> Double {
        guard info.isPlaying else { return tonearmRestAngle }
        guard let progress = playbackProgress(for: info, at: date, applyingStartClamp: false) else {
            return tonearmStartAngle
        }
        return tonearmAngle(forProgress: progress)
    }

    private func shouldSuppressSeekHandoffUpdate(from live: NowPlayingInfo) -> Bool {
        guard let seekHandoffUntil else { return false }

        let now = Date()
        guard now < seekHandoffUntil else {
            self.seekHandoffUntil = nil
            return false
        }

        if live.isPlaying != displayedNowPlaying.isPlaying {
            self.seekHandoffUntil = nil
            return false
        }

        return true
    }

    private func handleTrackIdentityChange(oldValue: String, newValue: String) {
        // Ignore bootstrap identity churn while the detector warms up.
        if !hasSeenInitialTrackIdentity {
            hasSeenInitialTrackIdentity = true
            lastObservedTrackIdentity = newValue
            return
        }

        if oldValue == newValue || lastObservedTrackIdentity == newValue {
            return
        }
        lastObservedTrackIdentity = newValue
        seekHandoffUntil = nil
        tonearmPlaybackTransition = nil
        trackProgressClampUntil = Date().addingTimeInterval(trackStartProgressClampDuration)

        let live = detector.nowPlaying
        let isPlayableTrack = !live.trackName.isEmpty

        if !isPlayableTrack {
            animator.cancelAndReset()
            displayedNowPlaying = live
            displayedAlbumArt = nil
            bufferedIncomingAlbumArt = nil
            artFetcher.fetchArt(from: "", trackKey: "", forceRefresh: true) { _ in
                extractedColours = .fallback
            }
            return
        }

        let isInitialTrack = oldValue.isEmpty || displayedNowPlaying.trackName.isEmpty
        if isInitialTrack {
            displayedNowPlaying = live
            refreshAlbumArt(forceRefresh: true, updateDisplayedArt: true)
            return
        }

        guard live.isPlaying else {
            // Don't commit to "paused" yet. Spotify can report a track's new
            // metadata a beat before its playback state catches up during a
            // genuine auto-advance (verified by polling through several real
            // track transitions — no paused/stopped tick ever showed there,
            // so this is about our own read racing the state settling, not
            // a state Spotify actually holds for long). Recheck shortly
            // before showing anything, so a real skip-to-next-while-playing
            // isn't shown stuck on the outgoing track's "paused" info.
            let previousInfo = displayedNowPlaying
            let previousArt = displayedAlbumArt
            recheckPlaybackAfterTrackChange(
                expectedIdentity: newValue,
                fallbackInfo: live,
                previousInfo: previousInfo,
                previousArt: previousArt
            )
            return
        }

        beginSongSwitchTransition(from: displayedNowPlaying, fromArt: displayedAlbumArt, to: live)
    }

    /// Gives a possibly-stale "not playing" read a moment to settle before
    /// treating a just-changed track as genuinely paused. If it turns out
    /// to really be playing, runs the normal transition (using the track/art
    /// that was on screen before this all started, not whatever's on screen
    /// by the time this fires). If it's still not playing, commits to the
    /// paused display then, not before.
    private func recheckPlaybackAfterTrackChange(
        expectedIdentity: String,
        fallbackInfo: NowPlayingInfo,
        previousInfo: NowPlayingInfo,
        previousArt: NSImage?
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            // If the track identity has already moved on again, whatever
            // handled that change owns the display now — don't clobber it.
            guard trackIdentityKey == expectedIdentity else { return }
            let recheck = detector.nowPlaying
            if recheck.isPlaying {
                beginSongSwitchTransition(from: previousInfo, fromArt: previousArt, to: recheck)
            } else {
                displayedNowPlaying = fallbackInfo
            }
        }
    }

    private func beginSongSwitchTransition(from previousInfo: NowPlayingInfo, fromArt: NSImage?, to live: NowPlayingInfo) {
        let resolvedIncomingArt = bufferedIncomingAlbumArt ?? artFetcher.albumArt

        guard widgetSettings.vinylTransitionAnimationEnabled else {
            // Animations off: snap straight to the next track instead of the
            // disc-lift/sleeve-eject choreography — the same instant swap the
            // Vinyl Horizontal widget already does (it has no sleeve
            // mechanism to animate in the first place). Set the buffered art
            // immediately so the body/colour update this instant rather than
            // waiting on the fetch below, which still runs to catch cases
            // where nothing was buffered yet.
            displayedNowPlaying = live
            displayedAlbumArt = resolvedIncomingArt
            if let art = displayedAlbumArt {
                themeManager.adaptiveColours = ColourExtractor.extract(from: art)
                updateBlurredBodyArt(from: art)
            }
            refreshAlbumArt(forceRefresh: true, updateDisplayedArt: true)
            return
        }

        let outgoingSnapshot = SongSwitchAnimator.TrackSnapshot(
            trackName: previousInfo.trackName,
            artistName: previousInfo.artistName,
            albumName: previousInfo.albumName,
            albumArt: fromArt
        )

        let incomingSnapshot = SongSwitchAnimator.TrackSnapshot(
            trackName: live.trackName,
            artistName: live.artistName,
            albumName: live.albumName,
            albumArt: resolvedIncomingArt
        )

        let request = SongSwitchAnimator.TransitionRequest(
            outgoing: outgoingSnapshot,
            incoming: incomingSnapshot,
            widgetFrameInScreen: widgetFrameInScreen(),
            platterCenterInScreen: platterCenterInScreen()
        )

        animator.startTransition(request)
        refreshAlbumArt(forceRefresh: true, updateDisplayedArt: false)
    }

    /// Fetch album art for current track and optionally update displayed center art.
    private func refreshAlbumArt(forceRefresh: Bool, updateDisplayedArt: Bool) {
        let artURL = detector.nowPlaying.albumArtURL ?? ""
        artFetcher.fetchArt(from: artURL, trackKey: trackIdentityKey, forceRefresh: forceRefresh) { image in
            guard let image else { return }
            extractedColours = ColourExtractor.extract(from: image)
            bufferedIncomingAlbumArt = image
            if updateDisplayedArt {
                displayedAlbumArt = image
                // No sleeve-flying transition happens on this path (first
                // track, widget just launched) — nothing to time the
                // Adaptive colour change against, so update immediately.
                themeManager.adaptiveColours = extractedColours
                updateBlurredBodyArt(from: image)
            } else if animator.isAnimating {
                animator.updateIncomingAlbumArtIfPossible(image, identityKey: animatorTrackIdentityKey)
            }
        }
    }

    private func animatorIdentityKey(trackName: String, artistName: String, albumName: String) -> String {
        [
            normalizedIdentity(trackName),
            normalizedIdentity(artistName),
            normalizedIdentity(albumName)
        ].joined(separator: "|")
    }

    private func isSameTrack(_ lhs: NowPlayingInfo, _ rhs: NowPlayingInfo) -> Bool {
        lhs.source == rhs.source &&
            animatorIdentityKey(
                trackName: lhs.trackName,
                artistName: lhs.artistName,
                albumName: lhs.albumName
            ) == animatorIdentityKey(
                trackName: rhs.trackName,
                artistName: rhs.artistName,
                albumName: rhs.albumName
            )
    }

    private func normalizedIdentity(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func widgetFrameInScreen() -> CGRect {
        if let frame = NSApp.windows.first(where: { $0 is WidgetWindow })?.frame {
            return frame
        }
        return CGRect(x: 0, y: 0, width: 372, height: 404)
    }

    private func platterCenterInScreen() -> CGPoint {
        let frame = widgetFrameInScreen()
        // Calibrated anchor for the platter center so lifted disk/sleeves stay locked to the vinyl.
        // Was +8 when the body was 380 tall; the taller body (460) moved the
        // platter 44pt up in view space, which is +44 in screen (y-up) space.
        return CGPoint(x: frame.midX, y: frame.midY + 61)
    }

    // MARK: - Platter Area (no tonearm — that's outside the clip)

    // MARK: - Design detail elements (trait-gated)

    private var vinylBodyDetails: some View {
        ZStack {
            if traits.caseBorder {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(LinearGradient(colors: theme.screwGradient, startPoint: .top, endPoint: .bottom), lineWidth: 3)
                    .frame(width: 300, height: 360)
                ForEach([CGFloat(170), 250], id: \.self) { y in
                    latch.position(x: 24, y: y)
                    latch.position(x: 336, y: y)
                }
            }
            if traits.hasPowerLED {
                Circle()
                    .fill(displayedNowPlaying.isPlaying ? Color(hex: "53e08a") : Color(hex: "2a4a32"))
                    .frame(width: 7, height: 7)
                    .shadow(color: displayedNowPlaying.isPlaying ? Color(hex: "53e08a").opacity(0.85) : .clear, radius: 4)
                    .position(x: 46, y: 388)
            }
            if traits.hasPitchSlider {
                pitchFader.position(x: 286, y: 372)
            }
        }
        .frame(width: 384, height: 516)
    }

    private var latch: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(LinearGradient(colors: theme.screwGradient, startPoint: .top, endPoint: .bottom))
            .frame(width: 8, height: 14)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.black.opacity(0.3), lineWidth: 0.5))
    }

    private var pitchFader: some View {
        ZStack {
            Capsule().fill(Color.black.opacity(0.5)).frame(width: 50, height: 6)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
            RoundedRectangle(cornerRadius: 2.5)
                .fill(LinearGradient(colors: theme.screwGradient, startPoint: .top, endPoint: .bottom))
                .frame(width: 11, height: 18)
                .overlay(Rectangle().fill(Color.black.opacity(0.4)).frame(width: 7, height: 0.8))
                .offset(x: 6)
                .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
        }
        .frame(width: 56, height: 22)
    }

    private var platterArea: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "2a2a2a"), Color(hex: "111111"), Color(hex: "080808")],
                        center: UnitPoint(x: 0.4, y: 0.35),
                        startRadius: 0,
                        endRadius: 136
                    )
                )
                .frame(width: 272, height: 272)
                .shadow(color: .black.opacity(0.8), radius: 12, x: 0, y: 4)

            // Audiophile platter rim
            if traits.hasPlatterRing {
                Circle()
                    .strokeBorder(
                        AngularGradient(colors: theme.screwGradient + [theme.screwGradient.first ?? .gray], center: .center),
                        lineWidth: 6
                    )
                    .frame(width: 286, height: 286)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            }

            SpinningVinylView(
                isPlaying: displayedNowPlaying.isPlaying,
                albumArt: displayedAlbumArt,
                vinylTint: extractedColours.dominant,
                isVisible: true,
                diskOpacity: animator.widgetDiskOpacity,
                freezeRotation: animator.platterRotationFrozen,
                overrideAlbumArt: animator.diskArtMode == .incoming
                    ? (animator.incomingAlbumArt ?? bufferedIncomingAlbumArt)
                    : nil,
                albumArtLabelGradient: theme.albumArtLabelGradient,
                albumArtRingColor: theme.albumArtRingColor,
                labelDiameter: 125,
                onAngleSample: { angle in
                    animator.updateRenderedPlatterAngle(angle)
                }
            )

            spindleView
        }
        .frame(width: 272, height: 272)
        .contentShape(Circle())
        .onTapGesture {
            detector.togglePlayback()
        }
    }

    // MARK: - Spindle (standard chrome dot or retro 45-adapter)

    @ViewBuilder
    private var spindleView: some View {
        switch traits.spindle {
        case .standard:
            EmptyView()
        case .retro45:
            ZStack {
                // Chrome 45-rpm adapter ring
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [Color(hex: "f0f0f0"), Color(hex: "8a8a8a"),
                                     Color(hex: "e8e8e8"), Color(hex: "707070"),
                                     Color(hex: "f0f0f0")],
                            center: .center
                        )
                    )
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                // Center pin hole
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "303030"), Color(hex: "0a0a0a")],
                            center: .center, startRadius: 0, endRadius: 5
                        )
                    )
                    .frame(width: 9, height: 9)
                // Top highlight
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 4, height: 4)
                    .offset(x: -5, y: -5)
                    .blur(radius: 1)
            }
        }
    }

    // MARK: - Retro transport controls (prev / play-pause / next)

    private var transportControls: some View {
        HStack(spacing: 14) {
            retroButton(icon: "backward.fill", size: 34) { detector.previousTrack() }
            retroButton(
                icon: displayedNowPlaying.isPlaying ? "pause.fill" : "play.fill",
                size: 34
            ) { detector.togglePlayback() }
            retroButton(icon: "forward.fill", size: 34) { detector.nextTrack() }
        }
    }

    private func retroButton(icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RetroTransportButtonFace(palette: theme, icon: icon, size: size)
        }
        .buttonStyle(RetroButtonStyle())
    }

    // MARK: - Tonearm

    private var tonearmView: some View {
        ZStack {
            // Arm rod — rendered first so the mounting joint below sits on top of it.
            // Two-layer shadow (tight contact shadow + soft ambient) so it reads as
            // a physical rod sitting above the platter rather than a flat drawn shape.
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

            // Mounting joint — a real tonearm's pivot attachment: a dark bezel
            // plate the rod plugs into, with a brushed-chrome cap on top.
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

            // Audiophile counterweight behind the pivot
            if traits.hasCounterweight {
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(colors: [Color(hex: "3a3a3a"), Color(hex: "0c0c0c")],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 17, height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                    .rotationEffect(.degrees(20))
                    .position(x: 80, y: 6)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            }
        }
        .frame(width: 90, height: 180)
    }

    // MARK: - Track Info (modern, sits directly on the body — no card)

    private var modernTrackPanel: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Text(displayedNowPlaying.trackName.isEmpty ? "Nothing Playing" : displayedNowPlaying.trackName)
                    .font(.system(size: 20, weight: .bold))
                    .tracking(0.2)
                    .foregroundStyle(panelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .truncationMode(.tail)

                Text(displayedNowPlaying.trackName.isEmpty ? " " : artistLine)
                    .font(.system(size: 14.5, weight: .medium))
                    .tracking(0.3)
                    .foregroundStyle(panelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.tail)
                    .padding(.top, 4)

                transportRow
                    .padding(.top, 12)
            }
            // The song-switch animator publishes its phase inside
            // withAnimation, and the reveal that swaps the track text rides
            // along in that same update — which cross-faded the title/artist
            // and pointlessly animated the transport glyphs, which never
            // actually change. Snap them, so the text flips at exactly the
            // moment the body colour does.
            .transaction { $0.animation = nil }

            scrubberRow
                .padding(.top, 12)
        }
        // Fixed height keeps the platter (and therefore the tonearm) at a
        // known position regardless of how the text metrics resolve.
        .frame(maxWidth: .infinity)
        .frame(height: 140)
    }

    /// "Artist - Album", collapsing gracefully when either is missing.
    private var artistLine: String {
        let artist = displayedNowPlaying.artistName
        let album = displayedNowPlaying.albumName
        guard !album.isEmpty, album != artist else { return artist }
        guard !artist.isEmpty else { return album }
        return "\(artist) - \(album)"
    }

    // Bare SF Symbol glyphs, no button chrome — matches Apple's Now Playing:
    // the play/pause glyph reads bigger and fully opaque (panelPrimary),
    // skip glyphs smaller and muted (panelSecondary), not all three uniform.
    private var transportRow: some View {
        HStack(spacing: 38) {
            glyphButton("backward.fill", size: 21, color: panelSecondary) { detector.previousTrack() }
            glyphButton(displayedNowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 27, color: panelPrimary) {
                detector.togglePlayback()
            }
            glyphButton("forward.fill", size: 21, color: panelSecondary) { detector.nextTrack() }
        }
    }

    private func glyphButton(_ icon: String, size: CGFloat, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: size, weight: .medium))
                .frame(width: size + 10, height: size + 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    /// Elapsed / remaining flanking a thin scrubbable bar. The knob only
    /// appears while scrubbing, like Apple's own transport.
    private var scrubberRow: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let fraction = isScrubbing
                ? scrubProgress
                : (playbackProgress(at: context.date) ?? 0)
            let duration = Double(displayedNowPlaying.durationMillis ?? 0) / 1000

            HStack(spacing: 9) {
                Text(timeLabel(duration * fraction))
                    .frame(width: 34, alignment: .leading)
                scrubBar(fraction: fraction)
                Text("-" + timeLabel(max(0, duration - duration * fraction)))
                    .frame(width: 34, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(panelSecondary)
        }
        // Visible whenever the track has a duration. This deliberately does
        // NOT use canSeek, which is false during a song-switch animation —
        // that's what made the bar vanish mid-skip. Seeking is still gated
        // on canSeek inside handleScrubDrag.
        .opacity(hasProgressData ? 1 : 0)
    }

    private func scrubBar(fraction: Double) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(panelSecondary.opacity(0.32))
                    .frame(height: isScrubbing ? 6 : 4)
                Capsule()
                    .fill(panelPrimary.opacity(0.92))
                    .frame(width: max(2, width * fraction), height: isScrubbing ? 6 : 4)
                Circle()
                    .fill(panelPrimary)
                    .frame(width: 11, height: 11)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: min(width - 11, max(0, width * fraction - 5.5)))
                    .opacity(isScrubbing ? 1 : 0)
            }
            .frame(height: 22)
            // An NSView capture, not a SwiftUI DragGesture: the window is
            // movable-by-background, and AppKit decides that at mouse-down —
            // too early for a gesture callback to veto, which is why dragging
            // the bar used to drag the whole widget.
            .overlay(
                DragCaptureView(
                    onBegan: { handleScrubDrag(fraction: $0.x / width) },
                    onMoved: { handleScrubDrag(fraction: $0.x / width) },
                    onEnded: {
                        handleScrubDrag(fraction: $0.x / width)
                        commitScrub()
                    },
                    onCancelled: { endScrubSession() }
                )
            )
        }
        .frame(height: 22)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isScrubbing)
    }

    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

}

private struct DragCaptureView: NSViewRepresentable {
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

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

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

// MARK: - SpinningVinylView (Isolated Vinyl Disc + Album Art Label)
/// Isolated subview for smooth vsync'd vinyl rotation.
/// - TimelineView(.animation) provides display-linked frame updates (native requestAnimationFrame equivalent)
/// - Persistent angle tracking: records paused angle, resumes from that point when playing
/// - 33.3 RPM = 199.8°/s rotation speed
/// - Album art label fades in/out as new art loads
/// - Subtle colour tint overlay from dominant album art colour (Phase 8)

struct SpinningVinylView: View {
    // MARK: - Properties
    let isPlaying: Bool
    let albumArt: NSImage?
    let vinylTint: Color
    var isVisible: Bool = true
    var diskOpacity: Double = 1.0
    var freezeRotation: Bool = false
    var overrideAlbumArt: NSImage? = nil
    var albumArtLabelGradient: [Color] = [Color(hex: "9B5523"), Color(hex: "6C3E1A"), Color(hex: "3a1a06")]
    var albumArtRingColor: Color = Color(hex: "ffbe50").opacity(0.30)
    /// Diameter of the album-art label at the disc centre. Defaults to the
    /// original 96 so the horizontal vinyl widget (which shares this view) is
    /// untouched; the v1 widget passes a larger value.
    var labelDiameter: CGFloat = 96
    var onAngleSample: ((Double) -> Void)? = nil

    @State private var pausedAngle: Double = 0
    @State private var playbackStartDate: Date?
    @State private var spinDownStartDate: Date?
    @State private var spinDownStartAngle: Double = 0
    @State private var spinDownEndAngle: Double = 0
    @State private var spinDownToken: UUID?

    private let degreesPerSecond: Double = (5.0 / 60.0) * 360.0
    private let spinDownDuration: TimeInterval = 1.5

    // MARK: - Body
    var body: some View {
        // TimelineView(.animation) fires once per display refresh (~120Hz on 120Hz displays)
        // Keep TimelineView running while decelerating so spin-down stays smooth.
        // This provides vsync-ed smooth rotation without the latency of manual Timer + dispatch
        TimelineView(.animation(paused: freezeRotation || (!isPlaying && spinDownStartDate == nil))) { context in
            let displayAngle = currentAngle(at: context.date)
            let effectiveOpacity = max(0.0, min(1.0, (isVisible ? 1.0 : 0.0) * diskOpacity))
            let sampledAngle = normalized(displayAngle)

            ZStack {
                vinylDisc

                Circle()
                    .fill(vinylTint)
                    .frame(width: 258, height: 258)
                    .opacity(0.12)
                    .blendMode(.softLight)

                Circle()
                    .fill(
                        AngularGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .white.opacity(0.04), location: 0.15),
                                .init(color: .white.opacity(0.08), location: 0.25),
                                .init(color: .white.opacity(0.04), location: 0.35),
                                .init(color: .clear, location: 0.5),
                                .init(color: .clear, location: 1.0)
                            ],
                            center: .center
                        )
                    )
                    .frame(width: 258, height: 258)

                Circle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.07), location: 0),
                                .init(color: .clear, location: 0.4),
                                .init(color: .clear, location: 0.6),
                                .init(color: .white.opacity(0.03), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 258, height: 258)

                albumArtLabel
            }
            .opacity(effectiveOpacity)
            .rotationEffect(.degrees(displayAngle))
            .drawingGroup()
            .onChange(of: sampledAngle) { _, newAngle in
                onAngleSample?(newAngle)
            }
        }
        .onAppear {
            if isPlaying && !freezeRotation {
                playbackStartDate = Date()
            } else {
                playbackStartDate = nil
                spinDownStartDate = nil
                spinDownToken = nil
            }
        }
        .onChange(of: freezeRotation) { _, frozen in
            let now = Date()
            if frozen {
                captureCurrentAngle(at: now)
            } else if isPlaying {
                playbackStartDate = now
            }
        }
        .onChange(of: isPlaying) { _, playing in
            let now = Date()
            if freezeRotation {
                captureCurrentAngle(at: now)
                return
            }
            if playing {
                // Resume exactly from the current decelerating angle if spin-down is in progress.
                if let spinDownStartDate = spinDownStartDate {
                    let elapsed = now.timeIntervalSince(spinDownStartDate)
                    let progress = max(0, min(1, elapsed / spinDownDuration))
                    // Constant deceleration profile (v decreases linearly to zero).
                    let decelProgress = (2 * progress) - (progress * progress)
                    let currentSpinDownAngle = spinDownStartAngle + ((spinDownEndAngle - spinDownStartAngle) * decelProgress)
                    pausedAngle = normalized(currentSpinDownAngle)
                } else {
                    pausedAngle = normalized(pausedAngle)
                }
                spinDownStartDate = nil
                spinDownToken = nil
                playbackStartDate = now
            } else {
                let startAngle: Double
                if let playbackStartDate = playbackStartDate {
                    let elapsed = now.timeIntervalSince(playbackStartDate)
                    startAngle = normalized(pausedAngle + (elapsed * degreesPerSecond))
                } else {
                    startAngle = normalized(pausedAngle)
                }

                let stopDelta = degreesPerSecond * spinDownDuration * 0.5
                pausedAngle = startAngle
                spinDownStartAngle = startAngle
                spinDownEndAngle = startAngle + stopDelta
                spinDownStartDate = now
                let token = UUID()
                spinDownToken = token
                playbackStartDate = nil

                DispatchQueue.main.asyncAfter(deadline: .now() + spinDownDuration) {
                    guard spinDownToken == token, !isPlaying else { return }
                    pausedAngle = normalized(spinDownEndAngle)
                    spinDownStartDate = nil
                    spinDownToken = nil
                }
            }
        }
    }

    // MARK: - Angle Calculation

    /// Compute current vinyl angle based on playback state
    /// When paused: return saved pausedAngle
    /// When playing: return pausedAngle + elapsed rotation since playback started
    private func currentAngle(at date: Date) -> Double {
        if isPlaying, let playbackStartDate = playbackStartDate {
            let elapsed = date.timeIntervalSince(playbackStartDate)
            return normalized(pausedAngle + (elapsed * degreesPerSecond))
        }

        if let spinDownStartDate = spinDownStartDate {
            let elapsed = date.timeIntervalSince(spinDownStartDate)
            let progress = max(0, min(1, elapsed / spinDownDuration))
            // Constant deceleration profile (v decreases linearly to zero).
            let decelProgress = (2 * progress) - (progress * progress)
            let deceleratingAngle = spinDownStartAngle + ((spinDownEndAngle - spinDownStartAngle) * decelProgress)
            return normalized(deceleratingAngle)
        }

        return normalized(pausedAngle)
    }

    /// Keep angle in 0–360° range (wrap around after full rotations)
    private func normalized(_ angle: Double) -> Double {
        let value = angle.truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }

    private func captureCurrentAngle(at date: Date) {
        pausedAngle = normalized(currentAngle(at: date))
        playbackStartDate = nil
        spinDownStartDate = nil
        spinDownToken = nil
    }

    // MARK: - Vinyl Disc

    private var vinylDisc: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "151515"), Color(hex: "0b0b0b"), Color(hex: "050505")],
                        center: .center,
                        startRadius: 12,
                        endRadius: 129
                    )
                )
                .frame(width: 258, height: 258)

            ForEach(0..<80, id: \.self) { i in
                let diameter: CGFloat = 102 + CGFloat(i) * 1.95
                let lightOpacity: Double = (i % 2 == 0) ? 0.06 : 0.03
                let darkOpacity: Double = (i % 2 == 0) ? 0.04 : 0.02

                Circle()
                    .strokeBorder(Color.white.opacity(lightOpacity), lineWidth: 0.35)
                    .frame(width: diameter, height: diameter)

                Circle()
                    .strokeBorder(Color.black.opacity(darkOpacity), lineWidth: 0.5)
                    .frame(width: diameter, height: diameter)
            }

            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 258, height: 258)

            Circle()
                .strokeBorder(Color.white.opacity(0.03), lineWidth: 1)
                .frame(width: 102, height: 102)
        }
    }

    private var albumArtLabel: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: albumArtLabelGradient,
                        center: .center,
                        startRadius: 0,
                        endRadius: labelDiameter / 2
                    )
                )
                .frame(width: labelDiameter, height: labelDiameter)

            if let art = overrideAlbumArt ?? albumArt {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
                    .frame(width: labelDiameter, height: labelDiameter)
                    .clipShape(Circle())
            }
        }
        .frame(width: labelDiameter, height: labelDiameter)
        .overlay(
            Circle()
                .strokeBorder(albumArtRingColor, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.8), radius: 6)
    }

}

// MARK: - Retro button press style

private struct RetroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .brightness(configuration.isPressed ? -0.12 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Springy press feedback for the modern bare-glyph transport buttons.
private struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.84 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Animation Overlay Window

class AnimationOverlayWindow: NSPanel {
    static let overlaySize = CGSize(width: 980, height: 860)

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: AnimationOverlayWindow.overlaySize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
    }

    func position(over widgetFrame: CGRect) {
        let origin = CGPoint(
            x: widgetFrame.midX - (AnimationOverlayWindow.overlaySize.width / 2),
            y: widgetFrame.midY - (AnimationOverlayWindow.overlaySize.height / 2)
        )
        setFrameOrigin(origin)
    }
}

// MARK: - Overlay View

struct AnimationOverlayView: View {
    @ObservedObject var animator: SongSwitchAnimator

    var body: some View {
        ZStack {
            if animator.showFloatingDisk {
                let pose = animator.floatingDiskPose
                LiftedDiskView(albumArt: animator.outgoingAlbumArt)
                    .rotationEffect(.degrees(animator.outgoingTransferAngle))
                    .offset(pose.offset)
                    .scaleEffect(pose.scale, anchor: .center)
                    .opacity(pose.opacity)
                    .rotation3DEffect(
                        .degrees(pose.yaw),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.5
                    )
                    .shadow(color: .black.opacity(pose.shadowOpacity), radius: pose.shadowRadius, y: pose.shadowY)
            }

            if animator.showOutgoingSleeve {
                let pose = animator.outgoingSleevePose
                FlyingSleeveView(
                    albumArt: animator.outgoingAlbumArt,
                    embeddedDiskArt: animator.outgoingAlbumArt,
                    diskExposure: animator.outgoingDiskExposure,
                    transferMode: .capture,
                    embeddedDiskRotation: animator.outgoingTransferAngle
                )
                    .offset(pose.offset)
                    .scaleEffect(pose.scale, anchor: .center)
                    .opacity(pose.opacity)
                    .rotation3DEffect(
                        .degrees(pose.yaw),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.5
                    )
                    .shadow(color: .black.opacity(pose.shadowOpacity), radius: pose.shadowRadius, y: pose.shadowY)
            }

            if animator.showIncomingSleeve {
                let pose = animator.incomingSleevePose
                FlyingSleeveView(
                    albumArt: animator.incomingAlbumArt,
                    embeddedDiskArt: animator.incomingAlbumArt,
                    diskExposure: animator.incomingDiskExposure,
                    transferMode: .reveal,
                    embeddedDiskRotation: 0
                )
                    .offset(pose.offset)
                    .scaleEffect(pose.scale, anchor: .center)
                    .opacity(pose.opacity)
                    .rotation3DEffect(
                        .degrees(pose.yaw),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.5
                    )
                    .shadow(color: .black.opacity(pose.shadowOpacity), radius: pose.shadowRadius, y: pose.shadowY)
            }
        }
        .frame(width: AnimationOverlayWindow.overlaySize.width, height: AnimationOverlayWindow.overlaySize.height)
        .allowsHitTesting(false)
    }
}

// MARK: - Floating Lifted Disk

struct LiftedDiskView: View {
    let albumArt: NSImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "151515"), Color(hex: "0b0b0b"), Color(hex: "050505")],
                        center: .center,
                        startRadius: 12,
                        endRadius: 129
                    )
                )
                .frame(width: 258, height: 258)

            ForEach(0..<80, id: \.self) { i in
                let diameter: CGFloat = 102 + CGFloat(i) * 1.95
                let lightOpacity: Double = (i % 2 == 0) ? 0.05 : 0.025
                let darkOpacity: Double = (i % 2 == 0) ? 0.035 : 0.02

                Circle()
                    .strokeBorder(Color.white.opacity(lightOpacity), lineWidth: 0.35)
                    .frame(width: diameter, height: diameter)

                Circle()
                    .strokeBorder(Color.black.opacity(darkOpacity), lineWidth: 0.5)
                    .frame(width: diameter, height: diameter)
            }

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "9B5523"), Color(hex: "6C3E1A"), Color(hex: "3a1a06")],
                            center: .center,
                            startRadius: 0,
                            endRadius: 62.5
                        )
                    )
                    .frame(width: 125, height: 125)

                if let art = albumArt {
                    Image(nsImage: art)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 125, height: 125)
                        .clipShape(Circle())
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(Color(hex: "ffbe50").opacity(0.3), lineWidth: 2)
            )
        }
        .frame(width: 258, height: 258)
        .overlay(
            Circle()
                .strokeBorder(
                    AngularGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .white.opacity(0.08), location: 0.12),
                            .init(color: .white.opacity(0.22), location: 0.20),
                            .init(color: .white.opacity(0.09), location: 0.28),
                            .init(color: .clear, location: 0.46),
                            .init(color: .clear, location: 1.0)
                        ],
                        center: .center
                    ),
                    lineWidth: 5
                )
                .blur(radius: 0.8)
                .frame(width: 250, height: 250)
        )
    }
}

// MARK: - Flying Sleeve View (Song Switch Animation Overlay)

struct FlyingSleeveView: View {
    enum TransferMode {
        case capture
        case reveal
    }

    let albumArt: NSImage?
    var embeddedDiskArt: NSImage? = nil
    var diskExposure: CGFloat = 0
    var transferMode: TransferMode = .reveal
    var embeddedDiskRotation: Double = 0
    private let size: CGFloat = 236

    var body: some View {
        let clampedExposure = max(0, min(1, diskExposure))
        // Clamp near-zero exposure in capture mode so no residual right-edge sliver lingers
        // after the disk is fully inside the outgoing sleeve.
        let renderExposure: CGFloat = (transferMode == .capture && clampedExposure < 0.16) ? 0 : clampedExposure
        let mouthBoundaryX = size * 0.12
        let revealedDiskX = -(size * 0.46)
        let diskX = mouthBoundaryX + (renderExposure * (revealedDiskX - mouthBoundaryX))
        let diskScale = transferMode == .capture
            ? (0.845 + (renderExposure * 0.01))
            : (0.845 + (renderExposure * 0.018))
        let artImage = albumArt ?? FallbackCoverArtGenerator.fallbackImage

        ZStack {
            if renderExposure > 0.001 {
                LiftedDiskView(albumArt: embeddedDiskArt ?? artImage)
                    .rotationEffect(.degrees(embeddedDiskRotation))
                    .scaleEffect(diskScale, anchor: .center)
                    .offset(x: diskX, y: 0)
                    .opacity(1.0)
                    .mask(
                        GeometryReader { proxy in
                            let visibleWidthMultiplier = transferMode == .capture
                                ? (0.06 + (0.94 * renderExposure))
                                : (0.14 + (0.86 * renderExposure))
                            let visibleWidth = proxy.size.width * visibleWidthMultiplier
                            Rectangle()
                                .frame(width: visibleWidth, height: proxy.size.height, alignment: .leading)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        }
                    )
            }

            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "161616"), Color(hex: "0c0c0c"), Color(hex: "050505")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.05), .clear, .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )

            // Platter-facing mouth lip
            HStack(spacing: 0) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.85), Color.black.opacity(0.15)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 12)
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))

            // Sleeve spine and body separation
            HStack(spacing: 0) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.05), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 18)
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))

            // Clean album cover — slightly oversized so the dark sleeve jacket
            // never peeks around the edges as a frame.
            Image(nsImage: artImage)
                .resizable()
                .scaledToFill()
                .frame(width: size + 2, height: size + 2)
                .clipShape(RoundedRectangle(cornerRadius: 2))

            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.04), .clear, .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .frame(width: size, height: size)
        .compositingGroup()
        // Soft, natural drop shadow — not the heavy dark halo that read as a border.
        .shadow(color: .black.opacity(0.38), radius: 14, x: 0, y: 10)
    }
}

#Preview {
    VinylWidgetView(
        animator: SongSwitchAnimator(),
        themeManager: WidgetThemeManager()
    )
}
