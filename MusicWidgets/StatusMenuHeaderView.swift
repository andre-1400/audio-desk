import SwiftUI

struct StatusMenuHeaderView: View {
    let isWidgetVisible: Bool
    let launchOnStartupEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VinylWidgetMenuMark()

                VStack(alignment: .leading, spacing: 2) {
                    Text("Vinyl Widget")
                        .font(.custom("Georgia", size: 15))
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "f0d890"))
                    Text(isWidgetVisible ? "Widget visible" : "Widget hidden")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "b89a60"))
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(launchOnStartupEnabled ? Color(hex: "f0a030") : Color(hex: "7a6040"))
                    .frame(width: 6, height: 6)
                Text(launchOnStartupEnabled ? "Launches on startup" : "Startup launch off")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "b89a60"))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 260, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(hex: "2a1a0a"), Color(hex: "170e06")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct VinylWidgetMenuMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "4a2a12"), Color(hex: "1f1208")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color(hex: "d8b97e").opacity(0.34), lineWidth: 1)
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "343434"), Color(hex: "090909"), Color.black],
                        center: UnitPoint(x: 0.38, y: 0.34),
                        startRadius: 1,
                        endRadius: 15
                    )
                )
                .frame(width: 30, height: 30)
                .offset(x: -3, y: 2)

            Circle()
                .stroke(Color.white.opacity(0.13), lineWidth: 1)
                .frame(width: 20, height: 20)
                .offset(x: -3, y: 2)

            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                .frame(width: 13, height: 13)
                .offset(x: -3, y: 2)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "d17a32"), Color(hex: "7a3515")],
                        center: .center,
                        startRadius: 1,
                        endRadius: 5
                    )
                )
                .frame(width: 8, height: 8)
                .offset(x: -3, y: 2)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "f1d690"), Color(hex: "a9782c")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 24)
                .rotationEffect(.degrees(-24))
                .offset(x: 13, y: -3)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(hex: "2b2b2b"))
                .frame(width: 7, height: 5)
                .rotationEffect(.degrees(-24))
                .offset(x: 17, y: 9)
        }
        .frame(width: 42, height: 42)
        .shadow(color: .black.opacity(0.28), radius: 7, x: 0, y: 4)
    }
}
