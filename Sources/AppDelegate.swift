import AppKit

/// Menüleisten-App: Katzensymbol oben rechts mit einem kurzen Menü für den Alltag –
/// alles Weitere steht im Einstellungsfenster.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let timerPresets = [5, 10, 15, 20, 30, 45, 60]

    private let settings = AppSettings()
    private let focusMonitor = FocusMonitor()
    private lazy var settingsWindow = SettingsWindow(settings: settings, focus: focusMonitor)
    private lazy var tasksWindow = TasksWindow(settings: settings)
    private lazy var onboardingWindow = OnboardingWindow(settings: settings)
    private let stats = StatsStore()
    private lazy var statsWindow = StatsWindow(store: stats, settings: settings)

    private var statusItem: NSStatusItem!
    private var cat: CatController!

    private var toggleItem: NSMenuItem!
    private var pomodoroItem: NSMenuItem!
    private var timerItem: NSMenuItem!
    private var timerMenu: NSMenu!
    /// Restzeit von Pomodoro oder Timer bzw. warum die Katze gerade versteckt ist
    private var infoItem: NSMenuItem!
    private var reminderItem: NSMenuItem!
    private var drinkItem: NSMenuItem!
    private var eyeItem: NSMenuItem!
    private var motivationItem: NSMenuItem!
    private var breakNowItem: NSMenuItem!
    private var taskItem: NSMenuItem!
    private var taskOnItem: NSMenuItem!
    private var taskCallsItem: NSMenuItem!
    private var selfTest: SelfTest?
    private var roamItem: NSMenuItem!
    private var feedItem: NSMenuItem!
    private var playItem: NSMenuItem!
    private var startleItem: NSMenuItem!
    private var sleepItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        cat = CatController(scale: settings.scale, coat: settings.coat, focusMonitor: focusMonitor)
        cat.stats = stats
        if settings.awayMode || settings.silentMode { cat.startRoamingOutside() }
        cat.apply(settings)
        settings.onChange = { [weak self] in
            guard let self else { return }
            cat.apply(settings)
            buildMenu() // Sprache könnte sich geändert haben
            buildMainMenu()
            statusItem.button?.toolTip = settings.displayName
            statusItem.button?.appearsDisabled = settings.silentMode // im Ruhemodus blass
        }
        // „Jetzt zeigen“ in den Einstellungen bzw. bei einer Aufgabe
        settings.onPreview = { [weak self] kind in
            guard let self else { return }
            cat.show()
            cat.showErrandNow(kind)
        }
        settings.onPreviewTask = { [weak self] id in
            guard let self else { return }
            cat.show()
            cat.showTaskNow(id)
        }
        settings.onOpenTasks = { [weak self] in self?.openTasks() }
        // Während der Einrichtung ist die Katze nicht auf dem Dock, danach kommt sie
        settings.onOpenStats = { [weak self] in self?.openStats() }
        settings.onPreviewBreak = { [weak self] in
            guard let self else { return }
            cat.show()
            cat.askForBreakNow()
        }
        settings.onOpenSetup = { [weak self] in
            self?.cat.hide()
            self?.onboardingWindow.show()
        }
        onboardingWindow.onClose = { [weak self] in self?.cat.show() }
        onboardingWindow.onDrop = { [weak self] rect, then in self?.cat.dropIn(from: rect, then: then) }
        settings.currentOutfit = { [weak self] in self?.cat.outfitNow() ?? Frames.Outfit() }

        // Start mit --demo: aktive Nachmittagskatze, die viel klettert
        if CommandLine.arguments.contains("--demo") { cat.enableDemo() }
        // Start mit --selftest: alle Erinnerungen auf dem Bildschirm durchspielen und prüfen
        if CommandLine.arguments.contains("--selftest") {
            selfTest = SelfTest(cat: cat, settings: settings)
            selfTest?.start(calls: CommandLine.arguments.contains("calls"))
        }
        // Start mit --outfit pumpkin|santa|party: Verkleidung vorführen
        if let i = CommandLine.arguments.firstIndex(of: "--outfit"), i + 1 < CommandLine.arguments.count {
            switch CommandLine.arguments[i + 1] {
            case "pumpkin": cat.outfitOverride = Frames.pumpkinHat
            case "santa": cat.outfitOverride = Frames.santaHat
            default: cat.outfitOverride = Frames.partyHat
            }
        }

        buildMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Frames.menuBarIcon()
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.toolTip = settings.displayName
        statusItem.button?.appearsDisabled = settings.silentMode
        buildMenu()
        cat.onStatusChange = { [weak self] text in self?.showStatus(text) }
        // Beim allerersten Start (oder mit --onboarding) erst die Einrichtung, danach kommt die Katze
        let selfTesting = CommandLine.arguments.contains("--selftest")
        let setup = CommandLine.arguments.contains("--onboarding") || (!settings.onboardingDone && !selfTesting)
        if ProcessInfo.processInfo.environment["PIXELCAT_CALIBRATE"] != nil {
            cat.runCalibration()
        } else if setup {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.onboardingWindow.show() }
        } else {
            cat.show()
        }
    }

    /// Wird die App erneut geöffnet (z. B. Doppelklick im Finder), kommt die Katze zurück.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        cat.show()
        return false
    }

    // MARK: Menü

    private func buildMenu() {
        func t(_ de: String, _ en: String) -> String { L10n.s(de, en) }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        // Ruhemodus: Sie geht weg, keine Erinnerungen, keine Töne
        toggleItem = item(t("Ruhemodus", "Silent mode"), #selector(toggleSilent), key: "k", icon: "bell.slash")
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        pomodoroItem = item("Pomodoro", #selector(togglePomodoro), icon: "timer")
        menu.addItem(pomodoroItem)
        timerMenu = NSMenu()
        for minutes in Self.timerPresets {
            let preset = item(t("\(minutes) Min.", "\(minutes) min"), #selector(startPresetTimer(_:)))
            preset.tag = minutes
            timerMenu.addItem(preset)
        }
        timerMenu.addItem(.separator())
        timerMenu.addItem(item(t("Eigene Zeit …", "Custom time …"), #selector(askForTimer), icon: "keyboard"))
        timerItem = NSMenuItem(title: "Timer", action: nil, keyEquivalent: "")
        timerItem.target = self
        timerItem.image = Self.symbol("hourglass")
        timerItem.submenu = timerMenu
        menu.addItem(timerItem)
        infoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        reminderItem = item(t("Pausenerinnerung", "Break reminder"), #selector(toggleReminders), icon: "cup.and.saucer")
        menu.addItem(reminderItem)
        // Jederzeit eine Pause: sofort, ohne zu fragen (während einer Pause: beenden)
        breakNowItem = item(t("Pause machen", "Take a break"), #selector(breakNow), icon: "pause.circle")
        menu.addItem(breakNowItem)
        drinkItem = item(t("Trinkerinnerung", "Drink reminder"), #selector(toggleDrinking), icon: "drop")
        menu.addItem(drinkItem)
        eyeItem = item(t("Augenpause", "Eye break"), #selector(toggleEyeBreaks), icon: "mountain.2")
        menu.addItem(eyeItem)
        // Aufgaben: Untermenü zum Ein-/Ausschalten und zum Bearbeiten der Liste
        let taskMenu = NSMenu()
        taskOnItem = item(t("Eingeschaltet", "On"), #selector(toggleTasks))
        taskMenu.addItem(taskOnItem)
        taskCallsItem = item(t("Auch während Videocalls", "Also during video calls"), #selector(toggleTasksDuringCalls))
        taskMenu.addItem(taskCallsItem)
        taskMenu.addItem(.separator())
        for task in settings.taskItems.sorted(by: { $0.time < $1.time }).prefix(8) {
            let entry = NSMenuItem(title: "\(task.timeText)  \(task.text)", action: nil, keyEquivalent: "")
            entry.isEnabled = false
            taskMenu.addItem(entry)
        }
        if settings.taskItems.count > 8 {
            let more = NSMenuItem(title: "…", action: nil, keyEquivalent: "")
            more.isEnabled = false
            taskMenu.addItem(more)
        }
        if !settings.taskItems.isEmpty { taskMenu.addItem(.separator()) }
        taskMenu.addItem(item(t("Aufgaben hinzufügen und bearbeiten …", "Add and edit tasks …"), #selector(openTasks), icon: "square.and.pencil"))
        taskItem = NSMenuItem(title: t("Aufgabenerinnerung", "Task reminder"), action: nil, keyEquivalent: "")
        taskItem.submenu = taskMenu
        taskItem.image = Self.symbol("checklist")
        menu.addItem(taskItem)
        motivationItem = item(t("Motivation", "Motivation"), #selector(toggleMotivation), icon: "sparkles")
        menu.addItem(motivationItem)
        // Mit Katzenkorb im Dock schläft sie dort, sonst geht sie auf Streifzug
        if settings.basketInDock {
            roamItem = item(t("Katzenkorb", "Cat Bed"), #selector(toggleRoaming), icon: "basket")
            roamItem.toolTip = t("Die Katze schläft im Korb im Dock und kommt nur zu Pausen und Erinnerungen heraus.",
                                 "The cat sleeps in the bed in the Dock and only comes out for breaks and reminders.")
        } else {
            roamItem = item(t("Streifzug", "Roaming"), #selector(toggleRoaming), icon: "pawprint")
            roamItem.toolTip = t("Die Katze geht weg und kommt nur zu Pausen und Erinnerungen herein.",
                                 "The cat heads out and only comes in for breaks and reminders.")
        }
        menu.addItem(roamItem)
        menu.addItem(.separator())

        feedItem = item(t("Füttern", "Feed"), #selector(feed), icon: "fork.knife")
        menu.addItem(feedItem)
        playItem = item(t("Mit Wollknäuel spielen", "Play with yarn"), #selector(togglePlaying), icon: "circle.dotted")
        menu.addItem(playItem)
        startleItem = item(t("Aufscheuchen", "Startle"), #selector(startle), icon: "hand.tap")
        menu.addItem(startleItem)
        sleepItem = item(t("Schlafen legen", "Put to sleep"), #selector(goToSleep), icon: "moon.zzz")
        menu.addItem(sleepItem)
        menu.addItem(.separator())

        menu.addItem(item(t("Einstellungen …", "Settings …"), #selector(openSettings), key: ",", icon: "gearshape"))
        menu.addItem(item(t("Statistik …", "Statistics …"), #selector(openStats), icon: "chart.bar"))
        let quit = NSMenuItem(title: t("Pixelcat beenden", "Quit Pixelcat"),
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        quit.image = Self.symbol("power")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    /// Menüleiste, wenn die App mit Körbchen im Dock aktiv ist: nur Einstellungen und Beenden.
    private func buildMainMenu() {
        func t(_ de: String, _ en: String) -> String { L10n.s(de, en) }
        let appMenu = NSMenu()
        appMenu.addItem(item(t("Einstellungen …", "Settings …"), #selector(openSettings), key: ","))
        appMenu.addItem(item(t("Statistik …", "Statistics …"), #selector(openStats)))
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: t("Pixelcat beenden", "Quit Pixelcat"),
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appMenu.addItem(quit)
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let main = NSMenu()
        main.addItem(appItem)
        NSApp.mainMenu = main
    }

    private func item(_ title: String, _ action: Selector, key: String = "", icon: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let icon { item.image = Self.symbol(icon) }
        return item
    }

    /// Kleines Symbol vor einem Menüpunkt (SF Symbols)
    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
    }

    /// Restzeit von Pomodoro oder Timer neben dem Katzenkopf in der Menüleiste.
    private func showStatus(_ text: String?) {
        guard let button = statusItem.button else { return }
        guard let text else {
            button.attributedTitle = NSAttributedString()
            return
        }
        button.attributedTitle = NSAttributedString(string: " " + text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular),
        ])
    }

    func menuWillOpen(_ menu: NSMenu) {
        func t(_ de: String, _ en: String) -> String { L10n.s(de, en) }
        toggleItem.state = settings.silentMode ? .on : .off

        // Haken = läuft; nochmal anklicken beendet. Pomodoro und Timer schließen sich aus.
        pomodoroItem.state = cat.pomodoro == nil ? .off : .on
        pomodoroItem.isEnabled = cat.timer == nil
        if cat.timer == nil {
            timerItem.submenu = timerMenu
            timerItem.action = nil
            timerItem.state = .off
        } else {
            timerItem.submenu = nil
            timerItem.action = #selector(stopTimer)
            timerItem.state = .on
        }
        timerItem.isEnabled = cat.pomodoro == nil

        func minutesLeft(_ end: Date) -> Int { max(1, Int((end.timeIntervalSinceNow / 60).rounded(.up))) }
        var info: String?
        if let pomodoro = cat.pomodoro {
            let minutes = minutesLeft(pomodoro.ends)
            info = pomodoro.stage == .focus
                ? t("Fokus: noch \(minutes) Min. Die Katze schläft.", "Focus: \(minutes) min left. The cat is asleep.")
                : t("Pause: noch \(minutes) Min.", "Break: \(minutes) min left")
        } else if let breakEnds = cat.breakEnds {
            let minutes = minutesLeft(breakEnds)
            info = t("Pause: noch \(minutes) Min. Die Katze bleibt bei dir.", "Break: \(minutes) min left. The cat stays with you.")
        } else if let timer = cat.timer {
            let minutes = minutesLeft(timer.ends)
            if timer.finished {
                info = t("Zeit um. Streichle oder klick die Katze.", "Time's up. Pet or click the cat.")
            } else {
                info = timer.breakEnds == nil
                    ? t("Noch \(minutes) Min. Die Katze schläft.", "\(minutes) min left. The cat is asleep.")
                    : t("Noch \(minutes) Min. Gerade Pause.", "\(minutes) min left. On a break.")
            }
        }
        if let reason = cat.hiddenBecause {
            let hidden = t("Versteckt: \(reason.title)", "Hidden: \(reason.title)")
            info = info.map { $0 + " · " + hidden } ?? hidden
        }
        infoItem.title = info ?? ""
        infoItem.isHidden = info == nil

        reminderItem.state = settings.breakReminders ? .on : .off
        reminderItem.isEnabled = cat.pomodoro == nil
        drinkItem.state = settings.drinkReminders ? .on : .off
        eyeItem.state = settings.eyeBreaks ? .on : .off
        motivationItem.state = settings.motivationEnabled ? .on : .off
        let onBreak = cat.breakEnds != nil
        breakNowItem.title = onBreak ? t("Pause beenden", "End break") : t("Pause machen", "Take a break")
        breakNowItem.image = Self.symbol(onBreak ? "play.circle" : "pause.circle")
        breakNowItem.isEnabled = cat.pomodoro == nil && cat.timer == nil
        taskItem.state = settings.taskReminders ? .on : .off
        taskOnItem.state = settings.taskReminders ? .on : .off
        taskCallsItem.state = settings.tasksDuringCalls ? .on : .off
        roamItem.state = settings.awayMode ? .on : .off

        // Schläft sie fest oder ist sie draußen, gibt es nichts zu füttern oder zu spielen
        let awake = !cat.isInFocus && !cat.isOutAndAbout
        feedItem.isEnabled = awake
        playItem.isEnabled = awake
        playItem.state = cat.isPlaying ? .on : .off
        startleItem.isEnabled = awake
        sleepItem.isEnabled = awake
    }

    // MARK: Aktionen

    @objc private func toggleSilent() {
        settings.silentMode.toggle()
    }

    @objc private func openStats() {
        statsWindow.show()
    }

    /// Statistik beim Beenden sicher speichern
    func applicationWillTerminate(_ notification: Notification) {
        stats.save(force: true)
    }

    @objc private func togglePomodoro() {
        cat.show()
        cat.pomodoro == nil ? cat.startPomodoro() : cat.stopPomodoro()
    }

    @objc private func startPresetTimer(_ sender: NSMenuItem) {
        cat.show()
        cat.startTimer(minutes: Double(sender.tag))
    }

    @objc private func stopTimer() {
        cat.stopTimer()
    }

    /// Kleines Eingabefenster für eine eigene Timerzeit.
    @objc private func askForTimer() {
        let alert = NSAlert()
        alert.messageText = L10n.s("Timer stellen", "Set timer")
        alert.informativeText = L10n.s(
            "Wie lange soll die Katze schlafen?\nMinuten eingeben, z. B. 25 oder 1:30 für anderthalb Stunden.",
            "How long should the cat sleep?\nEnter minutes, e.g. 25, or 1:30 for an hour and a half.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = L10n.s("Minuten", "Minutes")
        field.stringValue = UserDefaults.standard.string(forKey: "lastTimer") ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.s("Starten", "Start"))
        alert.addButton(withTitle: L10n.s("Abbrechen", "Cancel"))
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let minutes = Self.minutes(from: field.stringValue) else {
            NSSound.beep()
            askForTimer()
            return
        }
        UserDefaults.standard.set(field.stringValue, forKey: "lastTimer")
        cat.show()
        cat.startTimer(minutes: minutes)
    }

    /// "25" → 25 Minuten, "1:30" → 90 Minuten. Erlaubt sind 1 Minute bis 24 Stunden.
    static func minutes(from text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let value: Double?
        if cleaned.contains(":") {
            let parts = cleaned.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let hours = Double(parts[0]), let mins = Double(parts[1]) else { return nil }
            value = hours * 60 + mins
        } else {
            value = Double(cleaned)
        }
        guard let value, value >= 1, value <= 24 * 60 else { return nil }
        return value
    }

    @objc private func toggleReminders() {
        settings.breakReminders.toggle()
    }

    @objc private func toggleDrinking() {
        settings.drinkReminders.toggle()
    }

    @objc private func breakNow() {
        if cat.breakEnds != nil {
            cat.endBreak()
        } else {
            settings.silentMode = false // eine Pause ist kein Ruhemodus
            cat.show()
            cat.startBreakNow()
        }
    }

    @objc private func toggleMotivation() {
        settings.motivationEnabled.toggle()
    }

    @objc private func toggleEyeBreaks() {
        settings.eyeBreaks.toggle()
    }

    @objc private func toggleTasks() {
        settings.taskReminders.toggle()
        // Noch keine Aufgaben eingetragen: gleich die Einstellungen zeigen
        if settings.taskReminders, settings.taskItems.isEmpty { openTasks() }
    }

    @objc private func toggleTasksDuringCalls() {
        settings.tasksDuringCalls.toggle()
    }

    @objc private func openTasks() {
        tasksWindow.show()
    }

    @objc private func toggleRoaming() {
        cat.show()
        settings.awayMode.toggle()
    }

    @objc private func feed() {
        cat.show()
        cat.feed()
    }

    @objc private func togglePlaying() {
        cat.show()
        cat.setPlaying(!cat.isPlaying)
    }

    @objc private func startle() {
        cat.show()
        cat.startle()
    }

    @objc private func goToSleep() {
        cat.show()
        cat.goToSleep()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }
}
