import AppKit
import Combine
import SwiftUI

/// Fenster „Beat-Baukasten“: eigene Lo-Fi-Beats bauen, anhören und als Musik verwenden
@MainActor
final class BeatBuilderWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: AppSettings
    private let preview = BeatPreview()
    private var coatWatch: AnyCancellable?

    /// Offen oder zu: Solange er offen ist, pausiert die Musik im Menü
    private let onOpenChange: (Bool) -> Void

    init(settings: AppSettings, onOpenChange: @escaping (Bool) -> Void) {
        self.settings = settings
        self.onOpenChange = onOpenChange
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.minSize = NSSize(width: 600, height: 560)
            window.delegate = self
            window.center()
            self.window = window
            coatWatch = settings.$coat.sink { [weak window] coat in window?.appearance = coat.appearance }
        }
        if !(window?.contentView is NSHostingView<BeatBuilderView>) {
            window?.contentView = NSHostingView(rootView: BeatBuilderView(settings: settings, preview: preview))
        }
        window?.title = L10n.s("Beat-Baukasten", "Beat Builder")
        onOpenChange(true)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Zu: Vorschau verstummt, Inhalt wird verworfen
    func windowWillClose(_ notification: Notification) {
        preview.stop()
        window?.contentView = NSView()
        onOpenChange(false)
    }
}

/// Probehören im Baukasten (unabhängig von der Musik im Menü)
@MainActor
final class BeatPreview: ObservableObject {
    let player = LofiPlayer()
    @Published private(set) var isPlaying = false

    func toggle(_ beat: LofiBeat, volume: Double) {
        if isPlaying { stop() } else { play(beat, volume: volume) }
    }

    func play(_ beat: LofiBeat, volume: Double) {
        player.volume = Float(volume)
        player.play(beat)
        isPlaying = true
    }

    func stop() {
        player.stop()
        isPlaying = false
    }
}

struct BeatBuilderView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var preview: BeatPreview
    @State private var selectedID: UUID?
    @State private var pendingPreview: DispatchWorkItem?
    @State private var confirmDelete = false
    @State private var confirmReset = false
    /// Blatt für den Namen: neuer Beat oder „Speichern unter …“
    @State private var naming: Naming?

    private enum Naming: Identifiable {
        case new, saveAs
        var id: Self { self }
    }

    private func t(_ de: String, _ en: String) -> String { L10n.s(de, en) }

    private var index: Int {
        settings.lofiBeats.firstIndex { $0.id == (selectedID ?? settings.selectedBeat.id) } ?? 0
    }

    private var beat: Binding<LofiBeat> {
        Binding(
            get: { settings.lofiBeats.indices.contains(index) ? settings.lofiBeats[index] : LofiBeat.presets[0] },
            set: { value in
                guard settings.lofiBeats.indices.contains(index) else { return }
                settings.lofiBeats[index] = value
                schedulePreview(value)
            })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                gridSection
                chordSection
                soundSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            footer
        }
        .background(PixelBackdrop(coat: settings.coat))
        .environment(\.colorScheme, settings.coat.colorScheme)
        .frame(minWidth: 600, minHeight: 560)
        .onAppear { if selectedID == nil { selectedID = settings.selectedBeat.id } }
    }

    // MARK: Kopf: anhören, Beat wählen, neu, speichern unter, zurücksetzen

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    preview.toggle(beat.wrappedValue, volume: settings.musicVolume)
                } label: {
                    Image(systemName: preview.isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.accentColor.gradient))
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])
                .help(preview.isPlaying ? t("Anhalten (Leertaste)", "Stop (Space)") : t("Anhören (Leertaste)", "Listen (Space)"))
                VStack(alignment: .leading, spacing: 4) {
                    TextField("", text: beat.name, prompt: Text(t("Name des Beats", "Beat name")))
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("\(beat.wrappedValue.bpm) BPM · \(beat.wrappedValue.chords.map(\.name).joined(separator: " – "))")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: Binding(get: { settings.lofiBeats.indices.contains(index) ? settings.lofiBeats[index].id : nil },
                                              set: { selectedID = $0; restartPreview() })) {
                    ForEach(settings.lofiBeats) { beat in
                        Text(beat.name.isEmpty ? t("Ohne Namen", "Untitled") : beat.name).tag(Optional(beat.id))
                    }
                }
                .labelsHidden()
                .frame(width: 170)
                .help(t("Beat wechseln", "Switch beat"))
            }
            HStack(spacing: 8) {
                Button { naming = .new } label: { Label(t("Neuer Beat", "New beat"), systemImage: "plus") }
                Button { naming = .saveAs } label: {
                    Label(t("Speichern unter …", "Save as …"), systemImage: "square.and.arrow.down")
                }
                .help(t("Als neuen Beat mit eigenem Namen speichern", "Save as a new beat with its own name"))
                Button { confirmReset = true } label: {
                    Label(t("Zurücksetzen", "Reset"), systemImage: "arrow.counterclockwise")
                }
                .disabled(!beat.wrappedValue.canReset)
                .help(LofiBeat.original(of: beat.wrappedValue) == nil
                      ? t("Nur fertige Beats lassen sich aufs Original zurücksetzen", "Only built-in beats can be reset")
                      : t("Auf das Original zurücksetzen", "Back to the original"))
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label(t("Löschen", "Delete"), systemImage: "trash")
                }
                .disabled(settings.lofiBeats.count <= 1)
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: true, vertical: false)
            if !settings.missingPresets.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text(t("Du hast fertige Beats gelöscht.", "You deleted some built-in beats."))
                        .foregroundStyle(.secondary)
                    Button(t("Zurückholen", "Restore")) { settings.restoreMissingPresets() }
                        .buttonStyle(.link)
                }
                .font(.callout)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 34)
        .padding(.bottom, 6)
        .confirmationDialog(t("„\(beat.wrappedValue.name)“ löschen?", "Delete “\(beat.wrappedValue.name)”?"),
                            isPresented: $confirmDelete) {
            Button(t("Löschen", "Delete"), role: .destructive) { deleteCurrent() }
        }
        .confirmationDialog(t("„\(beat.wrappedValue.name)“ auf das Original zurücksetzen?",
                              "Reset “\(beat.wrappedValue.name)” to the original?"),
                            isPresented: $confirmReset) {
            Button(t("Zurücksetzen", "Reset"), role: .destructive) {
                if let original = LofiBeat.original(of: beat.wrappedValue) { beat.wrappedValue = original }
            }
        } message: {
            Text(t("Deine Änderungen an diesem Beat gehen verloren. Tipp: Vorher mit „Speichern unter …“ sichern.",
                   "Your changes to this beat are lost. Tip: keep them first with “Save as …”."))
        }
        .sheet(item: $naming) { mode in
            NameSheet(title: mode == .new ? t("Neuer Beat", "New beat") : t("Speichern unter …", "Save as …"),
                      message: mode == .new ? t("Ein leerer Beat zum Selberbauen.", "An empty beat to build yourself.")
                                            : t("Speichert diesen Beat als neuen Beat. Das Original bleibt, wie es ist.",
                                                "Saves this beat as a new beat. The original stays as it is."),
                      initial: mode == .new ? t("Mein Beat", "My beat") : beat.wrappedValue.name + t(" (Kopie)", " (copy)")) { name in
                if mode == .new {
                    var empty = LofiBeat.empty(name: name)
                    if name.trimmingCharacters(in: .whitespaces).isEmpty { empty.name = t("Mein Beat", "My beat") }
                    add(empty)
                } else {
                    add(beat.wrappedValue.copy(named: name))
                }
            }
        }
    }

    // MARK: Schlagzeug

    private var gridSection: some View {
        Section {
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !preview.isPlaying)) { context in
                let playing = playingStep(at: context.date)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(LofiBeat.Instrument.allCases, id: \.self) { instrument in
                        HStack(spacing: 10) {
                            Label(instrumentTitle(instrument), systemImage: instrumentIcon(instrument))
                                .labelStyle(.titleAndIcon)
                                .font(.system(.callout, design: .rounded).weight(.medium))
                                .frame(width: 92, alignment: .leading)
                            HStack(spacing: 10) {
                                ForEach(0..<4, id: \.self) { group in
                                    HStack(spacing: 4) {
                                        ForEach(0..<4, id: \.self) { offset in
                                            let step = group * 4 + offset
                                            StepCell(on: beat.wrappedValue.steps(for: instrument)[step],
                                                     color: instrumentColor(instrument),
                                                     current: playing == step, downbeat: offset == 0) {
                                                beat.wrappedValue.set(instrument, step: step,
                                                                      on: !beat.wrappedValue.steps(for: instrument)[step])
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            hint(t("Tipp ein Feld an: Dort schlägt das Instrument. Vier Felder sind ein Schlag, die ganze Reihe ein Takt.",
                   "Tap a square to add a hit. Four squares make a beat, the whole row one bar."))
        } header: {
            SectionTitle(t("Schlagzeug", "Drums"), icon: "square.grid.3x3.fill", color: .orange)
        }
    }

    // MARK: Akkorde

    private var chordSection: some View {
        Section {
            HStack(spacing: 10) {
                ForEach(0..<LofiBeat.barsPerLoop, id: \.self) { bar in
                    VStack(spacing: 4) {
                        Text(t("Takt \(bar + 1)", "Bar \(bar + 1)"))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                        Picker("", selection: Binding(get: { beat.wrappedValue.chords[bar] },
                                                      set: { beat.wrappedValue.chords[bar] = $0 })) {
                            ForEach(LofiChord.palette, id: \.self) { chord in Text(chord.name).tag(chord) }
                        }
                        .labelsHidden()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            hint(t("Jeder Takt hat seinen Akkord, danach geht es von vorn los. Der Bass spielt den Grundton mit.",
                   "Each bar has its chord, then it starts over. The bass plays along with the root note."))
        } header: {
            SectionTitle(t("Akkorde", "Chords"), icon: "pianokeys", color: .purple)
        }
    }

    // MARK: Klang

    private var soundSection: some View {
        Section {
            slider(t("Tempo", "Tempo"), value: Binding(get: { Double(beat.wrappedValue.bpm) },
                                                         set: { beat.wrappedValue.bpm = Int($0.rounded()) }),
                   range: Double(LofiBeat.tempoRange.lowerBound)...Double(LofiBeat.tempoRange.upperBound), step: 1,
                   text: "\(beat.wrappedValue.bpm) BPM")
            slider(t("Swing", "Swing"), value: beat.swing, range: 0...0.6, step: 0.05,
                   text: percent(beat.wrappedValue.swing / 0.6))
            slider(t("Wärme", "Warmth"), value: beat.warmth, range: 0...1, step: 0.05, text: percent(beat.wrappedValue.warmth))
            slider(t("Knistern", "Crackle"), value: beat.crackle, range: 0...1, step: 0.05, text: percent(beat.wrappedValue.crackle))
            slider(t("Akkorde", "Chords"), value: beat.chordVolume, range: 0...1, step: 0.05,
                   text: percent(beat.wrappedValue.chordVolume))
            hint(t("Swing macht es lässiger, Wärme dumpfer, Knistern klingt nach alter Platte.",
                   "Swing makes it laid-back, warmth makes it softer, crackle sounds like an old record."))
        } header: {
            SectionTitle(t("Klang", "Sound"), icon: "slider.horizontal.3", color: .teal)
        }
    }

    // MARK: Fuß: als Musik verwenden

    private var footer: some View {
        let inUse = settings.musicSource == .beat && settings.selectedBeat.id == beat.wrappedValue.id
        return HStack {
            Text(inUse ? t("Läuft als deine Musik (Menü › Lo-Fi-Musik).", "This is your music (menu › Lo-Fi music).")
                       : t("Änderungen werden sofort gespeichert.", "Changes are saved right away."))
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                settings.musicBeatID = beat.wrappedValue.id
                settings.musicSource = .beat
            } label: {
                Label(inUse ? t("Ist deine Musik", "Is your music") : t("Als Musik verwenden", "Use as my music"),
                      systemImage: inUse ? "checkmark" : "music.note")
            }
            .buttonStyle(CapsuleButtonStyle(prominent: !inUse))
            .disabled(inUse)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: Bausteine

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                        text: String) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range, step: step)
            Text(text)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }

    private func hint(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func instrumentTitle(_ instrument: LofiBeat.Instrument) -> String {
        switch instrument {
        case .kick: return t("Kick", "Kick")
        case .snare: return t("Snare", "Snare")
        case .hat: return "Hi-Hat"
        }
    }

    private func instrumentIcon(_ instrument: LofiBeat.Instrument) -> String {
        switch instrument {
        case .kick: return "circle.fill"
        case .snare: return "circle.circle"
        case .hat: return "sparkle"
        }
    }

    private func instrumentColor(_ instrument: LofiBeat.Instrument) -> Color {
        switch instrument {
        case .kick: return .orange
        case .snare: return .pink
        case .hat: return .teal
        }
    }

    /// Welcher Schritt gerade erklingt (ungefähr, ohne Swing)
    private func playingStep(at date: Date) -> Int? {
        guard preview.isPlaying, let started = preview.player.loopStarted else { return nil }
        let step = Int(date.timeIntervalSince(started) / beat.wrappedValue.stepSeconds)
        return step % LofiBeat.stepsPerBar
    }

    private func add(_ new: LofiBeat) {
        settings.lofiBeats.append(new)
        selectedID = new.id
        restartPreview()
    }

    private func deleteCurrent() {
        guard settings.lofiBeats.count > 1 else { return }
        let id = beat.wrappedValue.id
        settings.lofiBeats.removeAll { $0.id == id }
        if settings.musicBeatID == id { settings.musicBeatID = nil }
        selectedID = settings.lofiBeats.first?.id
        restartPreview()
    }

    /// Beim Bearbeiten: kurz warten, dann den geänderten Beat hören (nicht bei jedem Schieberegler-Schritt neu rechnen)
    private func schedulePreview(_ value: LofiBeat) {
        guard preview.isPlaying else { return }
        pendingPreview?.cancel()
        let work = DispatchWorkItem { [preview, volume = settings.musicVolume] in
            MainActor.assumeIsolated { if preview.isPlaying { preview.play(value, volume: volume) } }
        }
        pendingPreview = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func restartPreview() {
        guard preview.isPlaying else { return }
        DispatchQueue.main.async { preview.play(beat.wrappedValue, volume: settings.musicVolume) }
    }
}

/// Ein Feld im Schlagzeug-Raster
private struct StepCell: View {
    let on: Bool
    let color: Color
    let current: Bool
    let downbeat: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(on ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color.primary.opacity(downbeat ? 0.13 : 0.08)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(current ? Color.primary.opacity(0.8) : .clear, lineWidth: 2))
                .frame(width: 22, height: 30)
                .scaleEffect(current && on ? 1.12 : 1)
                .animation(.easeOut(duration: 0.08), value: current)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Kleines Blatt: Name eingeben, speichern oder abbrechen
private struct NameSheet: View {
    let title: String
    let message: String
    @State var initial: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(.title3, design: .rounded).weight(.bold))
            Text(message).font(.callout).foregroundStyle(.secondary)
            TextField(L10n.s("Name", "Name"), text: $initial)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
            HStack {
                Spacer()
                Button(L10n.s("Abbrechen", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.s("Speichern", "Save"), action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { focused = true }
    }

    private func save() {
        onSave(initial)
        dismiss()
    }
}
