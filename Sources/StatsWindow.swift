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
    /// 0 = diese Woche, -1 = letzte Woche …
    @State private var weekOffset = 0
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
    private var canGoBack: Bool { store.hasData(before: week.start) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                summary
                card(title: t("Aktiv gearbeitet", "Active work"), icon: "keyboard", color: .blue, info: activeInfo) { activeChart }
                card(title: t("Pausen", "Breaks"), icon: "cup.and.saucer.fill", color: .brown, info: breakInfo) { breakChart }
                card(title: t("Apps im Blick", "Apps to watch"), icon: "square.grid.2x2.fill", color: .teal) { appsList }
                pastWeeks
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
            VStack(alignment: .leading, spacing: 4) {
                Text(t("Statistik", "Statistics"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                HStack(spacing: 10) {
                    Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.borderless)
                        .disabled(!canGoBack)
                        .help(t("Woche davor", "Previous week"))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(weekTitle(offset: weekOffset))
                            .font(.system(.headline, design: .rounded))
                        Text(rangeText(week))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 150, alignment: .leading)
                    Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.borderless)
                        .disabled(weekOffset >= 0)
                        .help(t("Woche danach", "Next week"))
                }
            }
            .padding(.bottom, 6)
            Spacer()
        }
    }

    /// Was die Katze zur Woche denkt
    private var comment: String {
        let total = week.total
        let asked = total.breaksTaken + total.breaksSkipped
        if total.isEmpty {
            return weekOffset == 0 ? t("Die Woche ist noch frisch.", "The week is still fresh.")
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

    private var summary: some View {
        let now = week.total, before = comparison
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

    /// Ausgewählte Apps: aktive Zeit diese Woche, längste zuerst
    private var appsList: some View {
        let times = week.total.apps
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
