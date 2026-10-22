import AppKit
import SwiftUI

/// Alle Einstellungen an einem Ort. Jede Änderung wird sofort gespeichert und an die Katze weitergegeben.
@MainActor
final class AppSettings: ObservableObject {
    // Aussehen
    @Published var coat: Coat { didSet { changed() } }
    @Published var scale: Double { didSet { changed() } }
    // Verhalten
    @Published var climbing: Bool { didSet { changed() } }
    @Published var chaseCursor: Bool { didSet { changed() } }
    @Published var multiScreen: Bool { didSet { changed() } }
    /// Streifzug (ohne Körbchen): Sie geht aus dem Bild und kommt nur zu Pausen vorbei.
    @Published var roaming: Bool { didSet { changed() } }
    @Published var basketInDock: Bool {
        didSet {
            // Beim Einschalten gleich um die Freigabe bitten – damit findet sie das Körbchen überall genau
            if basketInDock, !oldValue, !loading, !DockLocator.isTrusted { DockLocator.requestTrust() }
            changed()
        }
    }
    /// Katzenkorb (mit Körbchen): Sie schläft im Körbchen im Dock und kommt nur zu Pausen heraus.
    @Published var basketNap: Bool { didSet { changed() } }
    @Published var breakReminders: Bool { didSet { changed() } }
    // Zeiten (Minuten)
    @Published var pomodoroFocus: Int { didSet { changed() } }
    @Published var pomodoroBreak: Int { didSet { changed() } }
    @Published var reminderMin: Int { didSet { if reminderMax < reminderMin { reminderMax = reminderMin }; changed() } }
    @Published var reminderMax: Int { didSet { if reminderMin > reminderMax { reminderMin = reminderMax }; changed() } }
    @Published var breakLength: Int { didSet { changed() } }
    /// Pausen-Erinnerung nach echter Aktivität (Tippen, Klicken) statt in festen Abständen
    @Published var breakByActivity: Bool { didSet { changed() } }
    @Published var activityMinutes: Int { didSet { changed() } }
    // Kleine Erinnerungen
    @Published var drinkReminders: Bool { didSet { changed() } }
    @Published var drinkInterval: Int { didSet { changed() } }
    @Published var eyeBreaks: Bool { didSet { changed() } }
    @Published var eyeInterval: Int { didSet { changed() } }
    @Published var quittingTimeEnabled: Bool { didSet { changed() } }
    /// Feierabend als Minuten nach Mitternacht
    @Published var quittingTime: Int { didSet { changed() } }
    @Published var quittingWeekdaysOnly: Bool { didSet { changed() } }
    /// Schlafmütze ab der Schlafenszeit (Minuten nach Mitternacht)
    @Published var bedtimeEnabled: Bool { didSet { changed() } }
    @Published var bedtime: Int { didSet { changed() } }
    /// Morgen-Outfit bis zu dieser Uhrzeit
    @Published var morningOutfit: Bool { didSet { changed() } }
    @Published var morningEnd: Int { didSet { changed() } }
    @Published var taskReminders: Bool { didSet { changed() } }
    @Published var taskInterval: Int { didSet { changed() } }
    @Published var taskItems: [String] { didSet { changed() } }
    /// An Aufgaben auch während Videocalls bzw. bei eingeschaltetem Mikrofon erinnern (nur die Blase)
    @Published var tasksDuringCalls: Bool { didSet { changed() } }
    // Ton & Rücksicht
    @Published var sounds: Bool { didSet { changed() } }
    @Published var purring: Bool { didSet { changed() } }
    @Published var hideDuringCalls: Bool { didSet { changed() } }
    @Published var respectFocus: Bool { didSet { changed() } }
    // Allgemein
    @Published var language: Language { didSet { L10n.language = language; changed() } }

    /// Ist die Katze weg – im Körbchen oder auf Streifzug, je nachdem, ob es das Körbchen gibt?
    var awayMode: Bool {
        get { basketInDock ? basketNap : roaming }
        set { if basketInDock { basketNap = newValue } else { roaming = newValue } }
    }

    /// Wird nach jeder Änderung aufgerufen
    var onChange: (() -> Void)?
    /// Knopf „Jetzt zeigen“: diese Erinnerung sofort vorführen
    var onPreview: ((ErrandKind) -> Void)?
    private var loading = true

    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [
            "coat": Coat.black.rawValue, "scale": 3.0,
            "climbing": false, "chaseCursor": true, "multiScreen": true, "roaming": false, "basketInDock": false,
            "breakReminders": false,
            "pomodoroFocus": 25, "pomodoroBreak": 5, "reminderMin": 45, "reminderMax": 55, "breakLength": 5,
            "breakByActivity": false, "activityMinutes": 50,
            "drinkReminders": false, "drinkInterval": 45, "eyeBreaks": false, "eyeInterval": 20,
            "quittingTimeEnabled": false, "quittingTime": 17 * 60 + 30, "quittingWeekdaysOnly": true,
            "bedtimeEnabled": false, "bedtime": 22 * 60 + 30, "morningOutfit": false, "morningEnd": 9 * 60,
            "taskReminders": false, "taskInterval": 30, "taskItems": [String](), "tasksDuringCalls": false,
            "sounds": true, "purring": true, "hideDuringCalls": true, "respectFocus": true,
            "language": Language.system.rawValue,
        ])
        coat = Coat(rawValue: defaults.string(forKey: "coat") ?? "") ?? .black
        scale = defaults.double(forKey: "scale")
        climbing = defaults.bool(forKey: "climbing")
        chaseCursor = defaults.bool(forKey: "chaseCursor")
        multiScreen = defaults.bool(forKey: "multiScreen")
        roaming = defaults.bool(forKey: "roaming")
        basketInDock = defaults.bool(forKey: "basketInDock")
        // Früher gab es nur den Streifzug – der galt auch fürs Körbchen
        basketNap = defaults.object(forKey: "basketNap") as? Bool
            ?? (defaults.bool(forKey: "basketInDock") && defaults.bool(forKey: "roaming"))
        breakReminders = defaults.bool(forKey: "breakReminders")
        pomodoroFocus = defaults.integer(forKey: "pomodoroFocus")
        pomodoroBreak = defaults.integer(forKey: "pomodoroBreak")
        reminderMin = defaults.integer(forKey: "reminderMin")
        reminderMax = defaults.integer(forKey: "reminderMax")
        breakLength = defaults.integer(forKey: "breakLength")
        breakByActivity = defaults.bool(forKey: "breakByActivity")
        activityMinutes = defaults.integer(forKey: "activityMinutes")
        drinkReminders = defaults.bool(forKey: "drinkReminders")
        drinkInterval = defaults.integer(forKey: "drinkInterval")
        eyeBreaks = defaults.bool(forKey: "eyeBreaks")
        eyeInterval = defaults.integer(forKey: "eyeInterval")
        quittingTimeEnabled = defaults.bool(forKey: "quittingTimeEnabled")
        quittingTime = defaults.integer(forKey: "quittingTime")
        quittingWeekdaysOnly = defaults.bool(forKey: "quittingWeekdaysOnly")
        bedtimeEnabled = defaults.bool(forKey: "bedtimeEnabled")
        bedtime = defaults.integer(forKey: "bedtime")
        morningOutfit = defaults.bool(forKey: "morningOutfit")
        morningEnd = defaults.integer(forKey: "morningEnd")
        taskReminders = defaults.bool(forKey: "taskReminders")
        taskInterval = defaults.integer(forKey: "taskInterval")
        taskItems = defaults.stringArray(forKey: "taskItems") ?? []
        tasksDuringCalls = defaults.bool(forKey: "tasksDuringCalls")
        sounds = defaults.bool(forKey: "sounds")
        purring = defaults.bool(forKey: "purring")
        hideDuringCalls = defaults.bool(forKey: "hideDuringCalls")
        respectFocus = defaults.bool(forKey: "respectFocus")
        language = Language(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
        L10n.language = language
        loading = false
    }

    private func changed() {
        guard !loading else { return }
        let values: [String: Any] = [
            "coat": coat.rawValue, "scale": scale,
            "climbing": climbing, "chaseCursor": chaseCursor, "multiScreen": multiScreen,
            "roaming": roaming, "basketInDock": basketInDock, "basketNap": basketNap, "breakReminders": breakReminders,
            "pomodoroFocus": pomodoroFocus, "pomodoroBreak": pomodoroBreak,
            "reminderMin": reminderMin, "reminderMax": reminderMax, "breakLength": breakLength,
            "breakByActivity": breakByActivity, "activityMinutes": activityMinutes,
            "drinkReminders": drinkReminders, "drinkInterval": drinkInterval,
            "eyeBreaks": eyeBreaks, "eyeInterval": eyeInterval,
            "quittingTimeEnabled": quittingTimeEnabled, "quittingTime": quittingTime,
            "quittingWeekdaysOnly": quittingWeekdaysOnly,
            "bedtimeEnabled": bedtimeEnabled, "bedtime": bedtime, "morningOutfit": morningOutfit, "morningEnd": morningEnd,
            "taskReminders": taskReminders, "taskInterval": taskInterval, "taskItems": taskItems,
            "tasksDuringCalls": tasksDuringCalls,
            "sounds": sounds, "purring": purring, "hideDuringCalls": hideDuringCalls,
            "respectFocus": respectFocus, "language": language.rawValue,
        ]
        for (key, value) in values { defaults.set(value, forKey: key) }
        onChange?()
    }
}

// MARK: - Fenster

@MainActor
final class SettingsWindow {
    private var window: NSWindow?
    private let settings: AppSettings
    private let focus: FocusMonitor

    init(settings: AppSettings, focus: FocusMonitor) {
        self.settings = settings
        self.focus = focus
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 620),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 460, height: 360)
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings, focus: focus))
            window.center()
            self.window = window
        }
        window?.title = L10n.s("Pixelcat – Einstellungen", "Pixelcat – Settings")
        focus.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Inhalt

/// Eine durchgehende Seite zum Durchscrollen – nur Schalter, Segmente und Schieberegler.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var focus: FocusMonitor
    /// Eingabefeld für eine neue Aufgabe
    @State private var newTask = ""
    /// Länger passt nicht gut in die Gedankenblase (drei Zeilen)
    private static let maxTaskLength = 45

    private func t(_ de: String, _ en: String) -> String { L10n.s(de, en) }

    var body: some View {
        Form {
            lookSection
            behaviorSection
            pomodoroSection
            reminderSection
            drinkSection
            eyeSection
            quittingSection
            outfitSection
            taskSection
            soundSection
            considerateSection
            languageSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 360)
        // Bei Sprachwechsel alles neu aufbauen
        .id(settings.language)
    }

    // MARK: Katze

    private var lookSection: some View {
        Section(t("Aussehen", "Look")) {
            LabeledContent(t("Fellfarbe", "Coat")) {
                Picker("", selection: $settings.coat) {
                    ForEach(Coat.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            LabeledContent(t("Größe", "Size")) {
                Picker("", selection: $settings.scale) {
                    Text(t("Klein", "Small")).tag(2.0)
                    Text(t("Mittel", "Medium")).tag(3.0)
                    Text(t("Groß", "Large")).tag(4.0)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
        }
    }

    private var behaviorSection: some View {
        Section(t("Verhalten", "Behavior")) {
            Toggle(t("Klettern auf Fenster", "Climb onto windows"), isOn: $settings.climbing)
            Toggle(t("Mauszeiger jagen", "Chase the mouse pointer"), isOn: $settings.chaseCursor)
            hint(t("Ruht die Maus am unteren Rand, schleicht sie sich an und springt – nicht im Streifzug.",
                   "When the pointer rests near the bottom, she sneaks up and pounces – not while roaming."))
            Toggle(t("Auf andere Bildschirme wechseln", "Wander to other displays"), isOn: $settings.multiScreen)
            Toggle(t("Katzenkorb im Dock", "Cat bed in the Dock"), isOn: $settings.basketInDock)
            hint(t("Zeigt einen Katzenkorb im Dock. Im Menü gibt es dann „Katzenkorb“ statt „Streifzug“.",
                   "Shows a cat bed in the Dock. The menu then offers “Cat Bed” instead of “Roaming”."))
            if settings.basketInDock {
                Toggle(t("Katzenkorb", "Cat Bed"), isOn: $settings.basketNap)
                hint(t("Sie legt sich in den Korb und schläft dort – zu Pausen und wenn der Timer abläuft, klettert sie heraus.",
                       "She curls up in the bed and sleeps there – she climbs out for breaks and when the timer runs out."))
            } else {
                Toggle(t("Streifzug", "Roaming"), isOn: $settings.roaming)
                hint(t("Sie geht weg und kommt nur zu Pausen in die Bildschirmmitte.",
                       "She goes away and only comes to the middle of the screen for breaks."))
            }
            if settings.basketInDock {
                HStack {
                    hint(DockLocator.isTrusted
                         ? t("Sie findet den Korb genau.", "She finds the bed exactly.")
                         : t("Ohne Bedienungshilfen schätzt sie, wo der Korb im Dock sitzt.",
                             "Without Accessibility access she estimates where the bed sits in the Dock."))
                    Spacer()
                    if !DockLocator.isTrusted {
                        Button(t("Genau finden …", "Find exactly …")) { DockLocator.requestTrust() }
                    }
                }
            }
        }
    }

    // MARK: Zeiten

    private var pomodoroSection: some View {
        Section("Pomodoro") {
            minutesSlider(t("Fokus", "Focus"), value: $settings.pomodoroFocus, range: 5...120, step: 5)
            minutesSlider(t("Pause", "Break"), value: $settings.pomodoroBreak, range: 1...30, step: 1)
        }
    }

    private var reminderSection: some View {
        Section(t("Pausen", "Breaks")) {
            Toggle(t("Pausen-Erinnerung", "Break reminder"), isOn: $settings.breakReminders)
            LabeledContent(t("Erinnern", "Remind")) {
                Picker("", selection: $settings.breakByActivity) {
                    Text(t("In festen Abständen", "At set intervals")).tag(false)
                    Text(t("Nach Aktivität", "By activity")).tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            if settings.breakByActivity {
                minutesSlider(t("Nach Arbeit am Stück", "After working for"), value: $settings.activityMinutes,
                              range: 15...120, step: 5)
                hint(t("Zählt nur, solange du tippst, klickst oder die Maus bewegst. Bist du 5 Minuten weg, war das schon eine Pause – dann fängt es von vorne an.",
                       "Only counts while you type, click or move the mouse. If you step away for 5 minutes, that already was a break – the count starts over."))
            } else {
                minutesSlider(t("Frühestens nach", "No sooner than"), value: $settings.reminderMin, range: 10...180, step: 5)
                minutesSlider(t("Spätestens nach", "No later than"), value: $settings.reminderMax, range: 10...180, step: 5)
                hint(t("Der genaue Zeitpunkt ist zufällig dazwischen – das wirkt natürlicher.",
                       "The exact moment is random in between – it feels more natural."))
            }
            minutesSlider(t("Länge einer Pause", "Length of a break"), value: $settings.breakLength, range: 1...30, step: 1)
            hint(t("Gilt für Pausen-Erinnerungen und für die Besuche im Streifzug.",
                   "Used for break reminders and for visits while roaming."))
        }
    }

    private var drinkSection: some View {
        Section(t("Trinken", "Drinking")) {
            Toggle(t("Trink-Erinnerung", "Drink reminder"), isOn: $settings.drinkReminders)
            minutesSlider(t("Ungefähr alle", "About every"), value: $settings.drinkInterval, range: 10...120, step: 5)
            HStack {
                hint(t("Sie stellt einen Wassernapf hin und trinkt eine Weile – darüber steht „Trinken“. Ein Klick lässt die Blase platzen.",
                       "She puts down a water bowl and drinks for a while, with “Drink” above her head. A click pops the bubble."))
                Spacer()
                previewButton(.drink)
            }
        }
    }

    private var eyeSection: some View {
        Section(t("Augen", "Eyes")) {
            Toggle(t("Augenpause", "Eye break"), isOn: $settings.eyeBreaks)
            minutesSlider(t("Ungefähr alle", "About every"), value: $settings.eyeInterval, range: 10...90, step: 5)
            HStack {
                hint(t("Ein Fenster ploppt auf, sie setzt sich davor und schaut eine halbe Minute hinaus – schau mit ihr in die Ferne.",
                       "A window pops up, she sits down in front of it and looks out for half a minute – look into the distance with her."))
                Spacer()
                previewButton(.lookout)
            }
        }
    }

    private var quittingSection: some View {
        Section(t("Feierabend", "End of the workday")) {
            Toggle(t("An den Feierabend erinnern", "Remind me to call it a day"), isOn: $settings.quittingTimeEnabled)
            LabeledContent(t("Uhrzeit", "Time")) {
                DatePicker("", selection: quittingClock, displayedComponents: .hourAndMinute)
                    .labelsHidden().fixedSize()
            }
            Toggle(t("Nur Montag bis Freitag", "Only Monday to Friday"), isOn: $settings.quittingWeekdaysOnly)
            HStack {
                hint(t("Sie setzt Zylinder und Fliege auf, kommt in die Mitte und denkt „Feierabend“. Den Zylinder trägt sie bis zur Schlafenszeit.",
                       "She puts on her top hat and bow tie, comes to the middle and thinks “Off work”. She keeps them on until bedtime."))
                Spacer()
                previewButton(.quittingTime)
            }
        }
    }

    private var outfitSection: some View {
        Section(t("Outfits", "Outfits")) {
            Toggle(t("Schlafmütze zur Schlafenszeit", "Nightcap at bedtime"), isOn: $settings.bedtimeEnabled)
            LabeledContent(t("Schlafenszeit", "Bedtime")) {
                DatePicker("", selection: clock($settings.bedtime), displayedComponents: .hourAndMinute)
                    .labelsHidden().fixedSize()
            }
            Toggle(t("Morgen-Outfit (Schlafmaske auf der Stirn)", "Morning outfit (sleep mask on her forehead)"),
                   isOn: $settings.morningOutfit)
            LabeledContent(t("Morgens bis", "Mornings until")) {
                DatePicker("", selection: clock($settings.morningEnd), displayedComponents: .hourAndMinute)
                    .labelsHidden().fixedSize()
            }
            hint(t("Die Schlafmütze trägt sie bis 5 Uhr, danach beginnt der Morgen. Nach Feierabend trägt sie Zylinder und Fliege.",
                   "She wears the nightcap until 5 am, then morning begins. After work she wears a top hat and bow tie."))
        }
    }

    /// Die Feierabend-Uhrzeit als Datum für den Zeitwähler (nur Stunde und Minute zählen)
    private var quittingClock: Binding<Date> { clock($settings.quittingTime) }

    /// Minuten nach Mitternacht als Datum für einen Zeitwähler (nur Stunde und Minute zählen)
    private func clock(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            })
    }

    private var taskSection: some View {
        Section(t("Aufgaben", "Tasks")) {
            Toggle(t("An Aufgaben erinnern", "Remind me of tasks"), isOn: $settings.taskReminders)
            minutesSlider(t("Ungefähr alle", "About every"), value: $settings.taskInterval, range: 5...120, step: 5)
            ForEach(Array(settings.taskItems.enumerated()), id: \.offset) { index, task in
                HStack {
                    Text(task)
                    Spacer()
                    Button {
                        settings.taskItems.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(t("Entfernen", "Remove"))
                }
            }
            HStack {
                TextField("", text: $newTask, prompt: Text(t("Neue Aufgabe, z. B. „Mama anrufen“", "New task, e.g. “Call mom”")))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTask)
                    .onChange(of: newTask) { value in
                        if value.count > Self.maxTaskLength { newTask = String(value.prefix(Self.maxTaskLength)) }
                    }
                Button(t("Hinzufügen", "Add"), action: addTask)
                    .disabled(newTask.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Toggle(t("Auch während Videocalls erinnern", "Also remind me during video calls"), isOn: $settings.tasksDuringCalls)
            hint(settings.hideDuringCalls
                 ? t("Bei Kamera oder Mikrofon bleibt die Katze versteckt – nur die Blase erscheint unten am Dock. Während der Bildschirm geteilt wird, nie.",
                     "While the camera or microphone is on, the cat stays hidden – only the bubble shows up at the Dock. Never while the screen is shared.")
                 : t("Gilt nur, wenn sie sich bei Videocalls versteckt (unter „Rücksicht“) – sonst erinnert sie ohnehin.",
                     "Only matters if she hides during video calls (see “Being considerate”) – otherwise she reminds you anyway."))
            HStack {
                hint(t("Sie denkt in zufälliger Reihenfolge an deine Einträge – erst an alle einmal, dann wieder von vorn. Im Körbchen oder auf Streifzug kommt sie dafür herein.",
                       "She thinks of your entries in random order – each once, then all over again. In her bed or while roaming she comes in for it."))
                Spacer()
                previewButton(.task).disabled(settings.taskItems.isEmpty)
            }
        }
    }

    private func addTask() {
        let task = newTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }
        settings.taskItems.append(task)
        newTask = ""
    }

    // MARK: Ton & Rücksicht

    private var soundSection: some View {
        Section(t("Töne", "Sounds")) {
            Toggle(t("Miauen (Pausen, Timer, Erinnerung)", "Meow (breaks, timer, reminder)"), isOn: $settings.sounds)
            Toggle(t("Schnurren beim Streicheln", "Purr while petting"), isOn: $settings.purring)
        }
    }

    private var considerateSection: some View {
        Section(t("Rücksicht", "Being considerate")) {
            Toggle(t("Bei Videocall oder Bildschirmfreigabe verstecken", "Hide during video calls and screen sharing"),
                   isOn: $settings.hideDuringCalls)
            hint(t("Sind Kamera oder Mikrofon an oder wird der Bildschirm geteilt, geht sie automatisch auf Streifzug – und kommt danach zurück.",
                   "While the camera or microphone is on or the screen is shared, she goes roaming – and comes back afterwards."))
            Toggle(t("Fokus berücksichtigen", "Respect Focus"), isOn: $settings.respectFocus)
            HStack {
                hint(focusStatusText)
                Spacer()
                if focus.access == .unknown {
                    Button(t("Zugriff erlauben …", "Allow access …")) { focus.requestAccess() }
                }
            }
        }
    }

    private var focusStatusText: String {
        switch focus.access {
        case .allowed:
            return t("Ist ein Fokus wie „Nicht stören“ an, ist sie still und schläft mehr.",
                     "While a Focus like Do Not Disturb is on, she stays quiet and sleeps more.")
        case .unknown:
            return t("macOS fragt einmalig, ob die Katze den Fokus-Status sehen darf.",
                     "macOS asks once whether the cat may see your Focus status.")
        case .denied:
            return t("Zugriff verweigert – erlauben unter Systemeinstellungen › Datenschutz & Sicherheit › Fokus.",
                     "Access denied – allow it in System Settings › Privacy & Security › Focus.")
        case .unavailable:
            return t("Der Fokus-Status ist auf diesem Mac nicht verfügbar.", "Focus status is not available on this Mac.")
        }
    }

    // MARK: Allgemein

    private var languageSection: some View {
        Section(t("Sprache", "Language")) {
            Picker("", selection: $settings.language) {
                ForEach(Language.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
        }
    }

    private var aboutSection: some View {
        Section(t("Über", "About")) {
            Text("Pixelcat \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
            hint("github.com/TheesBudde/pixelcat")
            hint(t("Katzenlaute: „Cat Purr & Meow“ von Kerzoven (opengameart.org, CC0)",
                   "Cat sounds: “Cat Purr & Meow” by Kerzoven (opengameart.org, CC0)"))
        }
    }

    // MARK: Bausteine

    /// Führt eine Erinnerung sofort vor
    private func previewButton(_ kind: ErrandKind) -> some View {
        Button(t("Jetzt zeigen", "Show now")) { settings.onPreview?(kind) }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    /// Schieberegler mit Minutenanzeige statt Plus/Minus-Pfeilen.
    private func minutesSlider(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        let double = Binding<Double>(get: { Double(value.wrappedValue) },
                                     set: { value.wrappedValue = Int($0.rounded()) })
        return LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: double, in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step))
                    .frame(width: 170)
                Text(t("\(value.wrappedValue) Min.", "\(value.wrappedValue) min"))
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }
}
