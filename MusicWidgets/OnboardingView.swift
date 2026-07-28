import SwiftUI

// MARK: - One-time welcome tips (shown in the gallery right after onboarding)

enum WelcomeTips {
    static let key = "tips.shown.v1"
    static var shouldShow: Bool { !UserDefaults.standard.bool(forKey: key) }
    static func markSeen() { UserDefaults.standard.set(true, forKey: key) }
}

/// A small, warm "good to know" card floated over the gallery exactly once.
/// Not a tutorial wall — three tips and a button.
struct WelcomeTipsCard: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Dimmed backdrop; click anywhere to dismiss
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AMTheme.gradient)
                        .frame(width: 62, height: 62)
                        .shadow(color: AMTheme.accent.opacity(0.4), radius: 10, y: 4)
                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(AMTheme.onAccent)
                }

                VStack(spacing: 6) {
                    Text("Your widget is live!")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Neu.text)
                    Text("Three things worth knowing:")
                        .font(.system(size: 13))
                        .foregroundStyle(Neu.subtext)
                }

                VStack(alignment: .leading, spacing: 16) {
                    tip(icon: "music.note", title: "Find it in the menu bar",
                        text: "This window closes, the ♪ icon up top stays. Click it to come back anytime.")
                    tip(icon: "hand.draw", title: "Drag it anywhere",
                        text: "Grab the widget and place it wherever it looks best on your desktop.")
                    tip(icon: "cursorarrow.click.2", title: "Right-click for quick controls",
                        text: "Right-click the widget or the menu bar icon to switch styles, hide, or tweak settings.")
                }
                .padding(.horizontal, 6)

                Button("Got it") { onDismiss() }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .tint(AMTheme.accent)
                    .controlSize(.large)
                    .buttonBorderShape(.capsule)
            }
            .padding(30)
            .frame(width: 420)
            .appCard(corner: 26, elevated: true)
        }
    }

    private func tip(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AMTheme.accent.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AMTheme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Neu.text)
                Text(text).font(.system(size: 12)).foregroundStyle(Neu.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// First-run-only welcome screen — Apple's own "Hello" greeting-rotation
/// pattern (macOS/iOS Setup Assistant) instead of a multi-step widget-setup
/// quiz. Picking a widget is exactly as fast from the gallery grid itself,
/// so there's nothing to front-load here; this is purely a one-time,
/// one-tap-to-dismiss welcome.
struct OnboardingView: View {
    let onFinish: () -> Void

    private static let greetings = ["Hello", "Привет", "Hola", "你好", "مرحباً"]
    @State private var greetingIndex = 0

    private let timer = Timer.publish(every: 2.2, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // No opaque fill of our own — this sits directly over
            // ContentView's own window vibrancy, plus a soft ambient glow
            // for atmosphere; that's the closest this app can get to
            // Apple's own blurred "Hello" backdrop without a bespoke image.
            RadialGradient(colors: [AMTheme.accent.opacity(0.09), .clear],
                           center: .center, startRadius: 40, endRadius: 440)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                // Placeholder mark — swap for the real logo once the app
                // is renamed; "logo" stands in for it everywhere for now.
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(AMTheme.gradient)
                        .frame(width: 104, height: 104)
                        .shadow(color: AMTheme.accent.opacity(0.4), radius: 16, y: 8)
                    Text("logo")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AMTheme.onAccent)
                }

                // Rotating greeting — `.id` on the changing string forces a
                // fresh view identity each time, so the transition below
                // actually plays as a cross-fade instead of the text just
                // jumping to the next word.
                Text(Self.greetings[greetingIndex])
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(Neu.text)
                    .id(greetingIndex)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .frame(height: 70)

                Text("Welcome to Audio Desk")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Neu.subtext)

                Spacer()

                Button("Continue") { onFinish() }
                    .buttonStyle(.borderedProminent)
                    .tint(AMTheme.accent)
                    .controlSize(.large)
                    .buttonBorderShape(.capsule)
                    .padding(.bottom, 54)
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.7)) {
                greetingIndex = (greetingIndex + 1) % Self.greetings.count
            }
        }
    }
}
