import AppKit

/// Was an einem Tag los war: Pausen, aktive Arbeit, Pomodoros, Trinken.
struct DayStats: Codable, Equatable {
    var breaksTaken = 0
    var breaksSkipped = 0
    /// Sekunden, in denen getippt, geklickt oder die Maus bewegt wurde (bis zu einer Minute Lesen zählt mit)
    var activeSeconds = 0.0
    var pomodoros = 0
    var drinks = 0
    var drinksSkipped = 0
    /// Davon aktiv, während Musik (oder anderer Ton) lief – ohne Videocalls
    var musicSeconds = 0.0
    /// Aktive Zeit in ausgewählten Apps (Bundle-ID → Sekunden)
    var apps: [String: Double] = [:]
    /// Aktive Zeit pro Stunde des Tages ("9" → Sekunden), für die Tagesansicht
    var hours: [String: Double] = [:]

    static func + (a: DayStats, b: DayStats) -> DayStats {
        DayStats(breaksTaken: a.breaksTaken + b.breaksTaken, breaksSkipped: a.breaksSkipped + b.breaksSkipped,
                 activeSeconds: a.activeSeconds + b.activeSeconds, pomodoros: a.pomodoros + b.pomodoros,
                 drinks: a.drinks + b.drinks, drinksSkipped: a.drinksSkipped + b.drinksSkipped,
                 musicSeconds: a.musicSeconds + b.musicSeconds, apps: a.apps.merging(b.apps, uniquingKeysWith: +),
                 hours: a.hours.merging(b.hours, uniquingKeysWith: +))
    }

    var isEmpty: Bool { self == DayStats() }
}

/// Ältere Statistik-Dateien kennen noch nicht alle Felder – was fehlt, ist 0
extension DayStats {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        breaksTaken = try values.decodeIfPresent(Int.self, forKey: .breaksTaken) ?? 0
        breaksSkipped = try values.decodeIfPresent(Int.self, forKey: .breaksSkipped) ?? 0
        activeSeconds = try values.decodeIfPresent(Double.self, forKey: .activeSeconds) ?? 0
        pomodoros = try values.decodeIfPresent(Int.self, forKey: .pomodoros) ?? 0
        drinks = try values.decodeIfPresent(Int.self, forKey: .drinks) ?? 0
        drinksSkipped = try values.decodeIfPresent(Int.self, forKey: .drinksSkipped) ?? 0
        musicSeconds = try values.decodeIfPresent(Double.self, forKey: .musicSeconds) ?? 0
        apps = try values.decodeIfPresent([String: Double].self, forKey: .apps) ?? [:]
        hours = try values.decodeIfPresent([String: Double].self, forKey: .hours) ?? [:]
    }
}

/// Name und Symbol einer App aus ihrer Bundle-ID (für Einstellungen und Statistik)
enum AppInfo {
    static func url(_ bundleID: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    static func name(_ bundleID: String) -> String {
        guard let url = url(bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(_ bundleID: String) -> NSImage? { url(bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) } }

    /// Beliebte Apps zum Lernen und Arbeiten – als Vorschlag, wenn sie installiert sind
    static let suggestions = ["net.ankiweb.dtop", "md.obsidian", "notion.id", "com.microsoft.Word", "com.apple.dt.Xcode"]
}

/// Eine Woche: die sieben Tage (in der Reihenfolge des Kalenders, bei uns Montag bis Sonntag) und die Summe
struct WeekStats {
    let start: Date
    let days: [(date: Date, stats: DayStats)]
    var total: DayStats { days.reduce(DayStats()) { $0 + $1.stats } }
}

/// Die Statistik, Tag für Tag. Bleibt auf dem Mac (`~/Library/Application Support/Pixelcat/Statistics.json`)
/// und wird höchstens einmal pro Minute geschrieben.
@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var days: [String: DayStats] = [:]
    /// Tagebuch (Tag starten und beenden), getrennt gespeichert
    @Published private(set) var journals: [String: DayJournal] = [:]
    var calendar = Calendar.current
    private let url: URL?
    private var journalURL: URL? { url?.deletingLastPathComponent().appendingPathComponent("Journal.json") }
    private var dirty = false
    private var lastSave = Date.distantPast

    /// Ohne `url` nur im Speicher (Tests)
    init(url: URL? = StatsStore.defaultURL) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode([String: DayStats].self, from: data) {
            days = stored
        }
        if let journalURL, let data = try? Data(contentsOf: journalURL),
           let stored = try? JSONDecoder().decode([String: DayJournal].self, from: data) {
            journals = stored
        }
    }

    func journal(for date: Date = Date()) -> DayJournal { journals[key(for: date)] ?? DayJournal() }

    /// Tagebuch ändern – wird sofort gespeichert (passiert nur zweimal am Tag)
    func updateJournal(for date: Date = Date(), _ change: (inout DayJournal) -> Void) {
        let key = key(for: date)
        var journal = journals[key] ?? DayJournal()
        change(&journal)
        journals[key] = journal
        guard let journalURL else { return }
        try? FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(journals) { Self.write(data, to: journalURL) }
    }

    /// Der Vorsatz vom letzten Tagesende vor diesem Tag (nach einem Freitag also am Montag)
    func lastImprovement(before date: Date = Date()) -> String? {
        let today = key(for: date)
        return journals.filter { $0.key < today }
            .sorted { $0.key > $1.key }
            .lazy.compactMap { $0.value.improvement?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// Tagebücher der Tage einer Woche
    func journals(in week: WeekStats) -> [(date: Date, journal: DayJournal)] {
        week.days.map { ($0.date, journal(for: $0.date)) }
    }

    /// Nur in der echten App (in Tests gibt es keine Bundle-ID)
    nonisolated static var defaultURL: URL? {
        guard Bundle.main.bundleIdentifier != nil,
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return support.appendingPathComponent("Pixelcat/Statistics.json")
    }

    func record(at date: Date = Date(), _ change: (inout DayStats) -> Void) {
        let key = key(for: date)
        var stats = days[key] ?? DayStats()
        change(&stats)
        days[key] = stats
        dirty = true
    }

    func day(_ date: Date) -> DayStats { days[key(for: date)] ?? DayStats() }

    /// Die Woche, in der `date` liegt (`offset` -1 = die davor)
    func week(containing date: Date, offset: Int = 0) -> WeekStats {
        let shifted = calendar.date(byAdding: .weekOfYear, value: offset, to: date) ?? date
        let start = calendar.dateInterval(of: .weekOfYear, for: shifted)?.start ?? calendar.startOfDay(for: shifted)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map { ($0, day($0)) }
        return WeekStats(start: start, days: days)
    }

    /// Gibt es vor dieser Woche überhaupt Daten? (zum Zurückblättern)
    func hasData(before date: Date) -> Bool {
        let first = key(for: date)
        return days.contains { $0.key < first && !$0.value.isEmpty }
    }

    /// Schreiben, wenn sich etwas geändert hat – höchstens einmal pro Minute (außer `force`)
    func save(force: Bool = false) {
        guard dirty, let url, force || Date().timeIntervalSince(lastSave) >= 60 else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(days), Self.write(data, to: url) {
            dirty = false
            lastSave = Date()
        }
    }

    /// Sicher schreiben: erst daneben, dann in einem Schritt umbenennen (bricht nichts halb ab)
    @discardableResult
    private static func write(_ data: Data, to url: URL) -> Bool {
        let temporary = url.appendingPathExtension("tmp")
        guard (try? data.write(to: temporary)) != nil else { return false }
        return rename(temporary.path, url.path) == 0
    }

    private func key(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
