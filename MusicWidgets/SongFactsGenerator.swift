import Foundation
import Combine

struct SongFactsReport: Codable, Equatable {
    var songTitle: String
    var artist: String
    var quickSummary: String
    var writers: [String]
    var producers: [String]
    var releaseDate: String?
    var productionDate: String?
    var album: String?
    var genre: String?
    var label: String?
    var funFacts: [String]
    var contextNotes: [String]
    var sources: [SongFactsSource]

    var hasDetails: Bool {
        !quickSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !writers.isEmpty ||
            !producers.isEmpty ||
            releaseDate != nil ||
            productionDate != nil ||
            album != nil ||
            label != nil ||
            !funFacts.isEmpty ||
            !contextNotes.isEmpty
    }
}

struct SongFactsSource: Codable, Equatable, Identifiable {
    var id: String { url.isEmpty ? title : url }
    var title: String
    var url: String
}

@MainActor
final class SongFactsGenerator: ObservableObject {
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var report: SongFactsReport?
    @Published private(set) var activeTrackKey: String?

    private let endpoint = GroqConfiguration.proxyEndpoint
    // Primary model does grounded web research (best, but most rate-limited).
    // Fallback uses the model's own music knowledge (rarely rate-limited) so
    // research still returns something when web search is throttled or fails.
    private let primaryModel = "groq/compound-mini"
    private let fallbackModel = "llama-3.3-70b-versatile"
    private var cache: [String: SongFactsReport] = [:]

    func clearIfNeeded(for trackKey: String) {
        guard activeTrackKey != nil, activeTrackKey != trackKey else { return }
        isLoading = false
        lastError = nil
        report = cache[trackKey]
        activeTrackKey = report == nil ? nil : trackKey
    }

    func facts(for info: NowPlayingInfo, trackKey: String) async {
        guard !info.trackName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            activeTrackKey = trackKey
            report = nil
            lastError = "Play a song first, then ask Vinyl Widget for the story behind it."
            return
        }

        if let cached = cache[trackKey] {
            activeTrackKey = trackKey
            report = cached
            lastError = nil
            return
        }

        activeTrackKey = trackKey
        isLoading = true
        lastError = nil
        report = nil

        // 1) Web-grounded research first (has verified sources).
        var firstError: Error?
        do {
            let fetched = try await fetchFacts(for: info, model: primaryModel, webSearch: true)
            guard activeTrackKey == trackKey else { return }
            cache[trackKey] = fetched
            report = fetched
            isLoading = false
            return
        } catch {
            firstError = error
        }

        // 2) Fall back to the model's own knowledge when web search is
        //    rate-limited / unavailable, so research still works.
        do {
            let fetched = try await fetchFacts(for: info, model: fallbackModel, webSearch: false)
            guard activeTrackKey == trackKey else { return }
            cache[trackKey] = fetched
            report = fetched
        } catch {
            guard activeTrackKey == trackKey else { return }
            lastError = friendlyError(firstError ?? error)
        }

        if activeTrackKey == trackKey {
            isLoading = false
        }
    }

    private func fetchFacts(for info: NowPlayingInfo, model: String, webSearch: Bool) async throws -> SongFactsReport {
        guard let url = URL(string: endpoint) else {
            throw SongFactsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("song-facts", forHTTPHeaderField: "X-Vinyl-Feature")
        request.timeoutInterval = webSearch ? 45 : 28
        if webSearch {
            request.setValue("latest", forHTTPHeaderField: "Groq-Model-Version")
        }

        let body = GroqSongFactsRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt(for: info))
            ],
            responseFormat: .init(type: "json_object"),
            citationOptions: webSearch ? "disabled" : nil,
            compoundCustom: webSearch ? .init(tools: .init(enabledTools: ["web_search", "visit_website"])) : nil
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SongFactsError.httpError(http.statusCode, message)
        }

        let report = try parseResponse(data)
        guard report.hasDetails, isReport(report, matching: info) else {
            throw SongFactsError.trackMismatch
        }
        return report
    }

    private func parseResponse(_ data: Data) throws -> SongFactsReport {
        let response = try JSONDecoder().decode(GroqSongFactsResponse.self, from: data)
        guard let content = response.choices?.first?.message?.content, !content.isEmpty else {
            throw SongFactsError.emptyResponse
        }

        if let contentData = content.data(using: .utf8),
           let report = try? JSONDecoder().decode(SongFactsReport.self, from: contentData) {
            return sanitize(report)
        }

        if let json = extractFirstJSONObject(from: content),
           let jsonData = json.data(using: .utf8),
           let report = try? JSONDecoder().decode(SongFactsReport.self, from: jsonData) {
            return sanitize(report)
        }

        throw SongFactsError.parseFailure
    }

    private func sanitize(_ report: SongFactsReport) -> SongFactsReport {
        func clean(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        func cleanArray(_ values: [String], limit: Int = 2) -> [String] {
            Array(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(limit))
        }

        var sanitized = report
        sanitized.songTitle = clean(report.songTitle) ?? "Current Track"
        sanitized.artist = clean(report.artist) ?? "Unknown Artist"
        sanitized.quickSummary = clean(report.quickSummary) ?? ""
        sanitized.writers = cleanArray(report.writers)
        sanitized.producers = cleanArray(report.producers)
        sanitized.releaseDate = clean(report.releaseDate)
        sanitized.productionDate = clean(report.productionDate)
        sanitized.album = clean(report.album)
        sanitized.genre = clean(report.genre)
        sanitized.label = clean(report.label)
        sanitized.funFacts = cleanArray(report.funFacts)
        sanitized.contextNotes = cleanArray(report.contextNotes, limit: 1)
        sanitized.sources = Array(report.sources.map {
            SongFactsSource(title: clean($0.title) ?? "Source", url: clean($0.url) ?? "")
        }
        .filter { !$0.url.isEmpty }
        .prefix(2))
        return sanitized
    }

    private func isReport(_ report: SongFactsReport, matching info: NowPlayingInfo) -> Bool {
        let requestedTitle = normalizedMatchText(info.trackName)
        let returnedTitle = normalizedMatchText(report.songTitle)
        let requestedArtist = normalizedMatchText(primaryArtist(from: info.artistName))
        let returnedArtist = normalizedMatchText(report.artist)

        guard !requestedTitle.isEmpty, !returnedTitle.isEmpty else { return false }

        let titleMatches = looselyMatches(requestedTitle, returnedTitle)
        let artistMatches = requestedArtist.isEmpty ||
            returnedArtist.isEmpty ||
            looselyMatches(requestedArtist, returnedArtist)

        guard titleMatches && artistMatches else { return false }

        if !report.quickSummary.isEmpty {
            let summary = normalizedMatchText(report.quickSummary)
            let summaryMentionsTrack = summary.contains(requestedTitle)
            let summaryMentionsArtist = !requestedArtist.isEmpty && summary.contains(requestedArtist)
            guard summaryMentionsTrack || summaryMentionsArtist else { return false }
        }

        if let returnedAlbum = report.album {
            let requestedAlbum = normalizedMatchText(info.albumName)
            let normalizedAlbum = normalizedMatchText(returnedAlbum)
            if !requestedAlbum.isEmpty,
               !normalizedAlbum.isEmpty,
               !looselyMatches(requestedAlbum, normalizedAlbum) {
                return false
            }
        }

        return true
    }

    private func primaryArtist(from artistName: String) -> String {
        let separators = [
            " feat. ", " ft. ", " featuring ", " with ", " x ", " & ", ",", ";"
        ]
        var result = artistName
        for separator in separators {
            if let range = result.range(of: separator, options: [.caseInsensitive, .diacriticInsensitive]) {
                result = String(result[..<range.lowerBound])
            }
        }
        return result
    }

    private func normalizedMatchText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func looselyMatches(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        if lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs) {
            return true
        }

        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
        let sharedCount = lhsTokens.intersection(rhsTokens).count
        let smallerCount = min(lhsTokens.count, rhsTokens.count)
        return smallerCount > 1 && sharedCount >= smallerCount
    }

    private func extractFirstJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else { return nil }
        return String(text[start...end])
    }

    private var systemPrompt: String {
        """
        You are Vinyl Widget's music research assistant.
        Use web search for current, source-grounded music information.
        Return valid JSON only. No markdown. No commentary. No code fences.

        Rules:
        - Research only the exact song title and artist the user provides.
        - Verify the exact title and artist together from a source before returning any non-null facts.
        - If search results point to a different song, artist, album, or similarly named track, ignore them.
        - If this exact track cannot be verified, return songTitle/artist for the provided track, quickSummary as an empty string, and null/[] for unknown details.
        - Prefer official artist/label pages, Genius, Discogs, MusicBrainz, Wikipedia/Wikidata, AllMusic, Songfacts, reputable interviews, and major music publications.
        - Do not invent exact dates, writers, producers, labels, samples, or anecdotes.
        - If a detail is not confidently found, use null for strings or [] for arrays.
        - Keep text concise and beautiful for a small macOS widget.
        - quickSummary: one polished sentence, max 125 characters, and mention the exact song title or primary artist.
        - writers/producers: include up to 2 confirmed names each.
        - funFacts/contextNotes: up to 2 short, source-grounded bullets, max 95 characters each.
        - sources: include up to 2 web sources with title and URL.

        JSON schema:
        {
          "songTitle": "string",
          "artist": "string",
          "quickSummary": "string",
          "writers": ["string"],
          "producers": ["string"],
          "releaseDate": "string or null",
          "productionDate": "string or null",
          "album": "string or null",
          "genre": "string or null",
          "label": "string or null",
          "funFacts": ["string"],
          "contextNotes": ["string"],
          "sources": [{"title":"string","url":"string"}]
        }
        """
    }

    private func userPrompt(for info: NowPlayingInfo) -> String {
        """
        Research this currently playing song:
        Track: \(info.trackName)
        Artist: \(info.artistName)
        Album: \(info.albumName.isEmpty ? "Unknown" : info.albumName)
        Source app: \(sourceLabel(info.source))
        Exact search phrase to verify first: "\(info.trackName)" "\(info.artistName)"
        """
    }

    private func sourceLabel(_ source: MusicSource) -> String {
        switch source {
        case .spotify:
            return "Spotify"
        case .appleMusic:
            return "Apple Music"
        case .none:
            return "Unknown"
        }
    }

    private func friendlyError(_ error: Error) -> String {
        switch error {
        case SongFactsError.httpError(let code, let message):
            if code == 401 || code == 403 { return "The Groq key is not authorized for song research." }
            if code == 429 { return "Song research is rate-limited. Try again in a moment." }
            if code >= 500 { return "Groq is temporarily unavailable. Try again shortly." }
            return "Song research failed (\(code)): \(message.prefix(90))"
        case SongFactsError.emptyResponse:
            return "No song details came back. Try again."
        case SongFactsError.parseFailure:
            return "The research response was not readable. Try again."
        case SongFactsError.trackMismatch:
            return "I could not verify this exact track. Try again when the song metadata is stable."
        case SongFactsError.invalidURL:
            return "Internal setup error."
        default:
            let message = error.localizedDescription
            if message.contains("timed out") { return "Song research timed out. Check your connection." }
            return message
        }
    }
}

private enum SongFactsError: Error {
    case invalidURL
    case httpError(Int, String)
    case emptyResponse
    case parseFailure
    case trackMismatch
}

private struct GroqSongFactsRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String
    }

    struct CompoundCustom: Encodable {
        struct Tools: Encodable {
            let enabledTools: [String]

            enum CodingKeys: String, CodingKey {
                case enabledTools = "enabled_tools"
            }
        }

        let tools: Tools
    }

    let model: String
    let messages: [Message]
    let responseFormat: ResponseFormat
    let citationOptions: String?
    let compoundCustom: CompoundCustom?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case responseFormat = "response_format"
        case citationOptions = "citation_options"
        case compoundCustom = "compound_custom"
    }
}

private struct GroqSongFactsResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message?
    }

    let choices: [Choice]?
}
