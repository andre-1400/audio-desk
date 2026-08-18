// VinylSleeveView.swift
// Phase 10 — Individual album art card for the queue shelf
// Clean rounded card with album art, "NOW" badge, animated entry

import SwiftUI
import AppKit

struct VinylSleeveView: View {

    let track: QueueTrack
    let isVisible: Bool
    let palette: WidgetThemePalette

    private static let albumArtCache = NSCache<NSString, NSImage>()
    private static var inFlightPrefetchTasks: [String: URLSessionDataTask] = [:]

    // Album art fetch state
    @State private var loadedArt: NSImage? = nil
    @State private var fetchTask: URLSessionDataTask? = nil
    @State private var lastRequestedAlbumArtURL: String? = nil

    // Card dimensions
    private let cardSize: CGFloat = 90

    static func prefetchAlbumArt(for tracks: [QueueTrack]) {
        let urls = Set(
            tracks.compactMap { normalizedAlbumArtURL(from: $0.albumArtURL) }
        )
        for url in urls {
            prefetchAlbumArt(urlString: url)
        }
    }

    private static func normalizedAlbumArtURL(from rawURLString: String?) -> String? {
        guard let rawURLString = rawURLString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURLString.isEmpty else {
            return nil
        }
        return rawURLString
    }

    private static func prefetchAlbumArt(urlString: String) {
        if albumArtCache.object(forKey: urlString as NSString) != nil {
            return
        }
        if inFlightPrefetchTasks[urlString] != nil {
            return
        }
        guard let url = URL(string: urlString) else { return }

        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            let fetchedImage = data.flatMap { NSImage(data: $0) }
            DispatchQueue.main.async {
                if let fetchedImage {
                    albumArtCache.setObject(fetchedImage, forKey: urlString as NSString)
                }
                inFlightPrefetchTasks[urlString] = nil
            }
        }
        inFlightPrefetchTasks[urlString] = task
        task.resume()
    }

    var body: some View {
        ZStack(alignment: .bottom) {

            // ── Card background ──
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: palette.sleeveCardGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(palette.sleeveCardBorder, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)

            // ── Album art or empty state ──
            if let art = track.albumArt ?? loadedArt {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cardSize - 8, height: cardSize - 8)
                    .opacity(0.9)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .frame(width: cardSize, height: cardSize)
            } else {
                emptySleeveContent
            }

            // ── "NOW" badge for current track ──
            if track.isCurrentTrack {
                Text("NOW")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundColor(palette.sleeveNowText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(palette.sleeveNowBackground.opacity(0.9))
                    )
                    .offset(y: -6)
            }
        }
        .frame(width: cardSize, height: cardSize)
        // Entry animation — rises from below
        .opacity(isVisible ? 1.0 : 0.0)
        .offset(y: isVisible ? 0 : 24)
        .onAppear { fetchArtIfNeeded() }
        .onChange(of: track.stableIdentity) { _ in fetchArtIfNeeded() }
        .onChange(of: track.albumArtURL) { _ in fetchArtIfNeeded() }
    }

    // MARK: - Empty slot content

    private var emptySleeveContent: some View {
        ZStack {
            // Vinyl record silhouette
            Circle()
                .fill(palette.sleevePlaceholderOuter.opacity(0.5))
                .frame(width: cardSize * 0.6, height: cardSize * 0.6)
            Circle()
                .fill(palette.sleevePlaceholderMiddle.opacity(0.6))
                .frame(width: cardSize * 0.22, height: cardSize * 0.22)
            Circle()
                .fill(palette.sleevePlaceholderInner.opacity(0.5))
                .frame(width: cardSize * 0.06, height: cardSize * 0.06)

            if !track.trackName.isEmpty {
                Text(String(track.trackName.prefix(1)))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(palette.sleevePlaceholderLetter.opacity(0.4))
            }
        }
    }

    // MARK: - Art fetching

    private func fetchArtIfNeeded() {
        // If the queue model already provides resolved art (transition snapshots / fallback),
        // prefer that image and avoid a stale URL fetch overriding it.
        if track.albumArt != nil {
            fetchTask?.cancel()
            fetchTask = nil
            loadedArt = nil
            lastRequestedAlbumArtURL = nil
            return
        }

        guard let rawURLString = Self.normalizedAlbumArtURL(from: track.albumArtURL),
              let url = URL(string: rawURLString) else {
            fetchTask?.cancel()
            fetchTask = nil
            loadedArt = nil
            lastRequestedAlbumArtURL = nil
            return
        }

        if let cachedArt = Self.albumArtCache.object(forKey: rawURLString as NSString) {
            fetchTask?.cancel()
            fetchTask = nil
            loadedArt = cachedArt
            lastRequestedAlbumArtURL = rawURLString
            return
        }

        if lastRequestedAlbumArtURL == rawURLString {
            if loadedArt != nil || fetchTask != nil {
                return
            }
        } else {
            fetchTask?.cancel()
            fetchTask = nil
            loadedArt = nil
            lastRequestedAlbumArtURL = rawURLString
        }

        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let image = NSImage(data: data) else {
                DispatchQueue.main.async {
                    if self.lastRequestedAlbumArtURL == rawURLString {
                        self.fetchTask = nil
                    }
                }
                return
            }
            DispatchQueue.main.async {
                guard self.lastRequestedAlbumArtURL == rawURLString else { return }
                Self.albumArtCache.setObject(image, forKey: rawURLString as NSString)
                self.loadedArt = image
                self.fetchTask = nil
            }
        }
        fetchTask = task
        task.resume()
    }
}
