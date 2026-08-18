import AppKit
import Combine
import Foundation

final class MusicDetector: ObservableObject {
    @Published var nowPlaying: NowPlayingInfo = .empty

    /// True when the OS has denied this app permission to send Apple Events to
    /// Spotify/Music (user clicked "Don't Allow" on the automation prompt, or
    /// revoked it later in System Settings). Distinguishes "denied" from
    /// "app isn't running" — both silently returned nil before this existed,
    /// so a misclick made the widget look permanently broken with no way to
    /// tell why.
    @Published var automationPermissionDenied = false

    private enum PlayerPlaybackState {
        case playing
        case paused
        case stopped
        case unknown
    }

    private enum ScriptOutcome {
        case success(String)
        case permissionDenied
        case otherError
    }

    private struct SourceProbe {
        let source: MusicSource
        let isRunning: Bool
        let playbackState: PlayerPlaybackState
        let nowPlaying: NowPlayingInfo
        let permissionDenied: Bool

        init(source: MusicSource, isRunning: Bool, playbackState: PlayerPlaybackState, nowPlaying: NowPlayingInfo, permissionDenied: Bool = false) {
            self.source = source
            self.isRunning = isRunning
            self.playbackState = playbackState
            self.nowPlaying = nowPlaying
            self.permissionDenied = permissionDenied
        }

        var isPlaying: Bool { playbackState == .playing }
        var isPaused: Bool { playbackState == .paused }
    }

    private struct ParsedNowPlaying {
        let info: NowPlayingInfo
        let playbackState: PlayerPlaybackState
    }

    private var timer: Timer?
    // Shared across every MusicDetector instance (menu-bar status item plus
    // whichever widget is active) rather than one queue per instance —
    // NSAppleScript isn't documented as thread-safe, and two instances each
    // running their own serial queue could still call executeAndReturnError
    // concurrently on two different threads at once. Funnelling every
    // instance's polling through one shared serial queue guarantees at most
    // one AppleScript call is in flight app-wide, which is what actually
    // needs to be true, not just serial-per-instance.
    private static let detectionQueue = DispatchQueue(label: "com.vinylwidget.music-detection", qos: .userInitiated)

    // User-initiated transport commands get their own queue rather than
    // sharing the polling one. Thread-safety against concurrent
    // NSAppleScript calls is already guaranteed further down by
    // executeAppleScript's own static execQueue (every script, from any
    // caller, runs serialized there), so detectionQueue was only ever
    // providing ordering — and sharing it meant a button tap had to wait
    // behind every poll already queued ahead of it. With up to eight
    // MusicDetector instances alive (menu bar + gallery + whichever
    // widgets are open), each enqueueing two scripts every 0.25s, that
    // backlog is what produced first the UI freeze (when this was a
    // blocking .sync) and then the multi-second command delay (once it
    // became .async). A tap now waits only for whatever single script is
    // actually mid-flight.
    private static let commandQueue = DispatchQueue(label: "com.vinylwidget.music-command", qos: .userInitiated)

    /// Guards against stacking polls. The 0.25s timer fires regardless of
    /// whether the previous poll finished, and a poll is two AppleScript
    /// round-trips — so without this, every instance could enqueue work
    /// faster than the shared serial queue drains it and the backlog grew
    /// without bound, pushing displayed state further and further behind
    /// reality the longer the app ran. Main-thread only (every caller is),
    /// so a plain Bool is enough.
    private var pollInFlight = false

    /// Guards the optimistic play/pause flip against the source app's own
    /// lag. `playpause` returns before Spotify/Music has finished applying
    /// it, so the very next poll can still report the *previous* state.
    /// Accepting that would flip the UI back and then forward again a tick
    /// later — and because the vinyl view starts a 0.42s tonearm animation
    /// on every isPlaying change, each spurious flip is a visible sweep, so
    /// the arm lurched toward the wrong position before settling. Hold the
    /// optimistic value until the source agrees with it, or the window
    /// lapses (so a command that silently failed still self-corrects).
    /// Mirrors the seek-handoff suppression the widget views already do.
    private var optimisticPlaybackUntil: Date?
    private var optimisticIsPlaying = false
    private let optimisticPlaybackWindow: TimeInterval = 1.0

    /// The same guard for seeks. `set player position` also returns before
    /// the source has applied it, so a poll landing in between reports the
    /// pre-seek position — which drags the tonearm back toward where the
    /// track *was* before it swings to the scrubbed position. Held until
    /// the source reports a position consistent with the seek target.
    private var seekHoldUntil: Date?
    private var seekTargetMillis = 0
    private var seekIssuedAt: Date = .distantPast
    private let seekHoldWindow: TimeInterval = 1.0
    /// How far off the expected position a sample may be and still count as
    /// "the seek landed". Generous, because the alternative failure — a
    /// short seek being mistaken for a stale sample — is invisible anyway:
    /// if the source is within this much of the target, so is the tonearm.
    private let seekPositionToleranceMillis = 1500

    // Used to resolve "both apps are playing" ties by the most recent state transition.
    private var lastSpotifyPlaybackState: PlayerPlaybackState = .stopped
    private var lastApplePlaybackState: PlayerPlaybackState = .stopped
    private var lastSpotifyStateChangeAt: Date = .distantPast
    private var lastAppleStateChangeAt: Date = .distantPast
    private var lastSelectedSource: MusicSource = .none

    func start() {
        stop()
        pollNowPlaying()
        let newTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.pollNowPlaying()
        }
        newTimer.tolerance = 0.03
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pollInFlight = false
        optimisticPlaybackUntil = nil
        seekHoldUntil = nil
    }

    deinit {
        stop()
    }

    private func pollNowPlaying() {
        // Skip rather than stack up — see pollInFlight. Dropping a tick is
        // harmless (the next one is 0.25s away); queueing it is not.
        guard !pollInFlight else { return }
        pollInFlight = true
        Self.detectionQueue.async { [weak self] in
            guard let self else { return }
            let (newState, permissionDenied) = self.detectNowPlaying()
            DispatchQueue.main.async {
                self.pollInFlight = false
                if permissionDenied != self.automationPermissionDenied {
                    self.automationPermissionDenied = permissionDenied
                }
                // Drop the whole sample rather than half-merging it — the
                // position that came back alongside a stale isPlaying is
                // just as stale. The next poll is 0.25s away.
                guard !self.shouldHoldOptimisticUpdate(against: newState) else { return }
                if newState != self.nowPlaying {
                    self.nowPlaying = newState
                }
            }
        }
    }

    private func detectNowPlaying() -> (NowPlayingInfo, permissionDenied: Bool) {
        let spotify = probeSource(.spotify)
        let apple = probeSource(.appleMusic)

        updateStateChangeTracking(for: spotify)
        updateStateChangeTracking(for: apple)

        let selectedSource = selectPreferredSource(spotify: spotify, apple: apple)
        lastSelectedSource = selectedSource
        let permissionDenied = spotify.permissionDenied || apple.permissionDenied

        switch selectedSource {
        case .spotify:
            return (spotify.nowPlaying, permissionDenied)
        case .appleMusic:
            return (apple.nowPlaying, permissionDenied)
        case .none:
            return (.empty, permissionDenied)
        }
    }

    private func probeSource(_ source: MusicSource) -> SourceProbe {
        let bundleIdentifier: String
        let scriptSource: String

        switch source {
        case .spotify:
            bundleIdentifier = "com.spotify.client"
            scriptSource = Self.spotifyAppleScript
        case .appleMusic:
            bundleIdentifier = "com.apple.Music"
            scriptSource = Self.appleMusicAppleScript
        case .none:
            return SourceProbe(source: .none, isRunning: false, playbackState: .stopped, nowPlaying: .empty)
        }

        guard Self.isApplicationRunning(bundleIdentifier: bundleIdentifier) else {
            return SourceProbe(
                source: source,
                isRunning: false,
                playbackState: .stopped,
                nowPlaying: emptyNowPlaying(for: source)
            )
        }

        switch Self.executeAppleScript(scriptSource) {
        case .success(let response):
            let parsed = Self.parseNowPlayingResponse(response, source: source)
            return SourceProbe(
                source: source,
                isRunning: true,
                playbackState: parsed.playbackState,
                nowPlaying: parsed.info
            )
        case .permissionDenied:
            return SourceProbe(
                source: source,
                isRunning: true,
                playbackState: .unknown,
                nowPlaying: emptyNowPlaying(for: source),
                permissionDenied: true
            )
        case .otherError:
            return SourceProbe(
                source: source,
                isRunning: true,
                playbackState: .unknown,
                nowPlaying: emptyNowPlaying(for: source)
            )
        }
    }

    private func updateStateChangeTracking(for probe: SourceProbe) {
        let now = Date()

        switch probe.source {
        case .spotify:
            guard probe.playbackState != .unknown else { return }
            if probe.playbackState != lastSpotifyPlaybackState {
                lastSpotifyPlaybackState = probe.playbackState
                lastSpotifyStateChangeAt = now
            }
        case .appleMusic:
            guard probe.playbackState != .unknown else { return }
            if probe.playbackState != lastApplePlaybackState {
                lastApplePlaybackState = probe.playbackState
                lastAppleStateChangeAt = now
            }
        case .none:
            break
        }
    }

    private func selectPreferredSource(spotify: SourceProbe, apple: SourceProbe) -> MusicSource {
        // Primary rule: if one source is playing and the other isn't, choose the playing source.
        if spotify.isPlaying && !apple.isPlaying { return .spotify }
        if apple.isPlaying && !spotify.isPlaying { return .appleMusic }
 
        // If both are actively playing, prefer the one whose player state changed most recently.
        if spotify.isPlaying && apple.isPlaying {
            if lastSpotifyStateChangeAt > lastAppleStateChangeAt { return .spotify }
            if lastAppleStateChangeAt > lastSpotifyStateChangeAt { return .appleMusic }
            if lastSelectedSource == .spotify || lastSelectedSource == .appleMusic {
                return lastSelectedSource
            }
            return .spotify
        }

        // Nobody is playing; if one source is paused and the other is not, prefer paused source.
        if spotify.isPaused && !apple.isPaused { return .spotify }
        if apple.isPaused && !spotify.isPaused { return .appleMusic }

        // Both paused: use the same tie-break rule.
        if spotify.isPaused && apple.isPaused {
            if lastSpotifyStateChangeAt > lastAppleStateChangeAt { return .spotify }
            if lastAppleStateChangeAt > lastSpotifyStateChangeAt { return .appleMusic }
            if lastSelectedSource == .spotify || lastSelectedSource == .appleMusic {
                return lastSelectedSource
            }
            return .spotify
        }

         
        // Fallback when scripts return partial metadata in unknown states.
        if !spotify.nowPlaying.trackName.isEmpty && apple.nowPlaying.trackName.isEmpty { return .spotify }
        if !apple.nowPlaying.trackName.isEmpty && spotify.nowPlaying.trackName.isEmpty { return .appleMusic }

        return .none
    }

    private func emptyNowPlaying(for source: MusicSource) -> NowPlayingInfo {
        NowPlayingInfo(
            trackName: "",
            artistName: "",
            albumName: "",
            albumArtURL: nil,
            isPlaying: false,
            source: source
        )
    }

    /// -1743 = errAEEventNotPermitted: the user denied (or later revoked) the
    /// automation permission prompt for this app. Any other error is treated
    /// as transient (e.g. the target app is launching/quitting mid-poll).
    private static let automationDeniedErrorNumber = -1743

    /// NSAppleScript.executeAndReturnError has no cancellation/timeout API
    /// of its own — if Spotify/Music is hung (beachballing, relaunching
    /// mid-call), this call just blocks forever. Every call site here goes
    /// through detectionQueue (either .sync from a transport button tap or
    /// .async from the polling timer), so an indefinite hang wasn't just
    /// slow, it could freeze the *next* transport tap too, since .sync
    /// callers share that same serial queue. Running the actual call on a
    /// separate queue and bounding how long we wait on it means a hung
    /// target app can no longer stall the caller past this timeout — the
    /// background call is simply abandoned (there's no way to force-kill
    /// it once started) and treated as a plain failure.
    private static let scriptTimeoutSeconds: TimeInterval = 5

    // One shared queue for every AppleScript call, not a fresh queue (and
    // thread) per call — this used to spin up a brand-new DispatchQueue on
    // every single invocation, which at a 0.25s poll interval with two
    // sources (Spotify + Apple Music) meant ~8 new threads/sec and was the
    // actual cause of the polling stutter, not the semaphore wait itself.
    private static let execQueue = DispatchQueue(label: "com.vinylwidget.applescript-exec", qos: .userInitiated)

    @discardableResult
    private static func executeAppleScript(_ source: String) -> ScriptOutcome {
        guard let script = NSAppleScript(source: source) else {
            return .otherError
        }

        let semaphore = DispatchSemaphore(value: 0)
        var outcome: ScriptOutcome = .otherError
        execQueue.async {
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if let error {
                let errorNumber = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
                outcome = errorNumber == automationDeniedErrorNumber ? .permissionDenied : .otherError
            } else if let text = result.stringValue {
                outcome = .success(text)
            }
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + scriptTimeoutSeconds) == .success else {
            return .otherError
        }
        return outcome
    }

    private static func parseNowPlayingResponse(_ response: String, source: MusicSource) -> ParsedNowPlaying {
        let parts = response
            .split(separator: "|", maxSplits: 6, omittingEmptySubsequences: false)
            .map(String.init)

        guard parts.count >= 5 else {
            return ParsedNowPlaying(
                info: NowPlayingInfo(
                    trackName: "",
                    artistName: "",
                    albumName: "",
                    albumArtURL: nil,
                    isPlaying: false,
                    source: source
                ),
                playbackState: .unknown
            )
        }

        let trackName = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let artistName = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let albumName = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let rawAlbumArtLocation = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
        let stateRaw = parts[4].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let positionMillis = parts.count > 5 ? parseOptionalMillis(parts[5]) : nil
        let durationMillis = parts.count > 6 ? parseOptionalMillis(parts[6]) : nil

        let playbackState: PlayerPlaybackState
        switch stateRaw {
        case "playing":
            playbackState = .playing
        case "paused":
            playbackState = .paused
        case "stopped":
            playbackState = .stopped
        default:
            playbackState = .unknown
        }

        let albumArtURL = normalizeArtworkLocation(rawAlbumArtLocation)
        let info = NowPlayingInfo(
            trackName: trackName,
            artistName: artistName,
            albumName: albumName,
            albumArtURL: albumArtURL,
            isPlaying: playbackState == .playing,
            source: source,
            positionMillis: positionMillis,
            durationMillis: durationMillis,
            progressSampledAt: playbackState == .playing && positionMillis != nil ? Date() : nil
        )

        return ParsedNowPlaying(info: info, playbackState: playbackState)
    }

    private static func parseOptionalMillis(_ rawValue: String) -> Int? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value >= 0 else { return nil }
        return value
    }

    private static func normalizeArtworkLocation(_ rawValue: String) -> String? {
        guard !rawValue.isEmpty, rawValue != "." else { return nil }
        if rawValue.hasPrefix("file://") || rawValue.hasPrefix("http://") || rawValue.hasPrefix("https://") {
            return rawValue
        }
        if rawValue.hasPrefix("/") {
            return URL(fileURLWithPath: rawValue).absoluteString
        }
        return nil
    }

    func togglePlayback() {
        // Queued on the same shared serial queue polling uses, so this
        // command and any in-flight poll still never overlap (NSAppleScript
        // isn't documented as thread-safe against that) — but dispatched
        // .async, not .sync. This used to block the calling thread (the
        // main thread, from a button tap) until its turn on the queue came
        // up AND the AppleScript round-trip finished, which meant a badly-
        // timed tap could freeze the entire UI for as long as an in-flight
        // poll (up to two AppleScript calls) plus this command took to run
        // — the exact "snappy, laggy" stall that was reported. Async keeps
        // the queue's ordering guarantee without blocking the tap itself.
        let source = nowPlaying.source == .none ? preferredToggleSourceFallback() : nowPlaying.source
        guard source != .none else { return }

        // Flip local state immediately so the widget responds to the click
        // itself rather than to the confirming poll a round-trip later. The
        // poll below still corrects this if the command didn't take.
        if !nowPlaying.trackName.isEmpty {
            let resuming = !nowPlaying.isPlaying
            nowPlaying = NowPlayingInfo(
                trackName: nowPlaying.trackName,
                artistName: nowPlaying.artistName,
                albumName: nowPlaying.albumName,
                albumArtURL: nowPlaying.albumArtURL,
                isPlaying: resuming,
                source: nowPlaying.source,
                positionMillis: estimatedPositionMillis(),
                durationMillis: nowPlaying.durationMillis,
                // Pausing freezes progress (no sample date); resuming
                // restarts the clock from the position just captured.
                progressSampledAt: resuming ? Date() : nil
            )
            // Hold this against stale polls until the source agrees.
            optimisticIsPlaying = resuming
            optimisticPlaybackUntil = Date().addingTimeInterval(optimisticPlaybackWindow)
        }

        Self.commandQueue.async { [weak self] in
            switch source {
            case .spotify:
                Self.executeAppleScript("tell application \"Spotify\" to playpause")
            case .appleMusic:
                Self.executeAppleScript("tell application \"Music\" to playpause")
            case .none:
                break
            }
            // Scheduled from the command's own completion, so it can't fire
            // before the command ran and read back the pre-toggle state.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.pollNowPlaying()
            }
        }
    }

    /// True while any local optimistic change is still waiting for the
    /// source app to agree, meaning this sample should be ignored. Both
    /// predicates run (no short-circuit) so each clears its own state.
    private func shouldHoldOptimisticUpdate(against incoming: NowPlayingInfo) -> Bool {
        let holdingPlayback = shouldHoldOptimisticPlayback(against: incoming)
        let holdingSeek = shouldHoldSeek(against: incoming)
        return holdingPlayback || holdingSeek
    }

    private func shouldHoldSeek(against incoming: NowPlayingInfo) -> Bool {
        guard let until = seekHoldUntil else { return false }

        guard Date() < until else {
            seekHoldUntil = nil
            return false
        }
        guard incoming.trackName == nowPlaying.trackName else {
            seekHoldUntil = nil
            return false
        }
        // No position to judge by — hold rather than risk snapping back.
        guard let incomingPosition = incoming.positionMillis else { return true }

        // Where the seek target should have drifted to by now, if playing.
        let elapsedMillis = nowPlaying.isPlaying
            ? max(0, Int(Date().timeIntervalSince(seekIssuedAt) * 1000))
            : 0
        let expected = seekTargetMillis + elapsedMillis

        guard abs(incomingPosition - expected) > seekPositionToleranceMillis else {
            seekHoldUntil = nil
            return false
        }
        return true
    }

    /// True while an optimistic play/pause flip is still waiting for the
    /// source app to agree, meaning this sample should be ignored.
    private func shouldHoldOptimisticPlayback(against incoming: NowPlayingInfo) -> Bool {
        guard let until = optimisticPlaybackUntil else { return false }

        // Window lapsed — the command presumably didn't take. Let the
        // truth through rather than holding a wrong state indefinitely.
        guard Date() < until else {
            optimisticPlaybackUntil = nil
            return false
        }
        // A different track means something changed out from under the
        // toggle (skip, queue advance); that update matters more.
        guard incoming.trackName == nowPlaying.trackName else {
            optimisticPlaybackUntil = nil
            return false
        }
        // Source caught up — stop holding, accept this and every sample after.
        guard incoming.isPlaying != optimisticIsPlaying else {
            optimisticPlaybackUntil = nil
            return false
        }
        return true
    }

    /// Current playback position, advanced by however long it's been since
    /// the last sample if playing. Used to hand the optimistic pause an
    /// accurate freeze point instead of a stale one.
    private func estimatedPositionMillis() -> Int? {
        guard let base = nowPlaying.positionMillis else { return nil }
        guard nowPlaying.isPlaying, let sampledAt = nowPlaying.progressSampledAt else { return base }
        let elapsed = Int(Date().timeIntervalSince(sampledAt) * 1000)
        guard elapsed > 0 else { return base }
        if let duration = nowPlaying.durationMillis {
            return min(duration, base + elapsed)
        }
        return base + elapsed
    }

    func nextTrack() {
        runTransportCommand(spotify: "next track", appleMusic: "next track")
    }

    func previousTrack() {
        runTransportCommand(spotify: "previous track", appleMusic: "back track")
    }

    private func runTransportCommand(spotify: String, appleMusic: String) {
        let source: MusicSource = nowPlaying.source == .none
            ? preferredToggleSourceFallback()
            : nowPlaying.source

        // Own queue, not the polling one — see commandQueue for why.
        Self.commandQueue.async { [weak self] in
            switch source {
            case .spotify:
                Self.executeAppleScript("tell application \"Spotify\" to \(spotify)")
            case .appleMusic:
                Self.executeAppleScript("tell application \"Music\" to \(appleMusic)")
            case .none:
                break
            }
            // Poll a couple of times so the new track shows up quickly,
            // timed from when the command actually finished.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.pollNowPlaying()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.pollNowPlaying()
            }
        }
    }

    func seek(toMillis targetMillis: Int) {
        let sanitizedMillis = max(0, targetMillis)
        let seconds = Double(sanitizedMillis) / 1000.0
        let secondsLiteral = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), seconds)

        switch nowPlaying.source {
        case .spotify, .appleMusic:
            break
        case .none:
            return
        }
        // Optimistic local update first — doesn't depend on the AppleScript
        // command's result at all (it's built purely from already-known
        // local state plus the target position), so there's no reason to
        // wait on the command to show the scrub instantly.
        let source = nowPlaying.source
        nowPlaying = NowPlayingInfo(
            trackName: nowPlaying.trackName,
            artistName: nowPlaying.artistName,
            albumName: nowPlaying.albumName,
            albumArtURL: nowPlaying.albumArtURL,
            isPlaying: nowPlaying.isPlaying,
            source: nowPlaying.source,
            positionMillis: sanitizedMillis,
            durationMillis: nowPlaying.durationMillis,
            progressSampledAt: nowPlaying.isPlaying ? Date() : nil
        )
        // Hold this against pre-seek polls until the source lands on it.
        seekTargetMillis = sanitizedMillis
        seekIssuedAt = Date()
        seekHoldUntil = Date().addingTimeInterval(seekHoldWindow)

        // Own queue, not the polling one — see commandQueue for why.
        Self.commandQueue.async { [weak self] in
            switch source {
            case .spotify:
                Self.executeAppleScript("tell application \"Spotify\" to set player position to \(secondsLiteral)")
            case .appleMusic:
                Self.executeAppleScript("tell application \"Music\" to set player position to \(secondsLiteral)")
            case .none:
                break
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.pollNowPlaying()
            }
        }
    }

    private func preferredToggleSourceFallback() -> MusicSource {
        let spotifyRunning = Self.isApplicationRunning(bundleIdentifier: "com.spotify.client")
        let appleRunning = Self.isApplicationRunning(bundleIdentifier: "com.apple.Music")

        if spotifyRunning && !appleRunning { return .spotify }
        if appleRunning && !spotifyRunning { return .appleMusic }
        if spotifyRunning && appleRunning {
            if lastSelectedSource == .spotify || lastSelectedSource == .appleMusic {
                return lastSelectedSource
            }
            return .spotify
        }
        return .none
    }

    private static func isApplicationRunning(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier
        }
    }

    private static let spotifyAppleScript = """
    tell application "Spotify"
      if player state is stopped then
        return "|||.|stopped||"
      end if
      set trackName to name of current track
      set artistName to artist of current track
      set albumName to album of current track
      set artworkURL to artwork url of current track
      -- Spotify's own scripting dictionary is asymmetric: "player position"
      -- is a real number of SECONDS (needs *1000), but "duration" is already
      -- an integer of MILLISECONDS. A previous version guessed at this with
      -- a magnitude heuristic (durationValue > 86400) instead of just
      -- trusting the dictionary — which silently multiplied by 1000 a
      -- second time for any track under ~86 seconds, producing an
      -- absurd remaining-time readout (e.g. a 33-second track showing
      -- "-555:36" remaining). Duration needs no conversion at all.
      set positionMillis to ""
      try
        set positionMillis to ((((player position) as real) * 1000) as integer) as text
      end try
      set durationMillis to ""
      try
        set durationMillis to (duration of current track) as integer as text
      end try
      if player state is playing then
        return trackName & "|" & artistName & "|" & albumName & "|" & artworkURL & "|playing|" & positionMillis & "|" & durationMillis
      else
        return trackName & "|" & artistName & "|" & albumName & "|" & artworkURL & "|paused|" & positionMillis & "|" & durationMillis
      end if
    end tell
    """

    private static let appleMusicAppleScript = """
    on replaceText(sourceText, searchText, replacementText)
        set AppleScript's text item delimiters to searchText
        set textItems to text items of sourceText
        set AppleScript's text item delimiters to replacementText
        set outputText to textItems as text
        set AppleScript's text item delimiters to ""
        return outputText
    end replaceText

    on sanitizeField(inputValue)
        set textValue to inputValue as text
        set textValue to my replaceText(textValue, linefeed, " ")
        set textValue to my replaceText(textValue, return, " ")
        set textValue to my replaceText(textValue, "|", " ")
        return textValue
    end sanitizeField

    on writeArtwork(binaryData, persistentIDValue, databaseIDValue)
        set tempFolder to POSIX path of (path to temporary items from user domain)
        set suffixValue to persistentIDValue as text
        if suffixValue is "" then set suffixValue to databaseIDValue as text
        if suffixValue is "" then set suffixValue to "current"
        set filePath to tempFolder & "vinylwidget_am_current_" & suffixValue & ".jpg"
        set fileRef to open for access POSIX file filePath with write permission
        try
            set eof fileRef to 0
            write binaryData to fileRef
        on error
            try
                close access fileRef
            end try
            error
        end try
        close access fileRef
        return filePath
    end writeArtwork

    on millisFromSeconds(secondsValue)
        return (((secondsValue as real) * 1000) as integer)
    end millisFromSeconds

    tell application "Music"
      if player state is stopped then
        return "|||.|stopped||"
      end if

      set trackRef to current track
      set trackName to my sanitizeField(name of trackRef)
      set artistName to my sanitizeField(artist of trackRef)
      set albumName to my sanitizeField(album of trackRef)
      set positionMillis to ""
      try
        set positionMillis to (my millisFromSeconds(player position)) as text
      end try
      set durationMillis to ""
      try
        set durationMillis to (my millisFromSeconds(duration of trackRef)) as text
      end try

      set persistentIDValue to ""
      try
        set persistentIDValue to my sanitizeField(persistent ID of trackRef)
      end try

      set databaseIDValue to ""
      try
        set databaseIDValue to my sanitizeField(database ID of trackRef as text)
      end try

      set artworkPath to "."
      try
        if (count of artworks of trackRef) > 0 then
          set artworkData to data of artwork 1 of trackRef
          if artworkData is not missing value then
            set artworkPath to my sanitizeField(my writeArtwork(artworkData, persistentIDValue, databaseIDValue))
          end if
        end if
      end try

      if player state is playing then
        return trackName & "|" & artistName & "|" & albumName & "|" & artworkPath & "|playing|" & positionMillis & "|" & durationMillis
      else
        return trackName & "|" & artistName & "|" & albumName & "|" & artworkPath & "|paused|" & positionMillis & "|" & durationMillis
      end if
    end tell
    """
}
