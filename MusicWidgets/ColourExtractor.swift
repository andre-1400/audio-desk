import AppKit
import SwiftUI
import CoreImage

struct ExtractedColours: Equatable {
    let dominant: Color
    let secondary: Color

    static let fallback = ExtractedColours(
        dominant: Color(hex: "9B5523"),
        secondary: Color(hex: "3a1a06")
    )

    /// Neutral grey/white — used only for Adaptive's gallery preview and its
    /// initial pre-playback state, so it doesn't read as "this style is
    /// brown," which .fallback (used for genuine extraction failures
    /// elsewhere) would suggest. Signals "this becomes whatever's playing"
    /// instead of implying a fixed colour.
    static let adaptivePreviewPlaceholder = ExtractedColours(
        dominant: Color(hex: "e4e4e6"),
        secondary: Color(hex: "9a9a9e")
    )
}

extension Color {
    /// Perceived (luma) brightness 0...1, used to pick readable text colour
    /// against a colour we don't control (e.g. Adaptive mode's album-art tint).
    var perceivedBrightness: Double {
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        return Double(ns.redComponent) * 0.299 + Double(ns.greenComponent) * 0.587 + Double(ns.blueComponent) * 0.114
    }
    var isPerceivedLight: Bool { perceivedBrightness > 0.58 }
}

/// Produces the heavily-blurred version of the album art used as the Adaptive
/// theme's widget body. Downscales first, then blurs — a small image blurred by
/// a proportionally small radius looks identical to the full-size version once
/// it's this soft, and costs a fraction of the work. Results are cached by the
/// caller (one per track), so this never runs per frame.
enum ArtBlurrer {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func blurredBody(from image: NSImage, targetSize: CGSize = CGSize(width: 160, height: 160)) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        // 1. Downscale to a small square (the body is drawn with scaledToFill,
        //    so aspect distortion here is invisible once blurred this far).
        let scaled = CIImage(cgImage: cgImage).transformed(by: CGAffineTransform(
            scaleX: targetSize.width / CGFloat(cgImage.width),
            y: targetSize.height / CGFloat(cgImage.height)
        ))

        // 2. Clamp before blurring, otherwise the edges bleed to transparent
        //    and the body gets a washed-out border.
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return nil }
        blur.setValue(scaled.clampedToExtent(), forKey: kCIInputImageKey)
        blur.setValue(targetSize.width * 0.14, forKey: kCIInputRadiusKey)

        guard let output = blur.outputImage?.cropped(to: scaled.extent),
              let rendered = context.createCGImage(output, from: scaled.extent)
        else { return nil }

        return NSImage(cgImage: rendered, size: targetSize)
    }
}

enum ColourExtractor {
    /// Samples pixels from an NSImage and returns the dominant and secondary colours.
    static func extract(from image: NSImage) -> ExtractedColours {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .fallback
        }

        let width = 10
        let height = 10
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return .fallback
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Collect all pixel colours with their brightness
        var pixels: [(r: Double, g: Double, b: Double, brightness: Double)] = []
        for i in 0..<(width * height) {
            let offset = i * bytesPerPixel
            let r = Double(pixelData[offset]) / 255.0
            let g = Double(pixelData[offset + 1]) / 255.0
            let b = Double(pixelData[offset + 2]) / 255.0
            let brightness = r * 0.299 + g * 0.587 + b * 0.114
            // Skip very dark or very bright pixels (not useful for tinting)
            if brightness > 0.05 && brightness < 0.95 {
                pixels.append((r, g, b, brightness))
            }
        }

        guard !pixels.isEmpty else { return .fallback }

        // Average all qualifying pixels for dominant colour
        let avgR = pixels.map(\.r).reduce(0, +) / Double(pixels.count)
        let avgG = pixels.map(\.g).reduce(0, +) / Double(pixels.count)
        let avgB = pixels.map(\.b).reduce(0, +) / Double(pixels.count)
        let dominant = Color(red: avgR, green: avgG, blue: avgB)

        // Secondary: darken the average by 40%
        let secondary = Color(red: avgR * 0.6, green: avgG * 0.6, blue: avgB * 0.6)

        return ExtractedColours(dominant: dominant, secondary: secondary)
    }
}
