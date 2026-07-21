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

/// The shared "Adaptive" look, used by every adaptive style in the app (vinyl,
/// vinyl horizontal, CD) so they can't drift apart: the widget body is the
/// album art, heavily blurred, slightly zoomed in and knocked back, with
/// foreground colours picked for contrast against it.
enum AdaptiveBody {
    /// Flat black scrim over the blurred art. Keeps the artwork's hue and
    /// internal shading while taking the edge off bright covers. Flat rather
    /// than a gradient on purpose — an evenly lit body gives one well-defined
    /// brightness for the contrast decision below.
    static let darkening: Double = 0.40

    /// Slight zoom so the body shows the middle of the cover rather than its
    /// full frame — keeps the softest part of the blur in view.
    static let zoom: CGFloat = 1.18

    /// 0.48, not the 0.58 of Color.isPerceivedLight: checked against WCAG
    /// contrast ratios across a spread of cover colours (re-checked after
    /// darkening moved 0.30 -> 0.40, which shifted the safe threshold down
    /// slightly), 0.48 picks whichever of white/black actually has the better
    /// contrast on every one of them, while 0.58 gets mid-light covers (e.g.
    /// pale pink) wrong.
    ///
    /// Note this measures the body *as drawn* — compositing black at alpha a
    /// scales the components by (1 - a), so the scrim scales perceived
    /// brightness the same way. Deciding against the raw artwork instead would
    /// leave dark text on covers that the scrim has already darkened.
    static func isLight(_ dominant: Color) -> Bool {
        dominant.perceivedBrightness * (1 - darkening) > 0.48
    }

    static func primary(_ dominant: Color) -> Color {
        isLight(dominant) ? Color.black.opacity(0.88) : .white
    }

    static func secondary(_ dominant: Color) -> Color {
        isLight(dominant) ? Color.black.opacity(0.58) : Color.white.opacity(0.72)
    }
}

/// Draws the blurred artwork as a widget body. Expects art already blurred by
/// ArtBlurrer (cached per track by the caller) — never blurs per frame.
struct AdaptiveBodyFill: View {
    let blurredArt: NSImage?
    let size: CGSize

    var body: some View {
        if let blurredArt {
            Image(nsImage: blurredArt)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .scaleEffect(AdaptiveBody.zoom)
                .clipped()
                .overlay(Color.black.opacity(AdaptiveBody.darkening))
        }
    }
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

        guard let blurred = blur.outputImage?.cropped(to: scaled.extent) else { return nil }

        // 3. Boost saturation — adaptively, not by a fixed amount.
        //
        // A fixed boost helps a cover with a large pale background (the blur
        // physically blends those pale pixels into the accent colour, same
        // dilution a naive colour average suffers from) but actively hurts a
        // busy, multi-hue cover: averaging genuinely different large regions
        // (e.g. sky + trees + dirt) lands on a muddy intermediate hue that
        // isn't "the" colour of anything in the image, and boosting THAT
        // just makes an arbitrary wrong hue more prominent. A real cover of
        // this shape (illustrated scene, no single dominant colour) measured
        // pre-boost at sat 0.271 — already "coloured enough" — and a fixed
        // 1.8x boost dragged it to a shouty sat 0.62 olive/brown that had
        // nothing to do with the artwork's actual look.
        //
        // So the boost scales down as the unboosted blur's own saturation
        // rises: full 1.8x at/below the washed-out anchor (sat 0.150, a real
        // cream-sleeve cover, the case that motivated boosting at all), down
        // to 1.0x (no boost) by sat 0.271 (the busy-cover anchor above), and
        // clamped to that floor beyond it. A near-grey cover sits below the
        // low anchor, so it still gets the full boost — harmless, since
        // boosting a near-zero saturation barely moves it either way.
        guard let averageFilter = CIFilter(name: "CIAreaAverage") else { return nil }
        averageFilter.setValue(blurred, forKey: kCIInputImageKey)
        averageFilter.setValue(CIVector(cgRect: scaled.extent), forKey: "inputExtent")
        guard let averageImage = averageFilter.outputImage else { return nil }
        var avgPixel = [UInt8](repeating: 0, count: 4)
        context.render(averageImage, toBitmap: &avgPixel, rowBytes: 4,
                        bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                        format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let avgR = Double(avgPixel[0]) / 255, avgG = Double(avgPixel[1]) / 255, avgB = Double(avgPixel[2]) / 255
        let maxC = max(avgR, avgG, avgB), minC = min(avgR, avgG, avgB)
        let preBoostSaturation = maxC == 0 ? 0 : (maxC - minC) / maxC

        let washedOutAnchor = 0.150, busyAnchor = 0.271
        let slope = (1.0 - 1.8) / (busyAnchor - washedOutAnchor)
        let saturationBoost = min(1.8, max(1.0, 1.8 + slope * (preBoostSaturation - washedOutAnchor)))

        guard let colorControls = CIFilter(name: "CIColorControls") else { return nil }
        colorControls.setValue(blurred, forKey: kCIInputImageKey)
        colorControls.setValue(saturationBoost, forKey: kCIInputSaturationKey)
        guard let boosted = colorControls.outputImage?.cropped(to: scaled.extent) else { return nil }

        guard let rendered = context.createCGImage(boosted, from: scaled.extent)
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

        // Weight by saturation rather than a flat average. A cover with a
        // large pale/neutral background (e.g. a cream sleeve with a small
        // vivid accent) would otherwise average toward that background —
        // measured against a real cover of this shape, a flat average landed
        // at #EED8B1 (sat 0.25) where saturation-weighting landed at #E58D3C
        // (sat 0.74), much closer to the actual accent colour. Low-saturation
        // covers (near-grey/monochrome) are barely affected — the floor
        // weight keeps every pixel counting for something.
        var weightedR = 0.0, weightedG = 0.0, weightedB = 0.0, totalWeight = 0.0
        for p in pixels {
            let maxC = max(p.r, p.g, p.b), minC = max(p.r, p.g, p.b) == 0 ? 0 : min(p.r, p.g, p.b)
            let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC
            let weight = 0.05 + pow(saturation, 3) * 6.0
            weightedR += p.r * weight
            weightedG += p.g * weight
            weightedB += p.b * weight
            totalWeight += weight
        }
        let avgR = weightedR / totalWeight
        let avgG = weightedG / totalWeight
        let avgB = weightedB / totalWeight
        let dominant = Color(red: avgR, green: avgG, blue: avgB)

        // Secondary: darken the average by 40%
        let secondary = Color(red: avgR * 0.6, green: avgG * 0.6, blue: avgB * 0.6)

        return ExtractedColours(dominant: dominant, secondary: secondary)
    }
}
