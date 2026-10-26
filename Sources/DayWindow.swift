import AppKit
import Combine
import SwiftUI

/// Fenster für den Tagesstart und das Tagesende – zum Durchklicken wie die Einrichtung, ein Schritt pro Seite.
@MainActor
final class DayWindow: NSObject, NSWindowDelegate {
    enum Kind { case start, end }

    private var window: NSWindow?
    private let store: StatsStore
    private let settings: AppSettings
    private var coatWatch: AnyCancellable?
    /// Fertig durchgeklickt (die Katze freut sich)
    var onFinish: ((Kind) -> Void)?

    init(store: StatsStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    /// Ist das Fenster gerade offen?
    var isOpen: Bool { window?.isVisible == true }
    private var shown: (kind: Kind, date: Date)?

    /// `date`: der Tag, um den es geht (beim Tagesende nach Mitternacht noch der gestrige)
    func show(_ kind: Kind, date: Date = Date()) {
        // Schon offen für dasselbe: nur nach vorn holen (sonst wäre alles Eingetragene weg)
        if isOpen, shown?.kind == kind, let day = shown?.date, Calendar.current.isDate(day, inSameDayAs: date) {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            return
        }
        shown = (kind, date)
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.delegate = self
            self.window = window
            coatWatch = settings.$coat.sink { [weak window] coat in window?.appearance = coat.appearance }
        }
        let close: () -> Void = { [weak self] in
            self?.window?.close()
            self?.onFinish?(kind)
        }
        switch kind {
        case .start:
            window?.contentView = NSHostingView(rootView: DayStartView(store: store, settings: settings, date: date,
                                                                       onFinish: close))
            window?.title = L10n.s("Tag starten", "Start your day")
        case .end:
            window?.contentView = NSHostingView(rootView: DayEndView(store: store, settings: settings, date: date,
                                                                     onFinish: close))
            window?.title = L10n.s("Tag beenden", "End your day")
        }
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = NSView()
    }
}

// MARK: - Tag starten

struct DayStartView: View {
    @ObservedObject var store: StatsStore
    @ObservedObject var settings: AppSettings
    var onFinish: () -> Void

    /// Der Tag, für den geplant wird (beim Öffnen festgehalten – auch wenn es beim Fertig schon nach Mitternacht ist)
    let date: Date
    @State private var page: Int

    init(store: StatsStore, settings: AppSettings, date: Date = Date(), page: Int = 0, onFinish: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        self.date = date
        self.onFinish = onFinish
        _page = State(initialValue: page)
    }
    @State private var forward = true
    @State private var mood: Int?
    @State private var todos: [TodoItem] = []
    @State private var newTodo = ""
    @State private var goals = ["", "", ""]

    private static let pages = 6
    private func t(_ de: String, _ en: String) -> String { L10n.s(de, en) }

    var body: some View {
        DayFlow(coat: settings.coat, page: page, pages: Self.pages, forward: forward,
                nextTitle: nextTitle, canGoNext: page != 1 || mood != nil,
                back: { go(-1) }, next: next) {
            switch page {
            case 0:
                DayPage(title: t("Guten Morgen!", "Good morning!"),
                        text: t("Lass uns kurz deinen Tag planen. Das dauert nur eine Minute.",
                                "Let's plan your day. It only takes a minute.")) {
                    PixelCat(coat: settings.coat, pose: .sit, scale: 6)
                }
            case 1:
                DayPage(title: t("Wie geht es dir?", "How are you feeling?"),
                        text: t("Ganz ehrlich, auf einer Skala von 1 bis 10.", "Honestly, on a scale from 1 to 10.")) {
                    MoodScale(value: $mood)
                }
            case 2:
                DayPage(title: t("Was steht heute an?", "What's on today?"),
                        text: t("Schreib erst alles auf, was du heute erledigen willst. Ordnen kommt gleich.",
                                "First write down everything you want to get done today. Ordering comes next.")) {
                    VStack(spacing: 12) {
                        FrogTip(text: t("Eat the Frog: Das Schwerste zuerst, das Leichteste zum Schluss.",
                                        "Eat the frog: the hardest task first, the easiest last."))
                        TodoEntry(todos: $todos, newTodo: $newTodo)
                    }
                }
            case 3:
                DayPage(title: t("Bring sie in eine Reihenfolge", "Put them in order"),
                        text: t("Ganz oben steht dein Frosch, die schwerste Aufgabe. Danach wird es leichter.",
                                "Your frog goes on top, the hardest task. Then it gets easier.")) {
                    TodoOrder(todos: $todos)
                }
            case 4:
                DayPage(title: t("Was willst du heute erreichen?", "What do you want to achieve today?"),
                        text: t("Bis zu drei Ziele. Kleine, klare Ziele schafft man eher.",
                                "Up to three goals. Small, clear goals are easier to reach.")) {
                    GoalEntry(goals: $goals)
                }
            default:
                DayPage(title: t("Los geht's!", "Let's go!"), text: doneText) {
                    VStack(spacing: 14) {
                        VStack(spacing: 6) {
                            if !todos.isEmpty { PixelSprite(sprite: PixelArt.frog, colors: PixelArt.frogColors, scale: 4) }
                            PixelCat(coat: settings.coat, pose: .petted, scale: 5)
                        }
                        // Was man sich beim letzten Tagesende vorgenommen hat
                        if let improvement = store.lastImprovement(before: date) {
                            ResolutionCard(title: t("Dein Vorsatz für heute", "Your resolution for today"), text: improvement)
                        }
                    }
                }
            }
        }
    }

    private var doneText: String {
        if let frog = todos.first {
            return t("Fang mit deinem Frosch an: „\(frog.text)“. Du schaffst das!",
                     "Start with your frog: “\(frog.text)”. You've got this!")
        }
        return t("Viel Erfolg heute. Ich bin da, wenn du eine Pause brauchst.",
                 "Good luck today. I'm here when you need a break.")
    }

    private var nextTitle: String {
        page == 0 ? t("Tag starten", "Start the day") : page == Self.pages - 1 ? t("Fertig", "Done") : t("Weiter", "Next")
    }

    private func next() {
        if page == 2, !newTodo.trimmingCharacters(in: .whitespaces).isEmpty {
            todos.append(TodoItem(text: newTodo.trimmingCharacters(in: .whitespaces)))
            newTodo = ""
        }
        guard page == Self.pages - 1 else { return go(1) }
        let goals = goals.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { GoalItem(text: $0) }
        let todos = todos
        let mood = mood
        store.updateJournal(for: date) { journal in
            journal.started = Date()
            journal.moodStart = mood
            journal.todos = todos
            journal.goals = goals
        }
        onFinish()
    }

    private func go(_ delta: Int) {
        forward = delta > 0
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { page = max(0, min(Self.pages - 1, page + delta)) }
    }
}

// MARK: - Tag beenden

struct DayEndView: View {
    @ObservedObject var store: StatsStore
    @ObservedObject var settings: AppSettings
    var onFinish: () -> Void

    /// Der Tag, der beendet wird (nach Mitternacht noch der gestrige)
    let date: Date
    @State private var page: Int

    init(store: StatsStore, settings: AppSettings, date: Date = Date(), page: Int = 0, onFinish: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        self.date = date
        self.onFinish = onFinish
        _page = State(initialValue: page)
    }
    @State private var forward = true
    @State private var mood: Int?
    @State private var todos: [TodoItem] = []
    @State private var goals: [GoalItem] = []
    @State private var potential: Int?
    @State private var improvement = ""
    @State private var loaded = false

    private static let pages = 7
    private func t(_ de: String, _ en: String) -> String { L10n.s(de, en) }

    var body: some View {
        DayFlow(coat: settings.coat, page: page, pages: Self.pages, forward: forward,
                nextTitle: nextTitle, canGoNext: canGoNext, back: { go(-1) }, next: next) {
            switch page {
            case 0:
                DayPage(title: t("Feierabend!", "Time to wrap up!"),
                        text: t("Lass uns kurz auf deinen Tag schauen. Dann hast du frei.",
                                "Let's take a quick look back at your day. Then you're off.")) {
                    PixelCat(coat: settings.coat, pose: .sit, scale: 6)
                }
            case 1:
                DayPage(title: t("Wie geht es dir jetzt?", "How are you feeling now?"),
                        text: t("Ganz ehrlich, auf einer Skala von 1 bis 10.", "Honestly, on a scale from 1 to 10.")) {
                    MoodScale(value: $mood)
                }
            case 2:
                DayPage(title: t("Was hast du geschafft?", "What did you get done?"),
                        text: todos.isEmpty ? t("Heute hattest du keine To-dos geplant.", "You had no to-dos planned today.")
                                            : t("Hak ab, was erledigt ist.", "Check off what's done.")) {
                    TodoCheck(todos: $todos)
                }
            case 3:
                DayPage(title: t("Hast du deine Ziele erreicht?", "Did you reach your goals?"),
                        text: goals.isEmpty ? t("Heute hattest du keine Ziele gesetzt.", "You set no goals today.")
                                            : t("Und wenn nicht: Was kam dazwischen?", "And if not: what got in the way?")) {
                    GoalReview(goals: $goals)
                }
            case 4:
                DayPage(title: t("Hast du rausgeholt, was drin war?", "Did you make the most of today?"),
                        text: t("1 heißt: gar nicht. 10 heißt: alles, was heute möglich war.",
                                "1 means not at all. 10 means everything that was possible today.")) {
                    MoodScale(value: $potential, low: t("gar nicht", "not at all"), high: t("alles gegeben", "all in"))
                }
            case 5:
                DayPage(title: t("Was kannst du morgen besser machen?", "What can you do better tomorrow?"),
                        text: t("Ein Satz reicht. Morgen beim Tagesstart erinnere ich dich daran.",
                                "One sentence is enough. I'll remind you when you start your day tomorrow.")) {
                    ImprovementField(text: $improvement)
                }
            default:
                DayPage(title: t("Schönen Feierabend!", "Enjoy your evening!"), text: summaryText) {
                    VStack(spacing: 6) {
                        FloatingHeart()
                        PixelCat(coat: settings.coat, pose: .sleep, scale: 6)
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private var canGoNext: Bool {
        switch page {
        case 1: return mood != nil
        case 3: return goals.allSatisfy { $0.achieved != nil }
        case 4: return potential != nil
        default: return true
        }
    }

    private var summaryText: String {
        var parts: [String] = []
        if !todos.isEmpty {
            parts.append(t("\(todos.filter(\.done).count) von \(todos.count) To-dos erledigt.",
                           "\(todos.filter(\.done).count) of \(todos.count) to-dos done."))
        }
        if !goals.isEmpty {
            parts.append(t("\(goals.filter { $0.achieved == true }.count) von \(goals.count) Zielen erreicht.",
                           "\(goals.filter { $0.achieved == true }.count) of \(goals.count) goals reached."))
        }
        if let start = store.journal(for: date).moodStart, let mood {
            parts.append(t("Stimmung: \(start) am Morgen, \(mood) jetzt.", "Mood: \(start) this morning, \(mood) now."))
        }
        return parts.isEmpty ? t("Gut gemacht heute.", "Well done today.") : parts.joined(separator: " ")
    }

    private var nextTitle: String {
        page == 0 ? t("Tag beenden", "End the day") : page == Self.pages - 1 ? t("Fertig", "Done") : t("Weiter", "Next")
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let journal = store.journal(for: date)
        todos = journal.todos
        goals = journal.goals
    }

    private func next() {
        guard page == Self.pages - 1 else { return go(1) }
        let (mood, todos, goals, potential) = (mood, todos, goals, potential)
        let note = improvement.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateJournal(for: date) { journal in
            journal.improvement = note.isEmpty ? nil : note
            journal.moodEnd = mood
            journal.todos = todos
            journal.goals = goals
            journal.potential = potential
            journal.ended = Date()
            if journal.started == nil { journal.started = journal.ended }
        }
        onFinish()
    }

    private func go(_ delta: Int) {
        forward = delta > 0
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { page = max(0, min(Self.pages - 1, page + delta)) }
    }
}

// MARK: - Bausteine

/// Rahmen: Hintergrund nach Fell, Seite mit Übergang, unten Zurück, Punkte, Weiter
private struct DayFlow<Content: View>: View {
    let coat: Coat
    let page: Int
    let pages: Int
    let forward: Bool
    let nextTitle: String
    let canGoNext: Bool
    let back: () -> Void
    let next: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            PixelBackdrop(coat: coat, opacity: 0.06)
            VStack(spacing: 0) {
                ZStack {
                    content
                        .id(page)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                HStack {
                    Button(L10n.s("Zurück", "Back"), action: back)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .opacity(page == 0 ? 0 : 1)
                        .disabled(page == 0)
                        .frame(width: 150, alignment: .leading)
                    Spacer()
                    HStack(spacing: 7) {
                        ForEach(0..<pages, id: \.self) { index in
                            Capsule()
                                .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.3))
                                .frame(width: index == page ? 20 : 7, height: 7)
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: page)
                    Spacer()
                    Button(nextTitle, action: next)
                        .buttonStyle(CapsuleButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canGoNext)
                        .opacity(canGoNext ? 1 : 0.45)
                        .frame(width: 150, alignment: .trailing)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 26)
            }
        }
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .ignoresSafeArea()
        .environment(\.colorScheme, coat.colorScheme)
    }
}

/// Eine Seite: oben Überschrift und Satz, darunter der Inhalt (Bild, Skala, Liste)
private struct DayPage<Content: View>: View {
    let title: String
    let text: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 30)
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(text)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            content
                .padding(.top, 24)
                .frame(maxWidth: 520)
            Spacer(minLength: 16)
        }
        .padding(.horizontal, 40)
    }
}

/// Skala von 1 bis 10 zum Anklicken
struct MoodScale: View {
    @Binding var value: Int?
    var low = L10n.s("gar nicht gut", "not good at all")
    var high = L10n.s("richtig gut", "really good")

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(1...10, id: \.self) { number in
                    Button { value = number } label: {
                        Text("\(number)")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .frame(width: 40, height: 40)
                            .foregroundStyle(value == number ? Color.white : Color.primary)
                            .background(Circle().fill(value == number ? AnyShapeStyle(Color.accentColor.gradient)
                                                                      : AnyShapeStyle(Color.primary.opacity(0.07))))
                            .scaleEffect(value == number ? 1.12 : 1)
                            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: value)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Text(low)
                Spacer()
                Text(high)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 472)
        }
    }
}

/// Abends: ein Satz für morgen
private struct ImprovementField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(L10n.s("Morgen will ich …", "Tomorrow I'll …")), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 17, design: .rounded))
            .lineLimit(3...5)
            .padding(16)
            .frame(width: 460)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(focused ? 0.5 : 0), lineWidth: 1.5))
            .focused($focused)
            .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

/// Morgens: der Vorsatz vom letzten Tagesende
private struct ResolutionCard: View {
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.yellow.gradient))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(text).font(.system(.body, design: .rounded))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 460)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

/// Hinweis zu „Eat the Frog“ (der Frosch selbst erscheint erst beim Ordnen)
private struct FrogTip: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
            Text(text).font(.system(.callout, design: .rounded))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.green.opacity(0.12)))
    }
}

/// To-dos aufschreiben: Feld mit Hinzufügen, darunter die Liste
private struct TodoEntry: View {
    @Binding var todos: [TodoItem]
    @Binding var newTodo: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("", text: $newTodo, prompt: Text(L10n.s("Neues To-do", "New to-do")))
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .rounded))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .focused($focused)
                    .onSubmit(add)
                Button(L10n.s("Hinzufügen", "Add"), action: add)
                    .disabled(newTodo.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(todos) { todo in
                        HStack {
                            Image(systemName: "circle").foregroundStyle(.secondary)
                            Text(todo.text)
                            Spacer()
                            Button { todos.removeAll { $0.id == todo.id } } label: { Image(systemName: "xmark") }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
                    }
                }
            }
            .frame(maxHeight: 150)
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func add() {
        let text = newTodo.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        todos.append(TodoItem(text: text))
        newTodo = ""
    }
}

/// To-dos ordnen: Pfeile nach oben und unten, der erste ist der Frosch
private struct TodoOrder: View {
    @Binding var todos: [TodoItem]

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                if todos.isEmpty {
                    Text(L10n.s("Keine To-dos. Du kannst auch einfach weiter.", "No to-dos. You can just go on."))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(todos.enumerated()), id: \.element.id) { index, todo in
                    HStack(spacing: 10) {
                        Text("\(index + 1).").font(.system(.body, design: .rounded).monospacedDigit()).foregroundStyle(.secondary)
                        if index == 0 {
                            PixelSprite(sprite: PixelArt.frog, colors: PixelArt.frogColors, scale: 2)
                        }
                        Text(todo.text)
                        Spacer()
                        Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                        Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless)
                            .disabled(index == todos.count - 1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(index == 0 ? Color.green.opacity(0.12) : Color.primary.opacity(0.05)))
                }
            }
        }
        .frame(maxHeight: 230)
    }

    private func move(_ index: Int, by delta: Int) {
        let target = index + delta
        guard todos.indices.contains(target) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { todos.swapAt(index, target) }
    }
}

/// Drei Ziele
private struct GoalEntry: View {
    @Binding var goals: [String]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.accentColor.gradient))
                    TextField("", text: $goals[index], prompt: Text(L10n.s("Ziel \(index + 1)", "Goal \(index + 1)")))
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
            }
        }
        .frame(width: 440)
    }
}

/// Abends: To-dos abhaken
private struct TodoCheck: View {
    @Binding var todos: [TodoItem]

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach($todos) { $todo in
                    Button { todo.done.toggle() } label: {
                        HStack(spacing: 10) {
                            Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(todo.done ? Color.green : Color.secondary)
                            Text(todo.text)
                                .strikethrough(todo.done)
                                .foregroundStyle(todo.done ? .secondary : .primary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 250)
    }
}

/// Abends: Ziel erreicht? Wenn nicht, warum nicht
private struct GoalReview: View {
    @Binding var goals: [GoalItem]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach($goals) { $goal in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(goal.text).font(.system(.body, design: .rounded).weight(.semibold))
                            Spacer()
                            choice(L10n.s("Erreicht", "Reached"), icon: "checkmark", selected: goal.achieved == true) {
                                goal.achieved = true
                                goal.reason = nil
                                goal.note = nil
                            }
                            choice(L10n.s("Nicht erreicht", "Not reached"), icon: "xmark", selected: goal.achieved == false) {
                                goal.achieved = false
                            }
                        }
                        if goal.achieved == false {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)], alignment: .leading, spacing: 6) {
                                ForEach(GoalReason.allCases, id: \.self) { reason in
                                    Button { goal.reason = reason } label: {
                                        Label(reason.title, systemImage: reason.icon)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Capsule().fill(goal.reason == reason ? Color.accentColor.opacity(0.25)
                                                                                             : Color.primary.opacity(0.06)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            // „Andere“: den Grund selbst hinschreiben
                            if goal.reason == .other {
                                TextField("", text: Binding(get: { goal.note ?? "" }, set: { goal.note = $0 }),
                                          prompt: Text(L10n.s("Was kam dazwischen?", "What got in the way?")))
                                    .textFieldStyle(.plain)
                                    .font(.callout)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
                }
            }
        }
        .frame(maxHeight: 270)
    }

    private func choice(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(Capsule().fill(selected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.primary.opacity(0.07))))
        }
        .buttonStyle(.plain)
    }
}
