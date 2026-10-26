import AppKit
import Charts
import Combine
import SwiftUI

/// Fenster mit der Statistik: diese Woche und die Wochen davor.
@MainActor
final class StatsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let store: StatsStore
    private let settings: AppSettings
    private var coatWatch: AnyCancellable?

    init(store: StatsStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    /// Geschlossen: Inhalt verwerfen, damit nichts im Verborgenen weiterläuft
    func windowWillClose(_ notification: Notification) {
        window?.contentView = NSView()
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 760),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.minSize = NSSize(width: 560, height: 480)
            window.delegate = self
            window.center()
            self.window = window
            coatWatch = settings.$coat.sink { [weak window] coat in window?.appearance = coat.appearance }
        }
        if !(window?.contentView is NSHostingView<StatsView>) {
            window?.contentView = NSHostingView(rootView: StatsView(store: store, settings: settings))
        }
        window?.title = L10n.s("Pixelcat Statistik", "Pixelcat Statistics")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct StatsView: View {
    @ObservedObject var store: StatsStore
    @ObservedObject var settings: AppSettings
    enum Mode: Hashable { case day, week }
    @State private var mode: Mode

    init(store: StatsStore, settings: AppSettings, mode: Mode = .week) {
        self.store = store
        self.settings = settings
        _mode = State(initialValue: mode)
    }
    /// 0 = diese Woche, -1 = letzte Woche …
    @State private var weekOffset = 0
    /// 0 = heute, -1 = gestern …
    @State private var dayOffset = 0
    @State private var hoveredHour: Int?
    @State private var hoveredActiveDay: String?
    @State private var hoveredBreakDay: String?
    @Environment(\.colorScheme) private var colorScheme

    /// Geprüfte Farben (hell/dunkel) für die beiden Reihen
    private var blue: Color { colorScheme == .dark ? Color(hex: 0x3987E5) : Color(hex: 0x2A78D6) }
    private var orange: Color { colorScheme == .dark ? Color(hex: 0xD95926) : Color(hex: 0xEB6834) }
    private var green: Color { colorScheme == .dark ? Color(hex: 0x199E70) : Color(hex: 0x1BAF7A) }

    private func t(_ de: String, _ en: String) -> String { L10n.s(de, en) }

    private var week: WeekStats { store.week(containing: Date(), offset: weekOffset) }
    private var previous: WeekStats { store.week(containing: Date(), offset: weekOffset - 1) }
    /// Zum Vergleich: die Woche davor – in der laufenden Woche nur bis zum selben Wochentag, sonst wäre es unfair
    private var comparison: DayStats {
        guard weekOffset == 0 else { return previous.total }
        let today = store.calendar.startOfDay(for: Date())
        let elapsed = week.days.filter { $0.date <= today }.count
        return previous.days.prefix(elapsed).reduce(DayStats()) { $0 + $1.stats }
    }
    private var day: Date { store.calendar.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date() }
    private var canGoBack: Bool {
        mode == .week ? store.hasData(before: week.start)
            : store.hasData(before: store.calendar.startOfDay(for: day)) || store.journals.keys.contains { $0 < dayKey(day) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if mode == .week {
                    summary(week.total, compare: comparison)
                    card(title: t("Aktiv gearbeitet", "Active work"), icon: "keyboard", color: .blue, info: activeInfo) { activeChart }
                    card(title: t("Pausen", "Breaks"), icon: "cup.and.saucer.fill", color: .brown, info: breakInfo) { breakChart }
                    journalWeekCard
                    card(title: t("Apps im Blick", "Apps to watch"), icon: "square.grid.2x2.fill", color: .teal) {
                        appsList(week.total.apps)
                    }
                    trendCard
                    pastWeeks
                } else {
                    summary(store.day(day), compare: nil)
                    card(title: t("Aktiv über den Tag", "Active through the day"), icon: "clock", color: .blue,
                         info: activeInfo) { hourChart }
                    dayJournalCard
                    card(title: t("Apps im Blick", "Apps to watch"), icon: "square.grid.2x2.fill", color: .teal) {
                        appsList(store.day(day).apps)
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 34)
            .padding(.bottom, 24)
        }
        .background(PixelBackdrop(coat: settings.coat))
        .environment(\.colorScheme, settings.coat.colorScheme)
        .frame(minWidth: 560, minHeight: 480)
        .id(settings.language)
    }

    // MARK: Kopf: Katze mit Kommentar, Woche wählen

    private var header: some View {
        HStack(alignment: .bottom, spacing: 18) {
            VStack(spacing: 2) {
                PixelSprite(sprite: BubbleFrames(text: comment).whole, colors: BubbleFrames.colors, scale: 2)
                    .offset(x: 14)
                PixelCat(coat: settings.coat, pose: .sit, scale: 3)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    Text(t("Statistik", "Statistics"))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Picker("", selection: $mode) {
                        Text(t("Tag", "Day")).tag(Mode.day)
                        Text(t("Woche", "Week")).tag(Mode.week)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                HStack(spacing: 10) {
                    Button { mode == .week ? (weekOffset -= 1) : (dayOffset -= 1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.borderless)
                        .disabled(!canGoBack)
                        .help(mode == .week ? t("Woche davor", "Previous week") : t("Tag davor", "Previous day"))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(mode == .week ? weekTitle(offset: weekOffset) : dayTitle)
                            .font(.system(.headline, design: .rounded))
                        Text(mode == .week ? rangeText(week) : dayDateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 150, alignment: .leading)
                    Button { mode == .week ? (weekOffset += 1) : (dayOffset += 1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.borderless)
                        .disabled(mode == .week ? weekOffset >= 0 : dayOffset >= 0)
                        .help(mode == .week ? t("Woche danach", "Next week") : t("Tag danach", "Next day"))
                }
            }
            .padding(.bottom, 6)
            Spacer()
        }
    }

    /// Was die Katze zur Woche bzw. zum Tag denkt
    private var comment: String {
        let total = mode == .week ? week.total : store.day(day)
        let asked = total.breaksTaken + total.breaksSkipped
        if mode == .day, let journal = Optional(store.journal(for: day)), let start = journal.moodStart,
           let end = journal.moodEnd, end > start {
            return t("Der Tag hat dir gutgetan!", "Today did you good!")
        }
        if total.isEmpty {
            let current = mode == .week ? weekOffset == 0 : dayOffset == 0
            return current ? (mode == .week ? t("Die Woche ist noch frisch.", "The week is still fresh.")
                                            : t("Der Tag ist noch frisch.", "The day is still fresh."))
                : t("Da war es ruhig.", "That was a quiet one.")
        }
        guard asked >= 3 else {
            return total.activeSeconds > 3600 ? t("Du warst fleißig!", "You worked hard!") : t("Schön, dass du da bist.", "Nice to see you.")
        }
        let rate = Double(total.breaksTaken) / Double(asked)
        if rate >= 0.8 { return t("Klasse, fast alle Pausen!", "Great, almost all breaks!") }
        if rate >= 0.5 { return t("Gut! Ein paar Pausen mehr?", "Good! A few more breaks?") }
        return t("Mehr Pausen tun dir gut.", "More breaks will do you good.")
    }

    // MARK: Kennzahlen

    /// Vier Kennzahlen; ohne Vergleich (Tagesansicht) ohne Pfeile
    private func summary(_ now: DayStats, compare before: DayStats?) -> some View {
        let before = before ?? DayStats()
        let compare = mode == .week
        func delta(_ a: Int, _ b: Int, unit: String = "") -> String? { compare ? self.delta(a, b, unit: unit) : nil }
        return HStack(spacing: 12) {
            StatTile(icon: "cup.and.saucer.fill", color: .brown, value: "\(now.breaksTaken)",
                     caption: t("Pausen gemacht", "Breaks taken"),
                     detail: now.breaksSkipped > 0 ? t("\(now.breaksSkipped) weggedrückt", "\(now.breaksSkipped) put off") : nil,
                     change: delta(now.breaksTaken, before.breaksTaken))
            StatTile(icon: "keyboard", color: .blue, value: Self.hoursText(now.activeSeconds),
                     caption: t("aktiv gearbeitet", "active work"),
                     detail: now.musicSeconds >= 60 ? t("davon \(Self.hoursText(now.musicSeconds)) mit Musik",
                                                        "\(Self.hoursText(now.musicSeconds)) with music") : nil,
                     change: delta(Int(now.activeSeconds / 3600), Int(before.activeSeconds / 3600), unit: t("Std.", "h")))
            StatTile(icon: "timer", color: .red, value: "\(now.pomodoros)",
                     caption: t("Pomodoros", "Pomodoros"), detail: nil,
                     change: delta(now.pomodoros, before.pomodoros))
            StatTile(icon: "drop.fill", color: .cyan, value: "\(now.drinks)",
                     caption: t("mal getrunken", "drinks"),
                     detail: now.drinksSkipped > 0 ? t("\(now.drinksSkipped) ausgelassen", "\(now.drinksSkipped) skipped") : nil,
                     change: delta(now.drinks, before.drinks))
        }
    }

    /// Vergleich mit der Woche davor, z. B. „▲ 3 mehr als die Woche davor“
    private func delta(_ now: Int, _ before: Int, unit: String = "") -> String? {
        guard !previous.total.isEmpty else { return nil }
        let unitText = unit.isEmpty ? "" : " " + unit
        if now > before { return t("▲ \(now - before)\(unitText) mehr", "▲ \(now - before)\(unitText) more") }
        if now < before { return t("▼ \(before - now)\(unitText) weniger", "▼ \(before - now)\(unitText) less") }
        return t("wie die Woche davor", "same as before")
    }

    // MARK: Diagramme

    private struct DayValue: Identifiable {
        let id: String // Kurzname des Tags, z. B. „Mo“
        let date: Date
        let stats: DayStats
        var hours: Double { stats.activeSeconds / 3600 }
    }

    private var dayValues: [DayValue] {
        week.days.map { DayValue(id: weekdayText($0.date), date: $0.date, stats: $0.stats) }
    }

    private var activeChart: some View {
        let values = dayValues
        let busiest = values.max { $0.hours < $1.hours }
        let quiet = t("Ohne Musik", "Without music"), music = t("Mit Musik", "With music")
        let total = week.total
        let share = total.activeSeconds > 0 ? Int((total.musicSeconds / total.activeSeconds * 100).rounded()) : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                LegendChip(color: blue, text: quiet)
                LegendChip(color: green, text: music)
                    .help(t("Es lief Ton, meist Musik, manchmal auch ein Video oder Podcast. Videocalls zählen nicht.",
                            "Sound was playing, usually music, sometimes a video or podcast. Video calls don't count."))
                Spacer()
                if let id = hoveredActiveDay, let day = values.first(where: { $0.id == id }) {
                    Text(t("\(id): \(Self.hoursText(day.stats.activeSeconds)), davon \(Self.hoursText(day.stats.musicSeconds)) mit Musik",
                           "\(id): \(Self.hoursText(day.stats.activeSeconds)), \(Self.hoursText(day.stats.musicSeconds)) with music"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if total.activeSeconds > 0 {
                    Label(t("\(share) % mit Musik", "\(share) % with music"), systemImage: "music.note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(values) { day in
                    let faded = hoveredActiveDay != nil && hoveredActiveDay != day.id
                    BarMark(x: .value(t("Tag", "Day"), day.id),
                            y: .value(quiet, max(0, day.stats.activeSeconds - day.stats.musicSeconds) / 3600), width: .ratio(0.5))
                        .foregroundStyle(by: .value(t("Art", "Kind"), quiet))
                        .cornerRadius(4)
                        .opacity(faded ? 0.45 : 1)
                    BarMark(x: .value(t("Tag", "Day"), day.id), y: .value(music, day.stats.musicSeconds / 3600), width: .ratio(0.5))
                        .foregroundStyle(by: .value(t("Art", "Kind"), music))
                        .cornerRadius(4)
                        .opacity(faded ? 0.45 : 1)
                        .annotation(position: .top) {
                            // Nur der fleißigste Tag (oder der unter der Maus) bekommt eine Zahl
                            if day.hours > 0, day.id == (hoveredActiveDay ?? busiest?.id) {
                                Text(Self.hoursText(day.stats.activeSeconds))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                }
            }
            .chartForegroundStyleScale([quiet: blue, music: green])
            .chartLegend(.hidden) // eigene Legende oben, in Textfarbe
            .chartXScale(domain: values.map(\.id))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel { if let hours = value.as(Double.self) { Text("\(Int(hours)) h") } }
                }
            }
            .chartXAxis { AxisMarks { _ in AxisValueLabel() } }
            .chartOverlay { proxy in hoverLayer(proxy) { hoveredActiveDay = $0 } }
            .frame(height: 170)
        }
    }

    /// Ausgewählte Apps: aktive Zeit, längste zuerst
    private func appsList(_ times: [String: Double]) -> some View {
        let apps = settings.trackedApps.map { (id: $0, seconds: times[$0] ?? 0) }.sorted { $0.seconds > $1.seconds }
        let longest = max(1, apps.first?.seconds ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            if apps.isEmpty {
                Text(t("Wähle in den Einstellungen unter „Apps im Blick“ Apps wie Anki, dann siehst du hier, wie lange du darin aktiv warst.",
                       "Pick apps like Anki in Settings under “Apps to watch” to see here how long you were active in them."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(apps, id: \.id) { app in
                HStack(spacing: 10) {
                    if let icon = AppInfo.icon(app.id) {
                        Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                    }
                    Text(AppInfo.name(app.id))
                        .frame(width: 130, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(blue)
                            .frame(width: max(app.seconds > 0 ? 4 : 0, geometry.size.width * app.seconds / longest))
                    }
                    .frame(height: 10)
                    Text(Self.hoursText(app.seconds))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .trailing)
                }
            }
        }
    }

    private var breakChart: some View {
        let values = dayValues
        let taken = t("Gemacht", "Taken"), skipped = t("Weggedrückt", "Put off")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                LegendChip(color: blue, text: taken)
                LegendChip(color: orange, text: skipped)
                Spacer()
                if let id = hoveredBreakDay, let day = values.first(where: { $0.id == id }) {
                    Text(t("\(id): \(day.stats.breaksTaken) gemacht, \(day.stats.breaksSkipped) weggedrückt",
                           "\(id): \(day.stats.breaksTaken) taken, \(day.stats.breaksSkipped) put off"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(values) { day in
                    BarMark(x: .value(t("Tag", "Day"), day.id), y: .value(taken, day.stats.breaksTaken), width: .ratio(0.5))
                        .foregroundStyle(by: .value(t("Art", "Kind"), taken))
                        .cornerRadius(4)
                        .opacity(hoveredBreakDay == nil || hoveredBreakDay == day.id ? 1 : 0.45)
                    BarMark(x: .value(t("Tag", "Day"), day.id), y: .value(skipped, day.stats.breaksSkipped), width: .ratio(0.5))
                        .foregroundStyle(by: .value(t("Art", "Kind"), skipped))
                        .cornerRadius(4)
                        .opacity(hoveredBreakDay == nil || hoveredBreakDay == day.id ? 1 : 0.45)
                }
            }
            .chartForegroundStyleScale([taken: blue, skipped: orange])
            .chartLegend(.hidden) // eigene Legende oben, in Textfarbe
            .chartXScale(domain: values.map(\.id))
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel()
                }
            }
            .chartXAxis { AxisMarks { _ in AxisValueLabel() } }
            .chartOverlay { proxy in hoverLayer(proxy) { hoveredBreakDay = $0 } }
            .frame(height: 150)
        }
    }

    /// Unsichtbare Fläche über dem Diagramm: Welcher Tag liegt unter der Maus?
    private func hoverLayer(_ proxy: ChartProxy, _ select: @escaping (String?) -> Void) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        let origin = geometry[proxy.plotAreaFrame].origin
                        select(proxy.value(atX: point.x - origin.x, as: String.self))
                    case .ended:
                        select(nil)
                    }
                }
        }
    }

    // MARK: Tagesansicht

    private var dayTitle: String {
        switch dayOffset {
        case 0: return t("Heute", "Today")
        case -1: return t("Gestern", "Yesterday")
        default: return weekdayLongText(day)
        }
    }

    private var dayDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isGerman ? "de_DE" : "en_US")
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: day)
    }

    private func weekdayLongText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isGerman ? "de_DE" : "en_US")
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter.string(from: date)
    }

    private func dayKey(_ date: Date) -> String {
        let parts = store.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Aktive Minuten pro Stunde – von der ersten bis zur letzten aktiven Stunde (mindestens 8 bis 18 Uhr)
    private var hourChart: some View {
        let hours = store.day(day).hours
        let active = hours.compactMap { Int($0.key) }
        let first = min(active.min() ?? 8, 8), last = max(active.max() ?? 18, 18)
        let values = (first...last).map { (hour: $0, minutes: (hours[String($0)] ?? 0) / 60) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                if let hour = hoveredHour, let value = values.first(where: { $0.hour == hour }) {
                    Text(t("\(hour) Uhr: \(Int(value.minutes.rounded())) min aktiv", "\(hour):00: \(Int(value.minutes.rounded())) min active"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(t("Minuten pro Stunde", "Minutes per hour")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(values, id: \.hour) { value in
                    BarMark(x: .value(t("Stunde", "Hour"), String(value.hour)), y: .value("min", value.minutes), width: .ratio(0.6))
                        .foregroundStyle(blue.opacity(hoveredHour == nil || hoveredHour == value.hour ? 1 : 0.45))
                        .cornerRadius(3)
                }
            }
            .chartXScale(domain: values.map { String($0.hour) })
            .chartYScale(domain: 0...60)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 30, 60]) { _ in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    if let label = value.as(String.self), let hour = Int(label), hour % 2 == 0 { AxisValueLabel() }
                }
            }
            .chartOverlay { proxy in hoverLayer(proxy) { hoveredHour = $0.flatMap(Int.init) } }
            .frame(height: 150)
        }
    }

    /// Das Tagebuch des Tages: Stimmung, To-dos, Ziele, ausgeschöpftes Potenzial
    private var dayJournalCard: some View {
        let journal = store.journal(for: day)
        return card(title: t("Dein Tag", "Your day"), icon: "sun.max.fill", color: .orange) {
            if journal.isEmpty {
                Text(t("Starte deinen Tag über das Menü (Tag starten …). Dann siehst du hier Stimmung, To-dos und Ziele.",
                       "Start your day from the menu (Start your day …). Then you'll see mood, to-dos and goals here."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        JournalNumber(title: t("Stimmung morgens", "Mood morning"), value: journal.moodStart.map { "\($0)" })
                        Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                        JournalNumber(title: t("Stimmung abends", "Mood evening"), value: journal.moodEnd.map { "\($0)" })
                        Spacer()
                        JournalNumber(title: t("Ausgeschöpft", "Made the most"), value: journal.potential.map { "\($0)/10" })
                    }
                    if !journal.todos.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(t("To-dos (\(journal.todos.filter(\.done).count) von \(journal.todos.count))",
                                   "To-dos (\(journal.todos.filter(\.done).count) of \(journal.todos.count))"))
                                .font(.callout.weight(.semibold))
                            ForEach(Array(journal.todos.enumerated()), id: \.element.id) { index, todo in
                                HStack(spacing: 8) {
                                    Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(todo.done ? Color.green : Color.secondary)
                                    if index == 0 { PixelSprite(sprite: PixelArt.frog, colors: PixelArt.frogColors, scale: 2) }
                                    Text(todo.text).strikethrough(todo.done).foregroundStyle(todo.done ? .secondary : .primary)
                                }
                                .font(.callout)
                            }
                        }
                    }
                    if let improvement = journal.improvement {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Für morgen", "For tomorrow")).font(.callout.weight(.semibold))
                                Text(improvement).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !journal.goals.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(t("Ziele", "Goals")).font(.callout.weight(.semibold))
                            ForEach(journal.goals) { goal in
                                HStack(spacing: 8) {
                                    Image(systemName: goal.achieved == true ? "checkmark.seal.fill"
                                                      : goal.achieved == false ? "xmark.seal" : "seal")
                                        .foregroundStyle(goal.achieved == true ? Color.green : Color.secondary)
                                    Text(goal.text)
                                    if let reason = goal.reasonText {
                                        Text(reason).font(.caption).foregroundStyle(.secondary)
                                            .padding(.horizontal, 8).padding(.vertical, 2)
                                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                                    }
                                }
                                .font(.callout)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Tagebuch in der Woche und im Verlauf

    /// Tagesbilanz der Woche: Durchschnitte und Stimmung pro Tag (nur, wenn es Tagebuch-Einträge gibt)
    @ViewBuilder
    private var journalWeekCard: some View {
        let days = store.journals(in: week)
        let summary = JournalSummary(days.map(\.journal))
        if summary.days > 0 {
            card(title: t("Tagesbilanz", "Daily review"), icon: "sun.max.fill", color: .orange, info: journalInfo) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(summary.days == 1
                         ? t("Durchschnitt über 1 Tag mit Tagebuch", "Average over 1 day with a journal")
                         : t("Durchschnitt über \(summary.days) Tage mit Tagebuch", "Average over \(summary.days) days with a journal"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    journalNumbers(summary)
                    moodChart(days.map { (label: weekdayText($0.date), start: $0.journal.moodStart, end: $0.journal.moodEnd) },
                              domain: week.days.map { weekdayText($0.date) })
                }
            }
        }
    }

    /// Verlauf der letzten 8 Wochen: Stimmung im Schnitt und häufigste Gründe für offene Ziele
    @ViewBuilder
    private var trendCard: some View {
        let weeks = (0..<8).reversed().map { store.week(containing: Date(), offset: weekOffset - $0) }
        let all = weeks.flatMap { store.journals(in: $0).map(\.journal) }
        let summary = JournalSummary(all)
        if summary.days >= 3 {
            card(title: t("Verlauf (8 Wochen)", "Trend (8 weeks)"), icon: "chart.line.uptrend.xyaxis", color: .purple,
                 info: journalInfo) {
                VStack(alignment: .leading, spacing: 14) {
                    moodChart(weeks.map { week -> (label: String, start: Int?, end: Int?) in
                        let s = JournalSummary(store.journals(in: week).map(\.journal))
                        let number = store.calendar.component(.weekOfYear, from: week.start)
                        return (t("KW \(number)", "W\(number)"), s.moodStart.map { Int($0.rounded()) }, s.moodEnd.map { Int($0.rounded()) })
                    }, domain: weeks.map { t("KW \(store.calendar.component(.weekOfYear, from: $0.start))",
                                              "W\(store.calendar.component(.weekOfYear, from: $0.start))") },
                       caption: t("Ø Stimmung pro Woche, 1 bis 10", "Ø mood per week, 1 to 10"))
                    journalNumbers(summary)
                    if !summary.reasons.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(t("Warum Ziele offen blieben", "Why goals stayed open")).font(.callout.weight(.semibold))
                            let most = max(1, summary.reasons.first?.count ?? 1)
                            ForEach(Array(summary.reasons.prefix(5).enumerated()), id: \.offset) { index, item in
                                HStack(spacing: 10) {
                                    Label(item.reason.title, systemImage: item.reason.icon)
                                        .frame(width: 200, alignment: .leading)
                                    GeometryReader { geometry in
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(blue.opacity(index == 0 ? 1 : 0.6))
                                            .frame(width: max(4, geometry.size.width * Double(item.count) / Double(most)))
                                    }
                                    .frame(height: 10)
                                    Text("\(item.count)×").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                        .frame(width: 40, alignment: .trailing)
                                }
                                .font(.callout)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Kleine Kennzahlen zum Tagebuch
    private func journalNumbers(_ summary: JournalSummary) -> some View {
        func number(_ value: Double?) -> String? { value.map { String(format: L10n.isGerman ? "%.1f" : "%.1f", $0).replacingOccurrences(of: ".", with: L10n.isGerman ? "," : ".") } }
        func percent(_ value: Double?) -> String? { value.map { "\(Int(($0 * 100).rounded())) %" } }
        let change = summary.moodChange.map { ($0 >= 0 ? "+" : "") + (number($0) ?? "") }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], alignment: .leading, spacing: 10) {
            // Alles Durchschnitte über die Tage mit Tagebuch
            JournalNumber(title: t("Ø Stimmung morgens", "Ø mood morning"), value: number(summary.moodStart))
            JournalNumber(title: t("Ø Stimmung abends", "Ø mood evening"), value: number(summary.moodEnd))
            JournalNumber(title: t("Ø Veränderung am Tag", "Ø change over the day"), value: change)
            JournalNumber(title: t("Ø To-dos pro Tag", "Ø to-dos per day"), value: number(summary.todosPerDay))
            JournalNumber(title: t("Ø To-dos erledigt", "Ø to-dos done"), value: percent(summary.todoRate))
            JournalNumber(title: t("Ø Ziele erreicht", "Ø goals reached"), value: percent(summary.goalRate))
            JournalNumber(title: t("Ø Ausgeschöpft", "Ø made the most"), value: number(summary.potential).map { $0 + "/10" })
        }
    }

    /// Stimmung morgens und abends als zwei Linien (Skala 1 bis 10)
    private func moodChart(_ values: [(label: String, start: Int?, end: Int?)], domain: [String],
                           caption: String = L10n.s("Stimmung, 1 bis 10", "Mood, 1 to 10")) -> some View {
        let morning = t("Morgens", "Morning"), evening = t("Abends", "Evening")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                LegendChip(color: blue, text: morning)
                LegendChip(color: orange, text: evening)
                Spacer()
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(values, id: \.label) { value in
                    if let start = value.start {
                        LineMark(x: .value(t("Tag", "Day"), value.label), y: .value(morning, start), series: .value("", morning))
                            .foregroundStyle(blue).lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value(t("Tag", "Day"), value.label), y: .value(morning, start))
                            .foregroundStyle(blue).symbolSize(60)
                    }
                    if let end = value.end {
                        LineMark(x: .value(t("Tag", "Day"), value.label), y: .value(evening, end), series: .value("", evening))
                            .foregroundStyle(orange).lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value(t("Tag", "Day"), value.label), y: .value(evening, end))
                            .foregroundStyle(orange).symbolSize(60)
                    }
                }
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: 1...10)
            .chartYAxis {
                AxisMarks(position: .leading, values: [1, 5, 10]) { _ in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel()
                }
            }
            .chartXAxis { AxisMarks { _ in AxisValueLabel() } }
            .frame(height: 140)
        }
    }

    private var journalInfo: [(String, String)] {
        [(t("Woher die Zahlen kommen", "Where the numbers come from"),
          t("Aus „Tag starten“ und „Tag beenden“: Stimmung morgens und abends, deine To-dos und Ziele und wie viel du rausgeholt hast.",
            "From “Start your day” and “End your day”: mood in the morning and evening, your to-dos and goals and how much you made of the day.")),
         (t("Veränderung am Tag", "Change over the day"),
          t("Stimmung abends minus morgens, im Schnitt über die Tage mit beiden Werten.",
            "Evening mood minus morning mood, averaged over the days with both.")),
         ("", t("Alles bleibt auf deinem Mac.", "Everything stays on your Mac."))]
    }

    // MARK: Vergangene Wochen

    private var pastWeeks: some View {
        let weeks = (1...8).map { offset in (offset: -offset, week: store.week(containing: Date(), offset: -offset)) }
            .filter { !$0.week.total.isEmpty }
        return Group {
            if !weeks.isEmpty {
                card(title: t("Letzte Wochen", "Past weeks"), icon: "calendar", color: .indigo) {
                    VStack(spacing: 0) {
                        ForEach(weeks, id: \.offset) { item in
                            Button { weekOffset = item.offset } label: { weekRow(item.week, offset: item.offset) }
                                .buttonStyle(.plain)
                            if item.offset != weeks.last?.offset { Divider().opacity(0.5) }
                        }
                    }
                }
            }
        }
    }

    private func weekRow(_ week: WeekStats, offset: Int) -> some View {
        let total = week.total
        let asked = total.breaksTaken + total.breaksSkipped
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(weekTitle(offset: offset)).font(.system(.callout, design: .rounded).weight(.semibold))
                Text(rangeText(week)).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 170, alignment: .leading)
            Label(t("\(total.breaksTaken) von \(asked)", "\(total.breaksTaken) of \(asked)"),
                  systemImage: "cup.and.saucer")
                .frame(width: 90, alignment: .leading)
            Label(Self.hoursText(total.activeSeconds), systemImage: "keyboard")
                .frame(width: 100, alignment: .leading)
            Label("\(total.pomodoros)", systemImage: "timer")
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .font(.callout)
        .foregroundStyle(weekOffset == offset ? Color.accentColor : Color.primary)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: Was gezählt wird

    /// Erklärung zu „Aktiv gearbeitet“ und vor allem zu „mit Musik“
    private var activeInfo: [(String, String)] {
        [(t("Aktiv gearbeitet", "Active work"),
          t("Zählt, solange du tippst, klickst oder die Maus bewegst. Bis zu einer Minute Lesen ohne Eingabe zählt mit.",
            "Counts while you type, click or move the mouse. Up to a minute of reading without input counts too.")),
         (t("Mit Musik", "With music"),
          t("Während du aktiv warst, lief auf deinem Mac Ton über Lautsprecher oder Kopfhörer. Das ist meist Musik, kann aber auch ein Video, ein Podcast oder ein anderer Ton sein. Videocalls und das Schnurren der Katze zählen nicht mit. Pixelcat fragt dafür nur, ob gerade Ton läuft, nicht was.",
            "While you were active, sound was playing on your Mac through speakers or headphones. Usually that's music, but it can also be a video, a podcast or another sound. Video calls and the cat's purring don't count. Pixelcat only asks whether sound is playing, not what.")),
         ("", t("Alles bleibt auf deinem Mac.", "Everything stays on your Mac."))]
    }

    private var breakInfo: [(String, String)] {
        [(t("Gemacht", "Taken"),
          t("Daumen hoch, „Pause machen“ im Menü und Pausen, in denen du weg vom Rechner warst.",
            "Thumbs up, “Take a break” in the menu and breaks while you were away from your Mac.")),
         (t("Weggedrückt", "Put off"), t("Daumen runter bei der Pausenfrage.", "Thumbs down on the break question.")),
         (t("Trinken", "Drinks"),
          t("Daumen hoch zählt als getrunken, Daumen runter als ausgelassen.",
            "Thumbs up counts as a drink, thumbs down as skipped."))]
    }

    // MARK: Bausteine

    private func card<Content: View>(title: String, icon: String, color: Color, info: [(String, String)]? = nil,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(title, icon: icon, color: color)
                Spacer()
                if let info { InfoButton(entries: info, help: t("Was wird gezählt?", "What is counted?")) }
            }
            content()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.background.opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.secondary.opacity(0.15)))
    }

    private func weekTitle(offset: Int) -> String {
        switch offset {
        case 0: return t("Diese Woche", "This week")
        case -1: return t("Letzte Woche", "Last week")
        default:
            let number = store.calendar.component(.weekOfYear, from: store.week(containing: Date(), offset: offset).start)
            return t("KW \(number)", "Week \(number)")
        }
    }

    private func rangeText(_ week: WeekStats) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isGerman ? "de_DE" : "en_US")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        let end = week.days.last?.date ?? week.start
        return t("\(formatter.string(from: week.start)) bis \(formatter.string(from: end))",
                 "\(formatter.string(from: week.start)) to \(formatter.string(from: end))")
    }

    private func weekdayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isGerman ? "de_DE" : "en_US")
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    /// Aktive Zeit, z. B. „3 h 20 min“ bzw. „45 min“
    static func hoursText(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }
}

/// Eine Kennzahl: Symbol, große Zahl, Beschriftung und der Vergleich mit der Woche davor
private struct StatTile: View {
    let icon: String
    let color: Color
    let value: String
    let caption: String
    let detail: String?
    let change: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.gradient))
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.secondary)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            if let change { Text(change).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.background.opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.secondary.opacity(0.15)))
    }
}

/// Eine kleine Zahl mit Beschriftung (Tagebuch)
private struct JournalNumber: View {
    let title: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let value {
                Text(value).font(.system(size: 20, weight: .bold, design: .rounded))
            } else {
                // Noch kein Wert (z. B. der Abend steht noch aus)
                Text(L10n.s("offen", "open"))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(height: 24, alignment: .bottom)
            }
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Kleines ⓘ: ein Klick zeigt, was gezählt wird
private struct InfoButton: View {
    let entries: [(String, String)]
    let help: String
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 3) {
                        if !entry.0.isEmpty { Text(entry.0).font(.callout.weight(.semibold)) }
                        Text(entry.1)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .frame(width: 320, alignment: .leading)
        }
    }
}

/// Legendenpunkt: Farbe für die Reihe, Text in Textfarbe
private struct LegendChip: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
