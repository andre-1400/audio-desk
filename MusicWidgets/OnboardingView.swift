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
    @State private var showGuide = false

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
                    // Listed first on purpose: until this is granted the
                    // widget shows "Nothing Playing" no matter what, which
                    // reads as a broken app rather than a missing permission.
                    tip(icon: "checkmark.shield", title: "Say yes to the permission box",
                        text: "macOS will ask if Audio Desk can read Spotify or Music. Click Allow — without it the widget can't see your songs.")
                    tip(icon: "music.note", title: "Find it in the menu bar",
                        text: "This window closes, the ♪ icon up top stays. Click it to come back anytime.")
                    tip(icon: "hand.draw", title: "Drag it anywhere",
                        text: "Grab the widget and place it wherever it looks best on your desktop.")
                    tip(icon: "cursorarrow.click.2", title: "Right-click for quick controls",
                        text: "Right-click the widget or the menu bar icon to switch styles, hide, or tweak settings.")
                }
                .padding(.horizontal, 6)

                VStack(spacing: 10) {
                    Button("Got it") { onDismiss() }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                        .tint(AMTheme.accent)
                        .controlSize(.large)
                        .clipShape(Capsule())

                    Button("Show me how to connect Spotify or Music") { showGuide = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(AMTheme.accent)
                }
            }
            .padding(30)
            .frame(width: 420)
            .appCard(corner: 26, elevated: true)
        }
        .sheet(isPresented: $showGuide) {
            StreamingSetupGuideView { showGuide = false }
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
                    .clipShape(Capsule())
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

// MARK: - Streaming service setup guide

/// macOS asks the user to approve one app reading another app's state, and
/// until that's granted every widget sits on "Nothing Playing" — which looks
/// identical to a broken app. The grant lives several levels deep in System
/// Settings, so the steps are spelled out with the actual screenshots rather
/// than described in prose, and the same content is reused in onboarding and
/// from the sidebar so a user who skipped the intro can still find it.
enum StreamingSetupGuide {

    struct Step: Identifiable {
        let id: Int
        let text: String
        let image: String
    }

    static let steps: [Step] = [
        Step(id: 1, text: "Open System Settings and choose Privacy & Security.",
             image: "GuidePrivacySecurity"),
        Step(id: 2, text: "Scroll down and click Automation.",
             image: "GuideAutomation"),
        Step(id: 3, text: "Find Audio Desk and switch on Music and Spotify.",
             image: "GuideToggles")
    ]

    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The full walkthrough, presented as a sheet from the sidebar.
struct StreamingSetupGuideView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Connect Spotify or Apple Music")
                    .font(.appTitle)
                    .foregroundStyle(Neu.text)
                Spacer()
                Button("Done", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .tint(AMTheme.accent)
                    .controlSize(.regular)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider().overlay(Neu.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Audio Desk shows whatever is already playing. macOS just needs your permission to read it once.")
                        .font(.system(size: 13))
                        .foregroundStyle(Neu.subtext)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(StreamingSetupGuide.steps) { step in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(step.id)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(AMTheme.onAccent)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(AMTheme.accent))
                                Text(step.text)
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(Neu.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Image(step.image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Neu.hairline, lineWidth: 1)
                                )
                                .padding(.leading, 32)
                        }
                    }

                    // The list is populated lazily by macOS: an app only shows
                    // up under Automation once it has actually asked. If the
                    // user opens Settings before that has happened, the row
                    // they're looking for simply isn't there yet.
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(AMTheme.accent)
                        Text("Don't see Audio Desk in that list? Start playing a song, then quit and reopen Audio Desk so macOS adds it.")
                            .font(.system(size: 12))
                            .foregroundStyle(Neu.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AMTheme.accent.opacity(0.08))
                    )

                    Button {
                        StreamingSetupGuide.openAutomationSettings()
                    } label: {
                        Label("Open Automation Settings", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(24)
            }
        }
        .frame(width: 480, height: 560)
        .background(VisualEffectBlur(.sheet))
    }
}
