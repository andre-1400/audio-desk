// SpotifyAuthManager.swift
// Phase 10 — Spotify OAuth2 PKCE authentication + queue fetching
// Tokens stored securely in macOS Keychain (never UserDefaults or source code)

import Foundation
import Combine
import CryptoKit
import Security
import AppKit

// MARK: - Queue Track Model

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

// MARK: - Spotify Auth Manager

class SpotifyAuthManager: ObservableObject {

    private static let normalizedQueueDepth = 10

    private struct SpotifyTokenStore: Codable {
        var accessToken: String
        var refreshToken: String
        var expiryISO8601: String
    }

    private struct PendingSpotifyAuth: Codable {
        var codeVerifier: String
        var state: String
        var startedAtISO8601: String
    }

    // Spotify Developer App credentials (Client ID is safe in client apps)
    static let clientID = "e51673d509ea49bba7b3b12377744323"
    static let redirectURI = "vinylwidget://callback"
    static let scopes = "user-read-currently-playing user-read-playback-state"

    // Keychain namespaces
    // One namespaced token blob reduces repeated keychain access prompts.
    private let keychainService = "com.vinylwidget.spotify.tokens"
    private let keychainAccount = "default"

    // Legacy key names (migration from old multi-key layout)
    private let legacyAccessTokenKey  = "vinylwidget.spotify.accessToken"
    private let legacyRefreshTokenKey = "vinylwidget.spotify.refreshToken"
    private let legacyTokenExpiryKey  = "vinylwidget.spotify.tokenExpiry"

    // PKCE state (held in memory during auth flow)
    private var codeVerifier: String?
    private var pendingAuthState: String?
    private let iso8601Formatter = ISO8601DateFormatter()
    private var cachedTokenStore: SpotifyTokenStore?
    private let pendingAuthDefaultsKey = "spotify.oauth.pendingAuth.v1"

    @Published var isConnected: Bool = false
    @Published var queueTracks: [QueueTrack] = (0..<SpotifyAuthManager.normalizedQueueDepth)
        .map { QueueTrack.empty(index: $0) }
    @Published var authStatus: String = "Not connected"
    @Published var lastAuthError: String?
    @Published var lastConnectionEventID: UUID?

    init() {
        // Load token state once at startup; keep in-memory cache for runtime reads.
        cachedTokenStore = loadTokenStore() ?? migrateLegacyTokensIfNeeded()
        isConnected = !(cachedTokenStore?.refreshToken.isEmpty ?? true)
        if isConnected {
            authStatus = "Connected"
        } else if loadPendingAuthPayload() != nil {
            authStatus = "Waiting for Spotify callback..."
        } else {
            authStatus = "Not connected"
        }
    }

    // MARK: - Step 1: Start Login Flow

    /// Opens Spotify login page in the user's default browser
    func startLoginFlow() {
        let verifier = generateCodeVerifier()
        let state = generateOAuthState()
        codeVerifier = verifier
        pendingAuthState = state
        let challenge = generateCodeChallenge(from: verifier)
        persistPendingAuthPayload(
            PendingSpotifyAuth(
                codeVerifier: verifier,
                state: state,
                startedAtISO8601: iso8601Formatter.string(from: Date())
            )
        )

        DispatchQueue.main.async {
            self.lastAuthError = nil
            self.authStatus = "Waiting for Spotify callback..."
        }

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id",             value: SpotifyAuthManager.clientID),
            .init(name: "response_type",          value: "code"),
            .init(name: "redirect_uri",           value: SpotifyAuthManager.redirectURI),
            .init(name: "scope",                  value: SpotifyAuthManager.scopes),
            .init(name: "code_challenge_method",  value: "S256"),
            .init(name: "code_challenge",         value: challenge),
            .init(name: "state",                  value: state),
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Step 2: Handle Callback (called from AppDelegate)

    /// Called when Spotify redirects back to vinylwidget://callback?code=...
    func handleCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            failAuth("Invalid callback URL.", clearPending: false)
            return
        }

        let queryItems = components.queryItems ?? []
        if let oauthError = queryItems.first(where: { $0.name == "error" })?.value {
            failAuth("Spotify authorization failed: \(oauthError).", clearPending: true)
            return
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            failAuth("Missing authorization code in callback.", clearPending: false)
            return
        }

        let callbackState = queryItems.first(where: { $0.name == "state" })?.value
        let persistedPayload = loadPendingAuthPayload()
        let expectedState = pendingAuthState ?? persistedPayload?.state
        if let expectedState, !expectedState.isEmpty,
           let callbackState,
           !callbackState.isEmpty,
           callbackState != expectedState {
            failAuth("State mismatch in callback. Please retry Spotify login.", clearPending: true)
            return
        }

        guard let verifier = codeVerifier ?? persistedPayload?.codeVerifier, !verifier.isEmpty else {
            failAuth("Missing PKCE verifier. Start Spotify login again.", clearPending: true)
            return
        }

        DispatchQueue.main.async {
            self.lastAuthError = nil
            self.authStatus = "Completing Spotify connection..."
        }

        exchangeCodeForTokens(code: code, verifier: verifier)
    }

    // MARK: - Step 3: Exchange Code for Tokens

    private func exchangeCodeForTokens(code: String, verifier: String) {
        guard let tokenURL = URL(string: "https://accounts.spotify.com/api/token") else { return }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type":    "authorization_code",
            "code":          code,
            "redirect_uri":  SpotifyAuthManager.redirectURI,
            "client_id":     SpotifyAuthManager.clientID,
            "code_verifier": verifier
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
         .joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            if let httpResponse = response as? HTTPURLResponse {
                print("[VinylWidget] OAuth token exchange status: \(httpResponse.statusCode)")
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken  = json["access_token"]  as? String,
                  let refreshToken = json["refresh_token"] as? String,
                  let expiresIn    = json["expires_in"]    as? Int else {
                if let data = data, let body = String(data: data, encoding: .utf8) {
                    print("[VinylWidget] OAuth token exchange failed response: \(body)")
                }
                self?.failAuth("Token exchange failed. Please retry Spotify login.", clearPending: true)
                return
            }

            let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
            let expiryISO8601 = ISO8601DateFormatter().string(from: expiryDate)
            let tokenStore = SpotifyTokenStore(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiryISO8601: expiryISO8601
            )

            self?.cachedTokenStore = tokenStore
            _ = self?.saveTokenStore(tokenStore)

            DispatchQueue.main.async {
                self?.isConnected = true
                self?.codeVerifier = nil
                self?.pendingAuthState = nil
                self?.clearPendingAuthPayload()
                self?.lastAuthError = nil
                self?.authStatus = "Connected"
                self?.lastConnectionEventID = UUID()
            }
        }.resume()
    }

    // MARK: - Token Refresh

    func refreshAccessTokenIfNeeded(completion: @escaping (String?) -> Void) {
        if cachedTokenStore == nil {
            cachedTokenStore = loadTokenStore() ?? migrateLegacyTokensIfNeeded()
        }

        // Check if current token is still valid (with 60s buffer)
        if let store = cachedTokenStore,
           let expiry = iso8601Formatter.date(from: store.expiryISO8601),
           expiry > Date().addingTimeInterval(60),
           !store.accessToken.isEmpty {
            completion(store.accessToken)
            return
        }

        // Need to refresh
        guard let refreshToken = cachedTokenStore?.refreshToken,
              !refreshToken.isEmpty,
              let tokenURL = URL(string: "https://accounts.spotify.com/api/token") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type":    "refresh_token",
            "refresh_token": refreshToken,
            "client_id":     SpotifyAuthManager.clientID
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
         .joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            if let httpResponse = response as? HTTPURLResponse {
                print("[VinylWidget] Token refresh status: \(httpResponse.statusCode)")
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String,
                  let expiresIn   = json["expires_in"]   as? Int else {
                print("[VinylWidget] Token refresh failed")
                if let data = data, let body = String(data: data, encoding: .utf8) {
                    print("[VinylWidget] Response: \(body)")
                }
                // Token is no longer valid — mark as disconnected so user can re-login
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.authStatus = "Disconnected"
                    self?.lastAuthError = "Spotify session expired. Please reconnect."
                }
                completion(nil)
                return
            }

            let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
            let expiryISO8601 = ISO8601DateFormatter().string(from: expiryDate)
            let updatedRefreshToken = (json["refresh_token"] as? String) ?? refreshToken
            let updatedStore = SpotifyTokenStore(
                accessToken: accessToken,
                refreshToken: updatedRefreshToken,
                expiryISO8601: expiryISO8601
            )
            self?.cachedTokenStore = updatedStore
            _ = self?.saveTokenStore(updatedStore)

            completion(accessToken)
        }.resume()
    }

    // MARK: - Fetch Queue

    func fetchQueue(completion: @escaping ([QueueTrack]) -> Void) {
        refreshAccessTokenIfNeeded { [weak self] token in
            guard let token = token,
                  let url = URL(string: "https://api.spotify.com/v1/me/player/queue") else {
                completion([])
                return
            }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { data, response, _ in
                if let httpResponse = response as? HTTPURLResponse {
                    print("[VinylWidget] Queue API status: \(httpResponse.statusCode)")
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("[VinylWidget] Queue API: failed to parse response")
                    completion([])
                    return
                }

                guard let self else {
                    completion((0..<Self.normalizedQueueDepth).map { QueueTrack.empty(index: $0) })
                    return
                }

                let currentTrack = (json["currently_playing"] as? [String: Any]).map { self.parseTrack($0, isCurrent: true) }
                let queueItems = (json["queue"] as? [[String: Any]] ?? [])
                    .map { self.parseTrack($0, isCurrent: false) }

                let normalizedTracks = self.normalizeQueue(current: currentTrack, upcoming: queueItems)
                completion(normalizedTracks)
            }.resume()
        }
    }

    private func parseTrack(_ json: [String: Any], isCurrent: Bool) -> QueueTrack {
        let name   = json["name"]   as? String ?? ""
        let artists = json["artists"] as? [[String: Any]] ?? []
        let artist = artists.first?["name"] as? String ?? ""
        let album  = json["album"]  as? [String: Any] ?? [:]
        let images = album["images"] as? [[String: Any]] ?? []
        let uri = json["uri"] as? String
        // Use the smallest image that's still ≥ 64px for efficiency
        let artURL = images.last?["url"] as? String ?? images.first?["url"] as? String

        return QueueTrack(
            id: UUID(),
            trackName: name,
            artistName: artist,
            albumArtURL: artURL,
            albumArt: nil,
            isCurrentTrack: isCurrent,
            spotifyURI: uri
        )
    }

    private func normalizeQueue(current: QueueTrack?, upcoming: [QueueTrack]) -> [QueueTrack] {
        var normalized: [QueueTrack] = []

        if let current, !current.stableIdentity.isEmpty {
            normalized.append(
                QueueTrack(
                    id: UUID(),
                    trackName: current.trackName,
                    artistName: current.artistName,
                    albumArtURL: current.albumArtURL,
                    albumArt: current.albumArt,
                    isCurrentTrack: true,
                    spotifyURI: current.spotifyURI,
                    stableIdentity: current.stableIdentity
                )
            )
        }

        // If Spotify `currently_playing` is temporarily unavailable, promote first queue item as NOW.
        if normalized.isEmpty, let firstUpcoming = upcoming.first, !firstUpcoming.stableIdentity.isEmpty {
            let promoted = QueueTrack(
                id: UUID(),
                trackName: firstUpcoming.trackName,
                artistName: firstUpcoming.artistName,
                albumArtURL: firstUpcoming.albumArtURL,
                albumArt: firstUpcoming.albumArt,
                isCurrentTrack: true,
                spotifyURI: firstUpcoming.spotifyURI,
                stableIdentity: firstUpcoming.stableIdentity
            )
            normalized.append(promoted)
        }

        let currentIdentity = normalized.first?.stableIdentity ?? ""

        // Drop every leading echo of the current track, then keep Spotify order.
        var upcomingStartIndex = 0
        if !currentIdentity.isEmpty {
            while upcomingStartIndex < upcoming.count {
                let candidate = upcoming[upcomingStartIndex]
                if !candidate.stableIdentity.isEmpty, candidate.stableIdentity == currentIdentity {
                    upcomingStartIndex += 1
                } else {
                    break
                }
            }
        }

        for track in upcoming.dropFirst(upcomingStartIndex) {
            if normalized.count == Self.normalizedQueueDepth { break }
            guard !track.stableIdentity.isEmpty else { continue }
            normalized.append(
                QueueTrack(
                    id: UUID(),
                    trackName: track.trackName,
                    artistName: track.artistName,
                    albumArtURL: track.albumArtURL,
                    albumArt: track.albumArt,
                    isCurrentTrack: false,
                    spotifyURI: track.spotifyURI,
                    stableIdentity: track.stableIdentity
                )
            )
        }

        while normalized.count < Self.normalizedQueueDepth {
            normalized.append(.empty(index: normalized.count))
        }

        return Array(normalized.prefix(Self.normalizedQueueDepth))
    }

    // MARK: - Disconnect

    func disconnect() {
        _ = deleteTokenStore()
        _ = keychainDeleteLegacy(key: legacyAccessTokenKey)
        _ = keychainDeleteLegacy(key: legacyRefreshTokenKey)
        _ = keychainDeleteLegacy(key: legacyTokenExpiryKey)
        cachedTokenStore = nil
        clearPendingAuthPayload()
        pendingAuthState = nil
        codeVerifier = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.authStatus = "Not connected"
            self.lastAuthError = nil
        }
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateOAuthState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func failAuth(_ message: String, clearPending: Bool) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.authStatus = "Connection failed"
            self.lastAuthError = message
        }
        if clearPending {
            codeVerifier = nil
            pendingAuthState = nil
            clearPendingAuthPayload()
        }
    }

    private func persistPendingAuthPayload(_ payload: PendingSpotifyAuth) {
        guard let encoded = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(encoded, forKey: pendingAuthDefaultsKey)
    }

    private func loadPendingAuthPayload() -> PendingSpotifyAuth? {
        guard let data = UserDefaults.standard.data(forKey: pendingAuthDefaultsKey),
              let payload = try? JSONDecoder().decode(PendingSpotifyAuth.self, from: data) else {
            return nil
        }
        return payload
    }

    private func clearPendingAuthPayload() {
        UserDefaults.standard.removeObject(forKey: pendingAuthDefaultsKey)
    }

    // MARK: - Keychain Helpers

    @discardableResult
    private func saveTokenStore(_ store: SpotifyTokenStore) -> Bool {
        guard let data = try? JSONEncoder().encode(store) else { return false }
        return keychainUpsert(service: keychainService, account: keychainAccount, data: data)
    }

    private func loadTokenStore() -> SpotifyTokenStore? {
        guard let data = keychainRead(service: keychainService, account: keychainAccount),
              let store = try? JSONDecoder().decode(SpotifyTokenStore.self, from: data) else {
            return nil
        }
        return store
    }

    @discardableResult
    private func deleteTokenStore() -> Bool {
        keychainDelete(service: keychainService, account: keychainAccount)
    }

    private func migrateLegacyTokensIfNeeded() -> SpotifyTokenStore? {
        guard let refreshToken = keychainLoadLegacy(key: legacyRefreshTokenKey) else { return nil }

        let accessToken = keychainLoadLegacy(key: legacyAccessTokenKey) ?? ""
        let expiry = keychainLoadLegacy(key: legacyTokenExpiryKey) ??
            iso8601Formatter.string(from: Date().addingTimeInterval(30))
        let migratedStore = SpotifyTokenStore(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiryISO8601: expiry
        )

        guard saveTokenStore(migratedStore) else { return nil }
        _ = keychainDeleteLegacy(key: legacyAccessTokenKey)
        _ = keychainDeleteLegacy(key: legacyRefreshTokenKey)
        _ = keychainDeleteLegacy(key: legacyTokenExpiryKey)
        return migratedStore
    }

    @discardableResult
    private func keychainUpsert(service: String, account: String, data: Data) -> Bool {
        let baseQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            return false
        }

        var addQuery = baseQuery
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    private func keychainRead(service: String, account: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return data
    }

    @discardableResult
    private func keychainDelete(service: String, account: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func keychainLoadLegacy(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private func keychainDeleteLegacy(key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
