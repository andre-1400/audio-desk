import SwiftUI
import Combine

// MARK: - Brand (which music service look the app wears)

enum Brand: String { case appleMusic, spotify }

final class BrandManager: ObservableObject {
    static let shared = BrandManager()
    private let key = "brand.v1"
    @Published var brand: Brand {
        didSet { UserDefaults.standard.set(brand.rawValue, forKey: key) }
    }
    private init() {
        brand = Brand(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .appleMusic
    }
}

// MARK: - Theme
// Apple Music = clean white + signature red.  Spotify = black + Spotify green.
// Values are computed from the current brand so the whole UI reskins live.

// Design tokens, repointed to native macOS semantics (Phase 1 redesign).
// The names stay so the hundreds of existing call sites are untouched; only
// the resolved values change — from hand-picked hex fills to system semantic
// colours and materials that adapt to the active NSAppearance (which the
// brand still drives: Apple Music = aqua/light, Spotify = darkAqua/dark).
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
enum AMTheme {
    private static var spotify: Bool { BrandManager.shared.brand == .spotify }
    static var accent: Color      { spotify ? Color(hex: "1db954") : Color(hex: "fa233b") }
    static var accentLight: Color { spotify ? Color(hex: "1ed760") : Color(hex: "fb5c74") }
    static var onAccent: Color    { spotify ? Color(hex: "000000") : Color(hex: "ffffff") }
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
    @ObservedObject private var brandM = BrandManager.shared   // reskin whole tree on brand change

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
        .preferredColorScheme(brandM.brand == .spotify ? .dark : .light)
        .animation(.easeInOut(duration: 0.3), value: brandM.brand)
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

private struct GallerySidebar: View {
    @Binding var category: WidgetCategory
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand header — a restrained app mark, no heavy accent gradient
            // tile (that read as an Android splash chip).
            HStack(spacing: 10) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AMTheme.accent)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MusicWidgets").font(.system(size: 15, weight: .semibold)).foregroundStyle(Neu.text)
                    Text("Desktop players").font(.appCaption).foregroundStyle(Neu.subtext)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 30)
            .padding(.bottom, 14)

            // Native sidebar list — system selection highlight, hover, row
            // metrics, exactly like Finder/Music. Tint is pinned to the
            // brand accent (not left to the user's system accent colour) —
            // the same way Music/Podcasts/News hard-brand their own sidebar
            // selection regardless of System Settings.
            List(selection: Binding(
                get: { category },
                set: { new in
                    if let new { withAnimation(.easeInOut(duration: 0.18)) { category = new } }
                }
            )) {
                Section("Library") {
                    ForEach(WidgetCategory.allCases) { cat in
                        Label(cat.title, systemImage: cat.icon)
                            .tag(cat)
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

                Text("MusicWidgets \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
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
    // Observed (not a stored `let`) so switching brand right here, in an
    // already-open sheet, live-updates every accent-tinted control below —
    // this is now the only place to change brand since onboarding no
    // longer asks (see OnboardingView's new welcome-screen-only flow).
    @ObservedObject private var brandM = BrandManager.shared

    private var accent: Color { AMTheme.accent }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.appTitle).foregroundStyle(Neu.text)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)

            // Native grouped Form — the same section/row language as macOS
            // System Settings, replacing the hand-drawn "block" cards.
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("App Style").font(.appBody).foregroundStyle(Neu.text)
                        Text("Recolours the whole app to match")
                            .font(.appCaption).foregroundStyle(Neu.subtext)
                        NeuSegmented(options: ["Apple Music", "Spotify"],
                                     selected: brandM.brand == .appleMusic ? 0 : 1) { i in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                brandM.brand = i == 0 ? .appleMusic : .spotify
                            }
                        }
                    }
                    .padding(.vertical, 4)

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
                    toggleRow(icon: "square.stack.3d.up", title: "Always on top",
                              subtitle: "Float above other windows",
                              isOn: $settings.alwaysOnTop)
                    toggleRow(icon: "cursorarrow.rays", title: "Click-through",
                              subtitle: "Clicks pass through to what's behind",
                              isOn: $settings.clickThrough)
                    toggleRow(icon: "moon.zzz", title: "Hide when paused",
                              subtitle: "Fade out when nothing is playing",
                              isOn: $settings.hideWhenPaused)
                    toggleRow(icon: "record.circle", title: "Track-change animation",
                              subtitle: "Off: the vinyl widget snaps to the next song instantly",
                              isOn: $settings.vinylTransitionAnimationEnabled)
                }

                Section {
                    HStack {
                        Label("Musical notes", systemImage: "music.note")
                            .foregroundStyle(Neu.text)
                        Spacer()
                        Toggle("", isOn: $settings.notesEnabled).labelsHidden().tint(accent)
                    }
                    if settings.notesEnabled {
                        NeuSegmented(options: ["Left", "Right"],
                                     selected: settings.notesSide == .left ? 0 : 1) { i in
                            settings.notesSide = i == 0 ? .left : .right
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                } header: {
                    Text("Musical Notes")
                } footer: {
                    Text("🎵 drift from a top corner while playing")
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: settings.notesEnabled)

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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "app").font(.system(size: 11))
                .foregroundStyle(Neu.subtext)

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Neu.well).frame(height: 5)
                    Capsule().fill(AMTheme.accent).frame(width: max(5, width * fraction), height: 5)
                    Circle().fill(Color.white)
                        .frame(width: 15, height: 15)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .offset(x: min(width - 15, max(0, width * fraction - 7.5)))
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

            Image(systemName: "app.fill").font(.system(size: 20))
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
            // Header — large SF Pro title (not SF Rounded), HIG type ramp.
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(category.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Neu.text)
                    Text("\(category.widgetCount) styles · hover to preview, click to place on your desktop")
                        .font(.appSubheadline).foregroundStyle(Neu.subtext)
                }
                Spacer()
                // Widget size, right where you pick the widget
                VStack(alignment: .trailing, spacing: 6) {
                    Text("SIZE")
                        .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(Neu.subtext)
                    WidgetSizeSlider(scale: $sizeM.scale)
                        .frame(width: 190)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 20)

            // Grid (grouped by form)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 30) {
                    if category == .vinyl {
                        ForEach(VinylStyle.forms) { form in
                            formSection(name: form.name, subtitle: form.subtitle,
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
                                            onHover: { setHover(style.id, $0) },
                                            action: {
                                                if style.themeID == .custom {
                                                    customColorTarget = .vinyl
                                                } else {
                                                    AppDelegate.shared?.launchVinylWidget(themeID: style.themeID)
                                                }
                                            }) { animated in
                                    VinylStylePreview(themeID: style.themeID, animated: animated, live: liveTrack)
                                }
                            }
                        }
                        formSection(name: "Horizontal", subtitle: "Disc + track info side by side",
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
                                        onHover: { setHover(model.id, $0) },
                                        action: {
                                            if model.themeID == .custom {
                                                customColorTarget = .vinylHorizontal(model)
                                            } else {
                                                AppDelegate.shared?.launchVinylHorizontalWidget(model: model)
                                            }
                                        }) { animated in
                                VinylHorizontalModelPreview(model: model, animated: animated, live: liveTrack)
                            }
                        }
                    } else if category == .cd {
                        ForEach(CDModel.forms) { form in
                            formSection(name: form.name, subtitle: form.subtitle,
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
                                    CDModelPreview(model: model, animated: animated, live: liveTrack)
                                }
                            }
                        }
                    } else {
                        formSection(name: "Album Art", subtitle: "Four takes on minimal",
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
        name: String, subtitle: String, count: Int,
        items: [Item],
        @ViewBuilder card: @escaping (Item) -> Card
    ) -> some View {
        // Adaptive/Custom, if this form has them, are always first (see each
        // model's own `.all`) — group them into their own compact row ahead
        // of a labelled divider, instead of blending into the regular grid.
        let special = items.filter { $0.isSpecialStyle }
        let prebuilt = items.filter { !$0.isSpecialStyle }

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(name).font(.system(size: 16, weight: .bold)).foregroundStyle(Neu.text)
                Text("·").foregroundStyle(Neu.subtext.opacity(0.6))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Neu.subtext)
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

    var id: String {
        switch self {
        case .vinyl: return "vinyl"
        case .vinylHorizontal(let model): return model.id
        case .cd(let model): return model.id
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
        }
    }

    private var accent: Color {
        switch target {
        case .vinyl, .vinylHorizontal: return WidgetCategory.vinyl.accentColor
        case .cd: return WidgetCategory.cd.accentColor
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom Colour").font(.system(size: 18, weight: .bold)).foregroundStyle(Neu.text)
                    Text("Full control — pick the exact colour this widget's body should be")
                        .font(.appCaption).foregroundStyle(Neu.subtext)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
    case adaptive, custom

    var badgeText: String { self == .adaptive ? "LIVE" : "CUSTOM" }
    var badgeIcon: String { self == .adaptive ? "dot.radiowaves.left.and.right" : "eyedropper" }
}

protocol GalleryStyleItem {
    var specialKind: SpecialStyleKind? { get }
}
extension GalleryStyleItem {
    var isSpecialStyle: Bool { specialKind != nil }
}

extension VinylStyle: GalleryStyleItem {
    var specialKind: SpecialStyleKind? {
        themeID == .adaptive ? .adaptive : (themeID == .custom ? .custom : nil)
    }
}
extension VinylHorizontalModel: GalleryStyleItem {
    var specialKind: SpecialStyleKind? {
        themeID == .adaptive ? .adaptive : (themeID == .custom ? .custom : nil)
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
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.quaternary.opacity(0.4))
                                if special {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(RadialGradient(colors: [accent.opacity(0.14), .clear],
                                                             center: .center, startRadius: 4, endRadius: 200))
                                }
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if special, let badgeText {
                        HStack(spacing: 4) {
                            Image(systemName: badgeIcon).font(.system(size: 9, weight: .bold))
                            Text(badgeText).font(.system(size: 10, weight: .bold)).tracking(0.3)
                        }
                        .foregroundStyle(AMTheme.onAccent)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Capsule().fill(accent))
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }

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

                    if active && !hovered {
                        HStack(spacing: 5) {
                            Circle().fill(Color(hex: "53e08a")).frame(width: 6, height: 6)
                                .shadow(color: Color(hex: "53e08a").opacity(0.8), radius: 3)
                            Text("On desktop").font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(Neu.text)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Neu.raised).shadow(color: .black.opacity(0.18), radius: 4, y: 1))
                        .overlay(Capsule().strokeBorder(Neu.hairline, lineWidth: 1))
                        .padding(12)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }

                VStack(spacing: 3) {
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
        // Special cards get a thin, restrained accent hairline — not a
        // glowing gradient border — the same quiet cue Apple's own
        // "featured" cards use (App Store, Music) rather than a neon ring.
        .appCard(corner: 20, elevated: hovered)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    special
                        ? accent.opacity(hovered ? 0.55 : 0.32)
                        : accent.opacity(hovered ? 0.4 : (active ? 0.28 : 0)),
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
                Capsule().fill(Neu.hairline).frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule().fill(Neu.subtext)
                                .frame(width: max(3, geo.size.width * progress))
                        }
                    }
                    .clipShape(Capsule())
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
    let subtitle: String
    let icon: String
    let styles: [VinylStyle]
}

extension VinylStyle {
    static let forms: [VinylForm] = [
        VinylForm(id: "vinyl", name: "Vinyl", subtitle: "Adaptive by default, a few colours if you want a fixed one",
                  icon: "record.circle",
                  styles: [
                    VinylStyle(themeID: .adaptive, name: "Adaptive", subtitle: "Matches the album art, live"),
                    VinylStyle(themeID: .custom,   name: "Custom",   subtitle: "Pick your own exact colour"),
                    VinylStyle(themeID: .default,  name: "Classic",  subtitle: "Warm wood & gold"),
                    VinylStyle(themeID: .obsidian, name: "Obsidian", subtitle: "Jet black & chrome"),
                    VinylStyle(themeID: .pearl,    name: "Pearl",    subtitle: "Cream & terracotta"),
                    VinylStyle(themeID: .midnight, name: "Midnight", subtitle: "Navy & steel")
                  ])
    ]

    static let all: [VinylStyle] = forms.flatMap { $0.styles }
}


struct CDModelPreview: View {
    let model: CDModel
    var animated: Bool = false
    @ObservedObject var live: GalleryLiveTrack = GalleryLiveTrack()

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
            previewBlurredArt: model.isAdaptive ? live.blurredArt : nil
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
    /// user's own picked colour instead.
    private var resolvedPalette: WidgetThemePalette {
        if themeID == .custom {
            return WidgetThemeID.adaptivePalette(from: customColors.vinyl.extractedColours)
        }
        guard themeID == .adaptive, live.art != nil else { return themeID.palette }
        return WidgetThemeID.adaptivePalette(from: live.colours)
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
                        RetroVFDDisplay(title: "NOW PLAYING", subtitle: "MusicWidgets")
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
            tonearmView
                .rotationEffect(.degrees(-6), anchor: UnitPoint(x: 68.0 / 90.0, y: 16.0 / 180.0))
                .offset(x: 115, y: -137)
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
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "2a2a2a"), Color(hex: "111111"), Color(hex: "080808")],
                        center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 136
                    )
                )
                .frame(width: 272, height: 272)
                .shadow(color: .black.opacity(0.8), radius: 12, x: 0, y: 4)

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
                Text(liveArtistName)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(palette.trackArtist)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.tail)
                    .padding(.top, 4)

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
            .frame(maxWidth: .infinity)
            .frame(height: 140)
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
        .frame(maxWidth: .infinity)
        .frame(height: 140)
    }
}



// MARK: - Category model

enum WidgetCategory: String, Identifiable, CaseIterable {
    case vinyl, cd, albumArt
    var id: String { rawValue }
    var title: String {
        switch self {
        case .vinyl: return "Vinyl"
        case .cd: return "CD Players"
        case .albumArt: return "Album Art"
        }
    }
    var icon: String {
        switch self {
        case .vinyl: return "record.circle"
        case .cd: return "opticaldisc"
        case .albumArt: return "photo.on.rectangle.angled"
        }
    }
    var widgetCount: Int {
        switch self {
        case .vinyl: return VinylStyle.all.count + VinylHorizontalModel.all.count
        case .cd: return CDModel.all.count
        case .albumArt: return AlbumArtModel.all.count
        }
    }
    var accentColor: Color { AMTheme.accent }
}
