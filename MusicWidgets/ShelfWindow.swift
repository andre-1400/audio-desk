// ShelfWindow.swift
// Phase 10 — Second floating NSPanel for the queue shelf
// Positions itself centered below the main widget (flips above near bottom edge)

import AppKit
import SwiftUI

enum ShelfPlacement {
    case below
    case above
}

class ShelfWindow: NSPanel {

    // Shelf dimensions (4 cards × 90 + spacing + padding)
    static let shelfWidth:  CGFloat = 440
    static let shelfHeight: CGFloat = 170

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {

        let rect = NSRect(x: 0, y: 0, width: ShelfWindow.shelfWidth, height: ShelfWindow.shelfHeight)
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)

        // Transparent, frameless, floating — same character as WidgetWindow
        isOpaque                = false
        backgroundColor         = .clear
        hasShadow               = false
        // Match exact same level as WidgetWindow — above desktop icons, below normal windows
        level                   = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior      = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        hidesOnDeactivate       = false
        ignoresMouseEvents      = false
    }

    // MARK: - Positioning

    /// Positions the shelf relative to the main widget window.
    /// Defaults to centered-below; flips above if below would clip off-screen.
    @discardableResult
    func positionRelativeTo(widgetFrame: NSRect) -> ShelfPlacement {
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.contains(CGPoint(x: widgetFrame.midX, y: widgetFrame.midY))
        }) ?? NSScreen.main else {
            return .below
        }

        let gap: CGFloat = 10
        let shelfW = ShelfWindow.shelfWidth
        let shelfH = ShelfWindow.shelfHeight
        let visible = screen.visibleFrame

        // Center shelf to widget horizontally and clamp to visible screen bounds.
        let centeredX = widgetFrame.midX - (shelfW / 2)
        let shelfX = min(max(centeredX, visible.minX), visible.maxX - shelfW)

        let belowY = widgetFrame.minY - gap - shelfH
        let placement: ShelfPlacement = belowY >= visible.minY ? .below : .above
        let rawY: CGFloat = placement == .below ? belowY : (widgetFrame.maxY + gap)
        let shelfY = min(max(rawY, visible.minY), visible.maxY - shelfH)

        setFrameOrigin(CGPoint(x: shelfX, y: shelfY))
        return placement
    }
}
