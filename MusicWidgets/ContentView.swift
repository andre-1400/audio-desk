import SwiftUI
import Combine

// MARK: - Theme
//
// One unified native look — no app-chrome "brand" skin anymore (the old
// Apple Music/Spotify dual-theme, and the Brand/BrandManager types that
// drove it, were removed entirely per explicit redesign request). The
// window now just follows the system's own light/dark appearance, the
// way every native Mac app does, instead of a manually-picked skin.

// Design tokens, repointed to native macOS semantics (Phase 1 redesign).
// The names stay so the hundreds of existing call sites are untouched; only
// the resolved values change — from hand-picked hex fills to system semantic
// colours and materials that adapt to the active NSAppearance (now just the
// system's own light/dark mode, not a brand toggle).
enum Neu {
    // Primary / secondary label colours — the system's, so they track
    // appearance, accessibility contrast, and vibrancy automatically.
    static var text: Color    { .primary }
    static var subtext: Color { .secondary }
    // Hairline separators use the real system separator colour.
    static var hairline: Color { Color(nsColor: .separatorColor) }

    // Surface fills. Kept as translucent-friendly semantic colours; most
    // chrome now sits on materials (VisualEffectBlur / .appCard) rather than
    // these opaque fills, but a few call sites still reference them.
    static var bg: Color      { Color(nsColor: .windowBackgroundColor) }
    static var raised: Color  { Color(nsColor: .controlBackgroundColor) }
    static var well: Color    { Color(nsColor: .underPageBackgroundColor) }
    static var elevated: Color { Color(nsColor: .controlBackgroundColor) }
    static var sidebar: Color { Color(nsColor: .windowBackgroundColor) }
    static var dark: Color    { Color.black.opacity(0.12) }
    static var light: Color   { Color.clear }
}

// Signature accent (red for Apple Music, green for Spotify) + the colour that reads on top of it.
// Kept as a thin namespace (not just `Color.accentColor` inline everywhere)
// so the many existing call sites (sidebar tint, gallery card badges,
// onboarding chrome) don't all need editing individually — every one of
// them now resolves to the system's own accent colour (system blue on any
// default Mac, and correctly follows the user's own accent choice if
// they've customised it in System Settings, exactly like Mail/Notes/
// System Settings itself do).
enum AMTheme {
    static var accent: Color { .accentColor }
    static var accentLight: Color { Color.accentColor.opacity(0.65) }
    static var onAccent: Color { .white }
    static var gradient: LinearGradient {
        LinearGradient(colors: [accentLight, accent], startPoint: .top, endPoint: .bottom)
    }
}

// The old neumorphic modifiers, now thin shims over the native material
// surfaces in DesignSystem.swift — so every existing call site (settings
// blocks, buttons, cards) becomes a material card with continuous corners
// and a soft shadow, no code churn at the call sites.
extension View {
    func neuRaised(_ corner: CGFloat = 22, pressed: Bool = false) -> some View {
        appCard(corner: corner, elevated: false)
    }
    // Recessed inset well (native material, no drop shadow).
    func neuInset(_ corner: CGFloat = 16) -> some View {
        appWell(corner: corner)
    }
}

// MARK: - Root (onboarding gate)

enum OnboardingGate {
    static let key = "onboarding.done.v1"
    static var shouldShow: Bool {
        #if DEBUG
        return true   // always show during development (Xcode runs)
        #else
        return !UserDefaults.standard.bool(forKey: key)
        #endif
    }
    static func markDone() { UserDefaults.standard.set(true, forKey: key) }
}

struct ContentView: View {
    @State private var showOnboarding = OnboardingGate.shouldShow

    var body: some View {
        ZStack {
            // Native window vibrancy behind the whole app — the "liquid glass"
            // base the flat Neu.bg fill used to cover.
            VisualEffectBlur(.underWindowBackground).ignoresSafeArea()
            if showOnboarding {
                OnboardingView(onFinish: {
                    OnboardingGate.markDone()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { showOnboarding = false }
                })
                .transition(.opacity)
            } else {
                GalleryRoot()
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 820, minHeight: 600)
        // No .preferredColorScheme override anymore — the window just
        // follows the system's own light/dark appearance, like every
        // native Mac app, instead of a brand-driven light/dark pick.
    }
}

struct GalleryRoot: View {
    @State private var category: WidgetCategory = .vinyl
    @State private var showSettings = false
    @State private var showTips = false
    @StateObject private var detector = MusicDetector()
    @ObservedObject private var activeWidget = ActiveWidgetState.shared

    var body: some View {
        HStack(spacing: 0) {
            GallerySidebar(category: $category, onSettings: { showSettings = true })
            GalleryDetail(category: category, detector: detector)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // No opaque fill here — the window's VisualEffectBlur (from
        // ContentView) shows through; the sidebar draws its own .sidebar
        // material on top.
        .overlay {
            if showTips {
                WelcomeTipsCard {
                    WelcomeTips.markSeen()
                    withAnimation(.easeOut(duration: 0.25)) { showTips = false }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.03)))
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(onClose: { showSettings = false })
        }
        .onAppear { detector.start() }
        .onDisappear { detector.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .openWidgetSettings)) { _ in
            showSettings = true
        }
        // The very first time a widget lands on the desktop, share three quick tips.
        .onChange(of: activeWidget.entry) { _, entry in
            if entry != nil && WelcomeTips.shouldShow {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { showTips = true }
            }
        }
    }
}

// MARK: - Sidebar

/// A small drawn silhouette of a MacBook's camera notch — flat top edge,
/// rounded only at the two bottom corners — for the sidebar's Notch row.
/// Sized/inset to sit in the same visual box a system symbol glyph would
/// (List row icons are laid out assuming roughly an 18x18pt slot), and
/// tinted via `.foregroundStyle` like any symbol so it still follows the
/// row's own selected/unselected colour automatically.
private struct NotchGlyph: View {
    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 4,
            bottomTrailingRadius: 4,
            topTrailingRadius: 0,
            style: .continuous
        )
        .frame(width: 17, height: 10)
        .frame(width: 18, height: 18)
    }
}

private struct GallerySidebar: View {
    @Binding var category: WidgetCategory
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand header — just the app name, no mark/tile and no subtitle
            // (both read as unnecessary chrome once the sidebar has its own
            // native section header below).
            HStack(spacing: 10) {
                Text("Audio Desk").font(.appTitle).foregroundStyle(Neu.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 30)
            .padding(.bottom, 14)

            // Native sidebar list — system selection highlight, hover, row
            // metrics, exactly like Finder/Music. Tint reads AMTheme.accent,
            // which is just .accentColor now — system blue on any default
            // Mac, correctly following the user's own accent colour choice
            // if they've customised it in System Settings.
            List(selection: Binding(
                get: { category },
                set: { new in
                    if let new { withAnimation(.easeInOut(duration: 0.18)) { category = new } }
                }
            )) {
                Section("Library") {
                    ForEach(WidgetCategory.availableCases) { cat in
                        // No SF Symbol actually looks like a MacBook notch
                        // (the closest, circle.grid.2x1.fill, is just two
                        // dots) — drawn directly instead so it reads as an
                        // actual notch silhouette.
                        if cat == .notch {
                            Label {
                                Text(cat.title)
                            } icon: {
                                NotchGlyph()
                            }
                            .tag(cat)
                        } else {
                            Label(cat.title, systemImage: cat.icon)
                                .tag(cat)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 30)
            .tint(AMTheme.accent)

            // Settings + version footer, matching sidebar row language.
            VStack(alignment: .leading, spacing: 2) {
                Button(action: onSettings) {
                    Label("Settings", systemImage: "gearshape")
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)

                Text("Audio Desk \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.appCaption)
                    .foregroundStyle(Neu.subtext.opacity(0.7))
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
            }
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(VisualEffectBlur(.sidebar, blendingMode: .behindWindow).ignoresSafeArea())
    }
}

// MARK: - Settings

struct SettingsView: View {
    let onClose: () -> Void
    @ObservedObject private var sizeM = WidgetSizeManager.shared
    @ObservedObject private var settings = WidgetSettings.shared
    @StateObject private var startup = LaunchOnStartupManager()

    private var accent: Color { AMTheme.accent }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.appTitle).foregroundStyle(Neu.text)
                Spacer()
                // A real labelled "Close" button — this sheet had no other
                // dismiss control, so the X icon button is replaced here
                // rather than just removed outright.
                Button("Close", action: onClose)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)

            // Native grouped Form — the same section/row language as macOS
            // System Settings, replacing the hand-drawn "block" cards.
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Widget Size").font(.appBody).foregroundStyle(Neu.text)
                        Text("Anywhere from icon-sized to over half the screen")
                            .font(.appCaption).foregroundStyle(Neu.subtext)
                        // A real native Slider with the system's own bookend-
                        // icon layout (minimumValueLabel/maximumValueLabel) —
                        // the same construct System Settings uses for
                        // brightness/volume — instead of hand-placing icons
                        // in an HStack next to it, which is what produced the
                        // uneven gap this replaces. Safe here (unlike the
                        // gallery header's copy) because this sheet isn't
                        // isMovableByWindowBackground, so there's no window-
                        // drag conflict to guard against.
                        Slider(value: $sizeM.scale, in: WidgetSizeManager.minScale...WidgetSizeManager.maxScale) {
                            EmptyView()
                        } minimumValueLabel: {
                            Image(systemName: "app").font(.system(size: 11)).foregroundStyle(Neu.subtext)
                        } maximumValueLabel: {
                            Image(systemName: "app.fill").font(.system(size: 16)).foregroundStyle(Neu.subtext)
                        }
                        .tint(accent)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Opacity").font(.appBody).foregroundStyle(Neu.text)
                        Text("Let the widget blend into your wallpaper")
                            .font(.appCaption).foregroundStyle(Neu.subtext)
                        HStack(spacing: 12) {
                            Slider(value: $settings.widgetOpacity, in: 0.5...1.0) {
                                EmptyView()
                            } minimumValueLabel: {
                                Image(systemName: "circle.dotted").font(.system(size: 12)).foregroundStyle(Neu.subtext)
                            } maximumValueLabel: {
                                Image(systemName: "circle.fill").font(.system(size: 12)).foregroundStyle(Neu.subtext)
                            }
                            .tint(accent)
                            Text("\(Int(settings.widgetOpacity * 100))%")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Neu.text)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Appearance")
                }

                Section("Behavior") {
                    windowLayerRow
                    toggleRow(icon: "cursorarrow.rays", title: "Click-through",
                              subtitle: "Clicks pass through to what's behind",
                              isOn: $settings.clickThrough)
                    toggleRow(icon: "moon.zzz", title: "Hide when paused",
                              subtitle: "Fade out when nothing is playing",
                              isOn: $settings.hideWhenPaused)
                    toggleRow(icon: "record.circle", title: "Track-change animation",
                              subtitle: "Off: the vinyl widgets snap to the next song instantly",
                              isOn: $settings.vinylTransitionAnimationEnabled)
                }

                Section("Startup") {
                    toggleRow(icon: "power", title: "Launch at login",
                              subtitle: startup.isEnabled ? "Opens automatically at login" : "Off — open it yourself",
                              isOn: Binding(
                                get: { startup.isEnabled },
                                set: { startup.setEnabled($0) }
                              ))
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 460, height: 620)
        .background(VisualEffectBlur(.sheet))
    }

    // Replaces the old plain "Always on top" toggle — a 3-way native
    // segmented control (Normal/Top/Bottom) instead of just on/off, same
    // row layout (label+icon, then control below) the Widget Size/Opacity
    // rows above already use.
    private var windowLayerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Window Layer").font(.appBody).foregroundStyle(Neu.text)
                    Text(windowLayerSubtitle).font(.appCaption).foregroundStyle(Neu.subtext)
                }
            } icon: {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(settings.windowLayer == .normal ? Neu.subtext : accent)
                    .frame(width: 20)
            }
            Picker("", selection: $settings.windowLayer) {
                ForEach(WidgetWindowLayer.allCases, id: \.self) { layer in
                    Text(layer.title).tag(layer)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private var windowLayerSubtitle: String {
        switch settings.windowLayer {
        case .normal: return "Sits just above the desktop icons"
        case .alwaysOnTop: return "Floats above other windows"
        case .alwaysOnBottom: return "Behind the icons — decorative only, can't be clicked"
        }
    }

    private func toggleRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.appBody).foregroundStyle(Neu.text)
                    Text(subtitle).font(.appCaption).foregroundStyle(Neu.subtext)
                }
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isOn.wrappedValue ? accent : Neu.subtext)
                    .frame(width: 20)
            }
        }
        .tint(accent)
    }
}

/// Same call-site API as before, now backed by the native macOS segmented
/// control (`Picker(.segmented)`) instead of a hand-drawn pill row.
struct NeuSegmented: View {
    let options: [String]
    let selected: Int
    let onSelect: (Int) -> Void

    var body: some View {
        Picker("", selection: Binding(
            get: { selected },
            set: { onSelect($0) }
        )) {
            ForEach(options.indices, id: \.self) { i in
                Text(options[i]).tag(i)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }
}

/// Continuous replacement for the old small/medium/large segmented control —
/// a small glyph and a large glyph bookend the slider, same visual language
/// as the opacity slider elsewhere in Settings.
///
/// Custom-drawn and dragged via SliderDragCaptureView rather than a plain
/// SwiftUI `Slider`: the gallery window (where this appears in the header)
/// is `isMovableByWindowBackground = true` for its frameless "drag from
/// anywhere" look, and a plain Slider doesn't reliably prevent that window
/// drag from hijacking the interaction — the exact bug already diagnosed
/// and fixed once for the vinyl widget's own progress scrubber.
struct WidgetSizeSlider: View {
    @Binding var scale: CGFloat

    private var fraction: CGFloat {
        (scale - WidgetSizeManager.minScale) / (WidgetSizeManager.maxScale - WidgetSizeManager.minScale)
    }

    // Still custom-drawn (not a real Slider — see SliderDragCaptureView's
    // own doc comment on why a real Slider isn't safe in this specific,
    // isMovableByWindowBackground window), but refined to match a native
    // continuous NSSlider's actual details more closely: a lighter,
    // material-toned empty track instead of a flat well fill, a thinner
    // 4pt track, and a thumb with a hairline border for definition instead
    // of shadow alone. Icon bookend sizes now match the real Slider used
    // for the same control in Settings (11/16) instead of a different,
    // larger pair (11/20) that made the two controls feel inconsistent.
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "app").font(.system(size: 11))
                .foregroundStyle(Neu.subtext)

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 4)
                    Capsule().fill(AMTheme.accent).frame(width: max(4, width * fraction), height: 4)
                    Circle().fill(Color.white)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .offset(x: min(width - 16, max(0, width * fraction - 8)))
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .overlay(
                    SliderDragCaptureView(onDrag: { x in
                        let f = min(1, max(0, x / width))
                        scale = WidgetSizeManager.minScale + f * (WidgetSizeManager.maxScale - WidgetSizeManager.minScale)
                    })
                )
            }
            .frame(height: 20)

            Image(systemName: "app.fill").font(.system(size: 16))
                .foregroundStyle(Neu.subtext)
        }
    }
}

/// Raw AppKit drag surface backing WidgetSizeSlider. Same shape as
/// VinylWidgetView's DragCaptureView (mouseDownCanMoveWindow = false, custom
/// hitTest) — kept as its own small type rather than shared, matching this
/// codebase's existing convention of not sharing exact interaction plumbing
/// between unrelated features.
private struct SliderDragCaptureView: NSViewRepresentable {
    var onDrag: (CGFloat) -> Void

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.onDrag = onDrag
        return view
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        nsView.onDrag = onDrag
    }

    final class DragView: NSView {
        var onDrag: ((CGFloat) -> Void)?

        override var isFlipped: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func mouseDown(with event: NSEvent) {
            window?.isMovableByWindowBackground = false
            onDrag?(convert(event.locationInWindow, from: nil).x)
        }

        override func mouseDragged(with event: NSEvent) {
            onDrag?(convert(event.locationInWindow, from: nil).x)
        }

        override func mouseUp(with event: NSEvent) {
            window?.isMovableByWindowBackground = true
        }
    }
}

/// Raw AppKit drag surface backing NowPlayingBar's progress scrubber — same
/// shape as SliderDragCaptureView (mouseDownCanMoveWindow = false, custom
/// hitTest, temporarily disabling isMovableByWindowBackground while
/// dragging), kept as its own type rather than shared per this codebase's
/// existing convention. The one difference: this needs a distinct "drag
/// ended" callback (to actually commit the seek), not just continuous
/// onDrag, since scrubbing previews a position without moving anything
/// until release.
private struct NowPlayingScrubDragCaptureView: NSViewRepresentable {
    var onDrag: (CGFloat) -> Void
    var onEnd: (CGFloat) -> Void

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.onDrag = onDrag
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        nsView.onDrag = onDrag
        nsView.onEnd = onEnd
    }

    final class DragView: NSView {
        var onDrag: ((CGFloat) -> Void)?
        var onEnd: ((CGFloat) -> Void)?

        override var isFlipped: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func mouseDown(with event: NSEvent) {
            window?.isMovableByWindowBackground = false
            onDrag?(convert(event.locationInWindow, from: nil).x)
        }

        override func mouseDragged(with event: NSEvent) {
            onDrag?(convert(event.locationInWindow, from: nil).x)
        }

        override func mouseUp(with event: NSEvent) {
            window?.isMovableByWindowBackground = true
            onEnd?(convert(event.locationInWindow, from: nil).x)
        }
    }
}

// MARK: - Detail pane (grid + now playing)

// MARK: - Live data for gallery preview cards

/// Feeds real track/art/colour into the gallery's preview cards, so hovering
/// a style shows what it would actually look like with the song that's
/// currently playing — without reintroducing the scroll-lag bug GalleryDetail
/// was fixed for. That fix was about observing detector.nowPlaying directly,
/// which republishes ~4x/second (it carries live playback position);
/// GalleryLiveTrack subscribes to the same detector but only republishes when
/// the track identity actually changes, so observing it costs nothing during
/// scroll and only re-renders the grid once per track change.
///
/// Art/colour/blur are computed once here, centrally, and hovering a card is
/// purely visual — the preview's transport buttons are never wired to real
/// playback (deliberately: real controls per visible card would mean actual
/// AppleScript commands firing from decorative buttons, for no benefit).
final class GalleryLiveTrack: ObservableObject {
    @Published private(set) var info: NowPlayingInfo = .empty
    @Published private(set) var art: NSImage?
    @Published private(set) var colours: ExtractedColours = .adaptivePreviewPlaceholder
    @Published private(set) var blurredArt: NSImage?

    private let artFetcher = AlbumArtFetcher()
    private var cancellable: AnyCancellable?
    private var lastIdentityKey = ""

    func start(observing detector: MusicDetector) {
        guard cancellable == nil else { return }
        cancellable = detector.$nowPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.handle($0) }
    }

    private func handle(_ np: NowPlayingInfo) {
        let key = "\(np.trackName)|\(np.artistName)|\(np.albumName)"
        guard key != lastIdentityKey else { return }
        lastIdentityKey = key
        info = np

        guard let url = np.albumArtURL, !url.isEmpty else {
            art = nil
            blurredArt = nil
            colours = .adaptivePreviewPlaceholder
            return
        }
        artFetcher.fetchArt(from: url, trackKey: key, forceRefresh: false) { [weak self] image in
            guard let self, let image else { return }
            self.art = image
            self.colours = ColourExtractor.extract(from: image)
            DispatchQueue.global(qos: .userInitiated).async {
                let blurred = ArtBlurrer.blurredBody(from: image)
                DispatchQueue.main.async { self.blurredArt = blurred }
            }
        }
    }
}

private struct GalleryDetail: View {
    let category: WidgetCategory
    // Not @ObservedObject on purpose: GalleryDetail never reads detector's
    // published properties itself, only hands it to NowPlayingBar. Observing
    // it here forced this view's entire body — the whole card grid — to
    // re-evaluate on every playback tick (~4x/second), competing with scroll
    // for no benefit. NowPlayingBar still observes it correctly, so it's the
    // only part of the tree that actually re-renders live.
    let detector: MusicDetector
    @ObservedObject private var activeWidget = ActiveWidgetState.shared
    @ObservedObject private var sizeM = WidgetSizeManager.shared
    @ObservedObject private var notchState = NotchWidgetState.shared
    // Deduped (identity-only) live feed for preview cards — see
    // GalleryLiveTrack's own doc comment for why this is safe to observe
    // here despite the scroll-lag history with the raw detector.
    @StateObject private var liveTrack = GalleryLiveTrack()
    @State private var hoveredID: String? = nil
    @State private var contentWidth: CGFloat = 0
    @State private var customColorTarget: CustomColorTarget? = nil

    // Eager column count derived from the measured width (replaces LazyVGrid,
    // whose lazy re-measuring of off-screen rows caused the scroll to jump).
    private var columnCount: Int {
        let spacing: CGFloat = 26
        let minItem: CGFloat = 250
        let avail = max(contentWidth - 68, minItem)   // 34pt horizontal padding each side
        return max(1, Int((avail + spacing) / (minItem + spacing)))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header — a genuine large title (the appLargeTitle token),
            // matching the scale/weight Music, Podcasts, and Mail use for
            // their own library page headers, with the slight negative
            // tracking SF Pro Display wants at large sizes. Extra top
            // clearance gives it room to breathe the way a real large-title
            // page does, instead of sitting flush under the titlebar.
            HStack(alignment: .firstTextBaseline) {
                Text(category.title)
                    .font(.appLargeTitle)
                    .tracking(-0.4)
                    .foregroundStyle(Neu.text)
                Spacer()
                // Widget size, right where you pick the widget — not
                // meaningful for Desktop (always full screen) or Notch
                // (sized to the physical notch, not user-adjustable).
                if category != .desktop && category != .notch {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("SIZE")
                            .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                            .foregroundStyle(Neu.subtext)
                        WidgetSizeSlider(scale: $sizeM.scale)
                            .frame(width: 190)
                    }
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 36)
            .padding(.bottom, 26)

            // Grid (grouped by form)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 30) {
                    if category == .vinyl {
                        ForEach(VinylStyle.forms) { form in
                            formSection(name: form.name,
                                        count: form.styles.count, items: form.styles) { style in
                                GalleryCard(title: style.name, subtitle: style.subtitle,
                                            accent: category.accentColor,
                                            hovered: hoveredID == style.id,
                                            active: activeWidget.entry == "vinyl:\(style.themeID.rawValue)",
                                            placeLabel: style.themeID == .custom ? "Customize" : "Place",
                                            placeIcon: style.themeID == .custom ? "eyedropper" : "arrow.up.forward.square.fill",
                                            special: style.isSpecialStyle,
                                            badgeText: style.specialKind?.badgeText,
                                            badgeIcon: style.specialKind?.badgeIcon ?? "sparkles",
                                            transparentPreview: style.themeID == .ghost,
                                            onHover: { setHover(style.id, $0) },
                                            action: {
                                                if style.themeID == .custom {
                                                    customColorTarget = .vinyl
                                                } else {
                                                    AppDelegate.shared?.launchVinylWidget(themeID: style.themeID)
                                                }
                                            }) { animated in
                                    VinylStylePreview(themeID: style.themeID, animated: animated, live: liveTrack, usesRainbowPreview: style.themeID == .custom)
                                }
                            }
                        }
                        formSection(name: "Horizontal",
                                    count: VinylHorizontalModel.all.count, items: VinylHorizontalModel.all) { model in
                            GalleryCard(title: model.name, subtitle: model.subtitle,
                                        accent: category.accentColor,
                                        hovered: hoveredID == model.id,
                                        active: activeWidget.entry == "vinylh:\(model.id)",
                                        placeLabel: model.themeID == .custom ? "Customize" : "Place",
                                        placeIcon: model.themeID == .custom ? "eyedropper" : "arrow.up.forward.square.fill",
                                        special: model.isSpecialStyle,
                                        badgeText: model.specialKind?.badgeText,
                                        badgeIcon: model.specialKind?.badgeIcon ?? "sparkles",
                                        transparentPreview: model.themeID == .ghost,
                                        onHover: { setHover(model.id, $0) },
                                        action: {
                                            if model.themeID == .custom {
                                                customColorTarget = .vinylHorizontal(model)
                                            } else {
                                                AppDelegate.shared?.launchVinylHorizontalWidget(model: model)
                                            }
                                        }) { animated in
                                VinylHorizontalModelPreview(model: model, animated: animated, live: liveTrack, usesRainbowPreview: model.themeID == .custom)
                            }
                        }
                    } else if category == .cd {
                        ForEach(CDModel.forms) { form in
                            formSection(name: form.name,
                                        count: form.models.count, items: form.models) { model in
                                GalleryCard(title: model.name, subtitle: model.subtitle,
                                            accent: category.accentColor,
                                            hovered: hoveredID == model.id,
                                            active: activeWidget.entry == "cd:\(model.id)",
                                            placeLabel: model.isCustom ? "Customize" : "Place",
                                            placeIcon: model.isCustom ? "eyedropper" : "arrow.up.forward.square.fill",
                                            special: model.isSpecialStyle,
                                            badgeText: model.specialKind?.badgeText,
                                            badgeIcon: model.specialKind?.badgeIcon ?? "sparkles",
                                            onHover: { setHover(model.id, $0) },
                                            action: {
                                                if model.isCustom {
                                                    customColorTarget = .cd(model)
                                                } else {
                                                    AppDelegate.shared?.launchCDWidget(model: model)
                                                }
                                            }) { animated in
                                    CDModelPreview(model: model, animated: animated, live: liveTrack, usesRainbowPreview: model.isCustom)
                                }
                            }
                        }
                    } else if category == .albumArt {
                        formSection(name: "Album Art",
                                    count: AlbumArtModel.all.count, items: AlbumArtModel.all) { model in
                            GalleryCard(title: model.name, subtitle: model.subtitle,
                                        accent: category.accentColor,
                                        hovered: hoveredID == model.id,
                                        active: activeWidget.entry == "albumart:\(model.id)",
                                        onHover: { setHover(model.id, $0) },
                                        action: { AppDelegate.shared?.launchAlbumArtWidget(model: model) }) { _ in
                                AlbumArtModelPreview(model: model, live: liveTrack)
                            }
                        }
                    } else if category == .desktop {
                        ForEach(DesktopWidgetModel.forms) { form in
                            formSection(name: form.name,
                                        count: form.models.count, items: form.models) { model in
                                GalleryCard(title: model.name, subtitle: model.subtitle,
                                            accent: category.accentColor,
                                            hovered: hoveredID == model.id,
                                            active: activeWidget.entry == "desktop:\(model.id)",
                                            placeLabel: model.isCustom ? "Customize" : "Place",
                                            placeIcon: model.isCustom ? "eyedropper" : "arrow.up.forward.square.fill",
                                            special: model.isSpecialStyle,
                                            badgeText: model.specialKind?.badgeText,
                                            badgeIcon: model.specialKind?.badgeIcon ?? "sparkles",
                                            onHover: { setHover(model.id, $0) },
                                            action: {
                                                if model.isCustom {
                                                    customColorTarget = .desktop(model)
                                                } else {
                                                    AppDelegate.shared?.launchDesktopWidget(model: model)
                                                }
                                            }) { animated in
                                    DesktopWidgetModelPreview(model: model, animated: animated, live: liveTrack, usesRainbowPreview: model.isCustom)
                                }
                            }
                        }
                    } else {
                        // Notch — a single on/off toggle, not a style grid:
                        // there's nothing to pick between, just enabled or
                        // not, so this skips formSection's grouping/grid
                        // machinery entirely and reuses GalleryCard directly.
                        GalleryCard(title: "Now Playing", subtitle: "Shows up in your MacBook's notch",
                                    accent: category.accentColor,
                                    hovered: hoveredID == "notch",
                                    active: notchState.isEnabled,
                                    placeLabel: notchState.isEnabled ? "Turn Off" : "Turn On",
                                    placeIcon: notchState.isEnabled ? "xmark.circle" : "power",
                                    onHover: { setHover("notch", $0) },
                                    action: { notchState.isEnabled.toggle() }) { animated in
                            NotchWidgetModelPreview(animated: animated, live: liveTrack)
                        }
                        .padding(.top, 4)
                        .frame(maxWidth: 340, alignment: .leading)
                    }
                }
                .padding(.horizontal, 34)
                .padding(.top, 4)
                .padding(.bottom, 26)
            }
            .background(
                GeometryReader { g in
                    Color.clear
                        .onAppear { contentWidth = g.size.width }
                        .onChange(of: g.size.width) { _, w in contentWidth = w }
                }
            )

            // Now playing bar
            NowPlayingBar(detector: detector)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { liveTrack.start(observing: detector) }
        .sheet(item: $customColorTarget) { target in
            CustomColorSheetView(target: target, live: liveTrack) {
                customColorTarget = nil
            }
        }
    }

    @ViewBuilder
    private func formSection<Item: Identifiable & GalleryStyleItem, Card: View>(
        name: String, count: Int,
        items: [Item],
        @ViewBuilder card: @escaping (Item) -> Card
    ) -> some View {
        // Adaptive/Custom, if this form has them, are always first (see each
        // model's own `.all`) — group them into their own compact row ahead
        // of a labelled divider, instead of blending into the regular grid.
        let special = items.filter { $0.isSpecialStyle }
        let prebuilt = items.filter { !$0.isSpecialStyle }

        // A real collection header (appCollectionTitle) instead of the old
        // ad-hoc 16pt — one clear step below the page's own large title,
        // the same "sub-heading" hierarchy Photos/Music use for their own
        // collection groupings within a library page.
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text(name).font(.appCollectionTitle).foregroundStyle(Neu.text)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Neu.subtext)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(Circle().fill(Neu.well))
            }

            if !special.isEmpty {
                // Its own compact row (not padded into the full column
                // count), so on wider windows these two read as a
                // deliberately featured pair rather than a sparse grid row.
                HStack(spacing: 26) {
                    ForEach(special) { item in
                        card(item).frame(maxWidth: .infinity)
                    }
                }
            }

            if !special.isEmpty && !prebuilt.isEmpty {
                HStack(spacing: 10) {
                    Rectangle().fill(Neu.hairline).frame(height: 1)
                    Text("PREBUILT COLOURS")
                        .font(.system(size: 10, weight: .bold)).tracking(1.3)
                        .foregroundStyle(Neu.subtext.opacity(0.75))
                        .fixedSize()
                    Rectangle().fill(Neu.hairline).frame(height: 1)
                }
                .padding(.vertical, 2)
            }

            if !prebuilt.isEmpty {
                // Eager rows (no LazyVGrid) so off-screen rows are never re-measured.
                let cols = columnCount
                let rows = stride(from: 0, to: prebuilt.count, by: cols).map { start in
                    Array(prebuilt[start..<min(start + cols, prebuilt.count)])
                }
                VStack(spacing: 26) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 26) {
                            ForEach(row) { item in
                                card(item).frame(maxWidth: .infinity)
                            }
                            if row.count < cols {
                                ForEach(0..<(cols - row.count), id: \.self) { _ in
                                    Color.clear.frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func setHover(_ id: String, _ on: Bool) {
        if on { hoveredID = id }
        else if hoveredID == id { hoveredID = nil }
    }
}

// MARK: - Custom colour picker sheet

/// Identifies which family's "Custom" card was clicked, carrying whatever
/// that family needs to actually place the widget once a colour is picked.
private enum CustomColorTarget: Identifiable {
    case vinyl
    case vinylHorizontal(VinylHorizontalModel)
    case cd(CDModel)
    case desktop(DesktopWidgetModel)

    var id: String {
        switch self {
        case .vinyl: return "vinyl"
        case .vinylHorizontal(let model): return model.id
        case .cd(let model): return model.id
        case .desktop(let model): return model.id
        }
    }
}

/// The picker sheet opened by any "Custom" gallery card. Binds directly to
/// CustomColorManager (no separate draft/commit step) so every drag updates
/// the colour live everywhere at once: this sheet's own preview, the grid
/// card behind it, and — if one happens to already be on the desktop — that
/// widget too. "Place on Desktop" just launches; the colour is already saved
/// by the time you'd click it.
private struct CustomColorSheetView: View {
    let target: CustomColorTarget
    let live: GalleryLiveTrack
    let onClose: () -> Void

    @ObservedObject private var customColors = CustomColorManager.shared

    private var binding: Binding<HSVColor> {
        switch target {
        case .vinyl:
            return Binding(get: { customColors.vinyl }, set: { customColors.vinyl = $0 })
        case .vinylHorizontal:
            return Binding(get: { customColors.vinylHorizontal }, set: { customColors.vinylHorizontal = $0 })
        case .cd(let model):
            if model.archetype == .discman {
                return Binding(get: { customColors.cdDiscman }, set: { customColors.cdDiscman = $0 })
            } else {
                return Binding(get: { customColors.cdHifi }, set: { customColors.cdHifi = $0 })
            }
        case .desktop(let model):
            if model.style == .vinyl {
                return Binding(get: { customColors.desktopVinyl }, set: { customColors.desktopVinyl = $0 })
            } else {
                return Binding(get: { customColors.desktopCover }, set: { customColors.desktopCover = $0 })
            }
        }
    }

    private var accent: Color {
        switch target {
        case .vinyl, .vinylHorizontal: return WidgetCategory.vinyl.accentColor
        case .cd: return WidgetCategory.cd.accentColor
        case .desktop: return WidgetCategory.desktop.accentColor
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // No header close (X) button — the "Close" button below is the
            // only dismiss affordance now, per redesign request to remove
            // redundant X close icons from app chrome in favour of a real
            // labelled button.
            VStack(alignment: .leading, spacing: 2) {
                Text("Custom Colour").font(.system(size: 18, weight: .bold)).foregroundStyle(Neu.text)
                Text("Full control — pick the exact colour this widget's body should be")
                    .font(.appCaption).foregroundStyle(Neu.subtext)
            }

            preview
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .appWell(corner: 16)

            LabeledColorPicker(value: binding)

            HStack(spacing: 12) {
                Button("Close") { onClose() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .buttonBorderShape(.capsule)
                    .frame(maxWidth: .infinity)
                Button {
                    place()
                } label: {
                    Label("Place on Desktop", systemImage: "arrow.up.forward.square.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(26)
        .frame(width: 440)
        .background(VisualEffectBlur(.sheet))
    }

    @ViewBuilder private var preview: some View {
        switch target {
        case .vinyl:
            VinylStylePreview(themeID: .custom, animated: true, live: live)
        case .vinylHorizontal(let model):
            VinylHorizontalModelPreview(model: model, live: live)
        case .cd(let model):
            CDModelPreview(model: model, animated: true, live: live)
        case .desktop(let model):
            DesktopWidgetModelPreview(model: model, animated: true, live: live)
        }
    }

    private func place() {
        customColors.recordPlaced(binding.wrappedValue)
        switch target {
        case .vinyl:
            AppDelegate.shared?.launchVinylWidget(themeID: .custom)
        case .vinylHorizontal(let model):
            AppDelegate.shared?.launchVinylHorizontalWidget(model: model)
        case .cd(let model):
            AppDelegate.shared?.launchCDWidget(model: model)
        case .desktop(let model):
            AppDelegate.shared?.launchDesktopWidget(model: model)
        }
        onClose()
    }
}

// MARK: - "Special" styles (Adaptive, Custom) vs. prebuilt colours
//
// Adaptive and Custom aren't just two more colour options — they're a
// different KIND of style (one lives, one is fully user-defined), so the
// gallery groups them together, right after the form header, ahead of and
// visually distinct from the prebuilt fixed colours below.

enum SpecialStyleKind {
    case adaptive, custom, ghost

    var badgeText: String {
        switch self {
        case .adaptive: return "LIVE"
        case .custom: return "CUSTOM"
        case .ghost: return "GHOST"
        }
    }
    var badgeIcon: String {
        switch self {
        case .adaptive: return "dot.radiowaves.left.and.right"
        case .custom: return "eyedropper"
        case .ghost: return "circle.dashed"
        }
    }
}

protocol GalleryStyleItem {
    var specialKind: SpecialStyleKind? { get }
}
extension GalleryStyleItem {
    var isSpecialStyle: Bool { specialKind != nil }
}

extension VinylStyle: GalleryStyleItem {
    var specialKind: SpecialStyleKind? {
        switch themeID {
        case .adaptive: return .adaptive
        case .custom: return .custom
        case .ghost: return .ghost
        default: return nil
        }
    }
}
extension VinylHorizontalModel: GalleryStyleItem {
    var specialKind: SpecialStyleKind? {
        switch themeID {
        case .adaptive: return .adaptive
        case .custom: return .custom
        case .ghost: return .ghost
        default: return nil
        }
    }
}
extension CDModel: GalleryStyleItem {
    var specialKind: SpecialStyleKind? {
        isAdaptive ? .adaptive : (isCustom ? .custom : nil)
    }
}
extension AlbumArtModel: GalleryStyleItem {
    var specialKind: SpecialStyleKind? { nil }
}
extension DesktopWidgetModel: GalleryStyleItem {
    var specialKind: SpecialStyleKind? {
        themeID == .adaptive ? .adaptive : (themeID == .custom ? .custom : nil)
    }
}

// MARK: - Gallery card (spacious, hover-to-animate)

private struct GalleryCard<P: View>: View {
    let title: String
    let subtitle: String
    let accent: Color
    let hovered: Bool
    var active: Bool = false
    // "Place" implies immediate placement, which is what every card does
    // except Custom — that one opens the colour picker first, so its cards
    // pass "Customize" instead.
    var placeLabel: String = "Place"
    var placeIcon: String = "arrow.up.forward.square.fill"
    // Adaptive/Custom: an always-visible accent border, a glow, and a small
    // corner badge, rather than only differing by their title text. See
    // GalleryStyleItem.isSpecialStyle for what counts as "special".
    var special: Bool = false
    var badgeText: String? = nil
    var badgeIcon: String = "sparkles"
    // Ghost has no body of its own — wrapping its preview in the usual
    // card backdrop (+ the special-card accent glow) put a visible surface
    // behind it that the real desktop widget doesn't have. Skips both so
    // the preview sits directly on the gallery's own background instead.
    var transparentPreview: Bool = false
    let onHover: (Bool) -> Void
    let action: () -> Void
    @ViewBuilder let preview: (Bool) -> P

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    preview(hovered)
                        .frame(height: 190)
                        .frame(maxWidth: .infinity)
                        .background {
                            // Special cards' accent glow removed — with a
                            // border + badge already marking them out, a
                            // radial tint behind every Adaptive/Custom/Ghost
                            // card in every category (many at once, across
                            // the whole grid) was a big contributor to the
                            // app reading as too blue overall.
                            if !transparentPreview {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.quaternary.opacity(0.4))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if hovered {
                        HStack(spacing: 5) {
                            Image(systemName: placeIcon).font(.system(size: 11, weight: .bold))
                            Text(placeLabel).font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundStyle(AMTheme.onAccent)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Capsule().fill(accent))
                        .padding(12)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }

                    // A plain checkmark badge instead of a labelled pill —
                    // the same minimal "this one's already active" language
                    // the App Store (installed) and Podcasts (played) use,
                    // rather than a capsule with text sitting on the tile.
                    if active && !hovered {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 20))
                            .foregroundStyle(Color(hex: "53e08a"))
                            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                            .padding(12)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }

                VStack(spacing: 5) {
                    // Moved down here from an overlay on the preview itself —
                    // it was sitting right on top of the disc/tonearm and
                    // covering part of the widget on every style that has
                    // one, not just Ghost.
                    // Neutral capsule with a coloured icon/text, not a solid
                    // accent-filled pill — one of these sits on every
                    // Adaptive/Custom/Ghost card simultaneously across the
                    // whole grid, so a full-colour fill on all of them at
                    // once was a real contributor to the app reading as too
                    // blue; the colour still reads clearly on the icon/text
                    // alone.
                    if special, let badgeText {
                        HStack(spacing: 4) {
                            Image(systemName: badgeIcon).font(.system(size: 8, weight: .bold))
                            Text(badgeText).font(.system(size: 9, weight: .bold)).tracking(0.3)
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(.thinMaterial))
                    }
                    Text(title).font(.appHeadline).foregroundStyle(Neu.text)
                    Text(subtitle).font(.appCaption).foregroundStyle(Neu.subtext).lineLimit(1)
                }
                .padding(.top, 14)
                .padding(.bottom, 2)
            }
            .padding(14)
        }
        .buttonStyle(.plain)
        // Native material card surface; hover deepens the shadow (elevation).
        // Ordinary (non-special) cards no longer get an accent-tinted ring
        // just from hovering/being active — that alone, repeated across a
        // whole grid of ordinary prebuilt-colour cards, was a big source of
        // stray blue. They get a plain neutral hairline instead, the same
        // separator language the rest of the app already uses. Special
        // cards keep a restrained accent hairline (much lower opacity than
        // before) — still the quiet "featured" cue Apple's own App
        // Store/Music cards use, just dialled back.
        .appCard(corner: 20, elevated: hovered)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    special
                        ? accent.opacity(hovered ? 0.32 : 0.16)
                        : Neu.hairline.opacity(hovered ? 1 : (active ? 0.7 : 0)),
                    lineWidth: 1
                )
        )
        .scaleEffect(hovered ? 1.012 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: hovered)
        .animation(.easeOut(duration: 0.2), value: active)
        .onHover { onHover($0) }
    }
}

// MARK: - Now playing bar

private struct NowPlayingBar: View {
    @ObservedObject var detector: MusicDetector
    @StateObject private var artFetcher = AlbumArtFetcher()
    @State private var art: NSImage? = nil

    private var np: NowPlayingInfo { detector.nowPlaying }
    private var hasTrack: Bool { !np.trackName.isEmpty }
    private var canSeek: Bool { hasTrack && (np.durationMillis ?? 0) > 0 }

    // Same 0...1 fraction the widgets compute for their own scrub bars —
    // just without their per-frame TimelineView interpolation, since this
    // bar already re-renders on every ~4Hz detector tick (see GalleryDetail's
    // doc comment on why only NowPlayingBar, not the whole grid, observes
    // the detector directly).
    private var progress: Double {
        guard let duration = np.durationMillis, duration > 0, let position = np.positionMillis else { return 0 }
        return min(1, max(0, Double(position) / Double(duration)))
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Neu.well)
                        .frame(width: 52, height: 52).neuInset(11)
                    if let art {
                        Image(nsImage: art).resizable().scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 19, weight: .medium)).foregroundStyle(Neu.subtext)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(hasTrack ? np.trackName : "Nothing playing")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Neu.text).lineLimit(1)
                    Text(hasTrack ? np.artistName : "Start a track in Spotify or Apple Music")
                        .font(.system(size: 11.5)).foregroundStyle(Neu.subtext).lineLimit(1)
                }

                Spacer(minLength: 8)

                // Same transport commands the widgets themselves use
                // (MusicDetector.previousTrack/togglePlayback/nextTrack) —
                // plain glyph buttons, no background chrome, matching
                // Apple Music's own mini-player controls. The play/pause
                // glyph itself conveys playing/paused state, so the old
                // separate status pill is gone — it's redundant now.
                if hasTrack {
                    transportControls
                }
            }

            if hasTrack {
                NowPlayingProgressBar(progress: progress, canSeek: canSeek) { fraction in
                    guard let duration = np.durationMillis else { return }
                    detector.seek(toMillis: Int((fraction * Double(duration)).rounded()))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .neuRaised(18)
        .onAppear { loadArt(np.albumArtURL) }
        .onChange(of: np.albumArtURL) { _, url in loadArt(url) }
    }

    // Sized/coloured to match Apple Music's own mini-player exactly: the
    // play/pause glyph reads much larger and fully opaque (primary), the
    // skip buttons smaller and muted (secondary) — not three same-size,
    // same-weight icons.
    private var transportControls: some View {
        HStack(spacing: 18) {
            transportButton("backward.fill", size: 14, color: Neu.subtext) { detector.previousTrack() }
            transportButton(np.isPlaying ? "pause.fill" : "play.fill", size: 22, color: Neu.text) { detector.togglePlayback() }
            transportButton("forward.fill", size: 14, color: Neu.subtext) { detector.nextTrack() }
        }
    }

    private func transportButton(_ icon: String, size: CGFloat, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadArt(_ url: String?) {
        guard let url, !url.isEmpty else { art = nil; return }
        artFetcher.fetchArt(from: url, trackKey: np.trackName + "|" + np.artistName) { img in
            art = img
        }
    }
}

/// Isolated from NowPlayingBar itself so drag/seek state changes only
/// re-render this small view — the actual source of the reported lag was
/// that isScrubbing/scrubProgress lived on NowPlayingBar directly, so every
/// single mouseDragged tick forced SwiftUI to re-evaluate NowPlayingBar's
/// *entire* body (album art loading logic, track text, transport buttons)
/// on top of the progress row, not just the row itself. The drag mechanism
/// itself isn't the bottleneck — WidgetSizeSlider already uses the same
/// NSView-capture technique smoothly elsewhere.
private struct NowPlayingProgressBar: View {
    let progress: Double
    let canSeek: Bool
    let onSeek: (Double) -> Void

    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0
    // Same seek-handoff idea the widgets' own scrub bars use: for a short
    // window right after committing a seek, keep showing the scrubbed
    // position instead of the live detector's (not yet caught up) one, so
    // the bar doesn't visibly snap back before the source app's own
    // position actually updates.
    @State private var seekHandoffUntil: Date? = nil
    @State private var seekHandoffProgress: Double = 0
    private let seekHandoffSuppressionDuration = 0.45

    private var displayProgress: Double {
        if isScrubbing { return scrubProgress }
        if let until = seekHandoffUntil, Date() < until { return seekHandoffProgress }
        return progress
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Neu.hairline).frame(height: isScrubbing ? 5 : 3)
                Capsule().fill(Neu.subtext).frame(width: max(3, width * displayProgress), height: isScrubbing ? 5 : 3)
                Circle().fill(Neu.text)
                    .frame(width: 10, height: 10)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: min(width - 10, max(0, width * displayProgress - 5)))
                    .opacity(isScrubbing ? 1 : 0)
            }
            .frame(height: 14)
            .contentShape(Rectangle())
            .overlay {
                if canSeek {
                    NowPlayingScrubDragCaptureView(
                        onDrag: { x in
                            isScrubbing = true
                            scrubProgress = min(1, max(0, x / width))
                        },
                        onEnd: { x in
                            let fraction = min(1, max(0, x / width))
                            seekHandoffProgress = fraction
                            seekHandoffUntil = Date().addingTimeInterval(seekHandoffSuppressionDuration)
                            isScrubbing = false
                            onSeek(fraction)
                        }
                    )
                }
            }
        }
        .frame(height: 14)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isScrubbing)
    }
}

// MARK: - Vinyl style model

struct VinylStyle: Identifiable {
    let themeID: WidgetThemeID
    let name: String
    let subtitle: String

    var id: String { themeID.rawValue }
}

// Vinyl players grouped into forms, each with colour options (mirrors CD flow).
struct VinylForm: Identifiable {
    let id: String
    let name: String
    let icon: String
    let styles: [VinylStyle]
}

extension VinylStyle {
    static let forms: [VinylForm] = [
        VinylForm(id: "vinyl", name: "Vinyl",
                  icon: "record.circle",
                  styles: [
                    VinylStyle(themeID: .adaptive, name: "Adaptive", subtitle: "Matches the album art, live"),
                    VinylStyle(themeID: .custom,   name: "Custom",   subtitle: "Pick your own exact colour"),
                    VinylStyle(themeID: .ghost,    name: "Ghost",    subtitle: "No body — just the disc and text")
                  ])
    ]

    static let all: [VinylStyle] = forms.flatMap { $0.styles }
}


struct CDModelPreview: View {
    let model: CDModel
    var animated: Bool = false
    @ObservedObject var live: GalleryLiveTrack = GalleryLiveTrack()
    // Gallery-grid tile only — set true by the caller for the Custom model,
    // never by the colour-picker sheet's own live preview.
    var usesRainbowPreview: Bool = false

    var body: some View {
        GeometryReader { geo in
            let base = model.archetype.baseSize
            let s = min(geo.size.width / base.width, geo.size.height / base.height)
            content
                .frame(width: base.width, height: base.height)
                .scaleEffect(s)
                .frame(width: base.width * s, height: base.height * s)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder private var content: some View {
        // Colour/blur only for the Adaptive model — every other CD style
        // has its own fixed material and must not pick up the live art's
        // colour or blurred housing (was leaking into all of them).
        let view = CDWidgetView(
            model: model, isPreview: true, previewSpinning: animated,
            previewInfo: live.info, previewArt: live.art,
            previewColours: model.isAdaptive ? live.colours : nil,
            previewBlurredArt: model.isAdaptive ? live.blurredArt : nil,
            usesRainbowPreview: usesRainbowPreview
        )
        if animated {
            view                       // live spin — don't flatten (drawingGroup re-rasterizes each frame)
        } else {
            view.drawingGroup()        // flatten heavy static art into one cached texture
        }
    }
}


// MARK: - Vinyl preview (fit-scaled, flattened)

struct VinylStylePreview: View {
    let themeID: WidgetThemeID
    var animated: Bool = false
    // Defaults to a fresh, never-started GalleryLiveTrack — callers that
    // don't pass one (e.g. OnboardingView) just get the static placeholder
    // look, unchanged.
    @ObservedObject var live: GalleryLiveTrack = GalleryLiveTrack()
    // Gallery-grid tile only — set true by the caller for the Custom style,
    // never by the colour-picker sheet's own live preview.
    var usesRainbowPreview: Bool = false
    // Observed so this preview (grid tile or the picker sheet's own preview)
    // updates live as the user drags — CustomColorManager writes straight
    // through on every change, no separate draft/commit step.
    @ObservedObject private var customColors = CustomColorManager.shared

    var body: some View {
        GeometryReader { geo in
            let base = CGSize(width: 384, height: 516)
            let s = min(geo.size.width / base.width, geo.size.height / base.height)
            content
                .frame(width: base.width, height: base.height)
                .scaleEffect(s)
                .frame(width: base.width * s, height: base.height * s)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// For Adaptive, the preview's whole palette tracks the real playing
    /// track's colours, same as the live widget. For Custom, it tracks the
    /// user's own picked colour instead — unless this is the gallery-grid
    /// tile, which shows a fixed rainbow spectrum instead so it reads as
    /// "pick any colour" rather than whatever's currently saved.
    private var resolvedPalette: WidgetThemePalette {
        if themeID == .custom {
            if usesRainbowPreview { return WidgetThemeID.rainbowPreviewPalette() }
            return WidgetThemeID.adaptivePalette(from: customColors.vinyl.extractedColours)
        }
        guard themeID == .adaptive || themeID == .ghost, live.art != nil else { return themeID.palette }
        return WidgetThemeID.adaptivePalette(from: live.colours, showBody: themeID != .ghost)
    }

    @ViewBuilder private var content: some View {
        let replica = VinylWidgetReplica(
            palette: resolvedPalette,
            traits: themeID.traits,
            spinning: animated,
            liveArt: live.art,
            liveBlurredArt: themeID == .adaptive ? live.blurredArt : nil,
            liveTrackName: live.info.trackName,
            liveArtistName: live.info.artistName
        )
        if animated {
            replica                    // live spin — don't flatten
        } else {
            replica.drawingGroup()     // flatten static art into one cached texture
        }
    }
}

private struct VinylWidgetReplica: View {
    let palette: WidgetThemePalette
    var traits: VinylModelTraits = VinylModelTraits()
    var spinning: Bool = false   // gallery hover: rotate the disc
    // Real playing-track data, threaded down from VinylStylePreview. All
    // default empty/nil so this replica still renders its plain placeholder
    // look wherever no live data is supplied.
    var liveArt: NSImage? = nil
    var liveBlurredArt: NSImage? = nil
    var liveTrackName: String = ""
    var liveArtistName: String = ""

    var body: some View {
        ZStack {
            // === Body shell (344×476) ===
            if palette.showBody {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(colors: palette.widgetBodyGradient,
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: .black.opacity(0.7), radius: 30, x: 0, y: 20)

                    // Adaptive preview: same real-blurred-art body as the
                    // live widget, not just the fixed palette gradient.
                    AdaptiveBodyFill(blurredArt: liveBlurredArt, size: CGSize(width: 344, height: 476))

                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(palette.widgetBorder, lineWidth: 1)

                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [palette.widgetTopSheen, .clear],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1
                        )

                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(colors: [Color.white.opacity(0.06), .clear],
                                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.28))
                        )

                    VinylBodyTexture(pattern: traits.pattern)
                }
                .frame(width: 344, height: 476)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }

            if palette.showBody { bodyDetails }

            // === Content (platter + track info / controls) ===
            VStack(spacing: 0) {
                platterArea
                    .padding(.top, palette.showBody ? 20 : 8)

                if traits.hasTransportControls {
                    VStack(spacing: 9) {
                        RetroVFDDisplay(title: "NOW PLAYING", subtitle: "Audio Desk")
                        transportControls
                    }
                    .padding(.top, 10)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)
                } else {
                    trackInfo
                        .padding(.top, 16)
                        .padding(.horizontal, 38)
                        .padding(.bottom, 20)
                }
            }

            // === Tonearm (cued onto the record) ===
            tonearmReplicaRealisticView
                .rotationEffect(.degrees(-5), anchor: tonearmReplicaRealisticPivot)
                .offset(x: tonearmReplicaRealisticOffset.x, y: tonearmReplicaRealisticOffset.y)
        }
        .frame(width: 384, height: 516)
    }

    // MARK: Static retro transport buttons (visual only)

    private var transportControls: some View {
        HStack(spacing: 14) {
            RetroTransportButtonFace(palette: palette, icon: "backward.fill", size: 34)
            RetroTransportButtonFace(palette: palette, icon: "play.fill", size: 34)
            RetroTransportButtonFace(palette: palette, icon: "forward.fill", size: 34)
        }
    }

    // MARK: Platter + disc (exact geometry from the live widget)

    private var platterArea: some View {
        ZStack {
            // Same Ghost fix as the live widget's own platterArea: this mat
            // is hardware the disc rests on, not the disc itself, so it
            // goes with the rest of the (invisible) housing.
            if palette.showBody {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "2a2a2a"), Color(hex: "111111"), Color(hex: "080808")],
                            center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 136
                        )
                    )
                    .frame(width: 272, height: 272)
                    .shadow(color: .black.opacity(0.8), radius: 12, x: 0, y: 4)
            }

            if traits.hasPlatterRing {
                Circle()
                    .strokeBorder(AngularGradient(colors: palette.screwGradient + [palette.screwGradient.first ?? .gray], center: .center), lineWidth: 6)
                    .frame(width: 286, height: 286)
            }

            TimelineView(.animation(paused: !spinning)) { ctx in
                // 30°/s = 5 RPM — must match SpinningVinylView's own
                // degreesPerSecond exactly. This replica draws its own
                // rotation independently (doesn't share that view), and a
                // stale hardcoded 132°/s here (4.4x too fast) was left
                // behind after the real widget's spin speed was tuned down.
                let a = spinning ? (ctx.date.timeIntervalSinceReferenceDate * 30).truncatingRemainder(dividingBy: 360) : 0
                ZStack {
                    vinylDisc
                    albumArtLabel
                }
                .rotationEffect(.degrees(a))
            }
            spindleView
        }
        .frame(width: 272, height: 272)
    }

    // Trait-gated design details

    private var bodyDetails: some View {
        ZStack {
            if traits.caseBorder {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(LinearGradient(colors: palette.screwGradient, startPoint: .top, endPoint: .bottom), lineWidth: 3)
                    .frame(width: 300, height: 360)
                ForEach([CGFloat(170), 250], id: \.self) { y in
                    latch.position(x: 24, y: y)
                    latch.position(x: 336, y: y)
                }
            }
            if traits.hasPowerLED {
                Circle().fill(Color(hex: "53e08a")).frame(width: 7, height: 7)
                    .shadow(color: Color(hex: "53e08a").opacity(0.85), radius: 4)
                    .position(x: 46, y: 388)
            }
            if traits.hasPitchSlider {
                pitchFader.position(x: 286, y: 372)
            }
        }
        .frame(width: 384, height: 516)
    }

    private var latch: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(LinearGradient(colors: palette.screwGradient, startPoint: .top, endPoint: .bottom))
            .frame(width: 8, height: 14)
    }

    private var pitchFader: some View {
        ZStack {
            Capsule().fill(Color.black.opacity(0.5)).frame(width: 50, height: 6)
            RoundedRectangle(cornerRadius: 2.5)
                .fill(LinearGradient(colors: palette.screwGradient, startPoint: .top, endPoint: .bottom))
                .frame(width: 11, height: 18).offset(x: 6)
        }
        .frame(width: 56, height: 22)
    }

    @ViewBuilder
    private var spindleView: some View {
        switch traits.spindle {
        case .standard:
            EmptyView()
        case .retro45:
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [Color(hex: "f0f0f0"), Color(hex: "8a8a8a"),
                                     Color(hex: "e8e8e8"), Color(hex: "707070"),
                                     Color(hex: "f0f0f0")],
                            center: .center
                        )
                    )
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                Circle()
                    .fill(
                        RadialGradient(colors: [Color(hex: "303030"), Color(hex: "0a0a0a")],
                                       center: .center, startRadius: 0, endRadius: 5)
                    )
                    .frame(width: 9, height: 9)
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 4, height: 4)
                    .offset(x: -5, y: -5)
                    .blur(radius: 1)
            }
        }
    }

    private var vinylDisc: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "151515"), Color(hex: "0b0b0b"), Color(hex: "050505")],
                        center: .center, startRadius: 12, endRadius: 129
                    )
                )
                .frame(width: 258, height: 258)

            ForEach(0..<40, id: \.self) { i in
                let diameter: CGFloat = 102 + CGFloat(i) * 3.9
                Circle()
                    .strokeBorder(Color.white.opacity(i % 2 == 0 ? 0.06 : 0.03), lineWidth: 0.4)
                    .frame(width: diameter, height: diameter)
            }

            Circle()
                .strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.5
                )
                .frame(width: 258, height: 258)
        }
    }

    @ViewBuilder private var albumArtLabel: some View {
        Group {
            if let liveArt {
                Image(nsImage: liveArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 125, height: 125)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(
                        RadialGradient(colors: palette.albumArtLabelGradient,
                                       center: .center, startRadius: 0, endRadius: 62.5)
                    )
                    .frame(width: 125, height: 125)
            }
        }
        .frame(width: 125, height: 125)
        .overlay(Circle().strokeBorder(palette.albumArtRingColor, lineWidth: 2))
        .shadow(color: .black.opacity(0.8), radius: 6)
    }

    // MARK: Tonearm (exact geometry from the live widget)

    private var tonearmView: some View {
        ZStack {
            // Arm rod — rendered first so the mounting joint below sits on top of it.
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(colors: [Color(hex: "1c1c1e"), Color(hex: "606064"), Color(hex: "1c1c1e")],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .frame(width: 8, height: 132)
                .rotationEffect(.degrees(20))
                .position(x: 46, y: 85)
                .shadow(color: .black.opacity(0.55), radius: 1.5, x: 1, y: 2)
                .shadow(color: .black.opacity(0.32), radius: 5, x: 2, y: 5)

            // Mounting joint — dark bezel plate + brushed-chrome cap.
            Circle()
                .fill(
                    LinearGradient(colors: [Color(hex: "38383c"), Color(hex: "222224"), Color(hex: "0e0e10")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                .position(x: 68, y: 16)

            Circle()
                .fill(
                    RadialGradient(colors: [Color(hex: "f2f2f4"), Color(hex: "c2c2c6"), Color(hex: "78787c")],
                                   center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 8)
                )
                .frame(width: 15, height: 15)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.28), lineWidth: 0.5))
                .position(x: 68, y: 16)

            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(colors: [Color(hex: "666666"), Color(hex: "222222")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 18, height: 16)
                .position(x: 24, y: 152)

            Rectangle()
                .fill(
                    LinearGradient(colors: [Color(hex: "bbbbbb"), Color(hex: "666666")],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 2, height: 8)
                .position(x: 28, y: 164)

            if traits.hasCounterweight {
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [Color(hex: "3a3a3a"), Color(hex: "0c0c0c")], startPoint: .top, endPoint: .bottom))
                    .frame(width: 17, height: 24)
                    .rotationEffect(.degrees(20))
                    .position(x: 80, y: 6)
            }
        }
        .frame(width: 90, height: 180)
    }

    // MARK: Realistic tonearm (same asset/proportions as VinylWidgetView)
    //
    // Rolled out from the main live widget once its calibration there was
    // confirmed. Same 90x180/384x516 geometry as that widget (this is a
    // static replica of it), so the same scale/pivot/offset numbers apply
    // directly rather than needing their own re-derivation. Fixed at -5°
    // (matching VinylWidgetView's own tonearmRealisticStartAngle) instead
    // of the old vector's -6°, since this replica is a static "cued onto
    // the record" pose, not progress-tracking.
    private let tonearmReplicaRealisticScale: CGFloat = 1.6

    private var tonearmReplicaRealisticPivot: UnitPoint {
        UnitPoint(x: 470.0 / 720.0, y: 310.0 / 1456.0)
    }

    private var tonearmReplicaRealisticOffset: CGPoint {
        let pivotFromCenterX = tonearmReplicaRealisticPivot.x * 90 - 45
        let pivotFromCenterY = tonearmReplicaRealisticPivot.y * 180 - 90
        let growth = tonearmReplicaRealisticScale - 1
        return CGPoint(
            x: 115 - pivotFromCenterX * growth,
            y: -137 - pivotFromCenterY * growth
        )
    }

    private var tonearmReplicaRealisticView: some View {
        Image("TonearmRealistic")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: .fit)
            .frame(width: 90 * tonearmReplicaRealisticScale, height: 180 * tonearmReplicaRealisticScale)
    }

    // MARK: Track info placeholder (mirrors the live widget's integrated panel)

    @ViewBuilder private var trackInfo: some View {
        if !liveTrackName.isEmpty {
            VStack(spacing: 0) {
                Text(liveTrackName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(palette.trackTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .truncationMode(.tail)
                    .shadow(color: .black.opacity(palette.showBody ? 0 : 0.55), radius: 6)
                Text(liveArtistName)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(palette.trackArtist)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.tail)
                    .padding(.top, 4)
                    .shadow(color: .black.opacity(palette.showBody ? 0 : 0.55), radius: 5)

                if palette.showBody {
                    HStack(spacing: 38) {
                        Image(systemName: "backward.fill").font(.system(size: 21, weight: .medium))
                            .foregroundStyle(palette.trackArtist)
                        Image(systemName: "play.fill").font(.system(size: 27, weight: .medium))
                            .foregroundStyle(palette.trackTitle)
                        Image(systemName: "forward.fill").font(.system(size: 21, weight: .medium))
                            .foregroundStyle(palette.trackArtist)
                    }
                    .frame(height: 37)
                    .padding(.top, 12)

                    HStack(spacing: 9) {
                        Text("0:00").frame(width: 34, alignment: .leading)
                        Capsule().fill(palette.trackArtist.opacity(0.32)).frame(height: 4)
                        Text("-0:00").frame(width: 34, alignment: .trailing)
                    }
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(palette.trackArtist.opacity(0.85))
                    .frame(height: 22)
                    .padding(.top, 12)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140, alignment: .top)
        } else {
            placeholderTrackInfo
        }
    }

    private var placeholderTrackInfo: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(palette.trackTitle.opacity(0.85))
                .frame(width: 132, height: 13)
            RoundedRectangle(cornerRadius: 2.5)
                .fill(palette.trackArtist.opacity(0.7))
                .frame(width: 96, height: 9)
                .padding(.top, 8)

            if palette.showBody {
                HStack(spacing: 38) {
                    Image(systemName: "backward.fill").font(.system(size: 21, weight: .medium))
                        .foregroundStyle(palette.trackArtist)
                    Image(systemName: "play.fill").font(.system(size: 27, weight: .medium))
                        .foregroundStyle(palette.trackTitle)
                    Image(systemName: "forward.fill").font(.system(size: 21, weight: .medium))
                        .foregroundStyle(palette.trackArtist)
                }
                .frame(height: 37)
                .padding(.top, 12)

                HStack(spacing: 9) {
                    Text("0:00").frame(width: 34, alignment: .leading)
                    Capsule().fill(palette.trackArtist.opacity(0.32)).frame(height: 4)
                    Text("-0:00").frame(width: 34, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(palette.trackArtist.opacity(0.85))
                .frame(height: 22)
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140, alignment: .top)
    }
}



// MARK: - Category model

enum WidgetCategory: String, Identifiable, CaseIterable {
    case vinyl, cd, albumArt, desktop, notch
    var id: String { rawValue }

    /// Notch is only offered on hardware that actually has one — no fallback
    /// pill on ordinary screens (per design decision), so it's simply
    /// omitted from the sidebar everywhere else rather than shown disabled.
    static var availableCases: [WidgetCategory] {
        allCases.filter { $0 != .notch || NotchDetector.hasNotch }
    }

    var title: String {
        switch self {
        case .vinyl: return "Vinyl"
        case .cd: return "CD Players"
        case .albumArt: return "Album Art"
        case .desktop: return "Desktop"
        case .notch: return "Notch"
        }
    }
    var icon: String {
        switch self {
        case .vinyl: return "record.circle"
        case .cd: return "opticaldisc"
        case .albumArt: return "photo.on.rectangle.angled"
        case .desktop: return "macwindow"
        case .notch: return "circle.grid.2x1.fill"
        }
    }
    var accentColor: Color { AMTheme.accent }
}
