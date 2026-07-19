import AppKit
import QuartzCore

enum WidgetLandingAnimator {
    static func animate(
        window: NSWindow,
        from sourceFrame: CGRect?,
        to finalFrame: CGRect,
        fading onboardingWindow: NSWindow?,
        completion: (() -> Void)? = nil
    ) {
        let overlayFrame = overlayFrame(containing: [sourceFrame, finalFrame])
        let startFrame = startingFrame(from: sourceFrame, finalFrame: finalFrame)
        let settleFrame = scaledFrame(finalFrame, scale: 1.025)
        let image = snapshot(of: window.contentView)
        let overlay = LandingOverlayWindow(frame: overlayFrame, above: onboardingWindow)
        let imageView = NSImageView(frame: localFrame(startFrame, in: overlayFrame))

        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.alphaValue = 0
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 16
        imageView.layer?.masksToBounds = false
        imageView.layer?.shadowColor = NSColor.black.cgColor
        imageView.layer?.shadowOpacity = 0.28
        imageView.layer?.shadowRadius = 18
        imageView.layer?.shadowOffset = CGSize(width: 0, height: -10)

        overlay.contentView?.addSubview(imageView)

        window.setFrame(finalFrame, display: false)
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
        window.contentView?.layoutSubtreeIfNeeded()

        overlay.orderFrontRegardless()

        fadeOut(onboardingWindow)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.42
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.82, 0.24, 1.0)
            imageView.animator().alphaValue = 1
            imageView.animator().frame = localFrame(settleFrame, in: overlayFrame)
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                imageView.animator().frame = localFrame(finalFrame, in: overlayFrame)
                window.animator().alphaValue = 1
                imageView.animator().alphaValue = 0
            } completionHandler: {
                window.setFrame(finalFrame, display: true)
                window.alphaValue = 1
                window.ignoresMouseEvents = false
                overlay.close()
                completion?()
            }
        }
    }

    private static func fadeOut(_ onboardingWindow: NSWindow?) {
        guard let onboardingWindow else { return }

        onboardingWindow.ignoresMouseEvents = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.50
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            onboardingWindow.animator().alphaValue = 0
        } completionHandler: {
            onboardingWindow.close()
            onboardingWindow.alphaValue = 1
        }
    }

    private static func startingFrame(from sourceFrame: CGRect?, finalFrame: CGRect) -> CGRect {
        guard let sourceFrame, sourceFrame.width > 1, sourceFrame.height > 1 else {
            return scaledFrame(finalFrame, scale: 0.44)
        }

        let sourceScale = min(sourceFrame.width / finalFrame.width, sourceFrame.height / finalFrame.height)
        let scale = min(max(sourceScale, 0.34), 0.54)
        let size = CGSize(width: finalFrame.width * scale, height: finalFrame.height * scale)
        return CGRect(
            x: sourceFrame.midX - size.width / 2,
            y: sourceFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func scaledFrame(_ frame: CGRect, scale: CGFloat) -> CGRect {
        let size = CGSize(width: frame.width * scale, height: frame.height * scale)
        return CGRect(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func localFrame(_ screenFrame: CGRect, in overlayFrame: CGRect) -> CGRect {
        screenFrame.offsetBy(dx: -overlayFrame.minX, dy: -overlayFrame.minY)
    }

    private static func overlayFrame(containing frames: [CGRect?]) -> CGRect {
        let concreteFrames = frames.compactMap { $0 }
        let unionFrame = concreteFrames.reduce(CGRect.null) { partial, frame in
            partial.isNull ? frame : partial.union(frame)
        }.insetBy(dx: -160, dy: -160)

        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(unionFrame) }) ?? NSScreen.main else {
            return unionFrame
        }

        return screen.frame
    }

    private static func snapshot(of view: NSView?) -> NSImage? {
        guard let view else { return nil }

        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }

        view.cacheDisplay(in: bounds, to: bitmap)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return image
    }
}

private final class LandingOverlayWindow: NSPanel {
    init(frame: CGRect, above onboardingWindow: NSWindow?) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if let onboardingWindow {
            level = NSWindow.Level(rawValue: onboardingWindow.level.rawValue + 2)
        } else {
            level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 3)
        }
    }
}
