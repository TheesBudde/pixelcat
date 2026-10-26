import AppKit
import Combine
import SwiftUI

/// Alle Einstellungen an einem Ort. Jede Änderung wird sofort gespeichert und an die Katze weitergegeben.
@MainActor
final class AppSettings: ObservableObject {
    // Aussehen
    /// Wie die Katze heißt (leer = „Pixelcat“)
    @Published var catName: String { didSet { changed() } }
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
            // Beim Einschalten gleich um die Freigabe bitten, damit sie das Körbchen überall genau findet
            // (die Einrichtung fragt selbst und schaltet das ab)
            if basketInDock, !oldValue, !loading, askForAccessWithBed, !DockLocator.isTrusted { DockLocator.requestTrust() }
            changed()
        }
    }
    /// Nach der Freigabe fragen, sobald der Katzenkorb eingeschaltet wird
    var askForAccessWithBed = true
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
    /// Aufgaben, jede mit ihrer Uhrzeit
    @Published var taskItems: [TaskItem] { didSet { changed() } }
    /// Motivation: eigene Sprüche, morgens und gegen Feierabend (leer = ihre eigenen)
    @Published var motivationEnabled: Bool { didSet { changed() } }
    @Published var motivationSayings: [String] { didSet { changed() } }
    /// An Aufgaben auch während Videocalls bzw. bei eingeschaltetem Mikrofon erinnern (nur die Blase)
    @Published var tasksDuringCalls: Bool { didSet { changed() } }
    /// Ist so lange niemand am Rechner, fliegt ein Vogel herum und sie jagt ihn
    @Published var birdWhenAway: Bool { didSet { changed() } }
    @Published var birdMinutes: Int { didSet { changed() } }
    // Ton & Rücksicht
    @Published var sounds: Bool { didSet { changed() } }
    @Published var purring: Bool { didSet { changed() } }
    /// Auch bei Aufgaben-Erinnerungen miauen
    @Published var meowForTasks: Bool { didSet { changed() } }
    @Published var hideDuringCalls: Bool { didSet { changed() } }
    /// Ruhemodus: Sie geht in den Korb bzw. aus dem Bild – keine Erinnerungen, keine Töne
    @Published var silentMode: Bool { didSet { changed() } }
    /// Geführte Pause: Nach Daumen hoch macht sie Übungen vor
    @Published var guidedBreaks: Bool { didSet { changed() } }
    /// Pomodoro-Pausen ebenfalls mit Übungen
    @Published var guidedPomodoros: Bool { didSet { changed() } }
    /// Apps, deren aktive Zeit in der Statistik erscheint (Bundle-IDs)
    @Published var trackedApps: [String] { didSet { changed() } }
    @Published var respectFocus: Bool { didSet { changed() } }
    // Allgemein
    @Published var language: Language { didSet { L10n.language = language; changed() } }
    /// Die Einrichtung beim ersten Start ist durchgeklickt (oder geschlossen)
    @Published var onboardingDone: Bool { didSet { changed() } }

    /// Der Name zum Anzeigen
    var displayName: String {
        let name = catName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Pixelcat" : name
    }

    /// Ist die Katze weg – im Körbchen oder auf Streifzug, je nachdem, ob es das Körbchen gibt?
    var awayMode: Bool {
        get { basketInDock ? basketNap : roaming }
        set { if basketInDock { basketNap = newValue } else { roaming = newValue } }
    }

    /// Wird nach jeder Änderung aufgerufen
    var onChange: (() -> Void)?
    /// Knopf „Jetzt zeigen“: diese Erinnerung sofort vorführen
    var onPreview: ((ErrandKind) -> Void)?
    /// Eine bestimmte Aufgabe sofort zeigen (Aufgabenfenster)
    var onPreviewTask: ((UUID) -> Void)?
    /// Das Aufgabenfenster öffnen
    var onOpenTasks: (() -> Void)?
    /// Die Einrichtung noch einmal zeigen
    var onOpenSetup: (() -> Void)?
    /// Die Pausenfrage gleich zeigen
    var onPreviewBreak: (() -> Void)?
    /// Was die Katze gerade trägt (Hut, Fliege), damit sie in der Einrichtung genauso aussieht
    var currentOutfit: (() -> Frames.Outfit)?
    private var loading = true

    private let defaults = UserDefaults.standard

    /// Sicherung aller Einstellungen als Datei (nur in der echten App, nicht in Tests). Gehen die Einstellungen
    /// verloren (neu installiert, zurückgesetzt), holt Pixelcat sie beim nächsten Start von hier zurück.
    static var backupURL: URL? {
        guard Bundle.main.bundleIdentifier != nil,
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return support.appendingPathComponent("Pixelcat/Settings.plist")
    }

    init() {
        Self.restoreBackupIfNeeded(into: defaults)
        defaults.register(defaults: [
            "catName": "", "coat": Coat.black.rawValue, "scale": 3.0,
            "climbing": false, "chaseCursor": true, "multiScreen": true, "roaming": false, "basketInDock": false,
            "breakReminders": false,
            "pomodoroFocus": 25, "pomodoroBreak": 5, "reminderMin": 45, "reminderMax": 55, "breakLength": 5,
            "breakByActivity": false, "activityMinutes": 50,
            "drinkReminders": false, "drinkInterval": 45, "eyeBreaks": false, "eyeInterval": 20,
            "quittingTimeEnabled": false, "quittingTime": 17 * 60 + 30, "quittingWeekdaysOnly": true,
            "bedtimeEnabled": false, "bedtime": 22 * 60 + 30, "morningOutfit": false, "morningEnd": 9 * 60,
            "taskReminders": false, "tasksDuringCalls": false, "motivation": false, "birdWhenAway": true, "birdMinutes": 10,
            "sounds": true, "purring": true, "silentMode": false, "guidedBreaks": true, "guidedPomodoros": true, "meowForTasks": false, "hideDuringCalls": true, "respectFocus": true,
            "language": Language.system.rawValue,
        ])
        catName = defaults.string(forKey: "catName") ?? ""
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
        if let stored = defaults.array(forKey: "taskList") as? [[String: Any]] {
            taskItems = stored.compactMap(TaskItem.init(dictionary:))
        } else {
            // Früher: nur Texte mit einem gemeinsamen Abstand
            taskItems = (defaults.stringArray(forKey: "taskItems") ?? []).map { TaskItem(text: $0, time: TaskItem.defaultTime) }
        }
        motivationEnabled = defaults.bool(forKey: "motivation")
        motivationSayings = defaults.stringArray(forKey: "motivationSayings") ?? []
        tasksDuringCalls = defaults.bool(forKey: "tasksDuringCalls")
        birdWhenAway = defaults.bool(forKey: "birdWhenAway")
        birdMinutes = defaults.integer(forKey: "birdMinutes")
        sounds = defaults.bool(forKey: "sounds")
        purring = defaults.bool(forKey: "purring")
        meowForTasks = defaults.bool(forKey: "meowForTasks")
        hideDuringCalls = defaults.bool(forKey: "hideDuringCalls")
        silentMode = defaults.bool(forKey: "silentMode")
        guidedBreaks = defaults.bool(forKey: "guidedBreaks")
        guidedPomodoros = defaults.bool(forKey: "guidedPomodoros")
        trackedApps = defaults.stringArray(forKey: "trackedApps") ?? []
        respectFocus = defaults.bool(forKey: "respectFocus")
        language = Language(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
        // Wer Pixelcat schon benutzt hat (gespeichertes Fell), bekommt die Einrichtung nicht ungefragt
        let stored = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        onboardingDone = defaults.object(forKey: "onboardingDone") as? Bool ?? (stored["coat"] != nil)
        L10n.language = language
        loading = false
        // Wer schon Einstellungen hat, bekommt gleich eine Sicherung
        if onboardingDone, let url = Self.backupURL, !FileManager.default.fileExists(atPath: url.path) {
            Self.writeBackup(storedValues)
        }
    }

    private func changed() {
        guard !loading else { return }
        let values = storedValues
        for (key, value) in values { defaults.set(value, forKey: key) }
        Self.writeBackup(values)
        onChange?()
    }

    /// Alles, was gespeichert wird
    private var storedValues: [String: Any] {
        [
            "catName": catName, "coat": coat.rawValue, "scale": scale,
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
            "taskReminders": taskReminders, "taskList": taskItems.map(\.dictionary),
            "motivation": motivationEnabled, "motivationSayings": motivationSayings,
            "tasksDuringCalls": tasksDuringCalls, "birdWhenAway": birdWhenAway, "birdMinutes": birdMinutes,
            "sounds": sounds, "purring": purring, "silentMode": silentMode, "guidedBreaks": guidedBreaks,
            "guidedPomodoros": guidedPomodoros, "trackedApps": trackedApps, "meowForTasks": meowForTasks, "hideDuringCalls": hideDuringCalls,
            "respectFocus": respectFocus, "language": language.rawValue, "onboardingDone": onboardingDone,
        ]
    }

    private static func writeBackup(_ values: [String: Any]) {
        guard let url = backupURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        (values as NSDictionary).write(to: url, atomically: true)
    }

    /// Sind keine Einstellungen gespeichert, aber eine Sicherung da: zurückholen
    private static func restoreBackupIfNeeded(into defaults: UserDefaults) {
        guard let url = backupURL, let id = Bundle.main.bundleIdentifier,
              (defaults.persistentDomain(forName: id) ?? [:])["coat"] == nil,
              let backup = NSDictionary(contentsOf: url) as? [String: Any]
        else { return }
        for (key, value) in backup { defaults.set(value, forKey: key) }
    }
}

// MARK: - Fenster

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: AppSettings
    private let focus: FocusMonitor
    private var coatWatch: AnyCancellable?

    init(settings: AppSettings, focus: FocusMonitor) {
        self.settings = settings
        self.focus = focus
    }

    /// Geschlossen: Inhalt verwerfen, damit keine Animation im Verborgenen weiterläuft
    func windowWillClose(_ notification: Notification) {
        window?.contentView = NSView()
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 660),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.minSize = NSSize(width: 480, height: 400)
            window.delegate = self
            window.center()
            self.window = window
            // Hell oder dunkel je nach Fell
            coatWatch = settings.$coat.sink { [weak window] coat in window?.appearance = coat.appearance }
        }
        if !(window?.contentView is NSHostingView<SettingsView>) {
            window?.contentView = NSHostingView(rootView: SettingsView(settings: settings, focus: focus))
        }
        window?.title = L10n.s("Pixelcat Einstellungen", "Pixelcat Settings")
        focus.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Inhalt

/// Eine durchgehende Seite zum Durchscrollen: oben die Katze, darunter die Abschnitte mit Schaltern,
/// Segmenten und Schiebereglern. Dahinter ein blasser Pixelhintergrund.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var focus: FocusMonitor
    @State private var newSaying = ""

    private func t(_ de: String, _ en: String) -> String { L10n.s(de, en) }

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(settings: settings)
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
                motivationSection
                appsSection
                birdSection
                soundSection
                considerateSection
                languageSection
                aboutSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background(PixelBackdrop(coat: settings.coat))
        .environment(\.colorScheme, settings.coat.colorScheme)
        .frame(minWidth: 480, minHeight: 400)
        // Bei Sprachwechsel alles neu aufbauen
        .id(settings.language)
    }

    // MARK: Katze

    private var lookSection: some View {
        Section {
            LabeledContent(t("Name", "Name")) {
                NameInput(name: $settings.catName)
            }
            LabeledContent(t("Fell", "Coat")) {
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
        } header: {
            SectionTitle(t("Aussehen", "Look"), icon: "paintpalette.fill", color: .pink)
        }
    }

    private var behaviorSection: some View {
        Section {
            Toggle(t("Auf Fenster klettern", "Climb onto windows"), isOn: $settings.climbing)
            Toggle(t("Mauszeiger jagen", "Chase the pointer"), isOn: $settings.chaseCursor)
            hint(t("Ruht der Zeiger unten am Rand, pirscht sie sich an und springt. Nicht im Streifzug.",
                   "When the pointer rests near the bottom, she sneaks up and pounces. Not while roaming."))
            Toggle(t("Auf andere Bildschirme wechseln", "Wander to other displays"), isOn: $settings.multiScreen)
            Toggle(t("Katzenkorb im Dock", "Cat bed in the Dock"), isOn: $settings.basketInDock)
            hint(t("Zeigt einen Korb im Dock. Im Menü steht dann Katzenkorb statt Streifzug.",
                   "Adds a bed to the Dock. The menu then shows Cat Bed instead of Roaming."))
            if settings.basketInDock {
                Toggle(t("Katzenkorb", "Cat Bed"), isOn: $settings.basketNap)
                hint(t("Sie schläft im Korb. Für Pausen, Timer und Erinnerungen klettert sie heraus und danach zurück.",
                       "She sleeps in the bed. She climbs out for breaks, timers and reminders and goes back afterwards."))
            } else {
                Toggle(t("Streifzug", "Roaming"), isOn: $settings.roaming)
                hint(t("Sie geht weg. Für Pausen, Timer und Erinnerungen kommt sie vorbei und geht danach wieder.",
                       "She heads out. She drops by for breaks, timers and reminders and leaves again afterwards."))
            }
            if settings.basketInDock {
                HStack {
                    hint(DockLocator.isTrusted
                         ? t("Sie findet den Korb genau.", "She finds the bed exactly.")
                         : t("Ohne Bedienungshilfen schätzt sie, wo der Korb steht.",
                             "Without Accessibility access she estimates where the bed is."))
                    Spacer()
                    if !DockLocator.isTrusted {
                        Button(t("Genau finden …", "Find exactly …")) { DockLocator.requestTrust() }
                    }
                }
            }
        } header: {
            SectionTitle(t("Verhalten", "Behavior"), icon: "pawprint.fill", color: .orange)
        }
    }

    // MARK: Zeiten

    private var pomodoroSection: some View {
        Section {
            minutesSlider(t("Fokus", "Focus"), value: $settings.pomodoroFocus, range: 5...120, step: 5)
            minutesSlider(t("Pause", "Break"), value: $settings.pomodoroBreak, range: 1...30, step: 1)
            Toggle(t("Geführte Pomodoro-Pausen", "Guided Pomodoro breaks"), isOn: $settings.guidedPomodoros)
            hint(t("In der Pomodoro-Pause macht sie Übungen vor, wie bei der geführten Pause.",
                   "During the Pomodoro break she shows you exercises, like in a guided break."))
        } header: {
            SectionTitle("Pomodoro", icon: "timer", color: .red)
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle(t("Pausenerinnerung", "Break reminder"), isOn: $settings.breakReminders)
            HStack {
                hint(t("Sie fragt mit einer Blase. Daumen hoch startet die Pause, Daumen runter verschiebt sie.",
                       "She asks with a bubble. Thumbs up starts the break, thumbs down puts it off."))
                Spacer()
                Button(t("Jetzt fragen", "Ask now")) { settings.onPreviewBreak?() }
            }
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
                hint(t("Zählt nur, wenn du tippst, klickst oder die Maus bewegst. Bist du 5 Minuten weg, war das eine Pause und es beginnt neu. Drückst du die Pause weg, fragt sie früher wieder, höchstens alle 15 Minuten.",
                       "Counts only while you type, click or move the mouse. Five minutes away count as a break and it starts over. Put a break off and she asks again sooner, at most every 15 minutes."))
            } else {
                minutesSlider(t("Frühestens nach", "No sooner than"), value: $settings.reminderMin, range: 10...180, step: 5)
                minutesSlider(t("Spätestens nach", "No later than"), value: $settings.reminderMax, range: 10...180, step: 5)
                hint(t("Der Zeitpunkt dazwischen ist zufällig. Drückst du die Pause weg, beginnt die Zeit neu.",
                       "The moment in between is random. Put a break off and the time starts over."))
            }
            minutesSlider(t("Pausenlänge", "Break length"), value: $settings.breakLength, range: 1...30, step: 1)
            Toggle(t("Geführte Pause", "Guided break"), isOn: $settings.guidedBreaks)
            hint(t("Nach Daumen hoch macht sie dir kleine Übungen vor: strecken, Katzenbuckel, atmen, Kopf drehen. In der Blase steht, was du tun sollst.",
                   "After thumbs up she shows you small exercises: stretching, a cat arch, breathing, turning your head. The bubble says what to do."))
            hint(t("So lange läuft die Pause nach Daumen hoch. Sie bleibt dabei bei dir, auch aus Katzenkorb oder Streifzug.",
                   "How long the break runs after thumbs up. She stays with you, even from the cat bed or roaming."))
        } header: {
            SectionTitle(t("Pausen", "Breaks"), icon: "cup.and.saucer.fill", color: .brown)
        }
    }

    private var drinkSection: some View {
        Section {
            Toggle(t("Trinkerinnerung", "Drink reminder"), isOn: $settings.drinkReminders)
            minutesSlider(t("Ungefähr alle", "About every"), value: $settings.drinkInterval, range: 10...120, step: 5)
            HStack {
                hint(t("Sie stellt einen Napf hin und fragt „Trinken?“. Daumen hoch zählt in der Statistik, Daumen runter räumt den Napf weg.",
                       "She puts down a bowl and asks “Drink?”. Thumbs up counts in your statistics, thumbs down clears the bowl."))
                Spacer()
                previewButton(.drink)
            }
        } header: {
            SectionTitle(t("Trinken", "Drinking"), icon: "drop.fill", color: .blue)
        }
    }

    private var eyeSection: some View {
        Section {
            Toggle(t("Augenpause", "Eye break"), isOn: $settings.eyeBreaks)
            minutesSlider(t("Ungefähr alle", "About every"), value: $settings.eyeInterval, range: 10...90, step: 5)
            HStack {
                hint(t("Ein Fenster erscheint und sie schaut eine halbe Minute hinaus. Schau mit ihr in die Ferne.",
                       "A window appears and she gazes out for half a minute. Look into the distance with her."))
                Spacer()
                previewButton(.lookout)
            }
        } header: {
            SectionTitle(t("Augen", "Eyes"), icon: "eye.fill", color: .teal)
        }
    }

    private var quittingSection: some View {
        Section {
            Toggle(t("An den Feierabend erinnern", "Remind me to call it a day"), isOn: $settings.quittingTimeEnabled)
            LabeledContent(t("Uhrzeit", "Time")) {
                DatePicker("", selection: clock($settings.quittingTime), displayedComponents: .hourAndMinute)
                    .labelsHidden().fixedSize()
            }
            Toggle(t("Nur Montag bis Freitag", "Monday to Friday only"), isOn: $settings.quittingWeekdaysOnly)
            HStack {
                hint(t("Sie kommt in die Mitte, setzt Zylinder und Fliege auf und denkt „Feierabend“. Beides trägt sie bis zur Schlafenszeit.",
                       "She comes to the middle, puts on a top hat and bow tie and thinks “Off work”. She wears both until bedtime."))
                Spacer()
                previewButton(.quittingTime)
            }
        } header: {
            SectionTitle(t("Feierabend", "End of the workday"), icon: "briefcase.fill", color: .indigo)
        }
    }

    private var outfitSection: some View {
        Section {
            Toggle(t("Schlafmütze zur Schlafenszeit", "Nightcap at bedtime"), isOn: $settings.bedtimeEnabled)
            LabeledContent(t("Schlafenszeit", "Bedtime")) {
                DatePicker("", selection: clock($settings.bedtime), displayedComponents: .hourAndMinute)
                    .labelsHidden().fixedSize()
            }
            Toggle(t("Morgenoutfit", "Morning outfit"), isOn: $settings.morningOutfit)
            LabeledContent(t("Morgens bis", "Mornings until")) {
                DatePicker("", selection: clock($settings.morningEnd), displayedComponents: .hourAndMinute)
                    .labelsHidden().fixedSize()
            }
            hint(t("Die Schlafmütze trägt sie bis 5 Uhr. Morgens sitzt die Schlafmaske auf der Stirn. Nach Feierabend trägt sie Zylinder und Fliege.",
                   "She wears the nightcap until 5 am. In the morning her sleep mask sits on her forehead. After work she wears a top hat and bow tie."))
        } header: {
            SectionTitle(t("Outfits", "Outfits"), icon: "tshirt.fill", color: .purple)
        }
    }

    private func clock(_ minutes: Binding<Int>) -> Binding<Date> { clockBinding(minutes) }

    private var taskSection: some View {
        Section {
            HStack {
                hint(taskSummary)
                Spacer()
                Button(t("Aufgaben bearbeiten …", "Edit tasks …")) { settings.onOpenTasks?() }
            }
        } header: {
            SectionTitle(t("Aufgaben", "Tasks"), icon: "checklist", color: .green)
        }
    }

    private var taskSummary: String {
        switch settings.taskItems.count {
        case 0: return t("Noch keine Aufgaben.", "No tasks yet.")
        case 1: return t("1 Aufgabe zu ihrer Uhrzeit.", "1 task at its time.")
        case let count: return t("\(count) Aufgaben, jede zu ihrer Uhrzeit.", "\(count) tasks, each at its time.")
        }
    }

    private var motivationSection: some View {
        Section {
            Toggle(t("Motivieren", "Motivate me"), isOn: $settings.motivationEnabled)
            hint(t("Morgens und gegen Feierabend denkt sie an einen deiner Sprüche. Höchstens alle 4 bis 5 Stunden und nie im Videocall.",
                   "In the morning and towards the end of your workday she thinks of one of your sayings. At most every 4 to 5 hours and never during video calls."))
            ForEach(Array(settings.motivationSayings.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: 10) {
                    TextField("", text: sayingBinding(index))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                    Button {
                        if settings.motivationSayings.indices.contains(index) { settings.motivationSayings.remove(at: index) }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(t("Entfernen", "Remove"))
                }
            }
            HStack(spacing: 10) {
                TextField("", text: $newSaying, prompt: Text(t("Neuer Spruch, z. B. „Du rockst das!“", "New saying, e.g. “You rock this!”")))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addSaying)
                    .onChange(of: newSaying) { value in
                        if value.count > TasksView.maxLength { newSaying = String(value.prefix(TasksView.maxLength)) }
                    }
                Button(t("Hinzufügen", "Add"), action: addSaying)
                    .disabled(newSaying.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                hint(settings.motivationSayings.isEmpty
                     ? t("Ohne eigene Sprüche nimmt sie ihre eigenen.", "Without sayings of your own she uses hers.")
                     : t("Sie nimmt jedes Mal einen anderen.", "She picks a different one each time."))
                Spacer()
                previewButton(.motivation)
            }
        } header: {
            SectionTitle(t("Motivation", "Motivation"), icon: "sparkles", color: .yellow)
        }
    }

    private func addSaying() {
        let saying = newSaying.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !saying.isEmpty else { return }
        settings.motivationSayings.append(saying)
        newSaying = ""
    }

    /// Ein Spruch zum Bearbeiten (sicher, auch wenn er gerade entfernt wird)
    private func sayingBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { settings.motivationSayings.indices.contains(index) ? settings.motivationSayings[index] : "" },
            set: { value in
                guard settings.motivationSayings.indices.contains(index) else { return }
                settings.motivationSayings[index] = String(value.prefix(TasksView.maxLength))
            })
    }

    private var appsSection: some View {
        Section {
            hint(t("Pixelcat zählt, wie lange du in diesen Apps aktiv bist, und zeigt es in der Statistik. Nur die Zeit, keine Inhalte. Alles bleibt auf deinem Mac.",
                   "Pixelcat counts how long you're active in these apps and shows it in your statistics. Only the time, no content. Everything stays on your Mac."))
            ForEach(settings.trackedApps, id: \.self) { id in
                HStack(spacing: 10) {
                    if let icon = AppInfo.icon(id) {
                        Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                    }
                    Text(AppInfo.name(id))
                    Spacer()
                    Button {
                        settings.trackedApps.removeAll { $0 == id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(t("Nicht mehr zählen", "Stop counting"))
                }
            }
            let suggestions = AppInfo.suggestions.filter { AppInfo.url($0) != nil && !settings.trackedApps.contains($0) }
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { id in
                    Button {
                        settings.trackedApps.append(id)
                    } label: {
                        Label(AppInfo.name(id), systemImage: "plus")
                    }
                }
                Spacer()
                Button(t("App wählen …", "Choose app …")) { chooseApp() }
            }
        } header: {
            SectionTitle(t("Apps im Blick", "Apps to watch"), icon: "square.grid.2x2.fill", color: .teal)
        }
    }

    /// Eine App aus dem Programme-Ordner wählen
    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.prompt = t("Hinzufügen", "Add")
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier, !settings.trackedApps.contains(id) else { return }
        settings.trackedApps.append(id)
    }

    private var birdSection: some View {
        Section {
            Toggle(t("Vogel jagen, wenn du weg bist", "Chase a bird while you're away"), isOn: $settings.birdWhenAway)
            minutesSlider(t("Weg seit", "Away for"), value: $settings.birdMinutes, range: 2...60, step: 1)
            HStack {
                hint(t("Dann fliegt ein Vogel herum und sie jagt ihn. Bist du zurück, fliegt er davon und sie geht zurück in den Korb oder auf Streifzug.",
                       "A bird then flies around and she chases it. When you're back, it flies off and she returns to her bed or roaming."))
                Spacer()
                previewButton(.bird)
            }
        } header: {
            SectionTitle(t("Wenn du weg bist", "While you're away"), icon: "bird.fill", color: .cyan)
        }
    }

    // MARK: Ton & Rücksicht

    private var soundSection: some View {
        Section {
            Toggle(t("Miauen", "Meow"), isOn: $settings.sounds)
            hint(t("Leise, echte Katzenlaute bei Pomodoro, Timer, Pausen, Trinken, Augenpause, Feierabend und Motivation. Nie im Videocall oder Fokus.",
                   "Soft, real cat sounds for Pomodoro, timers, breaks, drinking, eye breaks, the end of the day and motivation. Never in video calls or Focus."))
            Toggle(t("Auch bei Aufgaben miauen", "Also meow for tasks"), isOn: $settings.meowForTasks)
                .disabled(!settings.sounds)
            hint(t("Sonst erscheint bei Aufgaben nur die Blase, ohne Ton.", "Otherwise tasks only show the bubble, without sound."))
            Toggle(t("Schnurren beim Streicheln", "Purr when petted"), isOn: $settings.purring)
        } header: {
            SectionTitle(t("Töne", "Sounds"), icon: "speaker.wave.2.fill", color: .pink)
        }
    }

    private var considerateSection: some View {
        Section {
            Toggle(t("Ruhemodus", "Silent mode"), isOn: $settings.silentMode)
            hint(t("Sie geht in den Korb oder aus dem Bild. Keine Erinnerungen, keine Töne, bis du ihn ausschaltest. Auch im Menü mit ⌘K.",
                   "She goes to her bed or out of sight. No reminders, no sounds until you turn it off. Also in the menu with ⌘K."))
            Toggle(t("Bei Videocalls und Bildschirmfreigabe verstecken", "Hide during video calls and screen sharing"),
                   isOn: $settings.hideDuringCalls)
            hint(t("Bei Kamera, Mikrofon oder geteiltem Bildschirm versteckt sie sich. Erinnerungen warten so lange. Aufgaben auf Wunsch nicht, siehe Aufgabenfenster.",
                   "While the camera, mic or screen sharing is on, she hides. Reminders wait until then. Tasks can still show, see the tasks window."))
            Toggle(t("Fokus berücksichtigen", "Respect Focus"), isOn: $settings.respectFocus)
            HStack {
                hint(focusStatusText)
                Spacer()
                if focus.access == .unknown {
                    Button(t("Zugriff erlauben …", "Allow access …")) { focus.requestAccess() }
                }
            }
        } header: {
            SectionTitle(t("Rücksicht", "Being considerate"), icon: "hand.raised.fill", color: .gray)
        }
    }

    private var focusStatusText: String {
        switch focus.access {
        case .allowed:
            return t("Ist ein Fokus wie „Nicht stören“ an, bleibt sie still und schläft mehr.",
                     "During a Focus like Do Not Disturb she stays quiet and sleeps more.")
        case .unknown:
            return t("macOS fragt einmal, ob sie den Fokusstatus sehen darf.",
                     "macOS asks once whether she may see your Focus status.")
        case .denied:
            return t("Kein Zugriff. Erlauben unter Systemeinstellungen › Datenschutz & Sicherheit › Fokus.",
                     "No access. Allow it in System Settings › Privacy & Security › Focus.")
        case .unavailable:
            return t("Der Fokusstatus ist auf diesem Mac nicht verfügbar.", "Focus status isn't available on this Mac.")
        }
    }

    // MARK: Allgemein

    private var languageSection: some View {
        Section {
            Picker("", selection: $settings.language) {
                ForEach(Language.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
        } header: {
            SectionTitle(t("Sprache", "Language"), icon: "globe", color: .blue)
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Pixelcat \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                Spacer()
                Button(t("Einrichtung zeigen …", "Show setup …")) { settings.onOpenSetup?() }
            }
            hint("github.com/TheesBudde/pixelcat")
            hint(t("Katzenlaute: „Cat Purr & Meow“ von Kerzoven (opengameart.org, CC0)",
                   "Cat sounds: “Cat Purr & Meow” by Kerzoven (opengameart.org, CC0)"))
        } header: {
            SectionTitle(t("Über", "About"), icon: "info.circle.fill", color: .gray)
        } footer: {
            HStack {
                Spacer()
                PixelCat(coat: settings.coat, pose: .sleep, scale: 3)
                    .opacity(0.55)
                Spacer()
            }
            .padding(.top, 8)
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

/// Minuten nach Mitternacht als Datum für einen Zeitwähler (nur Stunde und Minute zählen)
func clockBinding(_ minutes: Binding<Int>) -> Binding<Date> {
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

/// Name der Katze: schlichter Text mit Stift, ohne Rahmen. Beim Bearbeiten wird die Fläche etwas kräftiger.
struct NameInput: View {
    @Binding var name: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            TextField("", text: $name, prompt: Text("Pixelcat"))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(.body, design: .rounded).weight(.medium))
                .focused($focused)
                .frame(width: 150)
                .onChange(of: name) { value in
                    if value.count > OnboardingView.maxNameLength { name = String(value.prefix(OnboardingView.maxNameLength)) }
                }
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(focused ? Color.accentColor : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(focused ? 0.09 : 0.05)))
        .contentShape(Capsule())
        .onTapGesture { focused = true }
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// Abschnittstitel mit farbigem Symbol wie in den Systemeinstellungen
struct SectionTitle: View {
    let title: String
    let icon: String
    let color: Color

    init(_ title: String, icon: String, color: Color) {
        self.title = title
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient))
            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.top, 4)
    }
}

/// Oben im Fenster: die Katze in ihrem Fell mit ihrem Namen
struct SettingsHeader: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            PixelCat(coat: settings.coat, pose: .sit, scale: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.displayName)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(L10n.s("Einstellungen", "Settings"))
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
            Spacer()
            VStack(spacing: 10) {
                PixelSprite(sprite: PixelArt.heart, colors: ["K": NSColor.systemPink.cgColor], scale: 3)
                    .opacity(0.5)
                    .offset(x: -14)
                PixelSprite(sprite: PixelArt.paw, colors: ["K": NSColor.secondaryLabelColor.cgColor], scale: 3)
                    .rotationEffect(.degrees(-15))
                    .opacity(0.35)
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 4)
    }
}
