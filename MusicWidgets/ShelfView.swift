// ShelfView.swift
// Phase 10 — Queue shelf with animated vinyl sleeves
// Clean rounded container with 4 album art cards + "Queue" pill bar

import SwiftUI
import AppKit
import Combine

// MARK: - Shelf View Model

class ShelfViewModel: ObservableObject {

    private static let visibleQueueSlotCount = 4
    private static let totalNormalizedQueueDepth = 10
    private static var hiddenQueueBufferCapacity: Int {
        max(0, totalNormalizedQueueDepth - visibleQueueSlotCount)
    }

    struct QueueShiftState: Equatable {
        let sourceIndex: Int
        let replacementTrack: QueueTrack
    }

    private struct TransitionQueueLock {
        let outgoing: SongSwitchAnimator.TrackSnapshot
        let incoming: SongSwitchAnimator.TrackSnapshot
    }

    @Published var isOpen: Bool = false
    @Published var placement: ShelfPlacement = .below
    @Published var sleeveStates: [Bool] = [false, false, false, false]
    @Published var tracks: [QueueTrack] = (0..<ShelfViewModel.visibleQueueSlotCount).map { QueueTrack.empty(index: $0) }
    @Published var queueShiftState: QueueShiftState? = nil
    @Published var queueShiftProgress: CGFloat = 0
    @Published var openProgress: CGFloat = 0
    @Published var activeSource: MusicSource = .none

    private var cancellables = Set<AnyCancellable>()
    private var staggerTimers: [DispatchWorkItem] = []
    private var pendingShiftTracks: [QueueTrack]?
    private var transitionQueueLock: TransitionQueueLock?
    private var queueFetchRequestID: Int = 0
    private var latestAppliedQueueFetchRequestID: Int = 0
    private var lastCarryoverReconcileAt: Date?
    private var hiddenBufferedTracks: [QueueTrack] = []
    private var pendingConsumedHiddenTrackIdentity: String?

    // Called by AppDelegate when it creates SpotifyAuthManager
    weak var authManager: SpotifyAuthManager?
    weak var appleQueueProvider: AppleMusicLocalQueueProvider?

    // Song switch animation: tracks if shelf was auto-opened
    var autoOpenedForAnimation: Bool = false

    // Song switch animation: hide the exact source sleeve currently flying out
    @Published var hiddenSleeveIndex: Int? = nil

    // MARK: Toggle

    func toggle() {
        if isOpen { close() } else { open() }
    }

    func updateActiveSource(_ source: MusicSource) {
        activeSource = source
    }

    var isAppleMusicModeActive: Bool {
        activeSource == .appleMusic
    }

    // MARK: Open

    func open(fetchQueue: Bool = true) {
        isOpen = true
        withAnimation(.easeOut(duration: 0.20)) {
            openProgress = 1
        }

        // Cancel any pending stagger timers
        staggerTimers.forEach { $0.cancel() }
        staggerTimers.removeAll()

        // Refresh queue from the active source (unless this is an animation-driven open).
        if fetchQueue {
            refreshQueueForActiveSource(reconcileDelays: [0.9, 1.8], staggerOnFirstFetch: true)
        } else {
            staggerSleeveIn()
        }
    }

    // MARK: Close

    func close() {
        staggerTimers.forEach { $0.cancel() }
        staggerTimers.removeAll()
        resetQueueShift()

        withAnimation(.easeIn(duration: 0.18)) {
            sleeveStates = [false, false, false, false]
            openProgress = 0
        }
        let work = DispatchWorkItem {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                self.isOpen = false
            }
        }
        staggerTimers.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    // MARK: Update current track art (called from ContentView on song change)

    func updateCurrentTrack(name: String, artist: String, art: NSImage?) {
        var updated = tracks
        if updated.isEmpty { return }
        updated[0] = QueueTrack(
            id: UUID(),
            trackName: name,
            artistName: artist,
            // Clear stale URL binding; canonical URL/queue order is refreshed from Spotify reconciliation.
            albumArtURL: nil,
            albumArt: art,
            isCurrentTrack: true,
            musicSource: activeSource == .none ? .spotify : activeSource
        )
        tracks = updated
    }

    func applyFetchedQueue(_ fetchedTracks: [QueueTrack]) {
        queueFetchRequestID += 1
        applyFetchedQueue(
            fetchedTracks,
            requestID: queueFetchRequestID,
            staggerOnApply: false
        )
    }

    func refreshQueueFromSpotify(
        reconcileDelays: [TimeInterval] = [],
        staggerOnFirstFetch: Bool = false
    ) {
        guard let auth = authManager, auth.isConnected else {
            if staggerOnFirstFetch {
                staggerSleeveIn()
            }
            return
        }

        requestQueueSnapshot(using: auth, staggerOnApply: staggerOnFirstFetch)

        for delay in reconcileDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                guard self.isOpen, self.transitionQueueLock == nil else { return }
                requestQueueSnapshot(using: auth, staggerOnApply: false)
            }
        }
    }

    func refreshQueueForActiveSource(
        reconcileDelays: [TimeInterval] = [],
        staggerOnFirstFetch: Bool = false
    ) {
        switch activeSource {
        case .spotify:
            refreshQueueFromSpotify(reconcileDelays: reconcileDelays, staggerOnFirstFetch: staggerOnFirstFetch)
        case .appleMusic:
            refreshQueueFromAppleLocal(reconcileDelays: reconcileDelays, staggerOnFirstFetch: staggerOnFirstFetch)
        case .none:
            if staggerOnFirstFetch {
                staggerSleeveIn()
            }
        }
    }

    func refreshQueueFromAppleLocal(
        reconcileDelays: [TimeInterval] = [],
        staggerOnFirstFetch: Bool = false
    ) {
        guard let appleQueueProvider else {
            if staggerOnFirstFetch {
                staggerSleeveIn()
            }
            return
        }

        queueFetchRequestID += 1
        let requestID = queueFetchRequestID
        appleQueueProvider.fetchLocalQueue { [weak self] tracks in
            self?.applyAppleLocalQueueSnapshot(
                tracks,
                requestID: requestID,
                staggerOnApply: staggerOnFirstFetch
            )
        }

        for delay in reconcileDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                guard self.isOpen, self.transitionQueueLock == nil, self.activeSource == .appleMusic else { return }
                self.queueFetchRequestID += 1
                let delayedRequestID = self.queueFetchRequestID
                appleQueueProvider.fetchLocalQueue { [weak self] tracks in
                    self?.applyAppleLocalQueueSnapshot(
                        tracks,
                        requestID: delayedRequestID,
                        staggerOnApply: false
                    )
                }
            }
        }
    }

    // MARK: Animation-triggered open/close

    func openForAnimation() {
        autoOpenedForAnimation = true
        open(fetchQueue: false)
    }

    func closeAfterAnimation() {
        guard autoOpenedForAnimation else { return }
        autoOpenedForAnimation = false
        close()
    }

    func beginTransitionQueueLock(outgoing: SongSwitchAnimator.TrackSnapshot, incoming: SongSwitchAnimator.TrackSnapshot) {
        transitionQueueLock = TransitionQueueLock(outgoing: outgoing, incoming: incoming)
        tracks = lockedQueueTracks(outgoing: outgoing, incoming: incoming)
    }

    func endTransitionQueueLock() {
        transitionQueueLock = nil
        if isOpen {
            refreshQueueForActiveSource(reconcileDelays: [0.9], staggerOnFirstFetch: false)
        }
    }

    // MARK: Queue shift choreography

    func prepareQueueShift(sourceIndex: Int?, incomingSnapshot: SongSwitchAnimator.TrackSnapshot?) {
        guard let sourceIndex,
              tracks.indices.contains(sourceIndex),
              sourceIndex > 0 else {
            resetQueueShift()
            return
        }
        guard trackHasRenderableContent(tracks[sourceIndex]) else {
            resetQueueShift()
            return
        }

        let replacementResolution = replacementQueueTrack(sourceIndex: sourceIndex, incomingSnapshot: incomingSnapshot)
        let replacement = replacementResolution.track
        pendingConsumedHiddenTrackIdentity = replacementResolution.bufferIdentityToConsume
        let shiftState = QueueShiftState(sourceIndex: sourceIndex, replacementTrack: replacement)

        var shifted = tracks
        shifted.remove(at: sourceIndex)
        shifted.append(replacement)
        while shifted.count < 4 {
            shifted.append(.empty(index: shifted.count))
        }
        pendingShiftTracks = Array(shifted.prefix(4))

        hiddenSleeveIndex = sourceIndex
        withAnimation(nil) {
            queueShiftState = shiftState
            queueShiftProgress = 0
        }
        withAnimation(.timingCurve(0.0, 0.0, 0.3, 1.0, duration: 1.46)) {
            queueShiftProgress = 1
        }
    }

    func commitQueueShiftIfNeeded() {
        guard let shifted = pendingShiftTracks else { return }
        withAnimation(nil) {
            tracks = shifted
            queueShiftState = nil
            queueShiftProgress = 0
            hiddenSleeveIndex = nil
        }
        if let consumedIdentity = pendingConsumedHiddenTrackIdentity,
           let consumedIndex = hiddenBufferedTracks.firstIndex(where: { $0.stableIdentity == consumedIdentity }) {
            hiddenBufferedTracks.remove(at: consumedIndex)
        }
        pendingConsumedHiddenTrackIdentity = nil
        pendingShiftTracks = nil
    }

    func resetQueueShift() {
        pendingShiftTracks = nil
        queueShiftState = nil
        queueShiftProgress = 0
        pendingConsumedHiddenTrackIdentity = nil
    }

    // MARK: Queue Selection Helpers

    /// Leftmost upcoming queue sleeve (first non-current with any content).
    func firstNonCurrentQueueIndex() -> Int? {
        for (index, track) in tracks.enumerated() where index > 0 {
            let hasContent = !track.trackName.isEmpty || track.albumArt != nil || (track.albumArtURL?.isEmpty == false)
            if hasContent {
                return index
            }
        }
        return tracks.indices.contains(1) ? 1 : nil
    }

    /// Prefer the queue sleeve matching the track we are skipping to, then fallback to leftmost upcoming.
    func sourceQueueIndex(forTrackName trackName: String, artistName: String) -> Int? {
        let targetTrack = normalizedIdentity(trackName)
        let targetArtist = normalizedIdentity(artistName)

        if !targetTrack.isEmpty || !targetArtist.isEmpty {
            for (index, track) in tracks.enumerated() where index > 0 {
                if normalizedIdentity(track.trackName) == targetTrack &&
                    normalizedIdentity(track.artistName) == targetArtist {
                    return index
                }
            }
        }

        return firstNonCurrentQueueIndex()
    }

    // MARK: Helpers

    private func staggerSleeveIn() {
        for i in 0..<4 {
            let work = DispatchWorkItem {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.68)) {
                    self.sleeveStates[i] = true
                }
            }
            staggerTimers.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 + Double(i) * 0.13, execute: work)
        }
    }

    private func requestQueueSnapshot(using auth: SpotifyAuthManager, staggerOnApply: Bool) {
        queueFetchRequestID += 1
        let requestID = queueFetchRequestID

        auth.fetchQueue { [weak self] tracks in
            DispatchQueue.main.async {
                self?.applyFetchedQueue(
                    tracks,
                    requestID: requestID,
                    staggerOnApply: staggerOnApply
                )
            }
        }
    }

    private func applyFetchedQueue(
        _ fetchedTracks: [QueueTrack],
        requestID: Int,
        staggerOnApply: Bool
    ) {
        guard requestID >= latestAppliedQueueFetchRequestID else { return }
        latestAppliedQueueFetchRequestID = requestID
        guard !fetchedTracks.isEmpty else {
            if staggerOnApply {
                staggerSleeveIn()
            }
            return
        }
        VinylSleeveView.prefetchAlbumArt(
            for: Array(fetchedTracks.prefix(Self.totalNormalizedQueueDepth))
        )
        guard transitionQueueLock == nil else { return }

        let fetchedVisible = Array(fetchedTracks.prefix(Self.visibleQueueSlotCount))
        let fetchedHiddenCandidates = Array(
            fetchedTracks
                .dropFirst(Self.visibleQueueSlotCount)
                .prefix(Self.hiddenQueueBufferCapacity)
        )
        let (mergedTracks, didCarryOverUpcoming) = mergeFetchedQueueKeepingUpcomingContinuity(
            fetchedTracks: fetchedVisible,
            existingTracks: tracks
        )
        tracks = mergedTracks
        let (resolvedBufferedTracks, didCarryOverBufferedTracks) = resolveHiddenQueueBuffer(
            fetchedCandidates: fetchedHiddenCandidates,
            existingCandidates: hiddenBufferedTracks,
            visibleTracks: mergedTracks
        )
        hiddenBufferedTracks = resolvedBufferedTracks

        if didCarryOverUpcoming || didCarryOverBufferedTracks {
            scheduleStrictCarryoverReconcileIfNeeded()
        }
        if staggerOnApply {
            staggerSleeveIn()
        }
    }

    private func applyAppleLocalQueueSnapshot(
        _ fetchedTracks: [QueueTrack],
        requestID: Int,
        staggerOnApply: Bool
    ) {
        guard requestID >= latestAppliedQueueFetchRequestID else { return }
        latestAppliedQueueFetchRequestID = requestID
        guard transitionQueueLock == nil else { return }

        var normalized = Array(fetchedTracks.prefix(Self.visibleQueueSlotCount)).enumerated().map { index, track in
            QueueTrack(
                id: UUID(),
                trackName: track.trackName,
                artistName: track.artistName,
                albumArtURL: track.albumArtURL,
                albumArt: track.albumArt,
                isCurrentTrack: index == 0,
                musicSource: .appleMusic,
                spotifyURI: nil,
                stableIdentity: track.stableIdentity
            )
        }
        while normalized.count < Self.visibleQueueSlotCount {
            normalized.append(.empty(index: normalized.count))
        }

        tracks = Array(normalized.prefix(Self.visibleQueueSlotCount))
        hiddenBufferedTracks = []
        lastCarryoverReconcileAt = nil

        if staggerOnApply {
            staggerSleeveIn()
        }
    }

    private func replacementQueueTrack(
        sourceIndex _: Int,
        incomingSnapshot _: SongSwitchAnimator.TrackSnapshot?
    ) -> (track: QueueTrack, bufferIdentityToConsume: String?) {
        if let buffered = firstValidBufferedTrackCandidate(visibleTracks: tracks) {
            return (normalizedQueueSlot(buffered, isCurrent: false), buffered.stableIdentity)
        }

        // Slot 4 is intentionally a placeholder until Spotify reconcile confirms the true next+2 track.
        return (.empty(index: 3), nil)
    }

    private func trackHasRenderableContent(_ track: QueueTrack) -> Bool {
        let hasTrackName = !track.trackName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImageURL = !(track.albumArtURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return hasTrackName || track.albumArt != nil || hasImageURL
    }

    private func normalizedQueueSlot(_ track: QueueTrack, isCurrent: Bool) -> QueueTrack {
        QueueTrack(
            id: UUID(),
            trackName: track.trackName,
            artistName: track.artistName,
            albumArtURL: track.albumArtURL,
            albumArt: track.albumArt,
            isCurrentTrack: isCurrent,
            musicSource: track.musicSource,
            spotifyURI: track.spotifyURI,
            stableIdentity: track.stableIdentity
        )
    }

    private func visibleIdentitySet(from tracks: [QueueTrack]) -> Set<String> {
        Set(tracks.compactMap { track -> String? in
            let identity = track.stableIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
            return identity.isEmpty ? nil : identity
        })
    }

    private func firstValidBufferedTrackCandidate(visibleTracks: [QueueTrack]) -> QueueTrack? {
        sanitizedHiddenBufferCandidates(hiddenBufferedTracks, visibleTracks: visibleTracks).first
    }

    private func sanitizedHiddenBufferCandidates(
        _ candidates: [QueueTrack],
        visibleTracks: [QueueTrack],
        additionalExcludedIdentities: Set<String> = []
    ) -> [QueueTrack] {
        var sanitized: [QueueTrack] = []
        var usedIdentities = visibleIdentitySet(from: visibleTracks)
        usedIdentities.formUnion(additionalExcludedIdentities)

        for candidate in candidates {
            let normalizedCandidate = normalizedQueueSlot(candidate, isCurrent: false)
            guard trackHasRenderableContent(normalizedCandidate) else { continue }

            let candidateIdentity = normalizedCandidate.stableIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidateIdentity.isEmpty else { continue }
            guard !usedIdentities.contains(candidateIdentity) else { continue }

            usedIdentities.insert(candidateIdentity)
            sanitized.append(normalizedCandidate)
            if sanitized.count == Self.hiddenQueueBufferCapacity {
                break
            }
        }

        return sanitized
    }

    private func resolveHiddenQueueBuffer(
        fetchedCandidates: [QueueTrack],
        existingCandidates: [QueueTrack],
        visibleTracks: [QueueTrack]
    ) -> (tracks: [QueueTrack], carriedOverExisting: Bool) {
        var resolved = sanitizedHiddenBufferCandidates(fetchedCandidates, visibleTracks: visibleTracks)
        var didCarryOverExisting = false

        guard resolved.count < Self.hiddenQueueBufferCapacity else {
            return (Array(resolved.prefix(Self.hiddenQueueBufferCapacity)), false)
        }

        let resolvedIdentities = Set(
            resolved.compactMap { track -> String? in
                let identity = track.stableIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
                return identity.isEmpty ? nil : identity
            }
        )
        let carriedCandidates = sanitizedHiddenBufferCandidates(
            existingCandidates,
            visibleTracks: visibleTracks,
            additionalExcludedIdentities: resolvedIdentities
        )

        for carried in carriedCandidates {
            guard resolved.count < Self.hiddenQueueBufferCapacity else { break }
            resolved.append(carried)
            didCarryOverExisting = true
        }

        return (Array(resolved.prefix(Self.hiddenQueueBufferCapacity)), didCarryOverExisting)
    }

    private func mergeFetchedQueueKeepingUpcomingContinuity(
        fetchedTracks: [QueueTrack],
        existingTracks: [QueueTrack]
    ) -> ([QueueTrack], Bool) {
        var fetched = Array(fetchedTracks.prefix(4))
        while fetched.count < 4 {
            fetched.append(.empty(index: fetched.count))
        }

        var merged = fetched.enumerated().map { index, track in
            normalizedQueueSlot(track, isCurrent: index == 0)
        }

        let currentIdentity = merged.first?.stableIdentity ?? ""
        var usedUpcomingIdentities = Set<String>()
        if !currentIdentity.isEmpty {
            usedUpcomingIdentities.insert(currentIdentity)
        }
        for slot in 1..<merged.count {
            let identity = merged[slot].stableIdentity
            if !identity.isEmpty {
                usedUpcomingIdentities.insert(identity)
            }
        }

        var didCarryOverUpcoming = false

        // Keep slot 4 strict placeholder-only when unknown; only carry slot 2/3.
        for slot in [1, 2] {
            guard merged.indices.contains(slot) else { continue }
            guard !trackHasRenderableContent(merged[slot]) else { continue }
            guard existingTracks.indices.contains(slot) else { continue }

            let candidate = normalizedQueueSlot(existingTracks[slot], isCurrent: false)
            guard trackHasRenderableContent(candidate) else { continue }

            let candidateIdentity = candidate.stableIdentity
            if !candidateIdentity.isEmpty {
                guard candidateIdentity != currentIdentity,
                      !usedUpcomingIdentities.contains(candidateIdentity) else {
                    continue
                }
                usedUpcomingIdentities.insert(candidateIdentity)
            }

            merged[slot] = candidate
            didCarryOverUpcoming = true
        }

        while merged.count < 4 {
            merged.append(.empty(index: merged.count))
        }

        return (Array(merged.prefix(4)), didCarryOverUpcoming)
    }

    private func scheduleStrictCarryoverReconcileIfNeeded() {
        guard isOpen, transitionQueueLock == nil, activeSource == .spotify else { return }

        let now = Date()
        if let lastRunAt = lastCarryoverReconcileAt, now.timeIntervalSince(lastRunAt) < 0.75 {
            return
        }
        lastCarryoverReconcileAt = now
        refreshQueueFromSpotify(reconcileDelays: [0.45, 0.9], staggerOnFirstFetch: false)
    }

    private func normalizedIdentity(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func trackIdentityKey(trackName: String, artistName: String) -> String {
        "\(normalizedIdentity(trackName))|\(normalizedIdentity(artistName))"
    }

    private func normalizedQueueTrack(_ track: QueueTrack) -> QueueTrack {
        QueueTrack(
            id: track.id,
            trackName: track.trackName,
            artistName: track.artistName,
            albumArtURL: track.albumArtURL,
            albumArt: track.albumArt,
            isCurrentTrack: false,
            musicSource: track.musicSource,
            spotifyURI: track.spotifyURI,
            stableIdentity: track.stableIdentity
        )
    }

    private func lockedQueueTracks(
        outgoing: SongSwitchAnimator.TrackSnapshot,
        incoming: SongSwitchAnimator.TrackSnapshot
    ) -> [QueueTrack] {
        let outgoingURL = tracks.first?.albumArtURL
        let incomingIdentity = trackIdentityKey(trackName: incoming.trackName, artistName: incoming.artistName)
        let incomingMatchedTrack = tracks
            .first {
                trackIdentityKey(trackName: $0.trackName, artistName: $0.artistName) == incomingIdentity &&
                (($0.albumArtURL?.isEmpty == false) || $0.albumArt != nil)
            }
        let incomingURL = incomingMatchedTrack?.albumArtURL

        let outgoingSlot = QueueTrack(
            id: UUID(),
            trackName: outgoing.trackName,
            artistName: outgoing.artistName,
            albumArtURL: outgoingURL,
            albumArt: outgoing.albumArt,
            isCurrentTrack: true,
            musicSource: tracks.first?.musicSource ?? activeSource,
            spotifyURI: tracks.first?.spotifyURI
        )

        let incomingSlot = QueueTrack(
            id: UUID(),
            trackName: incoming.trackName,
            artistName: incoming.artistName,
            albumArtURL: incomingURL,
            albumArt: incoming.albumArt,
            isCurrentTrack: false,
            musicSource: incomingMatchedTrack?.musicSource ?? activeSource,
            spotifyURI: incomingMatchedTrack?.spotifyURI
        )

        let filteredUpcoming = tracks.enumerated()
            .filter { $0.offset > 0 }
            .map(\.element)
            .filter {
                trackIdentityKey(trackName: $0.trackName, artistName: $0.artistName) != incomingIdentity
            }
            .map { normalizedQueueTrack($0) }

        var locked: [QueueTrack] = [outgoingSlot, incomingSlot]
        locked.append(contentsOf: filteredUpcoming.prefix(2))
        while locked.count < 4 {
            locked.append(.empty(index: locked.count))
        }
        return Array(locked.prefix(4))
    }
}

// MARK: - Shelf View

struct ShelfView: View {

    @ObservedObject var viewModel: ShelfViewModel
    @ObservedObject var authManager: SpotifyAuthManager
    @ObservedObject var themeManager: WidgetThemeManager
    private let shelfPanelOpacity: Double = 0.85
    private var theme: WidgetThemePalette { themeManager.palette }
    private var shouldShowSpotifyConnectOverlay: Bool {
        !authManager.isConnected && !viewModel.isAppleMusicModeActive
    }

    var body: some View {
        ZStack {
            if viewModel.isOpen {
                shelfBody
                    .transition(shelfTransition)
            }
        }
        .frame(width: ShelfWindow.shelfWidth, height: ShelfWindow.shelfHeight)
        .clipped()
        .animation(.spring(response: 0.48, dampingFraction: 0.76), value: viewModel.isOpen)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: viewModel.placement)
    }

    private var shelfTransition: AnyTransition {
        switch viewModel.placement {
        case .below:
            // Shelf drops down from the widget when placed below.
            return .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            )
        case .above:
            // Mirrored when shelf flips above the widget.
            return .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .bottom).combined(with: .opacity)
            )
        }
    }

    // MARK: - Shelf Body

    private var shelfBody: some View {
        VStack(spacing: 12) {
            // ── Album art row (4 cards) ──
            ZStack {
                sleevesRow

                // ── Spotify connect overlay (when not connected) ──
                if shouldShowSpotifyConnectOverlay {
                    connectSpotifyOverlay
                }
            }

            // ── "Queue" pill bar ──
            queueBar
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(
            ZStack {
                // Main fill — dark gradient matching widget
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: theme.shelfPanelGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Subtle top sheen
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.05), .clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.35)
                        )
                    )

                // Subtle edge feather so shelf opening does not read as a hard cut line.
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: viewModel.placement == .below
                                ? [Color.black.opacity(max(0.0, 0.24 * (1 - viewModel.openProgress))), .clear]
                                : [.clear, Color.black.opacity(max(0.0, 0.24 * (1 - viewModel.openProgress)))],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .opacity(shelfPanelOpacity)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            // Gold outline ring matching the widget
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(theme.shelfOutline, lineWidth: 1)
                .opacity(shelfPanelOpacity)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    // MARK: - Sleeves Row

    private var sleevesRow: some View {
        ZStack {
            HStack(spacing: 12) {
                ForEach(Array(viewModel.tracks.enumerated()), id: \.element.id) { index, track in
                    VinylSleeveView(
                        track: track,
                        isVisible: viewModel.sleeveStates[index],
                        palette: theme
                    )
                    // During song switch animation: source card eases out with the takeoff
                    // instead of hard-disappearing on a single frame.
                    .opacity(sourceCardOpacity(for: index))
                    .scaleEffect(sourceCardScale(for: index))
                    .offset(x: queueShiftOffset(for: index))
                }
            }

            if let shiftState = viewModel.queueShiftState {
                let startX: CGFloat = 255
                let endX: CGFloat = 153
                VinylSleeveView(track: shiftState.replacementTrack, isVisible: true, palette: theme)
                    .offset(
                        x: startX + ((endX - startX) * viewModel.queueShiftProgress),
                        y: 0
                    )
                    .opacity(1.0)
                    .allowsHitTesting(false)
            }
        }
    }

    private func queueShiftOffset(for index: Int) -> CGFloat {
        guard let shift = viewModel.queueShiftState else { return 0 }
        let progress = viewModel.queueShiftProgress
        if index > shift.sourceIndex {
            return -102 * progress
        }
        if index == shift.sourceIndex {
            return 22 * progress
        }
        return 0
    }

    private func sourceCardOpacity(for index: Int) -> Double {
        if let shift = viewModel.queueShiftState, index == shift.sourceIndex {
            return Double(max(0, 1 - (viewModel.queueShiftProgress * 1.15)))
        }
        if viewModel.hiddenSleeveIndex == index {
            return 0.0
        }
        return 1.0
    }

    private func sourceCardScale(for index: Int) -> CGFloat {
        if let shift = viewModel.queueShiftState, index == shift.sourceIndex {
            return max(0.72, 1 - (viewModel.queueShiftProgress * 0.28))
        }
        if viewModel.hiddenSleeveIndex == index {
            return 0.72
        }
        return 1.0
    }

    // MARK: - Queue Bar

    private var queueBar: some View {
        Text("Queue")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(theme.queueBarText)
            .tracking(1.5)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(theme.queueBarBackground.opacity(0.8))
                    .overlay(
                        Capsule()
                            .strokeBorder(theme.queueBarBorder, lineWidth: 0.5)
                    )
            )
    }

    // MARK: - Spotify Connect Overlay

    private var connectSpotifyOverlay: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .foregroundColor(theme.connectOverlayIcon)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text("Connect Spotify")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme.connectOverlayTitle)
                Text("to see your queue")
                    .font(.system(size: 9))
                    .foregroundColor(theme.connectOverlaySubtitle)
            }

            Spacer()

            Button(action: { authManager.startLoginFlow() }) {
                Text("Connect")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color(hex: "1DB954"))  // Official Spotify green
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.connectOverlayBackground.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(theme.connectOverlayBorder, lineWidth: 0.5)
                )
        )
    }
}
