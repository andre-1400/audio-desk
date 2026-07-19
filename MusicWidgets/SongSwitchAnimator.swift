// SongSwitchAnimator.swift
// Choreographs the full song-switch animation sequence (8.2s target)
// Uses tokenized scheduling so rapid skips never leave stale callbacks.

import SwiftUI
import AppKit
import Combine

enum SongSwitchPhase: Equatable {
    case idle
    case tonearmLifting
    case preLiftBrake
    case diskLifting
    case outgoingSleeveIn
    case outgoingSleeveOut
    case emptyPlatterHold
    case incomingSleeveFromShelf
    case incomingSleeveRevealsDisk
    case diskSettling
    case tonearmLowering
}

final class SongSwitchAnimator: ObservableObject {

    enum DiskArtMode {
        case outgoing
        case incoming
    }

    struct OverlayPose {
        let offset: CGSize
        let scale: CGFloat
        let opacity: Double
        let yaw: Double
        let shadowOpacity: Double
        let shadowRadius: CGFloat
        let shadowY: CGFloat
    }

    struct TrackSnapshot {
        let trackName: String
        let artistName: String
        let albumName: String
        let albumArt: NSImage?
    }

    struct TransitionRequest {
        let outgoing: TrackSnapshot
        let incoming: TrackSnapshot
        let widgetFrameInScreen: CGRect
        let platterCenterInScreen: CGPoint
    }

    @Published private(set) var phase: SongSwitchPhase = .idle
    @Published private(set) var outgoingAlbumArt: NSImage?
    @Published private(set) var incomingAlbumArt: NSImage?
    @Published private(set) var revealEventID: UUID?
    @Published private(set) var revealedIncomingSnapshot: TrackSnapshot?
    var onAnimationComplete: (() -> Void)?

    private var transitionID: UUID?
    private var scheduledWorkItems: [DispatchWorkItem] = []
    private var currentTransition: TransitionRequest?
    private var incomingCommittedForCurrentTransition = false
    private var incomingIdentityKey: String?
    private var latestRenderedPlatterAngle: Double = 0
    private var frozenOutgoingTransferAngle: Double = 0

    var isAnimating: Bool { phase != .idle }

    // Keep only the platter disk in the widget body.
    // Lifted disk and sleeves are rendered by the overlay window.
    var widgetDiskShouldBeVisible: Bool {
        widgetDiskOpacity > 0.001
    }

    /// Animated handoff value for the platter disk so it never hard-pops in/out.
    var widgetDiskOpacity: Double {
        switch phase {
        case .idle, .tonearmLifting, .preLiftBrake, .diskSettling, .tonearmLowering:
            return 1.0
        case .incomingSleeveRevealsDisk:
            let reveal = incomingDiskExposure
            if reveal < 0.52 { return 0.0 }
            return Double((reveal - 0.52) / 0.48)
        case .diskLifting, .outgoingSleeveIn, .outgoingSleeveOut, .emptyPlatterHold, .incomingSleeveFromShelf:
            return 0.0
        }
    }

    var diskArtMode: DiskArtMode {
        switch phase {
        case .idle, .tonearmLifting, .preLiftBrake, .diskLifting, .outgoingSleeveIn, .outgoingSleeveOut, .emptyPlatterHold, .incomingSleeveFromShelf:
            return .outgoing
        case .incomingSleeveRevealsDisk, .diskSettling, .tonearmLowering:
            return .incoming
        }
    }

    var platterRotationFrozen: Bool {
        switch phase {
        case .idle, .tonearmLifting:
            return false
        default:
            return true
        }
    }

    var outgoingTransferAngle: Double {
        switch phase {
        case .idle, .tonearmLifting:
            return latestRenderedPlatterAngle
        default:
            return frozenOutgoingTransferAngle
        }
    }

    // MARK: - Overlay payload (world-space relative to platter center)

    var showFloatingDisk: Bool {
        switch phase {
        case .preLiftBrake, .diskLifting:
            return true
        default:
            return false
        }
    }

    var floatingDiskPose: OverlayPose {
        switch phase {
        case .tonearmLifting:
            return OverlayPose(
                offset: platedOffset(CGSize(width: 0, height: 0)),
                scale: 1.0,
                opacity: 0.0,
                yaw: 0,
                shadowOpacity: 0.0,
                shadowRadius: 20,
                shadowY: 10
            )
        case .preLiftBrake:
            return OverlayPose(
                offset: platedOffset(CGSize(width: 0, height: 0)),
                scale: 1.0,
                opacity: 0.15,
                yaw: 0,
                shadowOpacity: 0.12,
                shadowRadius: 18,
                shadowY: 8
            )
        case .diskLifting:
            return OverlayPose(
                offset: platedOffset(CGSize(width: 0, height: -16)),
                scale: 1.08,
                opacity: 1.0,
                yaw: 0,
                shadowOpacity: 0.62,
                shadowRadius: 24,
                shadowY: 11
            )
        default:
            return OverlayPose(
                offset: platedOffset(CGSize(width: 0, height: -22)),
                scale: 1.10,
                opacity: 0.0,
                yaw: 0,
                shadowOpacity: 0.0,
                shadowRadius: 24,
                shadowY: 10
            )
        }
    }

    var showOutgoingSleeve: Bool {
        switch phase {
        case .outgoingSleeveIn, .outgoingSleeveOut:
            return true
        default:
            return false
        }
    }

    var outgoingSleevePose: OverlayPose {
        switch phase {
        case .diskLifting:
            return OverlayPose(
                offset: platedOffset(CGSize(width: 430, height: -4)),
                scale: 0.94,
                opacity: 0.0,
                yaw: -8,
                shadowOpacity: 0.20,
                shadowRadius: 16,
                shadowY: 10
            )
        case .outgoingSleeveIn:
            return OverlayPose(
                offset: platedOffset(CGSize(width: 108, height: -4)),
                scale: 1.0,
                opacity: 1.0,
                yaw: -2,
                shadowOpacity: 0.26,
                shadowRadius: 16,
                shadowY: 10
            )
        case .outgoingSleeveOut:
            return OverlayPose(
                offset: platedOffset(CGSize(width: -280, height: -4)),
                scale: 0.86,
                opacity: 0.0,
                yaw: -6,
                shadowOpacity: 0.12,
                shadowRadius: 14,
                shadowY: 8
            )
        default:
            return OverlayPose(
                offset: platedOffset(CGSize(width: 430, height: -4)),
                scale: 0.94,
                opacity: 0.0,
                yaw: -8,
                shadowOpacity: 0.0,
                shadowRadius: 22,
                shadowY: 10
            )
        }
    }

    var showIncomingSleeve: Bool {
        switch phase {
        case .emptyPlatterHold, .incomingSleeveFromShelf, .incomingSleeveRevealsDisk:
            return true
        default:
            return false
        }
    }

    var incomingSleevePose: OverlayPose {
        switch phase {
        case .emptyPlatterHold:
            return OverlayPose(
                offset: incomingEntryOffset,
                scale: 0.94,
                opacity: 0.0,
                yaw: -8,
                shadowOpacity: 0.20,
                shadowRadius: 16,
                shadowY: 10
            )
        case .incomingSleeveFromShelf:
            return OverlayPose(
                offset: platedOffset(CGSize(width: 108, height: -4)),
                scale: 1.0,
                opacity: 1.0,
                yaw: -2,
                shadowOpacity: 0.26,
                shadowRadius: 16,
                shadowY: 10
            )
        case .incomingSleeveRevealsDisk:
            return OverlayPose(
                offset: platedOffset(CGSize(width: 108, height: -4)),
                scale: 0.93,
                opacity: 1.0,
                yaw: 0,
                shadowOpacity: 0.20,
                shadowRadius: 14,
                shadowY: 9
            )
        case .diskSettling:
            return OverlayPose(
                offset: platedOffset(CGSize(width: 260, height: -4)),
                scale: 0.82,
                opacity: 0.0,
                yaw: 4,
                shadowOpacity: 0.10,
                shadowRadius: 14,
                shadowY: 8
            )
        default:
            return OverlayPose(
                offset: incomingEntryOffset,
                scale: 0.94,
                opacity: 0.0,
                yaw: -8,
                shadowOpacity: 0.0,
                shadowRadius: 20,
                shadowY: 10
            )
        }
    }

    /// 0...1 pocket exposure used to show the outgoing disk sliding into the sleeve.
    var outgoingDiskExposure: CGFloat {
        switch phase {
        case .preLiftBrake, .diskLifting:
            return 1.0
        case .outgoingSleeveIn:
            return 0.0
        case .outgoingSleeveOut:
            return 0.0
        default:
            return 0.0
        }
    }

    /// 0...1 pocket exposure used to show the incoming disk emerging from the sleeve.
    var incomingDiskExposure: CGFloat {
        switch phase {
        case .emptyPlatterHold:
            return 0.0
        case .incomingSleeveFromShelf:
            return 0.0
        case .incomingSleeveRevealsDisk:
            return 1.0
        default:
            return 0.0
        }
    }

    var tonearmShouldRest: Bool {
        switch phase {
        case .idle, .tonearmLowering:
            return false
        default:
            return true
        }
    }

    // MARK: - Commands

    func startTransition(_ request: TransitionRequest) {
        // Latest request wins: restart immediately.
        if isAnimating {
            cancelAndReset()
        }

        beginTransition(request)
    }

    func updateIncomingAlbumArtIfPossible(_ image: NSImage) {
        updateIncomingAlbumArtIfPossible(image, identityKey: nil)
    }

    func updateIncomingAlbumArtIfPossible(_ image: NSImage, identityKey: String?) {
        guard isAnimating, !incomingCommittedForCurrentTransition else { return }
        if let identityKey, let incomingIdentityKey {
            let normalizedIncoming = normalizedIdentity(identityKey)
            if normalizedIncoming != incomingIdentityKey {
                return
            }
        }
        incomingAlbumArt = image
    }

    func updateRenderedPlatterAngle(_ angle: Double) {
        latestRenderedPlatterAngle = normalizedAngle(angle)
    }

    func cancelAndReset() {
        cancelScheduledWork()
        transitionID = nil
        currentTransition = nil
        incomingCommittedForCurrentTransition = false
        incomingIdentityKey = nil
        outgoingAlbumArt = nil
        incomingAlbumArt = nil
        revealedIncomingSnapshot = nil
        revealEventID = nil
        phase = .idle
    }

    // MARK: - Internals

    private var platterCenterOffset: CGSize {
        guard let request = currentTransition else { return .zero }
        return CGSize(
            width: request.platterCenterInScreen.x - request.widgetFrameInScreen.midX,
            height: request.widgetFrameInScreen.midY - request.platterCenterInScreen.y
        )
    }

    private var incomingEntryOffset: CGSize {
        platedOffset(CGSize(width: 430, height: -4))
    }

    private func platedOffset(_ relative: CGSize) -> CGSize {
        CGSize(
            width: platterCenterOffset.width + relative.width,
            height: platterCenterOffset.height + relative.height
        )
    }

    private func beginTransition(_ request: TransitionRequest) {
        cancelScheduledWork()

        let id = UUID()
        transitionID = id
        currentTransition = request
        incomingCommittedForCurrentTransition = false
        incomingIdentityKey = identityKey(for: request.incoming)
        frozenOutgoingTransferAngle = latestRenderedPlatterAngle

        outgoingAlbumArt = request.outgoing.albumArt
        incomingAlbumArt = request.incoming.albumArt
        revealedIncomingSnapshot = nil
        revealEventID = nil

        advance(to: .tonearmLifting, transitionID: id)
    }

    private func advance(to nextPhase: SongSwitchPhase, transitionID id: UUID) {
        guard transitionID == id, let request = currentTransition else { return }

        if nextPhase == .idle {
            finishTransition(transitionID: id)
            return
        }

        applySideEffects(entering: nextPhase, request: request)

        withAnimation(animation(for: nextPhase)) {
            phase = nextPhase
        }

        let next = phaseAfter(nextPhase)
        schedule(after: duration(for: nextPhase), transitionID: id) { [weak self] in
            self?.advance(to: next, transitionID: id)
        }
    }

    private func applySideEffects(entering phase: SongSwitchPhase, request: TransitionRequest) {
        switch phase {
        case .preLiftBrake:
            // Snapshot platter orientation at brake completion so lifted disk
            // starts from the exact same angle (no visual jump).
            frozenOutgoingTransferAngle = latestRenderedPlatterAngle
        case .incomingSleeveRevealsDisk:
            if !incomingCommittedForCurrentTransition {
                incomingCommittedForCurrentTransition = true
                revealedIncomingSnapshot = TrackSnapshot(
                    trackName: request.incoming.trackName,
                    artistName: request.incoming.artistName,
                    albumName: request.incoming.albumName,
                    albumArt: incomingAlbumArt ?? request.incoming.albumArt
                )
                revealEventID = UUID()
            }
        default:
            break
        }
    }

    private func finishTransition(transitionID id: UUID) {
        guard transitionID == id else { return }

        cancelScheduledWork()
        transitionID = nil
        currentTransition = nil
        incomingCommittedForCurrentTransition = false
        incomingIdentityKey = nil

        phase = .idle
        outgoingAlbumArt = nil
        incomingAlbumArt = nil
        revealedIncomingSnapshot = nil
        revealEventID = nil

        onAnimationComplete?()
    }

    private func schedule(after seconds: TimeInterval, transitionID id: UUID, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.transitionID == id else { return }
            block()
        }
        scheduledWorkItems.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancelScheduledWork() {
        scheduledWorkItems.forEach { $0.cancel() }
        scheduledWorkItems.removeAll()
    }

    // Chained 8.2s timeline.
    private func duration(for phase: SongSwitchPhase) -> TimeInterval {
        switch phase {
        case .idle:
            return 0
        case .tonearmLifting:
            return 0.70
        case .preLiftBrake:
            return 0.50
        case .diskLifting:
            return 1.10
        case .outgoingSleeveIn:
            return 1.00
        case .outgoingSleeveOut:
            return 0.84
        case .emptyPlatterHold:
            return 0.74
        case .incomingSleeveFromShelf:
            return 1.40
        case .incomingSleeveRevealsDisk:
            return 1.02
        case .diskSettling:
            return 0.86
        case .tonearmLowering:
            return 0.42
        }
    }

    private func animation(for phase: SongSwitchPhase) -> Animation {
        switch phase {
        case .idle:
            return .linear(duration: 0.01)
        case .tonearmLifting:
            return .spring(response: 0.62, dampingFraction: 0.86)
        case .preLiftBrake:
            return .timingCurve(0.18, 0.90, 0.24, 1.0, duration: 0.50)
        case .diskLifting:
            return .easeOut(duration: 1.10)
        case .outgoingSleeveIn:
            return .easeInOut(duration: 1.00)
        case .outgoingSleeveOut:
            return .easeIn(duration: 0.84)
        case .emptyPlatterHold:
            return .linear(duration: 0.74)
        case .incomingSleeveFromShelf:
            return .easeInOut(duration: 1.40)
        case .incomingSleeveRevealsDisk:
            return .easeInOut(duration: 1.02)
        case .diskSettling:
            return .spring(response: 0.52, dampingFraction: 0.84)
        case .tonearmLowering:
            return .easeInOut(duration: 0.42)
        }
    }

    private func phaseAfter(_ phase: SongSwitchPhase) -> SongSwitchPhase {
        switch phase {
        case .idle:
            return .idle
        case .tonearmLifting:
            return .preLiftBrake
        case .preLiftBrake:
            return .diskLifting
        case .diskLifting:
            return .outgoingSleeveIn
        case .outgoingSleeveIn:
            return .outgoingSleeveOut
        case .outgoingSleeveOut:
            return .emptyPlatterHold
        case .emptyPlatterHold:
            return .incomingSleeveFromShelf
        case .incomingSleeveFromShelf:
            return .incomingSleeveRevealsDisk
        case .incomingSleeveRevealsDisk:
            return .diskSettling
        case .diskSettling:
            return .tonearmLowering
        case .tonearmLowering:
            return .idle
        }
    }

    private func identityKey(for snapshot: TrackSnapshot) -> String {
        [
            normalizedIdentity(snapshot.trackName),
            normalizedIdentity(snapshot.artistName),
            normalizedIdentity(snapshot.albumName)
        ].joined(separator: "|")
    }

    private func normalizedAngle(_ angle: Double) -> Double {
        let value = angle.truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }

    private func normalizedIdentity(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
