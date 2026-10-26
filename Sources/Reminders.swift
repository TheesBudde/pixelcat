import Foundation

/// Kleine Erinnerungen neben der Pause: trinken, aus dem Fenster schauen, an eine Aufgabe denken, Feierabend,
/// ein Motivationsspruch. Dazu der Vogel, den sie jagt, während niemand am Rechner ist.
enum ErrandKind: Hashable, CaseIterable {
    case drink, lookout, task, quittingTime, bird, motivation
}

struct Errand: Equatable {
    let kind: ErrandKind
    /// Bei Aufgaben: woran sie erinnert und welche es ist
    var text: String?
    var taskID: UUID?
}

/// Eine Aufgabe, an die sie einmal am Tag zu einer festen Uhrzeit erinnert.
struct TaskItem: Equatable, Identifiable {
    var id = UUID()
    var text: String
    /// Uhrzeit (Minuten nach Mitternacht)
    var time: Int

    static let defaultTime = 10 * 60

    /// Zum Speichern in den Einstellungen
    var dictionary: [String: Any] { ["id": id.uuidString, "text": text, "time": time] }

    init(id: UUID = UUID(), text: String, time: Int) {
        self.id = id
        self.text = text
        self.time = time
    }

    /// Früher gab es statt der Uhrzeit einen Abstand („minutes“) – solche Aufgaben kommen um 10 Uhr
    init?(dictionary: [String: Any]) {
        guard let text = dictionary["text"] as? String else { return nil }
        self.init(id: (dictionary["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID(),
                  text: text, time: dictionary["time"] as? Int ?? Self.defaultTime)
    }

    /// Die Uhrzeit, wie macOS sie schreibt (z. B. „14:30“ oder „2:30 PM“)
    var timeText: String { Self.timeText(time) }

    static func timeText(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

/// Plant die kleinen Erinnerungen und reiht fällige hintereinander ein – es läuft immer nur eine,
/// damit sich Napf, Fenster und Gedankenblasen nicht in die Quere kommen.
/// Reine Logik ohne Fenster, damit sie sich testen lässt.
final class ErrandScheduler {
    /// Wie weit die Abstände zufällig schwanken (±), damit es natürlich wirkt
    static let jitter = 0.2

    private(set) var queue: [Errand] = []
    private var nextDue: [ErrandKind: Date] = [:]
    private var intervals: [ErrandKind: Double] = [:]
    /// Aufgaben (nur die mit Text), jede einmal am Tag zu ihrer Uhrzeit
    private var tasks: [TaskItem] = []
    private var tasksEnabled = false
    /// Der Termin, an den sie zuletzt erinnert hat (pro Aufgabe)
    private var taskShown: [UUID: Date] = [:]
    /// So lange danach holt sie eine verpasste Aufgabe noch nach (Mac im Ruhezustand oder gerade gestartet)
    static let taskCatchUp: TimeInterval = 3 * 60 * 60

    /// Motivation: morgens, gegen Feierabend und an langen Tagen einmal dazwischen
    private var motivationEnabled = false
    private var workdayEnd = 17 * 60 + 30
    private var motivationWeekdaysOnly = false
    private var motivationDay: Date?
    private var motivationSlots: [Date] = []
    private var lastMotivation: Date?
    /// Mindestabstand zwischen zwei Sprüchen
    static let motivationSpacing: TimeInterval = 4 * 60 * 60
    /// War der Mac zur Zeit aus, kommt der Spruch bis so lange danach noch
    static let motivationWindow: TimeInterval = 90 * 60

    /// Feierabend: Uhrzeit (Minuten nach Mitternacht) und ob nur Montag bis Freitag
    private var quittingTime: (minutes: Int, weekdaysOnly: Bool)?
    /// Bis wann der Feierabend schon geprüft ist – er kommt nur, wenn die Uhrzeit überschritten wird,
    /// solange das Programm läuft (nicht nachträglich beim Start am Abend)
    private var quittingCheckedUntil: Date?

    var calendar = Calendar.current
    var random: () -> Double = { Double.random(in: 0..<1) }

    /// Wiederkehrende Erinnerung ein-/ausschalten bzw. ihren Abstand ändern (Minuten).
    func configure(_ kind: ErrandKind, every minutes: Double?, now: Date) {
        guard let minutes, minutes > 0 else {
            intervals[kind] = nil
            nextDue[kind] = nil
            queue.removeAll { $0.kind == kind }
            return
        }
        if intervals[kind] != minutes || nextDue[kind] == nil {
            intervals[kind] = minutes
            nextDue[kind] = now.addingTimeInterval(spread(minutes) * 60)
        }
    }

    /// Aufgaben übernehmen. Beim Start (`launch`) holt sie Verpasstes nach. Wird später eine Aufgabe neu angelegt
    /// oder auf eine Uhrzeit gestellt, die heute schon vorbei ist, kommt sie erst morgen.
    /// Ausgeschaltet bleibt die Liste erhalten (für „Jetzt zeigen“), aber nichts wird fällig.
    func configureTasks(_ items: [TaskItem], enabled: Bool, now: Date, launch: Bool = false) {
        let old = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        tasks = items.compactMap { item in
            var item = item
            item.text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return item.text.isEmpty ? nil : item
        }
        tasksEnabled = enabled
        if !launch {
            for task in tasks where old[task.id]?.time != task.time {
                taskShown[task.id] = lastOccurrence(of: task.time, upTo: now)
            }
        }
        // Was es nicht mehr gibt, fliegt aus der Schlange – „Jetzt zeigen“ bleibt
        let ids = Set(tasks.map(\.id))
        queue.removeAll { $0.kind == .task && !ids.contains($0.taskID ?? UUID()) }
    }

    /// Motivation ein- oder ausschalten. Der zweite Spruch des Tages richtet sich nach dem Feierabend.
    func configureMotivation(enabled: Bool, workdayEnd: Int?, weekdaysOnly: Bool) {
        motivationEnabled = enabled
        let end = workdayEnd ?? 17 * 60 + 30
        if end != self.workdayEnd || weekdaysOnly != motivationWeekdaysOnly {
            self.workdayEnd = end
            motivationWeekdaysOnly = weekdaysOnly
            motivationDay = nil // Zeiten für heute neu bestimmen
        }
        if !enabled { queue.removeAll { $0.kind == .motivation } }
    }

    /// Die Zeiten eines Tages: morgens zwischen 9 und 10 Uhr, 30 bis 75 Minuten vor Feierabend und an langen
    /// Tagen eine in der Mitte. Zwei Sprüche liegen immer mindestens 4 Stunden auseinander.
    func motivationTimes(for day: Date) -> [Date] {
        if motivationWeekdaysOnly, !isWorkday(day) { return [] }
        let start = calendar.startOfDay(for: day)
        let morning = 9 * 60 + 60 * random()
        let evening = Double(workdayEnd) - (30 + 45 * random())
        var minutes = [morning]
        if evening - morning >= 8 * 60 { minutes.append((morning + evening) / 2) }
        if evening - morning >= 4 * 60 { minutes.append(evening) }
        return minutes.map { calendar.date(byAdding: .minute, value: Int($0), to: start) ?? start }
    }

    func configureQuittingTime(hour: Int, minute: Int, weekdaysOnly: Bool, enabled: Bool) {
        quittingTime = enabled ? (hour * 60 + minute, weekdaysOnly) : nil
        if !enabled { queue.removeAll { $0.kind == .quittingTime } }
    }

    /// Fällige Erinnerungen einreihen (jede Art höchstens einmal) und neu planen.
    func collectDue(now: Date) {
        for (kind, due) in nextDue where now >= due {
            enqueue(kind)
            nextDue[kind] = now.addingTimeInterval(spread(intervals[kind] ?? 30) * 60)
        }
        if tasksEnabled {
            for task in tasks {
                let occurrence = lastOccurrence(of: task.time, upTo: now)
                guard now.timeIntervalSince(occurrence) <= Self.taskCatchUp,
                      (taskShown[task.id] ?? .distantPast) < occurrence else { continue }
                taskShown[task.id] = occurrence
                enqueue(task)
            }
        }
        if motivationEnabled {
            let today = calendar.startOfDay(for: now)
            if motivationDay != today {
                motivationDay = today
                motivationSlots = motivationTimes(for: now)
            }
            for slot in motivationSlots where now >= slot && now.timeIntervalSince(slot) <= Self.motivationWindow {
                if let lastMotivation, now.timeIntervalSince(lastMotivation) < Self.motivationSpacing { continue }
                lastMotivation = now
                enqueue(.motivation)
            }
            motivationSlots.removeAll { $0 <= now }
        }
        if let start = quittingCheckedUntil, quittingCrossing(after: start, upTo: now) != nil {
            enqueue(.quittingTime)
        }
        quittingCheckedUntil = now
    }

    /// Die nächste Erinnerung aus der Warteschlange, die gerade erlaubt ist (Aufgaben mit ihrem aktuellen Text).
    /// Nicht erlaubte bleiben in der Schlange und kommen später.
    func popNext(where allowed: (ErrandKind) -> Bool = { _ in true }) -> Errand? {
        guard let index = queue.firstIndex(where: { allowed($0.kind) }) else { return nil }
        var errand = queue.remove(at: index)
        if errand.kind == .task {
            guard let task = tasks.first(where: { $0.id == errand.taskID }) else { return popNext(where: allowed) }
            errand.text = task.text
        }
        return errand
    }

    /// Sofort zeigen („Jetzt zeigen“): vorne einreihen – bei Aufgaben eine zufällige.
    func requestNow(_ kind: ErrandKind) {
        if kind == .task {
            guard !tasks.isEmpty else { return }
            let task = tasks[min(tasks.count - 1, Int(random() * Double(tasks.count)))]
            return requestTask(task.id)
        }
        queue.removeAll { $0.kind == kind }
        queue.insert(Errand(kind: kind), at: 0)
    }

    /// Eine bestimmte Aufgabe sofort zeigen (Knopf in der Aufgabenliste).
    func requestTask(_ id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        queue.removeAll { $0.taskID == id }
        queue.insert(Errand(kind: .task, text: task.text, taskID: id), at: 0)
    }

    /// Ruhemodus: Was ansteht, fällt aus
    func clearQueue() {
        queue.removeAll()
    }

    /// Welche Erinnerungen gerade warten (für den Selbsttest)
    var queuedKinds: [ErrandKind] { queue.map(\.kind) }

    // MARK: Intern

    private func enqueue(_ kind: ErrandKind) {
        guard !queue.contains(where: { $0.kind == kind }) else { return }
        queue.append(Errand(kind: kind))
    }

    /// Jede Aufgabe höchstens einmal in der Schlange
    private func enqueue(_ task: TaskItem) {
        guard !queue.contains(where: { $0.taskID == task.id }) else { return }
        queue.append(Errand(kind: .task, text: task.text, taskID: task.id))
    }

    private func spread(_ minutes: Double) -> Double {
        minutes * (1 - Self.jitter + 2 * Self.jitter * random())
    }

    /// Der letzte Termin zu dieser Uhrzeit: heute, wenn schon erreicht, sonst gestern
    private func lastOccurrence(of minutes: Int, upTo now: Date) -> Date {
        // Über den Kalender, damit es auch am Tag der Zeitumstellung stimmt
        let today = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: now)
            ?? calendar.startOfDay(for: now)
        if today <= now { return today }
        return calendar.date(byAdding: .day, value: -1, to: today) ?? today
    }

    private func isWorkday(_ date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date) // 1 = Sonntag, 7 = Samstag
        return weekday != 1 && weekday != 7
    }

    /// Wurde zwischen `start` (ausschließlich) und `end` (einschließlich) die Feierabend-Uhrzeit erreicht?
    private func quittingCrossing(after start: Date, upTo end: Date) -> Date? {
        guard let quittingTime, end > start else { return nil }
        var day = calendar.startOfDay(for: start)
        while day <= end {
            if let moment = calendar.date(byAdding: .minute, value: quittingTime.minutes, to: day),
               moment > start, moment <= end, !quittingTime.weekdaysOnly || isWorkday(moment) {
                return moment
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return nil
    }
}

/// Was sie zu welcher Tageszeit trägt: nach Feierabend Zylinder und Fliege, ab der Schlafenszeit die Schlafmütze,
/// morgens die hochgeschobene Schlafmaske. (Feiertage gehen vor – das regelt der Controller.)
enum DayOutfit: Equatable {
    case evening, night, morning
}

struct OutfitTimes {
    /// Feierabend (Minuten nach Mitternacht) und ob nur werktags – nil = aus
    var quitting: (minutes: Int, weekdaysOnly: Bool)?
    /// Schlafenszeit – nil = keine Schlafmütze
    var bedtime: Int?
    /// Morgen-Outfit bis zu dieser Uhrzeit – nil = keins
    var morningEnd: Int?
    /// Um 5 Uhr endet die Nacht und beginnt der Morgen
    static let morningStart = 5 * 60

    func outfit(at date: Date, calendar: Calendar = .current) -> DayOutfit? {
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if let bedtime, Self.contains(minutes, from: bedtime, to: Self.morningStart) { return .night }
        if let morningEnd, Self.contains(minutes, from: Self.morningStart, to: morningEnd) { return .morning }
        if let quitting, Self.contains(minutes, from: quitting.minutes, to: bedtime ?? Self.morningStart) {
            // Nach Mitternacht zählt noch der Tag davor
            let day = minutes < quitting.minutes ? calendar.date(byAdding: .day, value: -1, to: date) ?? date : date
            let weekday = calendar.component(.weekday, from: day)
            if !quitting.weekdaysOnly || (weekday != 1 && weekday != 7) { return .evening }
        }
        return nil
    }

    /// Liegt `minutes` in [from, to) – auch über Mitternacht hinweg?
    private static func contains(_ minutes: Int, from: Int, to: Int) -> Bool {
        from <= to ? minutes >= from && minutes < to : minutes >= from || minutes < to
    }
}

/// Übungen der geführten Pause – jede mit einem kurzen Satz für die Gedankenblase
enum Exercise: CaseIterable, Equatable {
    case stretchUp, lookAround, arch, breathe, bow, blink, walk

    var text: String {
        switch self {
        case .stretchUp: return L10n.s("Streck die Arme hoch!", "Stretch your arms up!")
        case .lookAround: return L10n.s("Kopf langsam links und rechts.", "Turn your head left and right.")
        case .arch: return L10n.s("Mach einen Katzenbuckel!", "Arch your back like a cat!")
        case .breathe: return L10n.s("Atme tief ein und aus.", "Breathe in deeply and out.")
        case .bow: return L10n.s("Arme nach vorn, Rücken lang.", "Reach forward, long back.")
        case .blink: return L10n.s("Blinzle und schau in die Ferne.", "Blink and look far away.")
        case .walk: return L10n.s("Steh auf, geh ein paar Schritte.", "Get up, walk a few steps.")
        }
    }
}

/// Geführte Pause: Die Katze macht Übungen vor, eine nach der anderen. Sie nehmen etwa vier Fünftel der Pause ein
/// (jede 15 bis 45 Sekunden), danach heißt es einfach ausruhen.
struct GuidedBreak {
    struct Step: Equatable {
        /// nil = ausruhen
        let exercise: Exercise?
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }

    let steps: [Step]

    init(length: TimeInterval) {
        let order = Exercise.allCases
        let each = min(45, max(15, length * 0.8 / Double(order.count)))
        var steps: [Step] = []
        var time = 0.0
        for exercise in order where time + each <= length {
            steps.append(Step(exercise: exercise, text: exercise.text, start: time, end: time + each))
            time += each
        }
        if length - time >= 5 {
            steps.append(Step(exercise: nil, text: L10n.s("Jetzt einfach ausruhen.", "Now just relax."),
                              start: time, end: length))
        }
        self.steps = steps
    }

    /// Welcher Schritt gerade dran ist (Sekunden seit Beginn)
    func stepIndex(at elapsed: TimeInterval) -> Int? {
        steps.firstIndex { elapsed >= $0.start && elapsed < $0.end }
    }
}

/// Pause weggedrückt: Bei Pausen nach Aktivität kommt die nächste Erinnerung früher – jedes Mal etwas früher,
/// aber nie öfter als alle 15 Minuten. Nach einer echten Pause gilt wieder der volle Abstand.
struct BreakSnooze {
    static let shortest = 15.0
    /// Pro Wegdrücken bleibt so viel vom Abstand übrig
    static let factor = 0.6
    private(set) var count = 0

    /// Minuten Arbeit am Stück bis zur nächsten Erinnerung
    func minutes(base: Int) -> Double {
        let shortened = Double(base) * pow(Self.factor, Double(count))
        return max(min(Double(base), Self.shortest), shortened)
    }

    mutating func snoozed() { count += 1 }
    mutating func rested() { count = 0 }
}

/// Zählt, wie lange am Stück gearbeitet wird (Tastatur, Maus, Trackpad) – für Pausen nach echter Aktivität.
/// Wer länger als `restAfter` nichts tut, hat Pause gemacht: dann fängt die Zählung von vorne an.
struct ActivityTracker {
    /// Ab dieser Leerlaufzeit (Sekunden) zählt es als Pause
    var restAfter: Double = 5 * 60
    /// Bis zu dieser Leerlaufzeit gilt man noch als aktiv (Lesen, Nachdenken)
    var activeWithin: Double = 60
    private(set) var activeSeconds: Double = 0

    /// `idle`: Sekunden seit der letzten Eingabe
    mutating func update(dt: Double, idle: Double) {
        if idle >= restAfter {
            activeSeconds = 0
        } else if idle < activeWithin {
            activeSeconds += dt
        }
    }

    mutating func reset() { activeSeconds = 0 }
}
