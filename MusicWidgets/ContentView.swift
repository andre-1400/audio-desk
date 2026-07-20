import SwiftUI

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
                        block(title: "Widget Size", subtitle: "How big the widget appears") {
                            NeuSegmented(options: WidgetSize.allCases.map { $0.title },
                                         selected: WidgetSize.allCases.firstIndex(of: sizeM.size) ?? 1) { i in
                                sizeM.size = WidgetSize.allCases[i]
                            }
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

// MARK: - Detail pane (grid + now playing)

private struct GalleryDetail: View {
    let category: WidgetCategory
    @ObservedObject var detector: MusicDetector
    @ObservedObject private var activeWidget = ActiveWidgetState.shared
    @ObservedObject private var sizeM = WidgetSizeManager.shared
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
                    NeuSegmented(options: WidgetSize.allCases.map { $0.title },
                                 selected: WidgetSize.allCases.firstIndex(of: sizeM.size) ?? 1) { i in
                        sizeM.size = WidgetSize.allCases[i]
                    }
                    .frame(width: 230)
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
                                    VinylStylePreview(themeID: style.themeID, animated: animated)
                                }
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
                                    CDModelPreview(model: model, animated: animated)
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
                                AlbumArtModelPreview(model: model)
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
        VinylForm(id: "turntable", name: "Turntable", subtitle: "Classic record player", icon: "record.circle",
                  styles: [
                    VinylStyle(themeID: .default,  name: "Classic",  subtitle: "Warm wood & gold"),
                    VinylStyle(themeID: .obsidian, name: "Obsidian", subtitle: "Jet black & chrome"),
                    VinylStyle(themeID: .pearl,    name: "Pearl",    subtitle: "Cream & terracotta"),
                    VinylStyle(themeID: .midnight, name: "Midnight", subtitle: "Navy & steel"),
                    VinylStyle(themeID: .crimson,  name: "Crimson",  subtitle: "Burgundy & gold"),
                    VinylStyle(themeID: .emerald,  name: "Emerald",  subtitle: "Forest green & brass"),
                    VinylStyle(themeID: .carbon,   name: "Carbon",   subtitle: "Matte black & red"),
                    VinylStyle(themeID: .copper,   name: "Copper",   subtitle: "Burnished bronze")
                  ]),
        VinylForm(id: "studio", name: "Studio", subtitle: "Pro decks with extra hardware", icon: "dial.high",
                  styles: [
                    VinylStyle(themeID: .slate,     name: "Slate",     subtitle: "Brushed studio deck"),
                    VinylStyle(themeID: .walnut,    name: "Walnut",    subtitle: "Audiophile wood deck"),
                    VinylStyle(themeID: .sandstone, name: "Suitcase",  subtitle: "Canvas travel case"),
                    VinylStyle(themeID: .synthwave, name: "Synthwave", subtitle: "Neon night deck")
                  ]),
        VinylForm(id: "pop", name: "Pop", subtitle: "Soft pastel colourways", icon: "paintpalette",
                  styles: [
                    VinylStyle(themeID: .rosegold,  name: "Rose Gold", subtitle: "Blush & warm metal"),
                    VinylStyle(themeID: .mint,      name: "Mint",      subtitle: "Fresh green cream"),
                    VinylStyle(themeID: .bubblegum, name: "Bubblegum", subtitle: "Candy pink"),
                    VinylStyle(themeID: .lavender,  name: "Lavender",  subtitle: "Soft violet"),
                    VinylStyle(themeID: .glacier,   name: "Glacier",   subtitle: "Icy pale blue"),
                    VinylStyle(themeID: .honey,     name: "Honey",     subtitle: "Golden cream")
                  ]),
        VinylForm(id: "minimal", name: "Minimal", subtitle: "Floating disc, no body", icon: "circle",
                  styles: [
                    VinylStyle(themeID: .modern,       name: "Mono",  subtitle: "Black label"),
                    VinylStyle(themeID: .minimalIvory, name: "Ivory", subtitle: "Cream label"),
                    VinylStyle(themeID: .minimalRose,  name: "Rose",  subtitle: "Blush label"),
                    VinylStyle(themeID: .minimalSage,  name: "Sage",  subtitle: "Soft green label")
                  ]),
        VinylForm(id: "jukebox", name: "Jukebox", subtitle: "Retro consoles with buttons", icon: "radio",
                  styles: [
                    VinylStyle(themeID: .jukebox, name: "Cherry",  subtitle: "Cherry wood cabinet"),
                    VinylStyle(themeID: .diner,   name: "Diner",   subtitle: "Teal diner console"),
                    VinylStyle(themeID: .tweed,   name: "Tweed",   subtitle: "Tweed radiogram"),
                    VinylStyle(themeID: .boombox, name: "Blaze",   subtitle: "Black & orange deck"),
                    VinylStyle(themeID: .mustard, name: "Mustard", subtitle: "70s golden yellow")
                  ])
    ]

    static let all: [VinylStyle] = forms.flatMap { $0.styles }
}


struct CDModelPreview: View {
    let model: CDModel
    var animated: Bool = false

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
        let view = CDWidgetView(model: model, isPreview: true, previewSpinning: animated)
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
    var body: some View {
        GeometryReader { geo in
            let base = CGSize(width: 360, height: 420)
            let s = min(geo.size.width / base.width, geo.size.height / base.height)
            content
                .frame(width: base.width, height: base.height)
                .scaleEffect(s)
                .frame(width: base.width * s, height: base.height * s)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder private var content: some View {
        let replica = VinylWidgetReplica(palette: themeID.palette, traits: themeID.traits, spinning: animated)
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

    var body: some View {
        ZStack {
            // === Body shell (320×380) ===
            if palette.showBody {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(colors: palette.widgetBodyGradient,
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: .black.opacity(0.7), radius: 30, x: 0, y: 20)

                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(palette.widgetBorder, lineWidth: 1)

                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            LinearGradient(colors: [palette.widgetTopSheen, .clear],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1
                        )

                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(colors: [Color.white.opacity(0.06), .clear],
                                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.28))
                        )

                    VinylBodyTexture(pattern: traits.pattern)

                    cornerScrews
                }
                .frame(width: 320, height: 380)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            if palette.showBody { bodyDetails }

            // === Content (platter + track info / controls) ===
            VStack(spacing: 0) {
                platterArea
                    .padding(.top, palette.showBody ? 24 : 8)

                if traits.hasTransportControls {
                    VStack(spacing: 9) {
                        RetroVFDDisplay(title: "NOW PLAYING", subtitle: "MusicWidgets")
                        transportControls
                    }
                    .padding(.top, 10)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)
                } else {
                    trackInfoPlaceholder
                        .padding(.top, 16)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }

            // === Tonearm (cued onto the record) ===
            tonearmView
                .rotationEffect(.degrees(-6), anchor: UnitPoint(x: 68.0 / 90.0, y: 16.0 / 180.0))
                .offset(x: 115, y: -84)
        }
        .frame(width: 360, height: 420)
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
        .frame(width: 360, height: 420)
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
            Circle()
                .fill(
                    RadialGradient(colors: [Color(hex: "cccccc"), Color(hex: "666666")],
                                   center: .center, startRadius: 0, endRadius: 5)
                )
                .frame(width: 10, height: 10)
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

    private var albumArtLabel: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(colors: palette.albumArtLabelGradient,
                                   center: .center, startRadius: 0, endRadius: 48)
                )
                .frame(width: 96, height: 96)

            Circle()
                .fill(
                    RadialGradient(colors: [Color(hex: "cccccc"), Color(hex: "666666")],
                                   center: .center, startRadius: 0, endRadius: 5)
                )
                .frame(width: 10, height: 10)
        }
        .frame(width: 96, height: 96)
        .overlay(Circle().strokeBorder(palette.albumArtRingColor, lineWidth: 2))
        .shadow(color: .black.opacity(0.8), radius: 6)
    }

    // MARK: Tonearm (exact geometry from the live widget)

    private var tonearmView: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(colors: [Color(hex: "e6e6e8"), Color(hex: "a8a8ac"), Color(hex: "5c5c60")],
                                   center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 12)
                )
                .frame(width: 24, height: 24)
                .position(x: 68, y: 16)

            RoundedRectangle(cornerRadius: 2.5)
                .fill(
                    LinearGradient(colors: [Color(hex: "232326"), Color(hex: "58585c"), Color(hex: "232326")],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .frame(width: 5, height: 130)
                .rotationEffect(.degrees(20))
                .position(x: 46, y: 85)

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

    // MARK: Track info placeholder (status dot + title/artist bars)

    private var trackInfoPlaceholder: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(palette.trackPlayingDot)
                    .frame(width: 6, height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(palette.trackTitle.opacity(0.85))
                    .frame(width: 120, height: 9)
            }
            RoundedRectangle(cornerRadius: 2.5)
                .fill(palette.trackArtist.opacity(0.7))
                .frame(width: 78, height: 7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Corner screws

    private var cornerScrews: some View {
        GeometryReader { geo in
            let inset: CGFloat = 13
            screwDot.position(x: inset, y: inset)
            screwDot.position(x: geo.size.width - inset, y: inset)
            screwDot.position(x: inset, y: geo.size.height - inset)
            screwDot.position(x: geo.size.width - inset, y: geo.size.height - inset)
        }
    }

    private var screwDot: some View {
        Circle()
            .fill(
                RadialGradient(colors: palette.screwGradient,
                               center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 4.5)
            )
            .frame(width: 9, height: 9)
            .shadow(color: .black.opacity(0.6), radius: 1.5, x: 0, y: 1)
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
        case .vinyl: return VinylStyle.all.count
        case .cd: return CDModel.all.count
        case .albumArt: return AlbumArtModel.all.count
        }
    }
    var accentColor: Color { AMTheme.accent }
}
