import Foundation

/// Kleine Erinnerungen neben der Pause: trinken, aus dem Fenster schauen, an eine Aufgabe denken, Feierabend.
enum ErrandKind: Hashable, CaseIterable {
    case drink, lookout, task, quittingTime
}

struct Errand: Equatable {
    let kind: ErrandKind
    /// Bei Aufgaben: woran sie erinnert
    var text: String?
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
    private let tasks = TaskBag()

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

    func configureTasks(_ items: [String]) {
        tasks.items = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if tasks.items.isEmpty { queue.removeAll { $0.kind == .task } }
    }

    func configureQuittingTime(hour: Int, minute: Int, weekdaysOnly: Bool, enabled: Bool) {
        quittingTime = enabled ? (hour * 60 + minute, weekdaysOnly) : nil
        if !enabled { queue.removeAll { $0.kind == .quittingTime } }
    }

    /// Fällige Erinnerungen einreihen (jede Art höchstens einmal) und neu planen.
    func collectDue(now: Date) {
        for (kind, due) in nextDue where now >= due {
            if kind != .task || !tasks.items.isEmpty { enqueue(kind) }
            nextDue[kind] = now.addingTimeInterval(spread(intervals[kind] ?? 30) * 60)
        }
        if let start = quittingCheckedUntil, quittingCrossing(after: start, upTo: now) != nil {
            enqueue(.quittingTime)
        }
        quittingCheckedUntil = now
    }

    /// Die nächste Erinnerung aus der Warteschlange, die gerade erlaubt ist – Aufgaben bekommen dabei ihren Text.
    /// Nicht erlaubte bleiben in der Schlange und kommen später.
    func popNext(where allowed: (ErrandKind) -> Bool = { _ in true }) -> Errand? {
        guard let index = queue.firstIndex(where: { allowed($0.kind) }) else { return nil }
        var errand = queue.remove(at: index)
        if errand.kind == .task {
            guard let text = tasks.next(random: random) else { return popNext(where: allowed) }
            errand.text = text
        }
        return errand
    }

    /// Sofort zeigen (Knopf „Jetzt zeigen“ in den Einstellungen): vorne einreihen.
    func requestNow(_ kind: ErrandKind) {
        queue.removeAll { $0.kind == kind }
        if kind == .task, tasks.items.isEmpty { return }
        queue.insert(Errand(kind: kind), at: 0)
    }

    // MARK: Intern

    private func enqueue(_ kind: ErrandKind) {
        guard !queue.contains(where: { $0.kind == kind }) else { return }
        queue.append(Errand(kind: kind))
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

/// Geht die Aufgaben in zufälliger Reihenfolge durch: erst alle einmal, dann neu gemischt –
/// und nie zweimal dieselbe direkt hintereinander.
final class TaskBag {
    var items: [String] = [] {
        didSet { if items != oldValue { bag = [] } }
    }
    private var bag: [String] = []
    private(set) var last: String?

    func next(random: () -> Double) -> String? {
        guard !items.isEmpty else { return nil }
        if bag.isEmpty {
            bag = shuffled(items, random: random)
            // Nicht mit der zuletzt gezeigten anfangen, wenn es andere gibt
            if items.count > 1, bag.first == last { bag.append(bag.removeFirst()) }
        }
        let item = bag.removeFirst()
        last = item
        return item
    }

    private func shuffled(_ list: [String], random: () -> Double) -> [String] {
        var list = list
        guard list.count > 1 else { return list }
        for i in stride(from: list.count - 1, to: 0, by: -1) {
            let j = min(i, Int(random() * Double(i + 1)))
            list.swapAt(i, j)
        }
        return list
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
