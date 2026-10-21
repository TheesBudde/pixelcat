import AppKit
import SwiftUI

/// Alle Einstellungen an einem Ort. Jede Änderung wird sofort gespeichert und an die Katze weitergegeben.
@MainActor
final class AppSettings: ObservableObject {
    // Aussehen
    @Published var coat: Coat { didSet { changed() } }
    @Published var scale: Double { didSet { changed() } }
    @Published var seasonalOutfits: Bool { didSet { changed() } }
    // Verhalten
    @Published var climbing: Bool { didSet { changed() } }
    @Published var chaseCursor: Bool { didSet { changed() } }
    @Published var multiScreen: Bool { didSet { changed() } }
    @Published var roaming: Bool { didSet { changed() } }
    @Published var breakReminders: Bool { didSet { changed() } }
    // Zeiten (Minuten)
    @Published var pomodoroFocus: Int { didSet { changed() } }
    @Published var pomodoroBreak: Int { didSet { changed() } }
    @Published var reminderMin: Int { didSet { if reminderMax < reminderMin { reminderMax = reminderMin }; changed() } }
    @Published var reminderMax: Int { didSet { if reminderMin > reminderMax { reminderMin = reminderMax }; changed() } }
    @Published var breakLength: Int { didSet { changed() } }
    // Ton & Rücksicht
    @Published var sounds: Bool { didSet { changed() } }
    @Published var purring: Bool { didSet { changed() } }
    @Published var hideDuringCalls: Bool { didSet { changed() } }
    @Published var respectFocus: Bool { didSet { changed() } }
    // Allgemein
    @Published var language: Language { didSet { L10n.language = language; changed() } }

    /// Wird nach jeder Änderung aufgerufen
    var onChange: (() -> Void)?
    private var loading = true

    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [
            "coat": Coat.black.rawValue, "scale": 3.0, "seasonalOutfits": true,
            "climbing": false, "chaseCursor": true, "multiScreen": true, "roaming": false, "breakReminders": false,
            "pomodoroFocus": 25, "pomodoroBreak": 5, "reminderMin": 45, "reminderMax": 55, "breakLength": 5,
            "sounds": true, "purring": true, "hideDuringCalls": true, "respectFocus": true,
            "language": Language.system.rawValue,
        ])
        coat = Coat(rawValue: defaults.string(forKey: "coat") ?? "") ?? .black
        scale = defaults.double(forKey: "scale")
        seasonalOutfits = defaults.bool(forKey: "seasonalOutfits")
        climbing = defaults.bool(forKey: "climbing")
        chaseCursor = defaults.bool(forKey: "chaseCursor")
        multiScreen = defaults.bool(forKey: "multiScreen")
        roaming = defaults.bool(forKey: "roaming")
        breakReminders = defaults.bool(forKey: "breakReminders")
        pomodoroFocus = defaults.integer(forKey: "pomodoroFocus")
        pomodoroBreak = defaults.integer(forKey: "pomodoroBreak")
        reminderMin = defaults.integer(forKey: "reminderMin")
        reminderMax = defaults.integer(forKey: "reminderMax")
        breakLength = defaults.integer(forKey: "breakLength")
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
            "coat": coat.rawValue, "scale": scale, "seasonalOutfits": seasonalOutfits,
            "climbing": climbing, "chaseCursor": chaseCursor, "multiScreen": multiScreen,
            "roaming": roaming, "breakReminders": breakReminders,
            "pomodoroFocus": pomodoroFocus, "pomodoroBreak": pomodoroBreak,
            "reminderMin": reminderMin, "reminderMax": reminderMax, "breakLength": breakLength,
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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings, focus: focus))
            window.center()
            self.window = window
        }
        window?.title = L10n.s("Pixelkatze – Einstellungen", "Pixelkatze – Settings")
        focus.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Inhalt

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var focus: FocusMonitor

    private func t(_ de: String, _ en: String) -> String { L10n.s(de, en) }

    var body: some View {
        TabView {
            catTab.tabItem { Label(t("Katze", "Cat"), systemImage: "pawprint") }
            timesTab.tabItem { Label(t("Zeiten", "Times"), systemImage: "timer") }
            considerateTab.tabItem { Label(t("Ton & Rücksicht", "Sound & Quiet"), systemImage: "speaker.wave.2") }
            generalTab.tabItem { Label(t("Allgemein", "General"), systemImage: "gearshape") }
        }
        .padding(12)
        .frame(width: 480, height: 560)
        // Bei Sprachwechsel alles neu aufbauen
        .id(settings.language)
    }

    private var catTab: some View {
        Form {
            Section(t("Aussehen", "Look")) {
                Picker(t("Fellfarbe", "Coat"), selection: $settings.coat) {
                    ForEach(Coat.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker(t("Größe", "Size"), selection: $settings.scale) {
                    Text(t("Klein", "Small")).tag(2.0)
                    Text(t("Mittel", "Medium")).tag(3.0)
                    Text(t("Groß", "Large")).tag(4.0)
                }
                .pickerStyle(.segmented)
                Toggle(t("Verkleidung an Feiertagen", "Holiday outfits"), isOn: $settings.seasonalOutfits)
                Text(t("Weihnachtsmütze am 24./25. Dezember, Partyhut an Silvester und Neujahr.",
                       "Santa hat on Dec 24/25, party hat on New Year's Eve and New Year's Day."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(t("Verhalten", "Behavior")) {
                Toggle(t("Klettern auf Fenster", "Climb onto windows"), isOn: $settings.climbing)
                Toggle(t("Mauszeiger jagen", "Chase the mouse pointer"), isOn: $settings.chaseCursor)
                Toggle(t("Auf andere Bildschirme wechseln", "Wander to other displays"), isOn: $settings.multiScreen)
                Text(t("Mauszeiger jagen: Ruht die Maus am unteren Rand, schleicht sie sich an und springt – nicht im Streifzug.",
                       "Chase: when the pointer rests near the bottom, she sneaks up and pounces – not while roaming."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var timesTab: some View {
        Form {
            Section("Pomodoro") {
                Stepper(t("Fokus: \(settings.pomodoroFocus) Min.", "Focus: \(settings.pomodoroFocus) min"),
                        value: $settings.pomodoroFocus, in: 5...120, step: 5)
                Stepper(t("Pause: \(settings.pomodoroBreak) Min.", "Break: \(settings.pomodoroBreak) min"),
                        value: $settings.pomodoroBreak, in: 1...30)
            }
            Section(t("Pausen-Erinnerung", "Break reminder")) {
                Stepper(t("Frühestens nach \(settings.reminderMin) Min.", "No sooner than \(settings.reminderMin) min"),
                        value: $settings.reminderMin, in: 10...180, step: 5)
                Stepper(t("Spätestens nach \(settings.reminderMax) Min.", "No later than \(settings.reminderMax) min"),
                        value: $settings.reminderMax, in: 10...180, step: 5)
                Text(t("Der genaue Zeitpunkt ist zufällig dazwischen – das wirkt natürlicher.",
                       "The exact moment is random in between – it feels more natural."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(t("Pausen", "Breaks")) {
                Stepper(t("Länge einer Pause: \(settings.breakLength) Min.", "Length of a break: \(settings.breakLength) min"),
                        value: $settings.breakLength, in: 1...30)
                Text(t("Gilt für Pausen-Erinnerungen und für die Besuche im Streifzug.",
                       "Used for break reminders and for visits while roaming."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var considerateTab: some View {
        Form {
            Section(t("Töne", "Sounds")) {
                Toggle(t("Miauen (Pausen, Timer, Erinnerung)", "Meow (breaks, timer, reminder)"), isOn: $settings.sounds)
                Toggle(t("Schnurren beim Streicheln", "Purr while petting"), isOn: $settings.purring)
            }
            Section(t("Rücksicht", "Being considerate")) {
                Toggle(t("Bei Videocall oder Bildschirmfreigabe verstecken", "Hide during video calls and screen sharing"),
                       isOn: $settings.hideDuringCalls)
                Text(t("Sind Kamera oder Mikrofon an oder wird der Bildschirm geteilt, geht sie automatisch auf Streifzug – und kommt danach zurück.",
                       "While the camera or microphone is on or the screen is shared, she goes roaming – and comes back afterwards."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(t("Fokus berücksichtigen", "Respect Focus"), isOn: $settings.respectFocus)
                HStack {
                    Text(focusStatusText).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if focus.access == .unknown {
                        Button(t("Zugriff erlauben …", "Allow access …")) { focus.requestAccess() }
                    }
                }
            }
        }
        .formStyle(.grouped)
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

    private var generalTab: some View {
        Form {
            Section(t("Sprache", "Language")) {
                Picker(t("Sprache", "Language"), selection: $settings.language) {
                    ForEach(Language.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section(t("Über", "About")) {
                Text("Pixelkatze \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                Text("github.com/TheesBudde/pixelkatze").foregroundStyle(.secondary)
                Text(t("Katzenlaute: „Cat Purr & Meow“ von Kerzoven (opengameart.org, CC0)",
                       "Cat sounds: “Cat Purr & Meow” by Kerzoven (opengameart.org, CC0)"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
