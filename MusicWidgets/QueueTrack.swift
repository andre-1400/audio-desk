// QueueTrack.swift
// Shared track model used by the flying-sleeve animation and the local
// Apple Music queue heuristic. Extracted from the (now-removed) Spotify
// OAuth queue-fetching code, which this type outlived.

import AppKit

struct QueueTrack: Identifiable, Equatable {
    let id: UUID
    let trackName: String
    let artistName: String
    let albumArtURL: String?
    let spotifyURI: String?
    let musicSource: MusicSource
    let stableIdentity: String
    var albumArt: NSImage?
    let isCurrentTrack: Bool

    init(
        id: UUID = UUID(),
        trackName: String,
        artistName: String,
        albumArtURL: String?,
        albumArt: NSImage?,
        isCurrentTrack: Bool,
        musicSource: MusicSource = .spotify,
        spotifyURI: String? = nil,
        stableIdentity: String? = nil
    ) {
        self.id = id
        self.trackName = trackName
        self.artistName = artistName
        self.albumArtURL = albumArtURL
        self.albumArt = albumArt
        self.isCurrentTrack = isCurrentTrack
        self.musicSource = musicSource

        let normalizedURI = spotifyURI?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.spotifyURI = (normalizedURI?.isEmpty == false) ? normalizedURI : nil

        if let providedIdentity = stableIdentity?.trimmingCharacters(in: .whitespacesAndNewlines),
           !providedIdentity.isEmpty {
            self.stableIdentity = providedIdentity.lowercased()
        } else if let uri = self.spotifyURI {
            self.stableIdentity = "uri:\(uri.lowercased())"
        } else {
            let normalizedTrack = trackName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedArtist = artistName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedTrack.isEmpty && normalizedArtist.isEmpty {
                self.stableIdentity = ""
            } else if musicSource == .appleMusic {
                self.stableIdentity = "apple-meta:\(normalizedTrack)|\(normalizedArtist)"
            } else {
                self.stableIdentity = "meta:\(normalizedTrack)|\(normalizedArtist)"
            }
        }
    }

    static func empty(index: Int) -> QueueTrack {
        QueueTrack(
            id: UUID(),
            trackName: "",
            artistName: "",
            albumArtURL: nil,
            albumArt: nil,
            isCurrentTrack: false,
            musicSource: .none
        )
    }
}
