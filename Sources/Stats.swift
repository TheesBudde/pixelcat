import Foundation

/// Was an einem Tag los war: Pausen, aktive Arbeit, Pomodoros, Trinken.
struct DayStats: Codable, Equatable {
    var breaksTaken = 0
    var breaksSkipped = 0
    /// Sekunden, in denen getippt, geklickt oder die Maus bewegt wurde (bis zu einer Minute Lesen zählt mit)
    var activeSeconds = 0.0
    var pomodoros = 0
    var drinks = 0
    var drinksSkipped = 0

    static func + (a: DayStats, b: DayStats) -> DayStats {
        DayStats(breaksTaken: a.breaksTaken + b.breaksTaken, breaksSkipped: a.breaksSkipped + b.breaksSkipped,
                 activeSeconds: a.activeSeconds + b.activeSeconds, pomodoros: a.pomodoros + b.pomodoros,
                 drinks: a.drinks + b.drinks, drinksSkipped: a.drinksSkipped + b.drinksSkipped)
    }

    var isEmpty: Bool { self == DayStats() }
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
    var calendar = Calendar.current
    private let url: URL?
    private var dirty = false
    private var lastSave = Date.distantPast

    /// Ohne `url` nur im Speicher (Tests)
    init(url: URL? = StatsStore.defaultURL) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode([String: DayStats].self, from: data) {
            days = stored
        }
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
        if let data = try? JSONEncoder().encode(days) {
            try? data.write(to: url, options: .atomic)
            dirty = false
            lastSave = Date()
        }
    }

    private func key(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
