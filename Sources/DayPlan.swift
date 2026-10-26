import AppKit
import SwiftUI

/// Ein Zeitfenster im Tag (Minuten nach Mitternacht)
struct TimeBlock: Codable, Equatable {
    var start: Int
    var minutes: Int
    var end: Int { start + minutes }
}

/// Timeboxing am Morgen: grob, in Viertelstunden. Es geht um den Überblick über den Tag, nicht um Genauigkeit –
/// den genauen Plan hat man am besten im eigenen Kalender.
enum DayPlan {
    static let step = 15
    static let defaultMinutes = 60
    /// Voreingestellt: Mittagspause von 13 bis 14 Uhr (lässt sich verschieben, ändern und löschen)
    static let defaultLunch = TimeBlock(start: 13 * 60, minutes: 60)
    static let lunchID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!

    /// Auf die Viertelstunde runden
    static func snap(_ minutes: Double) -> Int { Int((minutes / Double(step)).rounded()) * step }

    /// Sichtbarer Bereich: volle Stunden rund um den Arbeitstag und alles, was schon geplant ist
    static func range(workdayStart: Int, workdayEnd: Int, blocks: [TimeBlock]) -> ClosedRange<Int> {
        var start = workdayStart, end = workdayEnd
        if end <= start { (start, end) = (9 * 60, 18 * 60) }
        for block in blocks {
            start = min(start, block.start)
            end = max(end, block.end)
        }
        let first = max(0, start / 60 * 60)
        let last = min(24 * 60, (end + 59) / 60 * 60)
        return first...max(last, first + 60)
    }

    /// Ganz im sichtbaren Bereich halten (mindestens eine Viertelstunde lang)
    static func clamp(_ block: TimeBlock, to range: ClosedRange<Int>) -> TimeBlock {
        var block = block
        block.minutes = max(step, min(block.minutes, range.upperBound - range.lowerBound))
        block.start = max(range.lowerBound, min(block.start, range.upperBound - block.minutes))
        return block
    }

    /// Die erste freie Lücke (erst so lang wie gewünscht, sonst kürzer); ist alles voll, ans Ende
    static func firstFree(minutes: Int, among blocks: [TimeBlock], in range: ClosedRange<Int>) -> TimeBlock {
        let sorted = blocks.sorted { $0.start < $1.start }
        for length in [minutes, 30, step] where length <= minutes {
            var start = range.lowerBound
            while start + length <= range.upperBound {
                guard let clash = sorted.first(where: { $0.start < start + length && $0.end > start }) else {
                    return TimeBlock(start: start, minutes: length)
                }
                start = clash.end
            }
        }
        return clamp(TimeBlock(start: range.upperBound - step, minutes: step), to: range)
    }

    /// Überlappende Blöcke nebeneinander: Spur und Anzahl der Spuren in ihrer Gruppe
    static func lanes(_ blocks: [(id: UUID, block: TimeBlock)]) -> [UUID: (lane: Int, count: Int)] {
        let sorted = blocks.sorted { ($0.block.start, $0.block.end) < ($1.block.start, $1.block.end) }
        var result: [UUID: (lane: Int, count: Int)] = [:]
        var group: [(id: UUID, lane: Int)] = []
        var laneEnds: [Int] = []
        var groupEnd = Int.min
        func flush() {
            let count = (group.map(\.lane).max() ?? -1) + 1
            for item in group { result[item.id] = (item.lane, count) }
            group = []
            laneEnds = []
        }
        for item in sorted {
            if item.block.start >= groupEnd, !group.isEmpty { flush() }
            let lane = laneEnds.firstIndex { $0 <= item.block.start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(item.block.end) } else { laneEnds[lane] = item.block.end }
            group.append((item.id, lane))
            groupEnd = group.count == 1 ? item.block.end : max(groupEnd, item.block.end)
        }
        flush()
        return result
    }

    /// Kurze Stunde für die Kalenderleiste: „9:00“ bzw. „9 AM“
    static func hourText(_ minute: Int) -> String {
        let hour = minute / 60 % 24
        let twelveHours = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false
        guard twelveHours else { return "\(hour):00" }
        return "\(hour % 12 == 0 ? 12 : hour % 12) \(hour < 12 ? "AM" : "PM")"
    }

    /// z. B. „9:00–10:30“ (wie macOS Uhrzeiten schreibt)
    static func timeText(_ block: TimeBlock) -> String {
        TaskItem.timeText(block.start) + "–" + TaskItem.timeText(block.end)
    }
}

extension TodoItem {
    var block: TimeBlock? { start.map { TimeBlock(start: $0, minutes: minutes ?? DayPlan.defaultMinutes) } }
}

extension Array where Element == TodoItem {
    /// Der Frosch: der markierte – oder bei älteren Tagen ohne Markierung der erste
    var frogID: UUID? {
        if let marked = first(where: { $0.frog == true }) { return marked.id }
        return allSatisfy { $0.frog == nil } ? first?.id : nil
    }

    /// Nach Uhrzeit (nicht eingeplante zum Schluss, in ihrer Reihenfolge)
    var byTime: [TodoItem] {
        enumerated().sorted { a, b in
            switch (a.element.start, b.element.start) {
            case let (x?, y?): return x != y ? x < y : a.offset < b.offset
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }
}

// MARK: - Kalender zum Planen

/// Links die To-dos, die noch keine Zeit haben, rechts der leere Tag. Man zieht ein To-do in den Tag (oder tippt es
/// an), verschiebt den Block und zieht ihn unten länger oder kürzer. Mittagspause ist voreingestellt.
struct TimeboxPlanner: View {
    @Binding var todos: [TodoItem]
    @Binding var lunch: TimeBlock?
    let range: ClosedRange<Int>
    var height: CGFloat = 350
    var calendarWidth: CGFloat = 400

    @State private var calendarFrame: CGRect = .zero
    /// Ein To-do wird aus der Liste gezogen (wo die Maus gerade ist)
    @State private var dragging: (id: UUID, location: CGPoint)?
    /// Ein Block wird verschoben bzw. in der Länge verändert (wie er vorher war)
    @State private var moving: (id: UUID, original: TimeBlock)?
    @State private var resizing: (id: UUID, original: TimeBlock)?
    /// Ein Block wird aus dem Kalender hinausgezogen (zurück in die Liste)
    @State private var leaving: UUID?

    private static let space = "planner"
    private static let labelWidth: CGFloat = 46
    private func t(_ de: String, _ en: String) -> String { L10n.s(de, en) }

    private var minuteHeight: CGFloat { height / CGFloat(range.upperBound - range.lowerBound) }
    private var unplaced: [TodoItem] { todos.filter { $0.start == nil } }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            inbox.frame(width: 190, height: height, alignment: .top)
            calendar
                .frame(width: calendarWidth, height: height, alignment: .topLeading)
                .background(GeometryReader { geometry in
                    Color.clear
                        .onAppear { calendarFrame = geometry.frame(in: .named(Self.space)) }
                        .onChange(of: geometry.frame(in: .named(Self.space))) { calendarFrame = $0 }
                })
        }
        .coordinateSpace(name: Self.space)
        .overlay { ghost }
    }

    // MARK: Liste links

    private var inbox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(unplaced.isEmpty ? t("Alles eingeplant", "All planned")
                                  : t("Noch einplanen: \(unplaced.count)", "Still to plan: \(unplaced.count)"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(unplaced.isEmpty ? Color.green : Color.secondary)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(unplaced) { todo in
                        chip(todo)
                            .opacity(dragging?.id == todo.id ? 0.35 : 1)
                            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
                                .onChanged { dragging = (todo.id, $0.location) }
                                .onEnded { value in
                                    drop(todo.id, at: value.location)
                                    dragging = nil
                                })
                            .onTapGesture { placeInFirstGap(todo.id) }
                    }
                    if unplaced.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)
                    }
                }
            }
            Spacer(minLength: 0)
            frogTip
            if lunch == nil {
                Button {
                    lunch = DayPlan.clamp(DayPlan.defaultLunch, to: range)
                } label: {
                    Label(t("Mittagspause", "Lunch break"), systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    private func chip(_ todo: TodoItem) -> some View {
        HStack(spacing: 6) {
            frogButton(todo)
            Text(todo.text)
                .font(.system(.callout, design: .rounded))
                .lineLimit(2)
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.07)))
        .contentShape(Rectangle())
        .help(t("In den Tag ziehen oder antippen", "Drag into the day or click"))
    }

    /// Frosch an der schwersten Aufgabe (genau einer)
    private func frogButton(_ todo: TodoItem) -> some View {
        let isFrog = todos.frogID == todo.id
        return Button { toggleFrog(todo.id) } label: {
            PixelSprite(sprite: PixelArt.frog, colors: PixelArt.frogColors, scale: 1.5)
                .opacity(isFrog ? 1 : 0.25)
        }
        .buttonStyle(.plain)
        .help(isFrog ? t("Dein Frosch: das Schwerste", "Your frog: the hardest task")
                     : t("Zum Frosch machen", "Make this your frog"))
    }

    private var frogTip: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                PixelSprite(sprite: PixelArt.frog, colors: PixelArt.frogColors, scale: 2)
                Text(t("Markier deine schwerste Aufgabe als Frosch und leg sie früh in den Tag.",
                       "Mark your hardest task as the frog and put it early in the day."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if frogIsLate {
                Text(t("Dein Frosch liegt nicht am Anfang. Sicher?", "Your frog isn't first. Sure?"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Liegt eine andere Aufgabe vor dem Frosch?
    private var frogIsLate: Bool {
        guard let frog = todos.first(where: { $0.id == todos.frogID }), let start = frog.start else { return false }
        return todos.contains { $0.id != frog.id && ($0.start ?? Int.max) < start }
    }

    // MARK: Kalender rechts

    private var calendar: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .frame(width: calendarWidth - Self.labelWidth + 4, height: height)
                .offset(x: Self.labelWidth - 4)
            ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: 60)), id: \.self) { minute in
                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: calendarWidth - Self.labelWidth, height: 1)
                    .offset(x: Self.labelWidth, y: y(minute))
                Text(DayPlan.hourText(minute))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: Self.labelWidth - 8, alignment: .trailing)
                    .offset(y: y(minute) - 7)
            }
            dropPreview
            ForEach(placedBlocks, id: \.id) { item in
                blockView(item)
            }
        }
    }

    private struct Placed {
        let id: UUID
        let block: TimeBlock
        let title: String
        let isLunch: Bool
        let isFrog: Bool
    }

    private var placedBlocks: [Placed] {
        let frog = todos.frogID
        var items = todos.compactMap { todo in
            todo.block.map { Placed(id: todo.id, block: $0, title: todo.text, isLunch: false, isFrog: todo.id == frog) }
        }
        if let lunch {
            items.append(Placed(id: DayPlan.lunchID, block: lunch, title: t("Mittagspause", "Lunch break"),
                                isLunch: true, isFrog: false))
        }
        return items
    }

    private func blockView(_ item: Placed) -> some View {
        let lanes = DayPlan.lanes(placedBlocks.map { ($0.id, $0.block) })
        let lane = lanes[item.id] ?? (0, 1)
        let area = calendarWidth - Self.labelWidth - 6
        let width = area / CGFloat(lane.count) - 3
        let blockHeight = max(12, CGFloat(item.block.minutes) * minuteHeight - 2)
        let color: Color = item.isLunch ? .orange : item.isFrog ? .green : .accentColor
        let roomy = blockHeight >= 30
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if item.isFrog { PixelSprite(sprite: PixelArt.frog, colors: PixelArt.frogColors, scale: 1.2) }
                if item.isLunch { Image(systemName: "fork.knife").font(.caption2) }
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(blockHeight >= 44 ? 2 : 1)
                Spacer(minLength: 0)
                Button { remove(item.id) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(item.isLunch ? t("Mittagspause löschen", "Remove lunch break")
                                       : t("Zurück in die Liste", "Back to the list"))
            }
            if roomy {
                Text(DayPlan.timeText(item.block)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, roomy ? 3 : 0)
        .frame(width: width, height: blockHeight, alignment: roomy ? .topLeading : .leading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.opacity(0.22)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(color.opacity(0.75), lineWidth: 1))
        .overlay(alignment: .bottom) { resizeHandle(item, color: color) }
        .opacity(leaving == item.id ? 0.4 : 1)
        .contentShape(Rectangle())
        .gesture(moveGesture(item))
        .offset(x: Self.labelWidth + 2 + CGFloat(lane.lane) * (area / CGFloat(lane.count)), y: y(item.block.start) + 1)
    }

    /// Unten am Block: länger oder kürzer ziehen
    private func resizeHandle(_ item: Placed, color: Color) -> some View {
        Capsule()
            .fill(color.opacity(0.8))
            .frame(width: 18, height: 3)
            .frame(maxWidth: .infinity, minHeight: 8)
            .contentShape(Rectangle())
            .onHover { inside in inside ? NSCursor.resizeUpDown.push() : NSCursor.pop() }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                .onChanged { value in
                    if resizing?.id != item.id { resizing = (item.id, item.block) }
                    guard let original = resizing?.original else { return }
                    let delta = DayPlan.snap(Double(value.translation.height / minuteHeight))
                    let minutes = max(DayPlan.step, min(original.minutes + delta, range.upperBound - original.start))
                    update(item.id, TimeBlock(start: original.start, minutes: minutes))
                }
                .onEnded { _ in resizing = nil })
    }

    private func moveGesture(_ item: Placed) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if moving?.id != item.id { moving = (item.id, item.block) }
                guard let original = moving?.original else { return }
                let delta = DayPlan.snap(Double(value.translation.height / minuteHeight))
                update(item.id, DayPlan.clamp(TimeBlock(start: original.start + delta, minutes: original.minutes), to: range))
                leaving = !item.isLunch && value.location.x < calendarFrame.minX ? item.id : nil
            }
            .onEnded { value in
                // Nach links aus dem Kalender gezogen: zurück in die Liste
                if !item.isLunch, value.location.x < calendarFrame.minX { remove(item.id) }
                moving = nil
                leaving = nil
            }
    }

    /// Gestrichelt: wo das gezogene To-do landen würde
    @ViewBuilder
    private var dropPreview: some View {
        if let dragging, let start = dropStart(at: dragging.location),
           let todo = todos.first(where: { $0.id == dragging.id }) {
            let block = DayPlan.clamp(TimeBlock(start: start, minutes: todo.minutes ?? DayPlan.defaultMinutes), to: range)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: calendarWidth - Self.labelWidth - 6, height: CGFloat(block.minutes) * minuteHeight - 2)
                .offset(x: Self.labelWidth + 2, y: y(block.start) + 1)
        }
    }

    /// Das gezogene To-do folgt der Maus
    @ViewBuilder
    private var ghost: some View {
        if let dragging, let todo = todos.first(where: { $0.id == dragging.id }) {
            chip(todo)
                .frame(width: 180)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                .position(dragging.location)
                .allowsHitTesting(false)
        }
    }

    // MARK: Ändern

    private func y(_ minute: Int) -> CGFloat { CGFloat(minute - range.lowerBound) * minuteHeight }

    /// Oberkante des Blocks: eine Viertelstunde über der Maus (nil = nicht über dem Kalender)
    private func dropStart(at point: CGPoint) -> Int? {
        guard calendarFrame.insetBy(dx: -12, dy: -12).contains(point) else { return nil }
        let minute = Double(range.lowerBound) + Double((point.y - calendarFrame.minY) / minuteHeight)
        return DayPlan.snap(minute - Double(DayPlan.step))
    }

    private func drop(_ id: UUID, at point: CGPoint) {
        guard let start = dropStart(at: point), let index = todos.firstIndex(where: { $0.id == id }) else { return }
        let block = DayPlan.clamp(TimeBlock(start: start, minutes: todos[index].minutes ?? DayPlan.defaultMinutes), to: range)
        todos[index].start = block.start
        todos[index].minutes = block.minutes
    }

    /// Antippen: in die erste freie Stunde
    private func placeInFirstGap(_ id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        let block = DayPlan.firstFree(minutes: todos[index].minutes ?? DayPlan.defaultMinutes,
                                      among: placedBlocks.map(\.block), in: range)
        withAnimation(.easeOut(duration: 0.2)) {
            todos[index].start = block.start
            todos[index].minutes = block.minutes
        }
    }

    private func update(_ id: UUID, _ block: TimeBlock) {
        if id == DayPlan.lunchID {
            lunch = block
        } else if let index = todos.firstIndex(where: { $0.id == id }) {
            todos[index].start = block.start
            todos[index].minutes = block.minutes
        }
    }

    private func remove(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.2)) {
            if id == DayPlan.lunchID {
                lunch = nil
            } else if let index = todos.firstIndex(where: { $0.id == id }) {
                todos[index].start = nil // die Länge bleibt, falls es wieder hineinkommt
            }
        }
    }

    private func toggleFrog(_ id: UUID) {
        let makeFrog = todos.frogID != id
        for index in todos.indices { todos[index].frog = makeFrog && todos[index].id == id }
    }
}
