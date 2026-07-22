import SwiftUI

/// Full manual colour picker: a hue strip, a saturation×brightness square,
/// and an intensity slider, bound to an HSVColor. Plain SwiftUI drag
/// gestures throughout — this only ever appears inside a sheet, which isn't
/// movable-by-background, so there's no window-drag conflict to guard
/// against here (unlike the desktop widgets' own scrub bars/sliders).
struct HSVColorPickerView: View {
    @Binding var value: HSVColor

    var body: some View {
        VStack(spacing: 18) {
            saturationBrightnessSquare
            hueSlider
            intensitySlider
        }
    }

    // MARK: - Saturation × Brightness square

    private var saturationBrightnessSquare: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                // Base: the pure hue at full saturation/brightness.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(value.pureHue)
                // Saturation: white (desaturated) on the left fading to
                // transparent on the right.
                LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                // Brightness: transparent at the top fading to black at the
                // bottom.
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)

                let knob = CGPoint(x: value.saturation * size.width, y: (1 - value.brightness) * size.height)
                Circle()
                    .fill(value.color)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .position(knob)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        value.saturation = min(1, max(0, drag.location.x / size.width))
                        value.brightness = min(1, max(0, 1 - drag.location.y / size.height))
                    }
            )
        }
        .frame(height: 200)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Neu.hairline, lineWidth: 1)
        )
    }

    // MARK: - Hue slider

    private var hueSlider: some View {
        let hues = stride(from: 0.0, through: 1.0, by: 1.0 / 12).map { Color(hue: $0, saturation: 1, brightness: 1) }
        return GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: hues, startPoint: .leading, endPoint: .trailing))
                sliderKnob(color: value.pureHue)
                    .offset(x: min(width - 11, max(-11, value.hue * width - 11)))
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        value.hue = min(1, max(0, drag.location.x / width))
                    }
            )
        }
        .frame(height: 22)
    }

    // MARK: - Intensity slider

    private var intensitySlider: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(
                    LinearGradient(colors: [Color(white: 0.5), value.rawColor], startPoint: .leading, endPoint: .trailing)
                )
                sliderKnob(color: value.color)
                    .offset(x: min(width - 11, max(-11, value.intensity * width - 11)))
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        value.intensity = min(1, max(0, drag.location.x / width))
                    }
            )
        }
        .frame(height: 22)
    }

    private func sliderKnob(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 22, height: 22)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

/// Label + the picker + a live swatch, matching the visual language used
/// elsewhere in Settings/the gallery.
struct LabeledColorPicker: View {
    @Binding var value: HSVColor
    // Every colour actually placed on the desktop before, across every
    // family — tapping one jumps straight back to it instead of re-mixing
    // it from scratch.
    @ObservedObject private var customColors = CustomColorManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tone").font(.system(size: 13, weight: .semibold)).foregroundStyle(Neu.text)
                    if !customColors.recentColors.isEmpty {
                        recentSwatches
                    }
                }
                Spacer(minLength: 8)
                Circle().fill(value.color).frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(Neu.hairline, lineWidth: 1))
            }
            HSVColorPickerView(value: $value)

            pickerRow(title: "Intensity", subtitle: "How strongly the colour reads versus neutral grey")
        }
    }

    /// Small tappable circles for every colour previously placed on the
    /// desktop, most recent first. Selecting one loads it straight into the
    /// live picker (still live-bound, so it saves/applies immediately, same
    /// as any other drag).
    private var recentSwatches: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(customColors.recentColors, id: \.self) { swatch in
                    Button {
                        value = swatch
                    } label: {
                        Circle().fill(swatch.color).frame(width: 18, height: 18)
                            .overlay(
                                Circle().strokeBorder(swatch == value ? Color.white : Neu.hairline,
                                                       lineWidth: swatch == value ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func pickerRow(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Neu.text)
            Text(subtitle).font(.system(size: 10.5)).foregroundStyle(Neu.subtext)
        }
    }
}
