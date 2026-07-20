import SwiftUI
import AppKit

// MARK: - Gallery model
//
// A new Vinyl form: a horizontal "bar" layout (small spinning disc on the
// left, track info + transport controls on the right) instead of the
// vertical turntable body. Reuses the existing WidgetThemeID palette system
// so it stays consistent with every other vinyl colourway, but is otherwise
// a fully separate, self-contained widget — it does not touch
// VinylWidgetView.swift or its animations at all.

struct VinylHorizontalModel: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let themeID: WidgetThemeID

    static let all: [VinylHorizontalModel] = [
        VinylHorizontalModel(id: "hbar-classic", name: "Classic", subtitle: "Warm wood & gold", themeID: .default),
        VinylHorizontalModel(id: "hbar-obsidian", name: "Obsidian", subtitle: "Jet black & chrome", themeID: .obsidian),
        VinylHorizontalModel(id: "hbar-walnut", name: "Walnut", subtitle: "Audiophile wood deck", themeID: .walnut)
    ]
}

let horizontalBaseSize = CGSize(width: 480, height: 172)

// MARK: - Widget

struct VinylHorizontalWidgetView: View {
    let model: VinylHorizontalModel
    var isPreview: Bool = false

    @StateObject private var detector = MusicDetector()
    @StateObject private var artFetcher = AlbumArtFetcher()

    @State private var displayedArt: NSImage?
    @State private var displayedInfo: NowPlayingInfo = .empty

    private var theme: WidgetThemePalette { model.themeID.palette }
    private var np: NowPlayingInfo { displayedInfo }
    private var trackKey: String { "\(np.trackName)|\(np.artistName)" }

    var body: some View {
        HStack(spacing: 18) {
            discArea
            VStack(alignment: .leading, spacing: 10) {
                trackText
                Spacer(minLength: 2)
                transportRow
                progressRow
            }
            .padding(.vertical, 18)
            .padding(.trailing, 22)
        }
        .padding(.leading, 18)
        .frame(width: horizontalBaseSize.width, height: horizontalBaseSize.height, alignment: .leading)
        .background(
            LinearGradient(colors: theme.widgetBodyGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(theme.widgetBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.32), radius: 18, x: 0, y: 10)
        .onAppear {
            guard !isPreview else { return }
            detector.start()
            displayedInfo = detector.nowPlaying
            refreshArt()
        }
        .onDisappear {
            guard !isPreview else { return }
            detector.stop()
        }
        .onChange(of: detector.nowPlaying) { _, live in
            guard !isPreview else { return }
            withAnimation(.easeInOut(duration: 0.3)) { displayedInfo = live }
        }
        .onChange(of: np.albumArtURL) { _, _ in
            guard !isPreview else { return }
            refreshArt()
        }
    }

    private func refreshArt() {
        artFetcher.fetchArt(from: np.albumArtURL ?? "", trackKey: trackKey, forceRefresh: false) { image in
            withAnimation(.easeInOut(duration: 0.35)) { displayedArt = image }
        }
    }

    private func togglePlayback() {
        guard !isPreview else { return }
        detector.togglePlayback()
    }

    // MARK: - Disc + tonearm (left side)

    private var discArea: some View {
        ZStack {
            TimelineView(.animation(paused: isPreview || !np.isPlaying)) { context in
                discFace
                    .rotationEffect(.degrees(spinAngle(at: context.date)))
            }
            .frame(width: 128, height: 128)

            // Small resting tonearm, top-right of the disc. Purely decorative
            // here (no seek interactivity) — matches the look established on
            // the main vinyl widget: dark rod + brushed-chrome pivot joint.
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(colors: [Color(hex: "1c1c1e"), Color(hex: "606064"), Color(hex: "1c1c1e")],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: 5, height: 56)
                    .rotationEffect(.degrees(28))
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 1, y: 1)
                    .shadow(color: .black.opacity(0.28), radius: 3, x: 1, y: 2)

                Circle()
                    .fill(
                        LinearGradient(colors: [Color(hex: "38383c"), Color(hex: "222224"), Color(hex: "0e0e10")],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 0.6))
                    .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
                    .offset(x: 20, y: -20)

                Circle()
                    .fill(
                        RadialGradient(colors: [Color(hex: "f2f2f4"), Color(hex: "c2c2c6"), Color(hex: "78787c")],
                                       center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 4)
                    )
                    .frame(width: 8, height: 8)
                    .offset(x: 20, y: -20)
            }
            .frame(width: 60, height: 60)
            .offset(x: 34, y: -34)
        }
        .contentShape(Rectangle())
        .onTapGesture { togglePlayback() }
    }

    /// ~33rpm feel — slow, continuous, driven purely by wall-clock time.
    /// No inertia/spin-up: this is a small decorative disc, not the main
    /// turntable. The TimelineView above freezes `date` while paused, so
    /// this naturally holds a static angle without any extra state.
    private func spinAngle(at date: Date) -> Double {
        let degreesPerSecond = 30.0
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 360.0 / degreesPerSecond) * degreesPerSecond
    }

    private var discFace: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(colors: [Color(hex: "2a2a2a"), Color(hex: "0a0a0a")],
                                   center: .center, startRadius: 0, endRadius: 64)
                )
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .strokeBorder(Color.black.opacity(0.35), lineWidth: 0.6)
                    .padding(10 + CGFloat(i) * 11)
            }
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(colors: theme.albumArtLabelGradient,
                                       center: .center, startRadius: 0, endRadius: 26)
                    )
                if let displayedArt {
                    Image(nsImage: displayedArt)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(Circle())
                }
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: "cccccc"), Color(hex: "666666")],
                                         center: .center, startRadius: 0, endRadius: 3))
                    .frame(width: 6, height: 6)
            }
            .frame(width: 52, height: 52)
            .overlay(Circle().strokeBorder(theme.albumArtRingColor, lineWidth: 1.5))
        }
        .frame(width: 128, height: 128)
        .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
    }

    // MARK: - Track info + controls (right side)

    private var trackText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(np.trackName.isEmpty ? "Nothing Playing" : np.trackName)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(theme.trackTitle)
                .lineLimit(1)
            if !np.artistName.isEmpty {
                Text(np.artistName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.trackArtist)
                    .lineLimit(1)
            }
        }
    }

    private var transportRow: some View {
        HStack(spacing: 22) {
            transportButton("backward.fill", size: 15) { detector.previousTrack() }
            transportButton(np.isPlaying ? "pause.fill" : "play.fill", size: 17) { togglePlayback() }
            transportButton("forward.fill", size: 15) { detector.nextTrack() }
        }
    }

    private func transportButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(theme.trackTitle)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPreview)
    }

    private var progressRow: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let fraction = progressFraction(at: context.date)
            HStack(spacing: 10) {
                Text(formatTime(elapsedMillis(at: context.date)))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.trackArtist)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.trackArtist.opacity(0.25))
                        Capsule().fill(theme.trackTitle)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 3)
                Text("-" + formatTime(remainingMillis(at: context.date)))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.trackArtist)
            }
        }
        .frame(width: 250)
    }

    private func elapsedMillis(at date: Date) -> Int {
        guard let pos = np.positionMillis else { return 0 }
        var elapsed = Double(pos)
        if np.isPlaying, let sampledAt = np.progressSampledAt {
            elapsed += date.timeIntervalSince(sampledAt) * 1000
        }
        if let dur = np.durationMillis { elapsed = min(elapsed, Double(dur)) }
        return max(0, Int(elapsed))
    }

    private func remainingMillis(at date: Date) -> Int {
        guard let dur = np.durationMillis else { return 0 }
        return max(0, dur - elapsedMillis(at: date))
    }

    private func progressFraction(at date: Date) -> Double {
        guard let dur = np.durationMillis, dur > 0 else { return 0 }
        return min(1, max(0, Double(elapsedMillis(at: date)) / Double(dur)))
    }

    private func formatTime(_ millis: Int) -> String {
        let totalSeconds = millis / 1000
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

// MARK: - Sized root (applies the global small/medium/large scale)

struct VinylHorizontalSizedRoot: View {
    let model: VinylHorizontalModel
    @ObservedObject private var sizeM = WidgetSizeManager.shared

    var body: some View {
        let s = sizeM.scale
        VinylHorizontalWidgetView(model: model)
            .scaleEffect(s)
            .frame(width: horizontalBaseSize.width * s, height: horizontalBaseSize.height * s)
    }
}

// MARK: - Gallery preview (fit-scaled, flattened)

struct VinylHorizontalModelPreview: View {
    let model: VinylHorizontalModel

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / horizontalBaseSize.width, geo.size.height / horizontalBaseSize.height)
            VinylHorizontalWidgetView(model: model, isPreview: true)
                .frame(width: horizontalBaseSize.width, height: horizontalBaseSize.height)
                .scaleEffect(s)
                .frame(width: horizontalBaseSize.width * s, height: horizontalBaseSize.height * s)
                .frame(width: geo.size.width, height: geo.size.height)
                .drawingGroup()
        }
    }
}
