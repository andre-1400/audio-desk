import Foundation

enum MusicSource {
    case spotify
    case appleMusic
    case none
}

struct NowPlayingInfo: Equatable {
    let trackName: String
    let artistName: String
    let albumName: String
    let albumArtURL: String?
    let isPlaying: Bool
    let source: MusicSource
    let positionMillis: Int?
    let durationMillis: Int?
    let progressSampledAt: Date?

    init(
        trackName: String,
        artistName: String,
        albumName: String,
        albumArtURL: String?,
        isPlaying: Bool,
        source: MusicSource,
        positionMillis: Int? = nil,
        durationMillis: Int? = nil,
        progressSampledAt: Date? = nil
    ) {
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.albumArtURL = albumArtURL
        self.isPlaying = isPlaying
        self.source = source
        self.positionMillis = positionMillis
        self.durationMillis = durationMillis
        self.progressSampledAt = progressSampledAt
    }

    static let empty = NowPlayingInfo(
        trackName: "",
        artistName: "",
        albumName: "",
        albumArtURL: nil,
        isPlaying: false,
        source: .none
    )
}
