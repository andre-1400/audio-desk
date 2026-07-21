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

enum Neu {
    private static var spotify: Bool { BrandManager.shared.brand == .spotify }
    static var bg: Color      { spotify ? Color(hex: "121212") : Color(hex: "ffffff") }  // content
    static var raised: Color  { spotify ? Color(hex: "181818") : Color(hex: "ffffff") }  // cards
    static var well: Color    { spotify ? Color(hex: "242424") : Color(hex: "f1f1f4") }  // inset backdrops
    static var elevated: Color { spotify ? Color(hex: "3a3a3a") : Color(hex: "ffffff") } // selected pill
    static var sidebar: Color { spotify ? Color(hex: "000000") : Color(hex: "f5f5f7") }  // sidebar panel
    static var dark: Color    { Color.black.opacity(spotify ? 0.45 : 0.08) }             // soft shadow
    static var light: Color   { Color.clear }
    static var text: Color    { spotify ? Color(hex: "ffffff") : Color(hex: "1d1d1f") }  // primary label
    static var subtext: Color { spotify ? Color(hex: "b3b3b3") : Color(hex: "86868b") }  // secondary label
    static var hairline: Color { spotify ? Color.white.opacity(0.10) : Color.black.opacity(0.07) }
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

private struct NeuRaised: ViewModifier {
    var corner: CGFloat = 22
    var pressed: Bool = false
    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Neu.raised)
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Neu.hairline, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(pressed ? 0.05 : 0.09),
                        radius: pressed ? 3 : 12, x: 0, y: pressed ? 1 : 5)
        )
    }
}

extension View {
    func neuRaised(_ corner: CGFloat = 22, pressed: Bool = false) -> some View {
        modifier(NeuRaised(corner: corner, pressed: pressed))
    }
    // Flat, light inset (clipped fill with a hairline edge).
    func neuInset(_ corner: CGFloat = 16) -> some View {
        clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Neu.hairline, lineWidth: 1)
            )
    }
}

struct NeuTileStyle: ButtonStyle {
    var corner: CGFloat = 20
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .neuRaised(corner, pressed: configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
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
            Neu.bg.ignoresSafeArea()
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
        .background(Neu.bg.ignoresSafeArea())
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
            // Brand
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(AMTheme.gradient)
                        .frame(width: 42, height: 42)
                        .shadow(color: AMTheme.accent.opacity(0.35), radius: 5, y: 2)
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AMTheme.onAccent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("MusicWidgets").font(.system(size: 15.5, weight: .bold, design: .rounded)).foregroundStyle(Neu.text)
                    Text("Desktop players").font(.system(size: 10.5)).foregroundStyle(Neu.subtext)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 32)
            .padding(.bottom, 28)

            Text("LIBRARY")
                .font(.system(size: 10.5, weight: .bold)).tracking(1.6)
                .foregroundStyle(Neu.subtext.opacity(0.8))
                .padding(.horizontal, 22)
                .padding(.bottom, 10)

            VStack(spacing: 7) {
                ForEach(WidgetCategory.allCases) { cat in
                    SidebarItem(category: cat, selected: category == cat) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { category = cat }
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            // Settings
            SidebarRowButton(icon: "slider.horizontal.3", label: "Settings", action: onSettings)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            Text("MusicWidgets \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.system(size: 10))
                .foregroundStyle(Neu.subtext.opacity(0.65))
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
        }
        .frame(width: 218)
        .frame(maxHeight: .infinity)
        .background(
            ZStack(alignment: .trailing) {
                Neu.sidebar
                Rectangle().fill(Neu.hairline).frame(width: 1)
            }
            .ignoresSafeArea()
        )
    }
}

private struct SidebarItem: View {
    let category: WidgetCategory
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(selected ? category.accentColor : Neu.subtext)
                    .frame(width: 22)
                Text(category.title)
                    .font(.system(size: 14, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Neu.text : Neu.subtext)
                Spacer()
                Text("\(category.widgetCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? category.accentColor : Neu.subtext.opacity(0.8))
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Circle().fill(selected ? AMTheme.accent.opacity(0.14) : Color.black.opacity(0.05)))
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? AMTheme.accent.opacity(0.10) : (hovered ? Color.black.opacity(0.04) : Color.clear))
            )
            .overlay(alignment: .leading) {
                if selected {
                    Capsule().fill(category.accentColor).frame(width: 3, height: 20).offset(x: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct SidebarRowButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundStyle(Neu.subtext).frame(width: 22)
                Text(label).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Neu.subtext)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovered ? Color.black.opacity(0.04) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Settings

struct SettingsView: View {
    let onClose: () -> Void
    @ObservedObject private var sizeM = WidgetSizeManager.shared
    @ObservedObject private var settings = WidgetSettings.shared
    @StateObject private var startup = LaunchOnStartupManager()

    private let accent = AMTheme.accent

    var body: some View {
        ZStack {
            Neu.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Settings")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Neu.text)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Neu.subtext).frame(width: 34, height: 34)
                    }
                    .buttonStyle(NeuTileStyle(corner: 10))
                }
                .padding(.bottom, 4)

                Text("Applies to the widget on your desktop")
                    .font(.system(size: 11)).foregroundStyle(Neu.subtext)
                    .padding(.bottom, 16)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {

                        // Appearance
                        block(title: "Widget Size", subtitle: "Anywhere from icon-sized to over half the screen") {
                            WidgetSizeSlider(scale: $sizeM.scale)
                        }

                        block(title: "Opacity", subtitle: "Let the widget blend into your wallpaper") {
                            HStack(spacing: 12) {
                                Image(systemName: "circle.dotted").font(.system(size: 13))
                                    .foregroundStyle(Neu.subtext)
                                Slider(value: $settings.widgetOpacity, in: 0.5...1.0).tint(accent)
                                Image(systemName: "circle.fill").font(.system(size: 13))
                                    .foregroundStyle(Neu.subtext)
                                Text("\(Int(settings.widgetOpacity * 100))%")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Neu.text)
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }

                        // Behavior
                        block(title: "Behavior", subtitle: "How the widget lives on your desktop") {
                            VStack(spacing: 0) {
                                toggleRow(icon: "square.stack.3d.up", title: "Always on top",
                                          subtitle: "Float above other windows",
                                          isOn: $settings.alwaysOnTop)
                                divider
                                toggleRow(icon: "cursorarrow.rays", title: "Click-through",
                                          subtitle: "Clicks pass through to what's behind",
                                          isOn: $settings.clickThrough)
                                divider
                                toggleRow(icon: "moon.zzz", title: "Hide when paused",
                                          subtitle: "Fade out when nothing is playing",
                                          isOn: $settings.hideWhenPaused)
                                divider
                                toggleRow(icon: "record.circle", title: "Track-change animation",
                                          subtitle: "Off: the vinyl widget snaps to the next song instantly",
                                          isOn: $settings.vinylTransitionAnimationEnabled)
                            }
                        }

                        // Musical notes
                        block(title: "Musical Notes", subtitle: "🎵 drift from a top corner while playing") {
                            VStack(spacing: 14) {
                                HStack {
                                    Text(settings.notesEnabled ? "On" : "Off")
                                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Neu.text)
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
                            }
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: settings.notesEnabled)
                        }

                        // Startup
                        block(title: "Startup", subtitle: "Open MusicWidgets when you log in") {
                            toggleRow(icon: "power", title: "Launch at login",
                                      subtitle: startup.isEnabled ? "Opens automatically at login" : "Off — open it yourself",
                                      isOn: Binding(
                                        get: { startup.isEnabled },
                                        set: { startup.setEnabled($0) }
                                      ))
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .padding(26)
        }
        .frame(width: 460, height: 620)
    }

    private var divider: some View {
        Rectangle().fill(Neu.hairline).frame(height: 1).padding(.vertical, 10)
    }

    private func toggleRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isOn.wrappedValue ? accent : Neu.subtext)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Neu.text)
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(Neu.subtext)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(accent)
        }
    }

    private func block<C: View>(title: String, subtitle: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Neu.text)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Neu.subtext)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neuRaised(18)
    }
}

struct NeuSegmented: View {
    let options: [String]
    let selected: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options.indices, id: \.self) { i in
                let isSel = i == selected
                Text(options[i])
                    .font(.system(size: 13, weight: isSel ? .semibold : .medium))
                    .foregroundStyle(isSel ? Neu.text : Neu.subtext)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(
                        Group {
                            if isSel {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Neu.elevated)
                                    .shadow(color: Color.black.opacity(0.18), radius: 3, y: 1)
                            }
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { onSelect(i) } }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neu.well))
        .neuInset(12)
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
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.title)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(Neu.text)
                    Text("\(category.widgetCount) styles · hover to preview, click to place on your desktop")
                        .font(.system(size: 12.5)).foregroundStyle(Neu.subtext)
                }
                Spacer()
                // Widget size, right where you pick the widget
                VStack(alignment: .trailing, spacing: 5) {
                    Text("SIZE")
                        .font(.system(size: 9.5, weight: .bold)).tracking(1.4)
                        .foregroundStyle(Neu.subtext.opacity(0.8))
                    WidgetSizeSlider(scale: $sizeM.scale)
                        .frame(width: 190)
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 30)
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
                                            onHover: { setHover(style.id, $0) },
                                            action: { AppDelegate.shared?.launchVinylWidget(themeID: style.themeID) }) { animated in
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
                                        onHover: { setHover(model.id, $0) },
                                        action: { AppDelegate.shared?.launchVinylHorizontalWidget(model: model) }) { _ in
                                VinylHorizontalModelPreview(model: model, live: liveTrack)
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
                                            onHover: { setHover(model.id, $0) },
                                            action: { AppDelegate.shared?.launchCDWidget(model: model) }) { animated in
                                    CDModelPreview(model: model, animated: animated, live: liveTrack)
                                }
                            }
                        }
                    } else {
                        formSection(name: "Album Art", subtitle: "Three sizes, one clean look",
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
    }

    @ViewBuilder
    private func formSection<Item: Identifiable, Card: View>(
        name: String, subtitle: String, count: Int,
        items: [Item],
        @ViewBuilder card: @escaping (Item) -> Card
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(name).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Neu.text)
                Text("·").foregroundStyle(Neu.subtext.opacity(0.6))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Neu.subtext)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Neu.subtext)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(Circle().fill(Neu.well))
            }
            // Eager rows (no LazyVGrid) so off-screen rows are never re-measured.
            let cols = columnCount
            let rows = stride(from: 0, to: items.count, by: cols).map { start in
                Array(items[start..<min(start + cols, items.count)])
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

    private func setHover(_ id: String, _ on: Bool) {
        if on { hoveredID = id }
        else if hoveredID == id { hoveredID = nil }
    }
}

// MARK: - Gallery card (spacious, hover-to-animate)

private struct GalleryCard<P: View>: View {
    let title: String
    let subtitle: String
    let accent: Color
    let hovered: Bool
    var active: Bool = false
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
                            RadialGradient(colors: [Neu.raised, Neu.well],
                                           center: .center, startRadius: 4, endRadius: 190)
                        )
                        .neuInset(16)

                    if hovered {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.forward.square.fill").font(.system(size: 11, weight: .bold))
                            Text("Place").font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundStyle(AMTheme.onAccent)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Capsule().fill(accent).shadow(color: accent.opacity(0.5), radius: 6, y: 2))
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
                    Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Neu.text)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Neu.subtext).lineLimit(1)
                }
                .padding(.top, 14)
                .padding(.bottom, 2)
            }
            .padding(14)
        }
        .buttonStyle(NeuTileStyle(corner: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(hovered ? accent.opacity(0.55) : (active ? accent.opacity(0.35) : .clear),
                              lineWidth: 1.5)
                .padding(1)
        )
        .scaleEffect(hovered ? 1.015 : 1.0)
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
    @State private var pulse = false

    private var np: NowPlayingInfo { detector.nowPlaying }
    private var hasTrack: Bool { !np.trackName.isEmpty }

    var body: some View {
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

            if hasTrack {
                HStack(spacing: 7) {
                    Circle()
                        .fill(np.isPlaying ? Color(hex: "53e08a") : Neu.subtext)
                        .frame(width: 7, height: 7)
                        .shadow(color: np.isPlaying ? Color(hex: "53e08a").opacity(0.8) : .clear, radius: 4)
                        .scaleEffect(np.isPlaying && pulse ? 1.35 : 1.0)
                    Text(np.isPlaying ? "Playing" : "Paused")
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Neu.subtext)
                }
                .padding(.horizontal, 13).frame(height: 30)
                .background(Capsule().fill(Neu.well))
                .overlay(Capsule().strokeBorder(Neu.hairline, lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .neuRaised(18)
        .onAppear {
            loadArt(np.albumArtURL)
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onChange(of: np.albumArtURL) { _, url in loadArt(url) }
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

    /// For the Adaptive style specifically, the preview's whole palette
    /// tracks the real playing track's colours, same as the live widget.
    private var resolvedPalette: WidgetThemePalette {
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
                let a = spinning ? (ctx.date.timeIntervalSinceReferenceDate * 132).truncatingRemainder(dividingBy: 360) : 0
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
                    Image(systemName: "play.fill").font(.system(size: 27, weight: .medium))
                    Image(systemName: "forward.fill").font(.system(size: 21, weight: .medium))
                }
                .foregroundStyle(palette.trackTitle)
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
                Image(systemName: "play.fill").font(.system(size: 27, weight: .medium))
                Image(systemName: "forward.fill").font(.system(size: 21, weight: .medium))
            }
            .foregroundStyle(palette.trackTitle)
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
