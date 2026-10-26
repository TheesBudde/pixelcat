import Foundation

/// Ein To-do des Tages, morgens grob in den Tag gelegt (Timeboxing)
struct TodoItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var done = false
    /// Geplante Zeit (Minuten nach Mitternacht) und Länge – nil = noch nicht eingeplant
    var start: Int?
    var minutes: Int?
    /// Der Frosch: die schwerste Aufgabe (nil bei älteren Tagen, da war es die erste)
    var frog: Bool?
}

/// Warum ein Ziel offen blieb
enum GoalReason: String, Codable, CaseIterable {
    case time, interruptions, tooBig, priorities, energy, blocked, procrastinated, other

    var title: String {
        switch self {
        case .time: return L10n.s("Zu wenig Zeit", "Not enough time")
        case .interruptions: return L10n.s("Unterbrechungen", "Interruptions")
        case .tooBig: return L10n.s("Zu groß geplant", "Planned too big")
        case .priorities: return L10n.s("Anderes war wichtiger", "Other priorities")
        case .energy: return L10n.s("Keine Energie", "No energy")
        case .blocked: return L10n.s("Auf andere gewartet", "Waiting on others")
        case .procrastinated: return L10n.s("Aufgeschoben", "Put it off")
        case .other: return L10n.s("Andere", "Other")
        }
    }

    var icon: String {
        switch self {
        case .time: return "clock"
        case .interruptions: return "bell.badge"
        case .tooBig: return "square.stack.3d.up"
        case .priorities: return "arrow.triangle.branch"
        case .energy: return "battery.25"
        case .blocked: return "hourglass"
        case .procrastinated: return "zzz"
        case .other: return "ellipsis.bubble"
        }
    }
}

/// Ein Ziel des Tages und abends: erreicht oder nicht, und warum nicht
struct GoalItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var achieved: Bool?
    var reason: GoalReason?
    /// Bei „Andere“: der Grund in eigenen Worten
    var note: String?

    /// Der Grund zum Anzeigen (bei „Andere“ mit eigenem Text)
    var reasonText: String? {
        guard let reason else { return nil }
        if reason == .other, let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            return L10n.s("Andere: \(note)", "Other: \(note)")
        }
        return reason.title
    }
}

/// Ein Arbeitstag: morgens Stimmung, To-dos und Ziele, abends Stimmung, Erledigtes, Ziele und wie viel man
/// herausgeholt hat. Gestartet und beendet wird er einmal am Tag.
struct DayJournal: Codable, Equatable {
    var started: Date?
    var ended: Date?
    var moodStart: Int?
    var moodEnd: Int?
    var todos: [TodoItem] = []
    var goals: [GoalItem] = []
    /// „Hast du herausgeholt, was drin war?“ (1 bis 10)
    var potential: Int?
    /// „Was kannst du morgen besser machen?“ – erscheint beim nächsten Tagesstart
    var improvement: String?
    /// Die eingeplante Mittagspause (nil = keine)
    var lunch: TimeBlock?

    var isEmpty: Bool { self == DayJournal() }
}

/// Ältere Tagebücher kennen noch nicht alle Felder – was fehlt, ist leer
extension DayJournal {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        started = try values.decodeIfPresent(Date.self, forKey: .started)
        ended = try values.decodeIfPresent(Date.self, forKey: .ended)
        moodStart = try values.decodeIfPresent(Int.self, forKey: .moodStart)
        moodEnd = try values.decodeIfPresent(Int.self, forKey: .moodEnd)
        todos = try values.decodeIfPresent([TodoItem].self, forKey: .todos) ?? []
        goals = try values.decodeIfPresent([GoalItem].self, forKey: .goals) ?? []
        potential = try values.decodeIfPresent(Int.self, forKey: .potential)
        improvement = try values.decodeIfPresent(String.self, forKey: .improvement)
        lunch = try values.decodeIfPresent(TimeBlock.self, forKey: .lunch)
    }
}

/// Wann die Katze nach dem Tag fragt: ab Beginn des Arbeitstags „Tag starten?“, ab Feierabend „Tag beenden?“ –
/// nur, wenn man am Mac ist, und nach Daumen runter erst wieder nach ein paar Minuten.
struct DayRitual {
    enum Ask: Equatable { case start, end }

    var enabled = false
    /// Beginn und Feierabend (Minuten nach Mitternacht)
    var start = 9 * 60
    var end = 17 * 60 + 30
    var weekdaysOnly = true
    var calendar = Calendar.current
    /// So lange nach dem Start fragt sie frühestens nach dem Ende
    static let minimumDay: TimeInterval = 60 * 60

    /// Ist gerade eine Frage fällig? `idle`: Sekunden seit der letzten Eingabe. `yesterday`: das Tagebuch von
    /// gestern – wer nach Mitternacht noch arbeitet, wird bis zum nächsten Arbeitsbeginn gefragt, ob er den
    /// gestrigen Tag beenden möchte.
    func due(now: Date, journal: DayJournal, yesterday: DayJournal? = nil, idle: Double, notBefore: Date?) -> Ask? {
        guard enabled, journal.ended == nil, idle < 60 else { return nil }
        if let notBefore, now < notBefore { return nil }
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        if journal.started == nil, let yesterday, yesterday.started != nil, yesterday.ended == nil, minutes < start {
            return .end
        }
        if journal.started == nil {
            // Ungefragt nur an Arbeitstagen; wer am Wochenende von Hand startet, wird abends trotzdem gefragt
            if weekdaysOnly {
                let weekday = calendar.component(.weekday, from: now)
                if weekday == 1 || weekday == 7 { return nil }
            }
            return minutes >= start && minutes < end ? .start : nil
        }
        // Erst nach Feierabend – und nicht gleich nach dem Start (wer erst abends anfängt, hat gerade begonnen)
        if let started = journal.started, now.timeIntervalSince(started) < Self.minimumDay { return nil }
        return minutes >= end ? .end : nil
    }
}

/// Auswertung mehrerer Tage: Stimmung morgens und abends, To-dos, Ziele, Gründe, ausgeschöpftes Potenzial
struct JournalSummary {
    let days: Int
    let moodStart: Double?
    let moodEnd: Double?
    /// Durchschnittliche Veränderung von morgens zu abends (nur Tage mit beiden Werten)
    let moodChange: Double?
    let todosPerDay: Double?
    let todosDone: Int
    let todosTotal: Int
    let goalsAchieved: Int
    let goalsRated: Int
    let potential: Double?
    /// Gründe für offene Ziele, häufigste zuerst
    let reasons: [(reason: GoalReason, count: Int)]

    var todoRate: Double? { todosTotal > 0 ? Double(todosDone) / Double(todosTotal) : nil }
    var goalRate: Double? { goalsRated > 0 ? Double(goalsAchieved) / Double(goalsRated) : nil }

    init(_ journals: [DayJournal]) {
        let used = journals.filter { $0.started != nil || $0.ended != nil }
        days = used.count
        func average(_ values: [Int]) -> Double? {
            values.isEmpty ? nil : Double(values.reduce(0, +)) / Double(values.count)
        }
        moodStart = average(used.compactMap(\.moodStart))
        moodEnd = average(used.compactMap(\.moodEnd))
        let changes = used.compactMap { day in day.moodStart.flatMap { start in day.moodEnd.map { $0 - start } } }
        moodChange = average(changes)
        let planned = used.filter { $0.started != nil }
        todosPerDay = planned.isEmpty ? nil : Double(planned.map(\.todos.count).reduce(0, +)) / Double(planned.count)
        let ended = used.filter { $0.ended != nil }
        todosTotal = ended.map(\.todos.count).reduce(0, +)
        todosDone = ended.map { $0.todos.filter(\.done).count }.reduce(0, +)
        let goals = ended.flatMap(\.goals).filter { $0.achieved != nil }
        goalsRated = goals.count
        goalsAchieved = goals.filter { $0.achieved == true }.count
        potential = average(used.compactMap(\.potential))
        var counts: [GoalReason: Int] = [:]
        for goal in goals where goal.achieved == false { if let reason = goal.reason { counts[reason, default: 0] += 1 } }
        reasons = counts.map { (reason: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.reason.rawValue < $1.reason.rawValue }
    }
}
