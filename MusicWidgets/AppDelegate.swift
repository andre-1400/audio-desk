import AppKit
import SwiftUI
import Combine

extension Notification.Name {
    /// Posted when something (widget context menu, menu bar) wants the gallery's settings sheet.
    static let openWidgetSettings = Notification.Name("openWidgetSettings")
}

/// Which widget is currently placed on the desktop ("vinyl:<themeID>" / "cd:<modelID>").
/// Published so the gallery can badge the active card live.
final class ActiveWidgetState: ObservableObject {
    static let shared = ActiveWidgetState()
    @Published var entry: String? = nil
    private init() {}
}

class AppDelegate: NSObject, NSApplicationDelegate {

    private var vinylWindow: WidgetWindow?
    private var overlayWindow: AnimationOverlayWindow?
    private var cdWindow: WidgetWindow?
    private var cdModel: CDModel?

    private var galleryWindow: NSWindow?
    private var statusItem: NSStatusItem?

    private let themeManager = WidgetThemeManager()
    private let animator = SongSwitchAnimator()

    /// App-level now-playing feed: menu-bar track info + hide-on-pause.
    private let statusDetector = MusicDetector()
    private var pauseHideWork: DispatchWorkItem?
    private var hiddenByPause = false
    private var hiddenByUser = false

    private var cancellables = Set<AnyCancellable>()        // per-vinyl-launch
    private var globalCancellables = Set<AnyCancellable>()  // settings (persistent)

    /// Grace period before hide-on-pause kicks in, so track changes don't flicker the widget.
    private let pauseHideGrace: TimeInterval = 4.0
    private let windowFadeDuration: TimeInterval = 0.32

    static var shared: AppDelegate?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar app — no Dock icon, accessible from the top menu bar.
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()

        themeManager.restoreGeneratedThemeIfNeeded()
        statusDetector.start()

        // Show the gallery on first launch so the user sees the app after install.
        showGallery()

        // Live-update the active widget when size or notes settings change.
        WidgetSizeManager.shared.$size
            .receive(on: DispatchQueue.main).dropFirst()
            .sink { [weak self] _ in self?.relayoutActiveWidget() }
            .store(in: &globalCancellables)
        WidgetSettings.shared.$notesEnabled
            .receive(on: DispatchQueue.main).dropFirst()
            .sink { [weak self] _ in self?.relayoutActiveWidget() }
            .store(in: &globalCancellables)

        // Window-level preferences (opacity, click-through, always-on-top).
        WidgetSettings.shared.$widgetOpacity
            .receive(on: DispatchQueue.main).dropFirst()
            .sink { [weak self] _ in self?.applyWindowPreferences() }
            .store(in: &globalCancellables)
        WidgetSettings.shared.$clickThrough
            .receive(on: DispatchQueue.main).dropFirst()
            .sink { [weak self] _ in self?.applyWindowPreferences() }
            .store(in: &globalCancellables)
        WidgetSettings.shared.$alwaysOnTop
            .receive(on: DispatchQueue.main).dropFirst()
            .sink { [weak self] _ in self?.applyWindowPreferences() }
            .store(in: &globalCancellables)
        WidgetSettings.shared.$hideWhenPaused
            .receive(on: DispatchQueue.main).dropFirst()
            .sink { [weak self] enabled in
                if enabled {
                    self?.handlePlaybackChange(self?.statusDetector.nowPlaying.isPlaying ?? false)
                } else {
                    self?.cancelPauseHide()
                    self?.unhideFromPause()
                }
            }
            .store(in: &globalCancellables)

        // Hide-on-pause: watch playback state app-wide.
        statusDetector.$nowPlaying
            .receive(on: DispatchQueue.main)
            .map(\.isPlaying)
            .removeDuplicates()
            .sink { [weak self] playing in self?.handlePlaybackChange(playing) }
            .store(in: &globalCancellables)

        // Keep the gallery window chrome matching the chosen brand (Apple Music light / Spotify dark).
        BrandManager.shared.$brand
            .receive(on: DispatchQueue.main)
            .sink { [weak self] brand in self?.applyBrandToGallery(brand) }
            .store(in: &globalCancellables)
    }

    private func applyBrandToGallery(_ brand: Brand) {
        guard let win = galleryWindow else { return }
        switch brand {
        case .spotify:
            win.appearance = NSAppearance(named: .darkAqua)
            win.backgroundColor = NSColor(red: 0.071, green: 0.071, blue: 0.071, alpha: 1) // #121212
        case .appleMusic:
            win.appearance = NSAppearance(named: .aqua)
            win.backgroundColor = .white
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // Accessory apps have no Dock icon, so macOS never fires the usual "reopen"
    // behavior on its own. Without this, relaunching (Spotlight, double-click in
    // Applications, etc.) while already running silently does nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showGallery()
        return true
    }

    // MARK: - Menu bar item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = AppDelegate.makeNoteIcon()
            button.toolTip = "MusicWidgets"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem?.menu = buildStatusMenu()
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            toggleGallery()
        }
    }

    /// Rebuilt on every right-click so track info and widget state are always current.
    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        let np = statusDetector.nowPlaying

        // Now playing header
        if !np.trackName.isEmpty {
            let track = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            let title = NSMutableAttributedString(
                string: (np.isPlaying ? "♪ " : "❚❚ ") + truncated(np.trackName, 34) + "\n",
                attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
            )
            title.append(NSAttributedString(
                string: truncated(np.artistName, 38),
                attributes: [.font: NSFont.systemFont(ofSize: 11),
                             .foregroundColor: NSColor.secondaryLabelColor]
            ))
            track.attributedTitle = title
            track.isEnabled = false
            menu.addItem(track)
            menu.addItem(.separator())
        }

        // Widget visibility
        if hasActiveWidget {
            let visible = isWidgetOrderedIn
            let toggle = NSMenuItem(title: visible ? "Hide Widget" : "Show Widget",
                                    action: #selector(toggleWidgetVisibility), keyEquivalent: "h")
            toggle.target = self
            menu.addItem(toggle)
        } else if let last = RecentWidgets.last, let name = displayName(for: last) {
            let show = NSMenuItem(title: "Show \(name)", action: #selector(showLastWidget), keyEquivalent: "h")
            show.target = self
            menu.addItem(show)
        }

        // Quick style switcher
        let recents = RecentWidgets.entries
        if !recents.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Recent Styles", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for entry in recents {
                guard let name = displayName(for: entry) else { continue }
                let item = NSMenuItem(title: name, action: #selector(launchRecent(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry
                item.indentationLevel = 1
                if entry == activeWidgetEntry {
                    item.state = .on
                }
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open MusicWidgets", action: #selector(showGallery), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)
        let settings = NSMenuItem(title: "Settings…", action: #selector(showGallerySettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit MusicWidgets", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func truncated(_ s: String, _ limit: Int) -> String {
        s.count > limit ? String(s.prefix(limit - 1)) + "…" : s
    }

    /// "vinyl:<themeID>" / "cd:<modelID>" for whatever widget is currently placed.
    private var activeWidgetEntry: String? {
        if vinylWindow != nil { return "vinyl:\(themeManager.themeID.rawValue)" }
        if let model = cdModel, cdWindow != nil { return "cd:\(model.id)" }
        return nil
    }

    private func displayName(for entry: String) -> String? {
        if entry.hasPrefix("vinyl:") {
            let raw = String(entry.dropFirst(6))
            guard let style = VinylStyle.all.first(where: { $0.themeID.rawValue == raw }) else { return nil }
            return "Vinyl · \(style.name)"
        }
        if entry.hasPrefix("cd:") {
            let raw = String(entry.dropFirst(3))
            guard let model = CDModel.all.first(where: { $0.id == raw }) else { return nil }
            let form = CDModel.forms.first { $0.models.contains(where: { $0.id == model.id }) }
            return "\(form?.name ?? "CD") · \(model.name)"
        }
        return nil
    }

    @objc private func launchRecent(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? String else { return }
        launch(entry: entry)
    }

    @objc private func showLastWidget() {
        guard let last = RecentWidgets.last else { return }
        launch(entry: last)
    }

    private func launch(entry: String) {
        if entry.hasPrefix("vinyl:") {
            launchVinylWidget(themeID: WidgetThemeID.fromPersisted(String(entry.dropFirst(6))))
        } else if entry.hasPrefix("cd:"),
                  let model = CDModel.all.first(where: { $0.id == String(entry.dropFirst(3)) }) {
            launchCDWidget(model: model)
        }
    }

    // MARK: - Widget visibility (menu + hide-on-pause)

    private var hasActiveWidget: Bool { vinylWindow != nil || cdWindow != nil }

    private var isWidgetOrderedIn: Bool {
        (vinylWindow?.isVisible ?? false) || (cdWindow?.isVisible ?? false)
    }

    private var activeWidgetWindows: [NSWindow] {
        [vinylWindow, cdWindow].compactMap { $0 }
    }

    @objc private func toggleWidgetVisibility() {
        if isWidgetOrderedIn {
            hiddenByUser = true
            for w in activeWidgetWindows { fadeOut(w, thenOrderOut: true) }
        } else {
            hiddenByUser = false
            hiddenByPause = false
            for w in activeWidgetWindows { fadeIn(w) }
        }
    }

    func hideActiveWidget() { if isWidgetOrderedIn { toggleWidgetVisibility() } }

    func closeActiveWidget() {
        closeVinylWidget()
        closeCDWidget()
    }

    @objc func showGallerySettings() {
        showGallery()
        NotificationCenter.default.post(name: .openWidgetSettings, object: nil)
    }

    private func handlePlaybackChange(_ playing: Bool) {
        guard WidgetSettings.shared.hideWhenPaused else { return }
        if playing {
            cancelPauseHide()
            unhideFromPause()
        } else {
            schedulePauseHide()
        }
    }

    private func schedulePauseHide() {
        cancelPauseHide()
        guard hasActiveWidget, !hiddenByUser else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, WidgetSettings.shared.hideWhenPaused,
                  !self.statusDetector.nowPlaying.isPlaying else { return }
            self.hiddenByPause = true
            for w in self.activeWidgetWindows { self.fadeOut(w, thenOrderOut: true) }
        }
        pauseHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + pauseHideGrace, execute: work)
    }

    private func cancelPauseHide() {
        pauseHideWork?.cancel()
        pauseHideWork = nil
    }

    private func unhideFromPause() {
        guard hiddenByPause, !hiddenByUser else { return }
        hiddenByPause = false
        for w in activeWidgetWindows { fadeIn(w) }
    }

    // MARK: - Window fades + preferences

    private var desktopWidgetLevel: NSWindow.Level {
        NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }
    private var desktopOverlayLevel: NSWindow.Level {
        NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)
    }

    /// Push opacity / click-through / always-on-top onto the live windows.
    private func applyWindowPreferences() {
        let s = WidgetSettings.shared
        let onTop = s.alwaysOnTop
        for w in activeWidgetWindows {
            w.level = onTop ? .floating : desktopWidgetLevel
            w.ignoresMouseEvents = s.clickThrough
            if w.isVisible { w.alphaValue = s.widgetOpacity }
        }
        if let o = overlayWindow {
            o.level = onTop ? NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
                            : desktopOverlayLevel
            o.alphaValue = s.widgetOpacity
        }
    }

    private func fadeIn(_ window: NSWindow) {
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = windowFadeDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = WidgetSettings.shared.widgetOpacity
        }
    }

    private func fadeOut(_ window: NSWindow, thenOrderOut: Bool = false, thenClose: Bool = false) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = windowFadeDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: {
            if thenClose { window.close() }
            else if thenOrderOut { window.orderOut(nil) }
        })
    }

    // MARK: - Gallery window

    @objc func showGallery() {
        if galleryWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            win.title = "MusicWidgets"
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.isMovableByWindowBackground = true
            win.isReleasedWhenClosed = false
            win.minSize = NSSize(width: 820, height: 600)
            win.contentView = NSHostingView(rootView: ContentView())
            win.center()
            galleryWindow = win
            applyBrandToGallery(BrandManager.shared.brand)
        }
        NSApp.activate(ignoringOtherApps: true)
        guard let win = galleryWindow else { return }
        if !win.isVisible {
            win.alphaValue = 0
            win.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                win.animator().alphaValue = 1
            }
        } else {
            win.makeKeyAndOrderFront(nil)
        }
    }

    private func toggleGallery() {
        if let w = galleryWindow, w.isVisible {
            w.orderOut(nil)
        } else {
            showGallery()
        }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    /// A custom eighth-note glyph for the menu bar (template image, auto-tints).
    static func makeNoteIcon() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            // notehead
            NSBezierPath(ovalIn: NSRect(x: 2.0, y: 1.6, width: 6.4, height: 5.0)).fill()
            // stem
            NSBezierPath(rect: NSRect(x: 7.1, y: 3.8, width: 1.5, height: 9.6)).fill()
            // flag
            let flag = NSBezierPath()
            flag.move(to: NSPoint(x: 8.6, y: 13.4))
            flag.curve(to: NSPoint(x: 12.8, y: 8.0),
                       controlPoint1: NSPoint(x: 13.0, y: 12.9),
                       controlPoint2: NSPoint(x: 13.4, y: 10.2))
            flag.curve(to: NSPoint(x: 8.6, y: 9.9),
                       controlPoint1: NSPoint(x: 11.4, y: 9.4),
                       controlPoint2: NSPoint(x: 9.9, y: 9.7))
            flag.close()
            flag.fill()
            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: - Sizing helpers

    private var notesPad: CGFloat { WidgetSettings.shared.notesEnabled ? 92 : 0 }

    private func vinylWindowSize() -> CGSize {
        let s = WidgetSizeManager.shared.scale
        let p = notesPad
        return CGSize(width: baseWidgetSize.width * s + 2 * p,
                      height: baseWidgetSize.height * s + 2 * p)
    }

    private func cdWindowSize(_ model: CDModel) -> CGSize {
        let s = WidgetSizeManager.shared.scale
        let p = notesPad
        return CGSize(width: model.archetype.baseSize.width * s + 2 * p,
                      height: model.archetype.baseSize.height * s + 2 * p)
    }

    private func relayoutActiveWidget() {
        if vinylWindow != nil { applyVinylLayout() }
        if cdWindow != nil { applyCDLayout() }
    }

    /// Returns a saved position only if it's actually visible on some screen,
    /// otherwise a sensible visible default (upper-left), so a launched widget
    /// never ends up hidden behind the gallery or off-screen.
    private func launchOrigin(xKey: String, yKey: String, size: CGSize) -> CGPoint {
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let sx = UserDefaults.standard.double(forKey: xKey)
        let sy = UserDefaults.standard.double(forKey: yKey)
        if sx != 0 || sy != 0 {
            let rect = CGRect(x: sx, y: sy, width: size.width, height: size.height)
            if NSScreen.screens.contains(where: { $0.frame.intersects(rect.insetBy(dx: 40, dy: 40)) }) {
                return CGPoint(x: sx, y: sy)
            }
        }
        return CGPoint(x: screen.minX + 70, y: screen.maxY - size.height - 90)
    }

    // MARK: - Launch vinyl widget

    func launchVinylWidget(themeID: WidgetThemeID = .default) {
        closeCDWidget()
        themeManager.setTheme(themeID)
        RecentWidgets.note(vinyl: themeID)
        ActiveWidgetState.shared.entry = "vinyl:\(themeID.rawValue)"
        hiddenByUser = false
        hiddenByPause = false

        if let existing = vinylWindow {
            existing.orderFrontRegardless()
            existing.alphaValue = WidgetSettings.shared.widgetOpacity
            return
        }

        let window = WidgetWindow()
        let size = vinylWindowSize()
        let origin = launchOrigin(xKey: "widgetX", yKey: "widgetY", size: size)
        window.setFrame(CGRect(origin: origin, size: size), display: false)

        let rootView = ScaledWidgetView(animator: animator, themeManager: themeManager, sizeManager: WidgetSizeManager.shared)
            .modifier(DesktopWidgetChrome())
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = window.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(hostingView)
        self.vinylWindow = window

        // Animation overlay window
        let overlay = AnimationOverlayWindow()
        let overlayHosting = NSHostingView(rootView: ScaledOverlayView(animator: animator, sizeManager: WidgetSizeManager.shared))
        overlayHosting.frame = overlay.contentView?.bounds ?? .zero
        overlayHosting.autoresizingMask = [.width, .height]
        overlayHosting.wantsLayer = true
        overlayHosting.layer?.backgroundColor = .clear
        overlay.contentView?.addSubview(overlayHosting)
        overlay.contentView?.wantsLayer = true
        overlay.contentView?.layer?.backgroundColor = .clear
        overlay.position(over: window.frame)
        overlay.orderOut(nil)
        self.overlayWindow = overlay

        animator.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                guard let self, let w = self.vinylWindow, let o = self.overlayWindow else { return }
                o.position(over: w.frame)
                if phase == .idle { o.orderOut(nil) } else { o.orderFrontRegardless() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
            guard let self, let w = self.vinylWindow else { return }
            UserDefaults.standard.set(w.frame.origin.x, forKey: "widgetX")
            UserDefaults.standard.set(w.frame.origin.y, forKey: "widgetY")
            if self.animator.isAnimating { self.overlayWindow?.position(over: w.frame) }
        }

        applyWindowPreferences()
        fadeIn(window)
    }

    private func applyVinylLayout() {
        guard let window = vinylWindow else { return }
        let size = vinylWindowSize()
        let c = window.frame
        let origin = CGPoint(x: c.midX - size.width / 2, y: c.midY - size.height / 2)
        window.setFrame(CGRect(origin: origin, size: size), display: true, animate: false)
        UserDefaults.standard.set(window.frame.origin.x, forKey: "widgetX")
        UserDefaults.standard.set(window.frame.origin.y, forKey: "widgetY")
        overlayWindow?.position(over: window.frame)
    }

    func closeVinylWidget() {
        if let window = vinylWindow {
            vinylWindow = nil
            fadeOut(window, thenClose: true)
            if ActiveWidgetState.shared.entry?.hasPrefix("vinyl:") == true {
                ActiveWidgetState.shared.entry = nil
            }
        }
        if let overlay = overlayWindow {
            overlayWindow = nil
            fadeOut(overlay, thenClose: true)
        }
        cancellables.removeAll()
    }

    // MARK: - Launch CD widget

    func launchCDWidget(model: CDModel) {
        closeVinylWidget()
        cdModel = model
        RecentWidgets.note(cd: model)
        ActiveWidgetState.shared.entry = "cd:\(model.id)"
        hiddenByUser = false
        hiddenByPause = false
        let size = cdWindowSize(model)

        if let existing = cdWindow {
            existing.contentView?.subviews.forEach { $0.removeFromSuperview() }
            let host = NSHostingView(rootView: CDSizedRoot(model: model).modifier(DesktopWidgetChrome()))
            host.frame = existing.contentView?.bounds ?? .zero
            host.autoresizingMask = [.width, .height]
            existing.contentView?.addSubview(host)
            applyCDLayout()
            existing.orderFrontRegardless()
            existing.alphaValue = WidgetSettings.shared.widgetOpacity
            return
        }

        let window = WidgetWindow()
        window.setContentSize(size)
        window.setFrameOrigin(launchOrigin(xKey: "cdWidgetX", yKey: "cdWidgetY", size: size))

        let host = NSHostingView(rootView: CDSizedRoot(model: model).modifier(DesktopWidgetChrome()))
        host.frame = window.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(host)
        self.cdWindow = window

        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { _ in
            UserDefaults.standard.set(window.frame.origin.x, forKey: "cdWidgetX")
            UserDefaults.standard.set(window.frame.origin.y, forKey: "cdWidgetY")
        }

        applyWindowPreferences()
        fadeIn(window)
    }

    private func applyCDLayout() {
        guard let window = cdWindow, let model = cdModel else { return }
        let size = cdWindowSize(model)
        let c = window.frame
        let origin = CGPoint(x: c.midX - size.width / 2, y: c.midY - size.height / 2)
        window.setFrame(CGRect(origin: origin, size: size), display: true, animate: false)
        UserDefaults.standard.set(window.frame.origin.x, forKey: "cdWidgetX")
        UserDefaults.standard.set(window.frame.origin.y, forKey: "cdWidgetY")
    }

    func closeCDWidget() {
        if let window = cdWindow {
            cdWindow = nil
            fadeOut(window, thenClose: true)
            if ActiveWidgetState.shared.entry?.hasPrefix("cd:") == true {
                ActiveWidgetState.shared.entry = nil
            }
        }
        cdModel = nil
    }
}

// MARK: - Desktop widget chrome (hover glow + right-click menu)

/// Shared wrapper for any widget placed on the desktop: a gentle brightness
/// lift while hovered and a right-click menu for quick actions. Purely
/// cosmetic — the widget's own animations are untouched.
struct DesktopWidgetChrome: ViewModifier {
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .brightness(hovered ? 0.045 : 0)
            .animation(.easeOut(duration: 0.22), value: hovered)
            .onHover { hovered = $0 }
            .contextMenu {
                Button {
                    AppDelegate.shared?.showGallery()
                } label: {
                    Label("Change Style…", systemImage: "square.grid.2x2")
                }
                Button {
                    AppDelegate.shared?.showGallerySettings()
                } label: {
                    Label("Settings…", systemImage: "slider.horizontal.3")
                }
                Divider()
                Button {
                    AppDelegate.shared?.hideActiveWidget()
                } label: {
                    Label("Hide Widget", systemImage: "eye.slash")
                }
                Button(role: .destructive) {
                    AppDelegate.shared?.closeActiveWidget()
                } label: {
                    Label("Close Widget", systemImage: "xmark.circle")
                }
            }
    }
}
