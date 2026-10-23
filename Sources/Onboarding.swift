import AppKit
import SwiftUI

/// Einrichtung beim ersten Start: Die Katze stellt sich vor, bekommt einen Namen, ihr Fell und ihr Zuhause,
/// dann die wichtigsten Erinnerungen und eine kleine Einführung. Ein Schritt pro Seite.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.delegate = self
            self.window = window
        }
        // Jedes Mal von vorne
        window?.contentView = NSHostingView(rootView: OnboardingView(settings: settings) { [weak self] in
            self?.window?.close()
        })
        window?.title = L10n.s("Willkommen bei Pixelcat", "Welcome to Pixelcat")
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Auch wer das Fenster einfach schließt, bekommt es nicht noch einmal ungefragt
    func windowWillClose(_ notification: Notification) {
        settings.onboardingDone = true
    }
}

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, name, coat, home, reminders, petting, menu, done
    }

    @ObservedObject var settings: AppSettings
    var onFinish: () -> Void
    @State private var step: Step
    @State private var forward = true

    static let maxNameLength = 16

    init(settings: AppSettings, start: Step = .welcome, onFinish: @escaping () -> Void = {}) {
        self.settings = settings
        self.onFinish = onFinish
        _step = State(initialValue: start)
    }

    private func t(_ de: String, _ en: String) -> String { L10n.s(de, en) }

    var body: some View {
        ZStack {
            PixelBackdrop(opacity: 0.06)
            LinearGradient(colors: [Color.orange.opacity(0.14), Color.pink.opacity(0.06), Color.clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                ZStack {
                    page(step)
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                footer
            }
        }
        .frame(width: 620, height: 500)
        .ignoresSafeArea()
    }

    // MARK: Seiten

    @ViewBuilder
    private func page(_ step: Step) -> some View {
        switch step {
        case .welcome:
            OnboardingPage(title: t("Hallo!", "Hi there!"),
                           text: t("Ich bin deine neue Pixelkatze und wohne ab jetzt auf deinem Dock.",
                                   "I'm your new pixel cat. From now on I live on your Dock.")) {
                PixelCat(coat: settings.coat, pose: .sit, scale: 7)
            }
        case .name:
            OnboardingPage(title: t("Wie soll ich heißen?", "What's my name?"),
                           text: t("Gib mir einen Namen. Du kannst ihn später ändern.",
                                   "Give me a name. You can change it later.")) {
                PixelCat(coat: settings.coat, pose: .sit, scale: 5)
            } below: {
                NameField(settings: settings)
            }
        case .coat:
            OnboardingPage(title: t("Welches Fell steht mir?", "Which coat suits me?"),
                           text: t("Schau mal aufs Dock. Ich ziehe mich gleich um.",
                                   "Take a look at the Dock. I change right away.")) {
                HStack(spacing: 18) {
                    ForEach(Coat.allCases, id: \.self) { coat in
                        ChoiceCard(selected: settings.coat == coat, title: coat.title) {
                            PixelCat(coat: coat, pose: .sit, scale: 4)
                        } action: {
                            settings.coat = coat
                        }
                    }
                }
            }
        case .home:
            OnboardingPage(title: t("Wo darf ich wohnen?", "Where may I live?"),
                           text: settings.basketInDock
                               ? t("Ich schlafe im Korb und komme zu Pausen heraus.",
                                   "I sleep in my bed and come out for breaks.")
                               : t("Ich laufe auf dem Dock herum und mache Nickerchen.",
                                   "I stroll along the Dock and take naps.")) {
                HStack(spacing: 22) {
                    ChoiceCard(selected: !settings.basketInDock, title: t("Auf dem Dock", "On the Dock")) {
                        PixelCat(coat: settings.coat, pose: .walk, scale: 4)
                    } action: {
                        settings.basketInDock = false
                    }
                    ChoiceCard(selected: settings.basketInDock, title: t("Im Katzenkorb", "In my cat bed")) {
                        CatInBed(coat: settings.coat, scale: 3)
                    } action: {
                        settings.basketInDock = true
                        settings.basketNap = true
                    }
                }
            }
        case .reminders:
            OnboardingPage(title: t("Woran soll ich dich erinnern?", "What should I remind you of?"),
                           text: t("Tipp an, was dir guttut. Mehr gibt es in den Einstellungen.",
                                   "Pick what's good for you. There's more in the settings.")) {
                HStack(spacing: 14) {
                    ReminderTile(title: t("Pausen", "Breaks"), icon: "cup.and.saucer.fill", color: .brown,
                                 isOn: $settings.breakReminders)
                    ReminderTile(title: t("Trinken", "Drinking"), icon: "drop.fill", color: .blue,
                                 isOn: $settings.drinkReminders)
                    ReminderTile(title: t("Augenpause", "Eye breaks"), icon: "eye.fill", color: .teal,
                                 isOn: $settings.eyeBreaks)
                    ReminderTile(title: t("Feierabend", "Day's end"), icon: "briefcase.fill", color: .indigo,
                                 isOn: $settings.quittingTimeEnabled)
                }
            }
        case .petting:
            OnboardingPage(title: t("Streichel mich", "Pet me"),
                           text: t("Fahr mit der Maus über mich, ohne zu klicken. Dann schnurre ich.",
                                   "Move the pointer over me without clicking. Then I purr.")) {
                VStack(spacing: 6) {
                    FloatingHeart()
                    PixelCat(coat: settings.coat, pose: .petted, scale: 6)
                }
            }
        case .menu:
            OnboardingPage(title: t("Mein Menü", "My menu"),
                           text: t("Oben in der Menüleiste gibt es Futter, Wollknäuel, Pomodoro und die Einstellungen.",
                                   "Up in the menu bar you'll find food, yarn, Pomodoro and the settings.")) {
                MenuBarSketch()
            }
        case .done:
            OnboardingPage(title: t("Schön, dass ich da bin!", "Happy to be here!"),
                           text: t("\(settings.displayName) wartet unten auf dem Dock auf dich.",
                                   "\(settings.displayName) is waiting for you on the Dock.")) {
                VStack(spacing: 6) {
                    FloatingHeart()
                    PixelCat(coat: settings.coat, pose: .sleep, scale: 6)
                }
            }
        }
    }

    // MARK: Unten: Zurück, Punkte, Weiter

    private var footer: some View {
        HStack {
            Button(t("Zurück", "Back")) { go(-1) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(step == .welcome ? 0 : 1)
                .disabled(step == .welcome)
                .frame(width: 140, alignment: .leading)
            Spacer()
            HStack(spacing: 7) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: item == step ? 20 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
            Spacer()
            Button(nextTitle, action: next)
                .buttonStyle(CapsuleButtonStyle())
                .keyboardShortcut(.defaultAction)
            .frame(width: 140, alignment: .trailing)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 26)
    }

    private var nextTitle: String {
        switch step {
        case .welcome: return t("Los geht's", "Let's go")
        case .done: return t("Fertig", "Done")
        default: return t("Weiter", "Next")
        }
    }

    private func next() {
        if step == .done {
            settings.onboardingDone = true
            onFinish()
        } else {
            go(1)
        }
    }

    private func go(_ delta: Int) {
        guard let target = Step(rawValue: step.rawValue + delta) else { return }
        forward = delta > 0
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { step = target }
    }
}

// MARK: - Bausteine

/// Eine Seite: Bild, große Überschrift, ein kurzer Satz und auf Wunsch darunter ein Eingabefeld
private struct OnboardingPage<Art: View, Below: View>: View {
    let title: String
    let text: String
    let art: Art
    let below: Below

    init(title: String, text: String, @ViewBuilder art: () -> Art, @ViewBuilder below: () -> Below) {
        self.title = title
        self.text = text
        self.art = art()
        self.below = below()
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            art
                .frame(minHeight: 150, alignment: .bottom)
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.top, 28)
            Text(text)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            below
                .padding(.top, 22)
            Spacer(minLength: 20)
        }
        .padding(.horizontal, 40)
    }
}

extension OnboardingPage where Below == EmptyView {
    init(title: String, text: String, @ViewBuilder art: () -> Art) {
        self.init(title: title, text: text, art: art, below: { EmptyView() })
    }
}

/// Runder, farbiger Knopf für „Weiter“
private struct CapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.accentColor.gradient))
            .shadow(color: Color.accentColor.opacity(0.3), radius: 6, y: 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Großes Namensfeld mit ein paar Vorschlägen
private struct NameField: View {
    @ObservedObject var settings: AppSettings
    @FocusState private var focused: Bool

    private var suggestions: [String] {
        L10n.isGerman ? ["Mochi", "Luna", "Pixel", "Minka", "Tiger"] : ["Mochi", "Luna", "Pixel", "Milo", "Tiger"]
    }

    var body: some View {
        VStack(spacing: 14) {
            TextField("", text: $settings.catName, prompt: Text("Pixelcat"))
                .textFieldStyle(.plain)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .frame(width: 280)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.background.opacity(0.9)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(focused ? 0.8 : 0.25), lineWidth: 2))
                .focused($focused)
                .onChange(of: settings.catName) { value in
                    if value.count > OnboardingView.maxNameLength {
                        settings.catName = String(value.prefix(OnboardingView.maxNameLength))
                    }
                }
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { name in
                    Button(name) { settings.catName = name }
                        .buttonStyle(.plain)
                        .font(.system(.callout, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(settings.catName == name
                                                   ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12)))
                }
            }
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

/// Auswahlkarte mit Bild und Titel, die ausgewählte leuchtet
private struct ChoiceCard<Art: View>: View {
    let selected: Bool
    let title: String
    @ViewBuilder var art: Art
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                art
                    .frame(width: 130, height: 100, alignment: .bottom)
                Text(title)
                    .font(.system(.callout, design: .rounded).weight(.medium))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.background.opacity(selected ? 0.95 : 0.55)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selected ? 3 : 1))
            .shadow(color: .black.opacity(selected ? 0.12 : 0), radius: 8, y: 3)
            .scaleEffect(selected ? 1.04 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Eine Erinnerung zum Antippen: an oder aus
private struct ReminderTile: View {
    let title: String
    let icon: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isOn ? .white : color)
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isOn ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.15))))
                Text(title)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .frame(width: 112, height: 140)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.background.opacity(isOn ? 0.95 : 0.55)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isOn ? color.opacity(0.7) : Color.secondary.opacity(0.2), lineWidth: isOn ? 2 : 1))
            .scaleEffect(isOn ? 1.03 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOn)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Die Katze schlafend im Korb
private struct CatInBed: View {
    let coat: Coat
    let scale: CGFloat

    var body: some View {
        let art = BasketArt.shared
        ZStack(alignment: .bottom) {
            PixelSprite(sprite: art.back, colors: BasketArt.colors, scale: scale)
            PixelCat(coat: coat, pose: .sleep, scale: scale)
                .padding(.bottom, CGFloat(art.catY) * scale)
            PixelSprite(sprite: art.front, colors: BasketArt.colors, scale: scale)
        }
    }
}

/// Ein Herz, das sanft auf und ab schwebt
private struct FloatingHeart: View {
    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            PixelSprite(sprite: PixelArt.heart, colors: ["K": NSColor.systemPink.cgColor], scale: 4)
                .offset(y: CGFloat(sin(phase * 2.2) * 4))
        }
        .frame(height: 32)
    }
}

/// Eine angedeutete Menüleiste mit dem Katzensymbol und dem aufgeklappten Menü
private struct MenuBarSketch: View {
    private func t(_ de: String, _ en: String) -> String { L10n.s(de, en) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 14) {
                Image(systemName: "wifi")
                Image(systemName: "battery.75")
                Image(nsImage: Frames.menuBarIcon())
                    .renderingMode(.template)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.3)))
                Text("9:41")
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .frame(width: 320, height: 26, alignment: .trailing)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.background.opacity(0.8)))
            VStack(alignment: .leading, spacing: 6) {
                menuRow(t("Füttern", "Feed"), "fork.knife")
                menuRow(t("Mit Wollknäuel spielen", "Play with yarn"), "circle.dotted")
                menuRow("Pomodoro", "timer")
                Divider()
                menuRow(t("Einstellungen …", "Settings …"), "gearshape")
            }
            .font(.system(size: 13))
            .padding(12)
            .frame(width: 220, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.background.opacity(0.92)))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .padding(.trailing, 46)
        }
    }

    private func menuRow(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 16).foregroundStyle(.secondary)
            Text(title)
        }
    }
}
