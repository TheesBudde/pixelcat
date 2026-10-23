import Foundation

/// Kleine Erinnerungen neben der Pause: trinken, aus dem Fenster schauen, an eine Aufgabe denken, Feierabend.
/// Dazu der Vogel, den sie jagt, während niemand am Rechner ist.
enum ErrandKind: Hashable, CaseIterable {
    case drink, lookout, task, quittingTime, bird
}

struct Errand: Equatable {
    let kind: ErrandKind
    /// Bei Aufgaben: woran sie erinnert und welche es ist
    var text: String?
    var taskID: UUID?
}

/// Eine Aufgabe, an die sie erinnert – jede mit eigenem Abstand.
struct TaskItem: Equatable, Identifiable {
    var id = UUID()
    var text: String
    /// Ungefähr alle so viele Minuten
    var minutes: Int

    /// Wählbare Abstände (Minuten)
    static let intervals = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240]
    static let defaultMinutes = 30

    /// Zum Speichern in den Einstellungen
    var dictionary: [String: Any] { ["id": id.uuidString, "text": text, "minutes": minutes] }

    init(id: UUID = UUID(), text: String, minutes: Int) {
        self.id = id
        self.text = text
        self.minutes = minutes
    }

    init?(dictionary: [String: Any]) {
        guard let text = dictionary["text"] as? String else { return nil }
        self.init(id: (dictionary["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID(),
                  text: text, minutes: dictionary["minutes"] as? Int ?? Self.defaultMinutes)
    }
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
    /// Aufgaben (nur die mit Text) und wann jede wieder dran ist
    private var tasks: [TaskItem] = []
    private var taskDue: [UUID: Date] = [:]

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

    /// Aufgaben übernehmen: Neue oder mit geändertem Abstand werden neu geplant, die anderen behalten ihren Termin.
    /// Ausgeschaltet bleibt die Liste erhalten (für „Jetzt zeigen“), aber nichts wird fällig.
    func configureTasks(_ items: [TaskItem], enabled: Bool, now: Date) {
        let old = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        tasks = items.compactMap { item in
            var item = item
            item.text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return item.text.isEmpty ? nil : item
        }
        var due: [UUID: Date] = [:]
        if enabled {
            for task in tasks {
                if let existing = taskDue[task.id], old[task.id]?.minutes == task.minutes {
                    due[task.id] = existing
                } else {
                    due[task.id] = now.addingTimeInterval(spread(Double(task.minutes)) * 60)
                }
            }
        }
        taskDue = due
        // Was es nicht mehr gibt (oder ausgeschaltet ist), fliegt aus der Schlange – „Jetzt zeigen“ bleibt
        let ids = Set(tasks.map(\.id))
        queue.removeAll { $0.kind == .task && !ids.contains($0.taskID ?? UUID()) }
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
        for task in tasks {
            guard let due = taskDue[task.id], now >= due else { continue }
            enqueue(task)
            taskDue[task.id] = now.addingTimeInterval(spread(Double(task.minutes)) * 60)
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
