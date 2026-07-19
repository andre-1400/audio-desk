import AppKit
import Combine
import Foundation

final class AlbumArtFetcher: ObservableObject {
    @Published var albumArt: NSImage?

    private var lastFetchedURL: String?
    private var lastTrackKey: String?
    private var currentTask: URLSessionDataTask?
    private var activeRequestID: UUID?
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    deinit {
        currentTask?.cancel()
    }

    func fetchArt(
        from urlString: String,
        trackKey: String = "",
        forceRefresh: Bool = false,
        completion: @escaping (NSImage?) -> Void
    ) {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTrackKey = trackKey.trimmingCharacters(in: .whitespacesAndNewlines)

        currentTask?.cancel()
        let requestID = UUID()
        activeRequestID = requestID

        guard !trimmedURL.isEmpty, trimmedURL != "." else {
            DispatchQueue.main.async {
                guard self.activeRequestID == requestID else { return }
                self.albumArt = nil
                self.lastFetchedURL = nil
                self.lastTrackKey = nil
                self.currentTask = nil
                completion(nil)
            }
            return
        }

        if !forceRefresh, trimmedURL == lastFetchedURL, normalizedTrackKey == lastTrackKey {
            DispatchQueue.main.async {
                guard self.activeRequestID == requestID else { return }
                self.currentTask = nil
                completion(self.albumArt)
            }
            return
        }

        let url: URL
        if let parsed = URL(string: trimmedURL) {
            url = parsed
        } else if trimmedURL.hasPrefix("/") {
            url = URL(fileURLWithPath: trimmedURL)
        } else {
            DispatchQueue.main.async {
                guard self.activeRequestID == requestID else { return }
                self.albumArt = nil
                self.currentTask = nil
                completion(nil)
            }
            return
        }

        if url.isFileURL {
            let image = (try? Data(contentsOf: url)).flatMap { NSImage(data: $0) }
            DispatchQueue.main.async {
                guard self.activeRequestID == requestID else { return }
                self.currentTask = nil
                if let image {
                    self.lastFetchedURL = trimmedURL
                    self.lastTrackKey = normalizedTrackKey
                    self.albumArt = image
                } else {
                    self.albumArt = nil
                }
                completion(image)
            }
            return
        }

        let task = session.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }

            if let urlError = error as? URLError, urlError.code == .cancelled {
                return
            }

            let image: NSImage?
            if let data = data, let downloadedImage = NSImage(data: data) {
                image = downloadedImage
            } else {
                image = nil
            }

            DispatchQueue.main.async {
                guard self.activeRequestID == requestID else { return }
                self.currentTask = nil
                if let image = image {
                    self.lastFetchedURL = trimmedURL
                    self.lastTrackKey = normalizedTrackKey
                    self.albumArt = image
                } else {
                    self.albumArt = nil
                }
                completion(image)
            }
        }

        currentTask = task
        task.resume()
    }
}
