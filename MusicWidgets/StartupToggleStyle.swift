import SwiftUI

struct StartupToggleStyle: ToggleStyle {
    var onTint: Color
    var offTint: Color
    var knobTint: Color
    var borderTint: Color
    var labelSpacing: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: labelSpacing) {
                configuration.label
                Spacer(minLength: 12)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? onTint : offTint)
                        .overlay(Capsule().strokeBorder(borderTint, lineWidth: 1))
                        .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)
                    Circle()
                        .fill(knobTint)
                        .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 2)
                        .padding(3)
                }
                .frame(width: 52, height: 30)
                .accessibilityLabel("Launch On Startup")
                .accessibilityValue(configuration.isOn ? "On" : "Off")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
