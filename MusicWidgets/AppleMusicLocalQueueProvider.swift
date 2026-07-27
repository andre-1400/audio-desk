import Foundation
import AppKit

final class AppleMusicLocalQueueProvider {
    private let workQueue = DispatchQueue(label: "com.vinylwidget.apple-music-local-queue", qos: .userInitiated)
    private let visibleSlotCount = 4

    func fetchLocalQueue(completion: @escaping ([QueueTrack]) -> Void) {
        workQueue.async {
            let rows = Self.fetchLocalQueueRowsSync(visibleSlotCount: self.visibleSlotCount)
            let visibleSlotCount = self.visibleSlotCount
            Task { @MainActor in
                let tracks = Self.makeQueueTracks(from: rows, visibleSlotCount: visibleSlotCount)
                completion(tracks)
            }
        }
    }

    private static func fetchLocalQueueRowsSync(visibleSlotCount: Int) -> [AppleMusicLocalQueueRow] {
        guard let response = executeAppleScript(appleLocalQueueScript)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !response.isEmpty else {
            return []
        }

        let rowSeparator = "\u{1E}"
        let fieldSeparator = "\u{1F}"
        let rows = response.split(separator: Character(rowSeparator), omittingEmptySubsequences: true)

        var parsedRows: [AppleMusicLocalQueueRow] = []
        for (slot, row) in rows.enumerated() where slot < visibleSlotCount {
            let fields = row.split(separator: Character(fieldSeparator), omittingEmptySubsequences: false)
            guard fields.count >= 6 else { continue }

            let trackName = String(fields[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let artistName = String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let albumName = String(fields[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            let artworkPathOrURL = String(fields[3]).trimmingCharacters(in: .whitespacesAndNewlines)
            let persistentID = String(fields[4]).trimmingCharacters(in: .whitespacesAndNewlines)
            let databaseID = String(fields[5]).trimmingCharacters(in: .whitespacesAndNewlines)

            let normalizedArtworkURL = normalizeArtworkURL(rawValue: artworkPathOrURL)
            let stableIdentity = stableIdentityForAppleTrack(
                persistentID: persistentID,
                databaseID: databaseID,
                trackName: trackName,
                artistName: artistName,
                albumName: albumName
            )

            parsedRows.append(
                AppleMusicLocalQueueRow(
                    slot: slot,
                    trackName: trackName,
                    artistName: artistName,
                    albumArtURL: normalizedArtworkURL,
                    stableIdentity: stableIdentity
                )
            )
        }

        return Array(parsedRows.prefix(visibleSlotCount))
    }

    @MainActor
    private static func makeQueueTracks(from rows: [AppleMusicLocalQueueRow], visibleSlotCount: Int) -> [QueueTrack] {
        var parsedTracks = rows.map { row in
            QueueTrack(
                id: UUID(),
                trackName: row.trackName,
                artistName: row.artistName,
                albumArtURL: row.albumArtURL,
                albumArt: row.albumArtURL.flatMap(loadImage),
                isCurrentTrack: row.slot == 0,
                musicSource: .appleMusic,
                spotifyURI: nil,
                stableIdentity: row.stableIdentity
            )
        }

        while parsedTracks.count < visibleSlotCount {
            parsedTracks.append(.empty(index: parsedTracks.count))
        }
        return Array(parsedTracks.prefix(visibleSlotCount))
    }

    private static func normalizeArtworkURL(rawValue: String) -> String? {
        guard !rawValue.isEmpty else { return nil }

        if rawValue.hasPrefix("file://") || rawValue.hasPrefix("http://") || rawValue.hasPrefix("https://") {
            return rawValue
        }

        if rawValue.hasPrefix("/") {
            return URL(fileURLWithPath: rawValue).absoluteString
        }

        return nil
    }

    @MainActor
    private static func loadImage(from urlString: String) -> NSImage? {
        guard let url = URL(string: urlString) else { return nil }

        if url.isFileURL {
            return NSImage(contentsOf: url)
        }

        if let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
            return image
        }

        return nil
    }

    private struct AppleMusicLocalQueueRow: Sendable {
        let slot: Int
        let trackName: String
        let artistName: String
        let albumArtURL: String?
        let stableIdentity: String
    }

    private static func stableIdentityForAppleTrack(
        persistentID: String,
        databaseID: String,
        trackName: String,
        artistName: String,
        albumName: String
    ) -> String {
        if !persistentID.isEmpty {
            return "apple-pid:\(persistentID.lowercased())"
        }
        if !databaseID.isEmpty {
            return "apple-dbid:\(databaseID.lowercased())"
        }
        let normalizedTrack = trackName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedArtist = artistName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedAlbum = albumName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedTrack.isEmpty && normalizedArtist.isEmpty && normalizedAlbum.isEmpty {
            return ""
        }
        return "apple-meta:\(normalizedTrack)|\(normalizedArtist)|\(normalizedAlbum)"
    }

    // Same reasoning as MusicDetector's own executeAppleScript: no built-in
    // cancellation/timeout, so a hung target app would otherwise block
    // whatever called this indefinitely. Bounded the same way — run on a
    // separate queue, cap how long the caller waits.
    private static let scriptTimeoutSeconds: TimeInterval = 5

    @discardableResult
    private static func executeAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }

        let semaphore = DispatchSemaphore(value: 0)
        var outcome: String?
        let execQueue = DispatchQueue(label: "com.vinylwidget.applemusic-queue-exec", qos: .userInitiated)
        execQueue.async {
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if error == nil {
                outcome = result.stringValue
            }
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + scriptTimeoutSeconds) == .success else {
            return nil
        }
        return outcome
    }

    private static let appleLocalQueueScript = """
    set rowSep to (ASCII character 30)
    set fieldSep to (ASCII character 31)

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
        set textValue to my replaceText(textValue, (ASCII character 30), " ")
        set textValue to my replaceText(textValue, (ASCII character 31), " ")
        set textValue to my replaceText(textValue, linefeed, " ")
        set textValue to my replaceText(textValue, return, " ")
        return textValue
    end sanitizeField

    on writeArtwork(binaryData, persistentIDValue, databaseIDValue, trackIndexValue)
        set tempFolder to POSIX path of (path to temporary items from user domain)
        set suffixValue to persistentIDValue as text
        if suffixValue is "" then set suffixValue to databaseIDValue as text
        if suffixValue is "" then set suffixValue to trackIndexValue as text
        set filePath to tempFolder & "vinylwidget_am_" & suffixValue & "_" & (trackIndexValue as text) & ".jpg"
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

    tell application "Music"
        if player state is stopped then return ""
        set currentTrackRef to current track
        set currentPlaylistRef to current playlist
        if currentTrackRef is missing value or currentPlaylistRef is missing value then return ""

        set oldFixedIndexing to fixed indexing
        set fixed indexing to true

        set rows to {}
        set currentTrackIndex to index of currentTrackRef
        set totalTrackCount to count of tracks of currentPlaylistRef

        repeat with offsetValue from 0 to 3
            set targetTrackIndex to currentTrackIndex + offsetValue
            if targetTrackIndex <= totalTrackCount then
                set trackRef to track targetTrackIndex of currentPlaylistRef
                set trackNameValue to my sanitizeField(name of trackRef)
                set artistNameValue to my sanitizeField(artist of trackRef)
                set albumNameValue to my sanitizeField(album of trackRef)

                set persistentIDValue to ""
                try
                    set persistentIDValue to my sanitizeField(persistent ID of trackRef)
                end try

                set databaseIDValue to ""
                try
                    set databaseIDValue to my sanitizeField(database ID of trackRef as text)
                end try

                set artworkPathValue to ""
                try
                    if (count of artworks of trackRef) > 0 then
                        set artworkData to data of artwork 1 of trackRef
                        if artworkData is not missing value then
                            set artworkPathValue to my sanitizeField(my writeArtwork(artworkData, persistentIDValue, databaseIDValue, targetTrackIndex))
                        end if
                    end if
                end try

                set rowValue to trackNameValue & fieldSep & artistNameValue & fieldSep & albumNameValue & fieldSep & artworkPathValue & fieldSep & persistentIDValue & fieldSep & databaseIDValue
                set end of rows to rowValue
            end if
        end repeat

        set fixed indexing to oldFixedIndexing
    end tell

    set AppleScript's text item delimiters to rowSep
    set payload to rows as text
    set AppleScript's text item delimiters to ""
    return payload
    """
}
