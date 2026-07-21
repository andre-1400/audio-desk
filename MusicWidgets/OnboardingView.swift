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
                        .font(.system(size: 21, weight: .bold, design: .rounded))
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

                Button(action: onDismiss) {
                    Text("Got it")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(AMTheme.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(AMTheme.gradient)
                                .shadow(color: AMTheme.accent.opacity(0.35), radius: 8, y: 4)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(30)
            .frame(width: 420)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Neu.raised)
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Neu.hairline, lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 40, y: 18)
            )
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

// First-run setup flow: craft your first widget (type → form → colour → size/notes).
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var step = 0
    @State private var type: WidgetCategory = .vinyl
    @State private var vinylFormID: String = VinylStyle.forms[0].id
    @State private var cdFormID: String = CDModel.forms[0].id
    @State private var vinylStyle: WidgetThemeID = VinylStyle.forms[0].styles[0].themeID
    @State private var cdModel: CDModel = CDModel.forms[0].models[0]
    @ObservedObject private var brandM = BrandManager.shared

    private let lastStep = 3
    private var accent: Color { AMTheme.accent }

    private var selectedVinylForm: VinylForm { VinylStyle.forms.first { $0.id == vinylFormID } ?? VinylStyle.forms[0] }
    private var selectedCDForm: CDForm { CDModel.forms.first { $0.id == cdFormID } ?? CDModel.forms[0] }

    var body: some View {
        VStack(spacing: 0) {
            // progress
            HStack(spacing: 7) {
                ForEach(0...lastStep, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? accent : Neu.subtext.opacity(0.3))
                        .frame(width: i == step ? 22 : 7, height: 7)
                }
            }
            .padding(.top, 26)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: step)

            Group {
                switch step {
                case 0: intro
                case 1: typeStep
                case 2: formStep
                default: colorStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: step)
    }

    // MARK: Step 0 — intro

    private var intro: some View {
        VStack(spacing: 20) {
            HStack {
                brandToggle
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AMTheme.gradient)
                    .frame(width: 120, height: 120)
                    .shadow(color: accent.opacity(0.4), radius: 14, y: 6)
                Image(systemName: "music.note")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(AMTheme.onAccent)
            }
            VStack(spacing: 9) {
                Text("Let's set up your player")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(Neu.text)
                Text("A few quick taps to put your first widget on the desktop.")
                    .font(.system(size: 14))
                    .foregroundStyle(Neu.subtext)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.horizontal, 50)
    }

    // Brand chooser (top-left of the welcome screen). Defaults to Apple Music.
    private var brandToggle: some View {
        HStack(spacing: 8) {
            brandButton(.appleMusic, label: "Apple Music", fill: .white, ink: Color(hex: "fa233b"))
            brandButton(.spotify, label: "Spotify", fill: Color(hex: "191414"), ink: Color(hex: "1ed760"))
        }
    }

    private func brandButton(_ b: Brand, label: String, fill: Color, ink: Color) -> some View {
        let selected = brandM.brand == b
        return Button {
            withAnimation(.easeInOut(duration: 0.3)) { brandM.brand = b }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(ink).frame(width: 8, height: 8)
                Text(label).font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 13).frame(height: 32)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(ink, lineWidth: selected ? 2 : 0))
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.12), lineWidth: selected ? 0 : 1))
            .opacity(selected ? 1 : 0.6)
            .shadow(color: .black.opacity(selected ? 0.18 : 0), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: Step 1 — type

    private var typeStep: some View {
        VStack(spacing: 24) {
            title("Vinyl or CD?", "Pick the kind of player.")
            HStack(spacing: 22) {
                typeCard(.vinyl)
                typeCard(.cd)
            }
            Spacer()
        }
        .padding(.horizontal, 50)
        .padding(.top, 22)
    }

    private func typeCard(_ cat: WidgetCategory) -> some View {
        let isSel = type == cat
        return Button { type = cat } label: {
            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(Neu.well).frame(width: 92, height: 92).neuInset(46)
                    Image(systemName: cat.icon)
                        .font(.system(size: 38, weight: .ultraLight))
                        .foregroundStyle(cat.accentColor)
                }
                Text(cat.title).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(Neu.text)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 190)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isSel ? accent : .clear, lineWidth: 2)
                    .padding(1)
            )
        }
        .buttonStyle(NeuTileStyle(corner: 22))
    }

    // MARK: Step 2 — form

    private var formStep: some View {
        VStack(spacing: 22) {
            title("Which \(type.title.lowercased()) player?",
                  "Choose a body — colours come next.")
            HStack(spacing: 18) {
                if type == .vinyl {
                    ForEach(VinylStyle.forms) { form in
                        formCard(icon: form.icon, name: form.name, subtitle: form.subtitle,
                                 count: form.styles.count, selected: vinylFormID == form.id) {
                            vinylFormID = form.id
                            vinylStyle = form.styles[0].themeID
                        }
                    }
                } else {
                    ForEach(CDModel.forms) { form in
                        formCard(icon: form.icon, name: form.name, subtitle: form.subtitle,
                                 count: form.models.count, selected: cdFormID == form.id) {
                            cdFormID = form.id
                            cdModel = form.models[0]
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 44)
        .padding(.top, 22)
    }

    private func formCard(icon: String, name: String, subtitle: String, count: Int,
                          selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 13) {
                ZStack {
                    Circle().fill(Neu.well).frame(width: 70, height: 70).neuInset(35)
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(selected ? type.accentColor : Neu.text)
                }
                VStack(spacing: 3) {
                    Text(name).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Neu.text)
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(Neu.subtext)
                        .multilineTextAlignment(.center).lineLimit(2)
                }
                Text("\(count) colours")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(selected ? type.accentColor : Neu.subtext)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Neu.well))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .padding(.horizontal, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(selected ? accent : .clear, lineWidth: 2)
                    .padding(1)
            )
        }
        .buttonStyle(NeuTileStyle(corner: 20))
    }

    // MARK: Step 3 — colour

    private var colorStep: some View {
        VStack(spacing: 14) {
            title(type == .vinyl ? "\(selectedVinylForm.name) colours" : "\(selectedCDForm.name) colours",
                  "Tap a colour you like.")
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    if type == .vinyl {
                        ForEach(selectedVinylForm.styles) { s in
                            styleTile(name: s.name, selected: vinylStyle == s.themeID) {
                                VinylStylePreview(themeID: s.themeID)
                            } action: { vinylStyle = s.themeID }
                        }
                    } else {
                        ForEach(selectedCDForm.models) { m in
                            styleTile(name: m.name, selected: cdModel.id == m.id) {
                                CDModelPreview(model: m)
                            } action: { cdModel = m }
                        }
                    }
                }
                .padding(.horizontal, 44)
                .padding(.bottom, 10)
            }
        }
        .padding(.top, 18)
    }

    private func styleTile<P: View>(name: String, selected: Bool, @ViewBuilder preview: () -> P, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview()
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .background(Neu.well)
                    .neuInset(14)
                Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Neu.text)
            }
            .padding(12)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? accent : .clear, lineWidth: 2)
                    .padding(1)
            )
        }
        .buttonStyle(NeuTileStyle(corner: 18))
    }

    // MARK: Bits

    private func title(_ t: String, _ s: String) -> some View {
        VStack(spacing: 5) {
            Text(t).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Neu.text)
            Text(s).font(.system(size: 13)).foregroundStyle(Neu.subtext)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if step > 0 {
                    Button(action: back) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                            Text("Back").font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(Neu.subtext)
                        .padding(.horizontal, 20).frame(height: 46)
                    }
                    .buttonStyle(NeuTileStyle(corner: 14))
                }
                Button(action: primary) {
                    Text(step == lastStep ? "Create my widget" : "Continue")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AMTheme.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AMTheme.gradient)
                                .shadow(color: accent.opacity(0.35), radius: 8, y: 4)
                        )
                }
                .buttonStyle(.plain)
            }
            Button(action: onFinish) {
                Text("Skip setup").font(.system(size: 12, weight: .medium)).foregroundStyle(Neu.subtext.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 50)
        .padding(.bottom, 24)
    }

    // MARK: Actions

    private func back() { if step > 0 { step -= 1 } }

    private func primary() {
        if step < lastStep { step += 1 } else { create() }
    }

    private func create() {
        // Sensible default; size & musical notes are adjustable later in Settings.
        WidgetSizeManager.shared.scale = WidgetSizeManager.defaultScale
        if type == .vinyl {
            AppDelegate.shared?.launchVinylWidget(themeID: vinylStyle)
        } else {
            AppDelegate.shared?.launchCDWidget(model: cdModel)
        }
        onFinish()
    }
}
