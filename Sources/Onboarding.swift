import AppKit
import Combine
import SwiftUI

/// Einrichtung beim ersten Start: Die Katze stellt sich vor, bekommt einen Namen, ihr Fell und ihr Zuhause,
/// dann die wichtigsten Erinnerungen und eine kleine Einführung. Ein Schritt pro Seite.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: AppSettings
    private var coatWatch: AnyCancellable?
    /// Fenster zu: Jetzt darf die Katze aufs Dock
    var onClose: (() -> Void)?
    /// Mit „Fertig“: Die Katze springt aus dem Fenster aufs Dock (wo sie steht, in Bildschirmpunkten),
    /// danach das Zuhause übernehmen
    var onDrop: ((NSRect, @escaping () -> Void) -> Void)?
    private var dropping = false

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
            // Hell oder dunkel je nach Fell, auch während man es aussucht
            coatWatch = settings.$coat.sink { [weak window] coat in window?.appearance = coat.appearance }
        }
        // Jedes Mal von vorne
        window?.alphaValue = 1
        window?.contentView = NSHostingView(rootView: OnboardingView(settings: settings) { [weak self] rect, apply in
            self?.finish(catRect: rect, apply: apply)
        })
        window?.title = L10n.s("Willkommen bei Pixelcat", "Welcome to Pixelcat")
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Auch wer das Fenster einfach schließt, bekommt es nicht noch einmal ungefragt
    func windowWillClose(_ notification: Notification) {
        settings.onboardingDone = true
        if !dropping { onClose?() }
        dropping = false
        // Inhalt verwerfen: Die kleinen Animationen sollen nicht im Verborgenen weiterlaufen
        window?.contentView = NSView()
    }

    /// „Fertig“: Die Katze springt heraus, das Fenster blendet aus und schließt sich.
    private func finish(catRect: CGRect?, apply: @escaping () -> Void) {
        guard let window, let content = window.contentView, let catRect, catRect.width > 0, onDrop != nil else {
            self.window?.close()
            apply()
            return
        }
        // SwiftUI misst von oben links
        let local = content.isFlipped ? catRect
            : NSRect(x: catRect.minX, y: content.bounds.height - catRect.maxY, width: catRect.width, height: catRect.height)
        let onScreen = window.convertToScreen(content.convert(local, to: nil))
        dropping = true
        onDrop?(onScreen, apply)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            window.animator().alphaValue = 0
        }, completionHandler: { [weak window] in
            MainActor.assumeIsolated { window?.close() }
        })
    }
}

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, language, name, coat, home, bedAccess, reminders, motivation
        /// Kleine Führung: was sie kann
        case tourReminders, tourTasks, tourAway, petting, menu, done

        /// Die Frage nach der Freigabe gehört zum Zuhause und bekommt keinen eigenen Punkt
        static var dots: [Step] { allCases.filter { $0 != .bedAccess } }
    }

    @ObservedObject var settings: AppSettings
    /// Fertig: wo die Katze im Fenster steht (für den Sprung aufs Dock) und was danach zu übernehmen ist
    var onFinish: (CGRect?, @escaping () -> Void) -> Void
    @State private var step: Step
    /// „Fertig“ gedrückt: Sie wacht auf und steht auf, dann springt sie hinaus
    @State private var wokeAt: Date?
    @State private var jumped = false
    @State private var catFrame: CGRect = .zero
    @State private var forward = true
    /// Das Zuhause gilt erst am Ende, wenn die Katze aufs Dock kommt
    @State private var home: Home

    static let maxNameLength = 16

    init(settings: AppSettings, start: Step = .welcome,
         onFinish: @escaping (CGRect?, @escaping () -> Void) -> Void = { _, apply in apply() }) {
        self.settings = settings
        self.onFinish = onFinish
        _step = State(initialValue: start)
        _home = State(initialValue: Home(settings))
    }

    private func t(_ de: String, _ en: String) -> String { L10n.s(de, en) }

    var body: some View {
        ZStack {
            PixelBackdrop(coat: settings.coat, opacity: 0.06)
            if settings.coat == .black {
                LinearGradient(colors: [Color.orange.opacity(0.14), Color.pink.opacity(0.06), Color.clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
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
        .frame(minWidth: 620, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
        .ignoresSafeArea()
        .environment(\.colorScheme, settings.coat.colorScheme)
        .animation(.easeInOut(duration: 0.35), value: settings.coat)
    }

    // MARK: Seiten

    @ViewBuilder
    private func page(_ step: Step) -> some View {
        switch step {
        case .language:
            OnboardingPage(title: t("Deutsch oder Englisch?", "English or German?"),
                           text: t("Wähle deine Sprache.", "Choose your language.")) {
                PixelCat(coat: settings.coat, pose: .sit, scale: 4)
            } below: {
                HStack(spacing: 18) {
                    ForEach([Language.german, Language.english], id: \.self) { language in
                        ChoiceCard(selected: L10n.isGerman == (language == .german), title: language.title, artHeight: 44) {
                            Text(language == .german ? "Hallo!" : "Hello!")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                        } action: {
                            settings.language = language
                        }
                    }
                }
            }
        case .welcome:
            OnboardingPage(title: t("Hallo!", "Hi there!"),
                           text: t("Ich bin deine neue Pixelkatze und wohne ab jetzt auf deinem Dock.",
                                   "I'm your new pixel cat. From now on I live on your Dock.")) {
                PlayfulCat(coat: settings.coat, scale: 6)
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
                           text: t("Alle drei sind sehr gemütlich. Du kannst es später ändern.",
                                   "All three are very cozy. You can change it later.")) {
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
            OnboardingPage(title: t("Wo darf ich wohnen?", "Where may I live?"), text: homeText) {
                HStack(spacing: 14) {
                    ChoiceCard(selected: home == .bed, title: t("Im Katzenkorb", "In my cat bed")) {
                        CatInBed(coat: settings.coat, scale: 3)
                    } action: {
                        home = .bed
                    }
                    ChoiceCard(selected: home == .dock, title: t("Auf dem Dock", "On the Dock")) {
                        PixelCat(coat: settings.coat, pose: .walk, scale: 4)
                    } action: {
                        home = .dock
                    }
                    ChoiceCard(selected: home == .roaming, title: t("Auf Streifzug", "Roaming")) {
                        SneakingOut(coat: settings.coat, scale: 3.5)
                    } action: {
                        home = .roaming
                    }
                }
            }
        case .bedAccess:
            OnboardingPage(title: t("Soll ich meinen Korb genau finden?", "Shall I find my bed exactly?"),
                           text: t("Dafür fragt macOS einmal nach den Bedienungshilfen. Ohne schätze ich, wo er steht.",
                                   "macOS will ask once for Accessibility access. Without it I estimate where it is.")) {
                CatInBed(coat: settings.coat, scale: 4)
            } below: {
                HStack(spacing: 14) {
                    Button(t("Nein, schätzen", "No, estimate")) { go(1) }
                        .buttonStyle(CapsuleButtonStyle(prominent: false))
                    Button(t("Ja, genau finden", "Yes, find it")) {
                        DockLocator.requestTrust()
                        go(1)
                    }
                    .buttonStyle(CapsuleButtonStyle())
                }
            }
        case .reminders:
            OnboardingPage(title: t("Woran soll ich dich erinnern?", "What should I remind you of?"),
                           text: t("Tipp an, was dir guttut. Mehr gibt es in den Einstellungen.",
                                   "Pick what's good for you. There's more in the settings.")) {
                HStack(spacing: 10) {
                    ReminderTile(title: t("Pausen", "Breaks"), icon: "cup.and.saucer.fill", color: .brown,
                                 isOn: $settings.breakReminders)
                    ReminderTile(title: t("Trinken", "Drinking"), icon: "drop.fill", color: .blue,
                                 isOn: $settings.drinkReminders)
                    ReminderTile(title: t("Augenpause", "Eye breaks"), icon: "eye.fill", color: .teal,
                                 isOn: $settings.eyeBreaks)
                    ReminderTile(title: t("Feierabend", "Day's end"), icon: "briefcase.fill", color: .indigo,
                                 isOn: $settings.quittingTimeEnabled)
                    ReminderTile(title: t("Motivation", "Motivation"), icon: "sparkles", color: .orange,
                                 isOn: $settings.motivationEnabled)
                }
            }
        case .motivation:
            OnboardingPage(title: t("Was motiviert dich?", "What keeps you going?"),
                           text: t("Schreib ein paar Sätze auf, die dir Mut machen. Ich denke morgens und vor Feierabend daran.",
                                   "Write down a few lines that lift you up. I'll think of them in the morning and before you finish."),
                           compact: true) {
                // Etwas kleiner als sonst, damit unten Platz für die Sprüche bleibt
                VStack(spacing: 2) {
                    PixelSprite(sprite: BubbleFrames(text: settings.motivationSayings.last ?? t("Du schaffst das!", "You've got this!")).whole,
                                colors: BubbleFrames.colors, scale: 2)
                        .offset(x: 12)
                    PixelCat(coat: settings.coat, pose: .sit, scale: 3)
                }
            } below: {
                SayingsEditor(settings: settings)
            }
        case .tourReminders:
            OnboardingPage(title: t("Ich erinnere dich", "I remind you"),
                           text: t("An Pausen, ans Trinken, an deine Augen und an den Feierabend. Ganz sanft, mit einer Gedankenblase.",
                                   "To take breaks, drink, rest your eyes and call it a day. Gently, with a thought bubble.")) {
                HStack(alignment: .bottom, spacing: 26) {
                    PixelSprite(sprite: LookoutArt.frames[6], colors: LookoutArt.colors, scale: 3)
                    ThinkingCat(coat: settings.coat, thought: t("PAUSE", "BREAK"))
                    PixelSprite(sprite: Frames.waterFullA, colors: PropColors.colors, scale: 6)
                }
            }
        case .tourTasks:
            OnboardingPage(title: t("Ich merke mir Dinge", "I remember things"),
                           text: t("Trag Aufgaben mit Uhrzeit ein und ich denke für dich daran. Und morgens und abends gibt es einen Spruch zur Motivation.",
                                   "Add tasks with a time and I'll think of them for you. In the morning and evening I also cheer you on.")) {
                ThinkingCat(coat: settings.coat, thought: t("Mama anrufen", "Call mom"))
            }
        case .tourAway:
            OnboardingPage(title: t("Immer da oder unterwegs?", "Always here or out and about?"),
                           text: t("Das stellst du in den Einstellungen ein. Mit Streifzug oder Katzenkorb komme ich nur zu Pausen und Erinnerungen heraus.",
                                   "You choose in the settings. With Roaming or the cat bed I only come out for breaks and reminders.")) {
                HStack(spacing: 14) {
                    ModeTile(title: t("Katzenkorb", "Cat bed"),
                             caption: t("schläft im Dock", "naps in the Dock"),
                             current: home == .bed) {
                        CatInBed(coat: settings.coat, scale: 2)
                    }
                    ModeTile(title: t("Immer da", "Always here"),
                             caption: t("auf dem Dock", "on the Dock"),
                             current: home == .dock) {
                        PixelCat(coat: settings.coat, pose: .walk, scale: 3)
                    }
                    ModeTile(title: t("Streifzug", "Roaming"),
                             caption: t("unterwegs", "out and about"),
                             current: home == .roaming) {
                        SneakingOut(coat: settings.coat, scale: 3)
                    }
                }
            }
        case .petting:
            OnboardingPage(title: t("Streichel mich", "Pet me"),
                           text: t("Fahr mit der Maus über mich, ohne zu klicken. Dann schnurre ich.",
                                   "Move the pointer over me without clicking. Then I purr.")) {
                PettableCat(coat: settings.coat, scale: 6, purrs: settings.purring)
            }
        case .menu:
            OnboardingPage(title: t("Mein Menü", "My menu"),
                           text: t("Oben in der Menüleiste gibt es Futter, Wollknäuel, Pomodoro und die Einstellungen.",
                                   "Up in the menu bar you'll find food, yarn, Pomodoro and the settings.")) {
                MenuBarSketch()
            }
        case .done:
            OnboardingPage(title: t("Schön, dass ich da bin!", "Happy to be here!"),
                           text: t("\(settings.displayName) kommt gleich auf dein Dock.",
                                   "\(settings.displayName) is on the way to your Dock.")) {
                VStack(spacing: 6) {
                    FloatingHeart()
                        .opacity(wokeAt == nil ? 1 : 0)
                    WakingCat(coat: settings.coat, scale: 6, wokeAt: wokeAt,
                              outfit: settings.currentOutfit?() ?? Frames.Outfit())
                        .opacity(jumped ? 0 : 1)
                        .background(GeometryReader { geometry in
                            Color.clear
                                .onAppear { catFrame = geometry.frame(in: .global) }
                                .onChange(of: geometry.frame(in: .global)) { catFrame = $0 }
                        })
                }
                .animation(.easeOut(duration: 0.3), value: wokeAt)
            } below: {
                MadeWith()
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
                ForEach(Step.dots, id: \.self) { item in
                    let current = item == (step == .bedAccess ? .home : step)
                    Capsule()
                        .fill(current ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: current ? 20 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
            Spacer()
            Button(nextTitle, action: next)
                .buttonStyle(CapsuleButtonStyle())
                .keyboardShortcut(.defaultAction)
                // Bei der Frage nach der Freigabe antwortet man mit Ja oder Nein
                .opacity(step == .bedAccess ? 0 : 1)
                .disabled(step == .bedAccess)
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
            guard wokeAt == nil else { return }
            settings.onboardingDone = true
            // Aufwachen, aufstehen, dann aus dem Fenster aufs Dock springen. Das Zuhause gilt erst, wenn sie unten ist
            wokeAt = Date()
            let home = home
            let settings = settings
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                jumped = true
                onFinish(catFrame) { home.apply(to: settings) }
            }
        } else {
            go(1)
        }
    }

    private var homeText: String {
        switch home {
        case .dock: return t("Ich bleibe auf dem Dock, laufe herum und mache Nickerchen.",
                             "I stay on the Dock, stroll around and take naps.")
        case .roaming: return t("Ich gehe auf Streifzug und komme nur zu Pausen und Erinnerungen vorbei.",
                                "I head out and only drop by for breaks and reminders.")
        case .bed: return t("Ich schlafe im Korb im Dock und komme zu Pausen und Erinnerungen heraus.",
                            "I sleep in my bed in the Dock and come out for breaks and reminders.")
        }
    }

    private func go(_ delta: Int) {
        guard var target = Step(rawValue: step.rawValue + delta) else { return }
        // Die Frage nach der Freigabe nur mit Katzenkorb und wenn sie noch fehlt
        if target == .bedAccess, home != .bed || DockLocator.isTrusted {
            guard let skip = Step(rawValue: target.rawValue + delta) else { return }
            target = skip
        }
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
    /// Seiten mit viel Inhalt unten kommen mit einer kleineren Bildfläche aus
    var compact = false

    init(title: String, text: String, compact: Bool = false, @ViewBuilder art: () -> Art,
         @ViewBuilder below: () -> Below) {
        self.title = title
        self.text = text
        self.compact = compact
        self.art = art()
        self.below = below()
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: compact ? 20 : 40)
            art
                .frame(minHeight: compact ? 90 : 150, alignment: .bottom)
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.top, compact ? 16 : 28)
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

/// Wo sie wohnt: immer auf dem Dock, auf Streifzug oder im Katzenkorb
enum Home: Equatable {
    case dock, roaming, bed

    @MainActor init(_ settings: AppSettings) {
        if settings.basketInDock, settings.basketNap {
            self = .bed
        } else if !settings.basketInDock, settings.roaming {
            self = .roaming
        } else {
            self = .dock
        }
    }

    /// Übernehmen. Nach der Freigabe hat die Einrichtung schon selbst gefragt.
    @MainActor func apply(to settings: AppSettings) {
        guard Home(settings) != self else { return }
        settings.askForAccessWithBed = false
        switch self {
        case .dock:
            settings.basketInDock = false
            settings.roaming = false
        case .roaming:
            settings.basketInDock = false
            settings.roaming = true
        case .bed:
            settings.basketInDock = true
            settings.basketNap = true
        }
        settings.askForAccessWithBed = true
    }
}

/// Runder Knopf für „Weiter“: farbig, oder zurückhaltend für die zweite Wahl
struct CapsuleButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .background(Capsule().fill(prominent ? AnyShapeStyle(Color.accentColor.gradient)
                                                 : AnyShapeStyle(Color.primary.opacity(0.08))))
            .shadow(color: Color.accentColor.opacity(prominent ? 0.3 : 0), radius: 6, y: 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Großes Namensfeld mit ein paar Vorschlägen
/// Eigene Motivationssprüche: eintragen, Vorschläge antippen, wieder entfernen
private struct SayingsEditor: View {
    @ObservedObject var settings: AppSettings
    @State private var newSaying = ""
    @FocusState private var focused: Bool

    private var suggestions: [String] {
        L10n.isGerman
            ? ["Du schaffst das!", "Ein Schritt nach dem anderen.", "Fertig ist besser als perfekt.", "Heute wird ein guter Tag!"]
            : ["You've got this!", "One step at a time.", "Done is better than perfect.", "Today is going to be great!"]
    }

    var body: some View {
        VStack(spacing: 12) {
            Toggle(L10n.s("Motivieren", "Motivate me"), isOn: $settings.motivationEnabled)
                .toggleStyle(.switch)
                .font(.system(.callout, design: .rounded))
            HStack(spacing: 8) {
                TextField("", text: $newSaying, prompt: Text(L10n.s("Dein Spruch", "Your saying")))
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .rounded))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .focused($focused)
                    .onSubmit { add(newSaying) }
                    .onChange(of: newSaying) { value in
                        if value.count > TasksView.maxLength { newSaying = String(value.prefix(TasksView.maxLength)) }
                    }
                Button(L10n.s("Hinzufügen", "Add")) { add(newSaying) }
                    .disabled(newSaying.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .frame(width: 420)
            // Eigene Sprüche als Kapseln, mit × zum Entfernen
            if !settings.motivationSayings.isEmpty {
                FlowRow(items: settings.motivationSayings) { saying in
                    HStack(spacing: 6) {
                        Text(saying).font(.system(.callout, design: .rounded))
                        Button { settings.motivationSayings.removeAll { $0 == saying } } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                }
            }
            // Vorschläge zum Antippen
            let open = suggestions.filter { !settings.motivationSayings.contains($0) }
            if !open.isEmpty {
                FlowRow(items: open) { saying in
                    Button { add(saying) } label: {
                        Label(saying, systemImage: "plus")
                            .font(.system(.caption, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 520)
    }

    /// Ein Spruch dazu – damit ist die Motivation auch eingeschaltet
    private func add(_ saying: String) {
        let text = saying.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !settings.motivationSayings.contains(text) { settings.motivationSayings.append(text) }
        settings.motivationEnabled = true
        newSaying = ""
    }
}

/// Kapseln nebeneinander, die in die nächste Zeile umbrechen
private struct FlowRow<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { content($0) }
        }
        .frame(maxWidth: 520)
    }
}

private struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? 520, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? 520, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            // Jede Zeile mittig
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(width: CGFloat, subviews: LayoutSubviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

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
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .frame(width: 280)
                .background(Capsule().fill(Color.primary.opacity(focused ? 0.08 : 0.05)))
                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(focused ? 0.55 : 0), lineWidth: 1.5))
                .animation(.easeOut(duration: 0.15), value: focused)
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
    var artHeight: CGFloat = 100
    @ViewBuilder var art: Art
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                art
                    .frame(width: 130, height: artHeight, alignment: .bottom)
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
            .frame(width: 96, height: 140)
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
struct FloatingHeart: View {
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

// MARK: - Lebendige Katzen

/// Schläft, bis die Maus ins Fenster kommt. Dann wacht sie auf, setzt sich kurz, steht gleich auf und schlendert
/// gemächlich hin und her. Erst nach einer Weile setzt sie sich mal, putzt sich oder streckt sich. Ist die Maus eine
/// Weile weg, dreht sie sich und legt sich wieder schlafen.
@MainActor
final class PlayfulCatModel: ObservableObject {
    private enum Phase: Equatable {
        case sleeping, waking, stretching, sitting, grooming, standing, yawning, lyingDown
        case walking(to: CGFloat)
        /// Kurz von hinten zu sehen, dann schaut sie in die andere Richtung
        case turning(thenLieDown: Bool)
    }

    @Published private(set) var sprite: Sprite = Frames.sleepA
    @Published private(set) var x: CGFloat = 0
    @Published private(set) var facingLeft = false

    /// So weit darf sie nach links und rechts gehen (Punkte)
    var range: CGFloat = 100
    var hovering = false {
        didSet { if hovering { lastHover = clock } }
    }

    private var phase: Phase = .sleeping
    private var phaseTime: Double = 0
    private var phaseLength: Double = 0
    private var clock: Double = 0
    private var lastHover: Double = -100
    /// Seit wann sie wach ist: Hinsetzen, Putzen und Strecken kommen erst später
    private var awakeSince: Double = 0

    func tick(_ dt: Double) {
        clock += dt
        phaseTime += dt
        if hovering { lastHover = clock }
        switch phase {
        case .sleeping:
            sprite = Int(phaseTime / 1.3) % 2 == 0 ? Frames.sleepA : Frames.sleepB
            if hovering, phaseTime > 0.5 { start(.waking, for: 1.3) }
        case .waking:
            // Augen auf, kurz aufsetzen, dann gleich aufstehen
            sprite = phaseTime < 0.4 ? Frames.lieBlink : phaseTime < 0.9 ? Frames.sit : Frames.stand
            if phaseTime >= phaseLength {
                awakeSince = clock
                facingLeft = Bool.random()
                walk()
            }
        case .stretching:
            sprite = phaseTime < 0.9 ? Frames.stretchBowA : Frames.stretchBowB
            if phaseTime >= phaseLength { start(.standing, for: 1.0) }
        case .sitting:
            sprite = Int(phaseTime * 10) % 40 < 2 ? Frames.sitBlink : Frames.sit
            if phaseTime >= phaseLength { next() }
        case .grooming:
            sprite = Int(phaseTime / 0.35) % 2 == 0 ? Frames.groomA : Frames.groomB
            if phaseTime >= phaseLength { start(.sitting, for: .random(in: 1.5...2.5)) }
        case .standing:
            sprite = Int(phaseTime * 10) % 30 < 2 ? Frames.standBlink : Frames.stand
            if phaseTime >= phaseLength { next() }
        case .yawning:
            sprite = Frames.yawn
            if phaseTime >= phaseLength { start(.sitting, for: .random(in: 1.5...2.5)) }
        case .walking(let target):
            // Gemächlich, ein paar Schritte
            let step = 22 * CGFloat(dt)
            facingLeft = target < x
            if abs(target - x) <= step {
                x = target
                start(.standing, for: .random(in: 0.6...1.4))
            } else {
                x += facingLeft ? -step : step
                sprite = Int(phaseTime / 0.32) % 2 == 0 ? Frames.walkA : Frames.walkB
            }
        case .turning(let lieDown):
            sprite = Frames.sitBackA
            if phaseTime >= phaseLength {
                facingLeft.toggle()
                if lieDown { start(.lyingDown, for: 1.6) } else { walk() }
            }
        case .lyingDown:
            sprite = phaseTime < 0.7 ? Frames.sit : Frames.lie
            if phaseTime >= phaseLength { start(.sleeping, for: 0) }
        }
    }

    private func start(_ next: Phase, for length: Double) {
        phase = next
        phaseTime = 0
        phaseLength = length
    }

    /// Was als Nächstes kommt. Meistens schlendert sie weiter, erst später setzt sie sich auch mal.
    private func next() {
        if clock - lastHover > 6 {
            start(.turning(thenLieDown: true), for: 0.6)
            return
        }
        let settled = clock - awakeSince > 10
        let roll = Double.random(in: 0..<1)
        switch roll {
        case ..<0.50: walk()
        case ..<0.62: start(.turning(thenLieDown: false), for: 0.6)
        case ..<0.74: start(.standing, for: .random(in: 1.0...2.0))
        case ..<0.84 where settled: start(.sitting, for: .random(in: 2.0...3.0))
        case ..<0.93 where settled: start(.grooming, for: .random(in: 1.6...2.4))
        case ..<0.97 where settled: start(.stretching, for: 1.8)
        case ..<1 where settled: start(.yawning, for: 1.2)
        default: walk()
        }
    }

    /// Gemächlich ein Stück gehen, mal weiter, mal nur ein paar Schritte
    private func walk() {
        var distance = CGFloat.random(in: 35...90)
        if facingLeft { distance = -distance }
        var target = x + distance
        // Am Rand umdrehen
        if abs(target) > range { target = x - distance }
        start(.walking(to: max(-range, min(range, target))), for: 0)
    }
}

struct PlayfulCat: View {
    let coat: Coat
    var scale: CGFloat = 6
    @StateObject private var model = PlayfulCatModel()
    private let timer = Timer.publish(every: 1.0 / 20, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            PixelSprite(sprite: model.sprite, colors: coat.colors, scale: scale, mirrored: model.facingLeft)
                .offset(x: model.x)
        }
        .frame(width: 2 * model.range + 40 * scale, height: 22 * scale, alignment: .bottom)
        .onReceive(timer) { _ in model.tick(1.0 / 20) }
        // Die Maus irgendwo im Fenster weckt sie
        .background(HoverReporter { model.hovering = $0 })
    }
}

/// Meldet, ob die Maus im Fenster ist (auch über Knöpfen und Text)
private struct HoverReporter: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var area: NSTrackingArea?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let content = window.contentView else { return }
            if let area { content.removeTrackingArea(area) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
            content.addTrackingArea(area)
            self.area = area
            // Steht die Maus schon im Fenster, wacht sie gleich auf
            let inside = content.bounds.contains(content.convert(window.mouseLocationOutsideOfEventStream, from: nil))
            onChange?(inside)
        }

        override func removeFromSuperview() {
            if let area { window?.contentView?.removeTrackingArea(area) }
            super.removeFromSuperview()
        }

        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }
    }
}

/// Zum Streicheln: Fährt die Maus über sie, kneift sie zufrieden die Augen zu, schmiegt sich an und schnurrt.
struct PettableCat: View {
    let coat: Coat
    var scale: CGFloat = 6
    var purrs = true

    @State private var lastStroke: Date = .distantPast
    @State private var lastPoint: CGPoint?
    @State private var tick = 0
    @State private var purr = Purr()
    private let timer = Timer.publish(every: 1.0 / 20, on: .main, in: .common).autoconnect()

    private var petted: Bool { Date().timeIntervalSince(lastStroke) < 0.8 }

    var body: some View {
        VStack(spacing: 6) {
            FloatingHeart()
                .opacity(petted ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: petted)
            PixelSprite(sprite: sprite, colors: coat.colors, scale: scale)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        // Nur echtes Streichen zählt, nicht stillhalten
                        if let lastPoint, hypot(point.x - lastPoint.x, point.y - lastPoint.y) > 2 { lastStroke = Date() }
                        lastPoint = point
                    case .ended:
                        lastPoint = nil
                    }
                }
        }
        .onReceive(timer) { _ in
            tick += 1
            purr.update(dt: 1.0 / 20, active: purrs && petted)
        }
        .onDisappear { purr.stop() }
    }

    private var sprite: Sprite {
        if petted { return (tick / 8) % 2 == 0 ? Frames.petStandTall : Frames.petStand }
        return tick % 70 < 3 ? Frames.standBlink : Frames.stand
    }
}

// MARK: - Bilder der Führung

/// Die Katze sitzt und denkt an etwas, mit der echten Gedankenblase
struct ThinkingCat: View {
    let coat: Coat
    let thought: String

    var body: some View {
        VStack(spacing: 2) {
            PixelSprite(sprite: BubbleFrames(text: thought).whole, colors: BubbleFrames.colors, scale: 3)
                .offset(x: 18)
            PixelCat(coat: coat, pose: .sit, scale: 4)
        }
    }
}

/// Eine der drei Arten, wo sie lebt. Die aktuelle Einstellung ist markiert.
private struct ModeTile<Art: View>: View {
    let title: String
    let caption: String
    let current: Bool
    @ViewBuilder var art: Art

    var body: some View {
        VStack(spacing: 8) {
            art
                .frame(width: 140, height: 70, alignment: .bottom)
            Text(title)
                .font(.system(.callout, design: .rounded).weight(.semibold))
            Text(caption)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 168)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.background.opacity(current ? 0.95 : 0.55)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(current ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: current ? 2 : 1))
    }
}

/// Ganz unten auf der letzten Seite: gemacht mit Liebe, Claude und Kaffee
private struct MadeWith: View {
    var body: some View {
        HStack(spacing: 0) {
            Text(L10n.s("Gemacht mit ", "Made with "))
            PixelSprite(sprite: PixelArt.heart, colors: ["K": NSColor.systemPink.cgColor], scale: 2)
            Text(", ")
            PixelSprite(sprite: PixelArt.claudeSpark, colors: ["K": PixelArt.claudeOrange], scale: 2)
            Text(L10n.s(" und ", " & "))
            PixelSprite(sprite: PixelArt.coffee, colors: PixelArt.coffeeColors, scale: 2)
                .offset(y: -2)
        }
        .font(.system(.callout, design: .rounded).weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
    }
}

/// Schläft, bis „Fertig“ gedrückt wird: dann Augen auf, aufsetzen, aufstehen
private struct WakingCat: View {
    let coat: Coat
    let scale: CGFloat
    let wokeAt: Date?
    /// Hut und Fliege wie auf dem Dock
    let outfit: Frames.Outfit

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            Image(nsImage: sprite(at: context.date).nsImage(colors: coat.colors, scale: scale, outfit: outfit))
                .interpolation(.none)
                .accessibilityHidden(true)
        }
    }

    private func sprite(at date: Date) -> Sprite {
        guard let wokeAt else {
            return Int(date.timeIntervalSinceReferenceDate / 1.1) % 2 == 0 ? Frames.sleepA : Frames.sleepB
        }
        switch date.timeIntervalSince(wokeAt) {
        case ..<0.35: return Frames.lieBlink
        case ..<0.8: return Frames.sit
        default: return Frames.stand
        }
    }
}

/// Streifzug: Sie zieht los wie eine kleine Abenteurerin, mit dem Wanderbündel über der Schulter
private struct SneakingOut: View {
    let coat: Coat
    let scale: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let pose = Int(context.date.timeIntervalSinceReferenceDate / 0.25) % 2 == 0 ? Frames.walkA : Frames.walkB
            Image(nsImage: pose.nsImage(colors: coat.colors, scale: scale, pieces: Self.bindle(on: pose)))
                .interpolation(.none)
                .accessibilityHidden(true)
        }
    }

    /// Der Stock liegt auf der Schulter, ein Stück hinter dem Kopf, das Bündel hängt hinten oben
    private static func bindle(on sprite: Sprite) -> [(sprite: Sprite, x: Int, y: Int)] {
        guard let ears = sprite.earAnchor else { return [] }
        let shoulderX = ears.center - 4, shoulderRow = ears.row + 6
        let stick = PixelArt.bindle
        return [(stick, shoulderX - (stick.width - 1), sprite.height - 1 - shoulderRow)]
    }
}
