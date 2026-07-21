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
    private let detectionQueue = DispatchQueue(label: "com.vinylwidget.music-detection", qos: .userInitiated)

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
    }

    deinit {
        stop()
    }

    private func pollNowPlaying() {
        detectionQueue.async { [weak self] in
            guard let self else { return }
            let (newState, permissionDenied) = self.detectNowPlaying()
            DispatchQueue.main.async {
                if newState != self.nowPlaying {
                    self.nowPlaying = newState
                }
                if permissionDenied != self.automationPermissionDenied {
                    self.automationPermissionDenied = permissionDenied
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

    @discardableResult
    private static func executeAppleScript(_ source: String) -> ScriptOutcome {
        guard let script = NSAppleScript(source: source) else {
            return .otherError
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let errorNumber = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
            return errorNumber == automationDeniedErrorNumber ? .permissionDenied : .otherError
        }

        guard let text = result.stringValue else {
            return .otherError
        }
        return .success(text)
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
        switch nowPlaying.source {
        case .spotify:
            Self.executeAppleScript("tell application \"Spotify\" to playpause")
        case .appleMusic:
            Self.executeAppleScript("tell application \"Music\" to playpause")
        case .none:
            let fallbackSource = preferredToggleSourceFallback()
            switch fallbackSource {
            case .spotify:
                Self.executeAppleScript("tell application \"Spotify\" to playpause")
            case .appleMusic:
                Self.executeAppleScript("tell application \"Music\" to playpause")
            case .none:
                break
            }
        }

        // Poll immediately so the UI updates fast
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.pollNowPlaying()
        }
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

        switch source {
        case .spotify:
            Self.executeAppleScript("tell application \"Spotify\" to \(spotify)")
        case .appleMusic:
            Self.executeAppleScript("tell application \"Music\" to \(appleMusic)")
        case .none:
            break
        }

        // Poll a couple of times so the new track shows up quickly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.pollNowPlaying()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.pollNowPlaying()
        }
    }

    func seek(toMillis targetMillis: Int) {
        let sanitizedMillis = max(0, targetMillis)
        let seconds = Double(sanitizedMillis) / 1000.0
        let secondsLiteral = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), seconds)

        switch nowPlaying.source {
        case .spotify:
            Self.executeAppleScript("tell application \"Spotify\" to set player position to \(secondsLiteral)")
        case .appleMusic:
            Self.executeAppleScript("tell application \"Music\" to set player position to \(secondsLiteral)")
        case .none:
            return
        }

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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.pollNowPlaying()
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
      set positionMillis to ""
      try
        set positionMillis to ((((player position) as real) * 1000) as integer) as text
      end try
      set durationMillis to ""
      try
        set durationValue to duration of current track
        if durationValue > 86400 then
          set durationMillis to (durationValue as integer) as text
        else
          set durationMillis to ((((durationValue as real) * 1000) as integer) as text)
        end if
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
