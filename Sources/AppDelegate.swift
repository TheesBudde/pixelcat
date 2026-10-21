import AppKit

/// Menüleisten-App: Katzensymbol oben rechts mit Menü für alles Weitere.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let sizes: [(name: String, scale: CGFloat)] = [
        ("Klein", 2), ("Mittel", 3), ("Groß", 4),
    ]
    private static let timerPresets = [5, 10, 15, 20, 30, 45, 60]

    private var statusItem: NSStatusItem!
    private var cat: CatController!
    private var toggleItem: NSMenuItem!
    private var pomodoroItem: NSMenuItem!
    private var timerItem: NSMenuItem!
    private var timerMenu: NSMenu!
    /// Restzeit von Pomodoro oder Timer
    private var infoItem: NSMenuItem!
    private var reminderItem: NSMenuItem!
    private var soundItem: NSMenuItem!
    private var climbItem: NSMenuItem!
    private var roamItem: NSMenuItem!
    private var feedItem: NSMenuItem!
    private var playItem: NSMenuItem!
    private var startleItem: NSMenuItem!
    private var sleepItem: NSMenuItem!
    private var sizeItems: [NSMenuItem] = []
    private var coatItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "scale": 3.0, "coat": Coat.black.rawValue, "breakReminders": false, "sounds": true, "climbing": false, "roaming": false,
        ])
        let coat = Coat(rawValue: defaults.string(forKey: "coat") ?? "") ?? .black
        cat = CatController(scale: defaults.double(forKey: "scale"), coat: coat)
        cat.breakReminders = defaults.bool(forKey: "breakReminders")
        cat.sounds = defaults.bool(forKey: "sounds")
        cat.climbing = defaults.bool(forKey: "climbing")
        if defaults.bool(forKey: "roaming") { cat.startRoamingOutside() }
        // Start mit --demo: aktive Nachmittagskatze, die viel klettert
        if CommandLine.arguments.contains("--demo") { cat.enableDemo() }
        setUpStatusItem()
        cat.onStatusChange = { [weak self] text in self?.showStatus(text) }
        cat.show()
    }

    /// Wird die App erneut geöffnet (z. B. Doppelklick im Finder), kommt die Katze zurück.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        cat.show()
        return false
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Frames.menuBarIcon()
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.toolTip = "Pixelkatze"

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        toggleItem = item("Katze ausblenden", #selector(toggleCat), key: "k")
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        pomodoroItem = item("Pomodoro", #selector(togglePomodoro))
        menu.addItem(pomodoroItem)

        timerMenu = NSMenu()
        for minutes in Self.timerPresets {
            let preset = item("\(minutes) Min.", #selector(startPresetTimer(_:)))
            preset.tag = minutes
            timerMenu.addItem(preset)
        }
        timerMenu.addItem(.separator())
        timerMenu.addItem(item("Eigene Zeit …", #selector(askForTimer)))
        timerItem = NSMenuItem(title: "Timer", action: nil, keyEquivalent: "")
        timerItem.target = self
        timerItem.submenu = timerMenu
        menu.addItem(timerItem)

        infoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        reminderItem = item("Pausen-Erinnerung", #selector(toggleReminders))
        menu.addItem(reminderItem)
        menu.addItem(.separator())

        soundItem = item("Miauen", #selector(toggleSounds))
        menu.addItem(soundItem)
        climbItem = item("Klettern", #selector(toggleClimbing))
        menu.addItem(climbItem)
        roamItem = item("Streifzug", #selector(toggleRoaming))
        roamItem.toolTip = "Die Katze geht nach draußen und kommt nur zu Pausen in die Bildschirmmitte: "
            + "Pomodoro-Pause, Pausen-Erinnerung oder wenn der Timer abläuft."
        menu.addItem(roamItem)

        feedItem = item("Füttern", #selector(feed))
        menu.addItem(feedItem)
        playItem = item("Mit Wollknäuel spielen", #selector(togglePlaying))
        menu.addItem(playItem)
        startleItem = item("Aufscheuchen", #selector(startle))
        menu.addItem(startleItem)
        sleepItem = item("Schlafen legen", #selector(goToSleep))
        menu.addItem(sleepItem)
        menu.addItem(.separator())

        let coatMenu = NSMenu()
        for (index, coat) in Coat.allCases.enumerated() {
            let coatItem = item(coat.title, #selector(changeCoat(_:)))
            coatItem.tag = index
            coatMenu.addItem(coatItem)
            coatItems.append(coatItem)
        }
        let coatParent = NSMenuItem(title: "Farbe", action: nil, keyEquivalent: "")
        coatParent.submenu = coatMenu
        menu.addItem(coatParent)

        let sizeMenu = NSMenu()
        for (index, size) in Self.sizes.enumerated() {
            let sizeItem = item(size.name, #selector(changeSize(_:)))
            sizeItem.tag = index
            sizeMenu.addItem(sizeItem)
            sizeItems.append(sizeItem)
        }
        let sizeParent = NSMenuItem(title: "Größe", action: nil, keyEquivalent: "")
        sizeParent.submenu = sizeMenu
        menu.addItem(sizeParent)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Pixelkatze beenden",
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// Restzeit des Pomodoro neben dem Katzenkopf in der Menüleiste.
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
        toggleItem.title = cat.isVisible ? "Katze ausblenden" : "Katze einblenden"

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
        if let pomodoro = cat.pomodoro {
            infoItem.title = pomodoro.stage == .focus
                ? "Fokus: noch \(minutesLeft(pomodoro.ends)) Min. – die Katze schläft"
                : "Pause: noch \(minutesLeft(pomodoro.ends)) Min."
            infoItem.isHidden = false
        } else if let timer = cat.timer {
            if timer.finished {
                infoItem.title = "Zeit um – streichle oder klick die Katze"
            } else {
                infoItem.title = timer.breakEnds == nil
                    ? "Noch \(minutesLeft(timer.ends)) Min. – die Katze schläft"
                    : "Noch \(minutesLeft(timer.ends)) Min. – gerade Pause"
            }
            infoItem.isHidden = false
        } else {
            infoItem.isHidden = true
        }
        reminderItem.state = cat.breakReminders ? .on : .off
        soundItem.state = cat.sounds ? .on : .off
        climbItem.state = cat.climbing ? .on : .off
        roamItem.state = cat.roaming ? .on : .off
        reminderItem.isEnabled = cat.pomodoro == nil

        // Während der Fokuszeit schläft die Katze – dann gibt es nichts zu füttern oder zu spielen
        let awake = !cat.isInFocus && !cat.isOutAndAbout
        feedItem.isEnabled = awake
        playItem.isEnabled = awake
        playItem.state = cat.isPlaying ? .on : .off
        startleItem.isEnabled = awake
        sleepItem.isEnabled = awake

        for item in sizeItems {
            item.state = Self.sizes[item.tag].scale == cat.scale ? .on : .off
        }
        for item in coatItems {
            item.state = Coat.allCases[item.tag] == cat.coat ? .on : .off
        }
    }

    @objc private func toggleCat() {
        cat.isVisible ? cat.hide() : cat.show()
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
        alert.messageText = "Timer stellen"
        alert.informativeText = "Wie lange soll die Katze schlafen?\nMinuten eingeben, z. B. 25 – oder 1:30 für anderthalb Stunden."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "Minuten"
        field.stringValue = UserDefaults.standard.string(forKey: "lastTimer") ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Starten")
        alert.addButton(withTitle: "Abbrechen")
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

    @objc private func toggleSounds() {
        cat.sounds.toggle()
        UserDefaults.standard.set(cat.sounds, forKey: "sounds")
        // Zum Probehören
        if cat.sounds { Meow.play(.breakStarts) }
    }

    @objc private func toggleRoaming() {
        cat.show()
        cat.roaming.toggle()
        UserDefaults.standard.set(cat.roaming, forKey: "roaming")
    }

    @objc private func toggleClimbing() {
        cat.show()
        cat.climbing.toggle()
        UserDefaults.standard.set(cat.climbing, forKey: "climbing")
    }

    @objc private func toggleReminders() {
        cat.breakReminders.toggle()
        UserDefaults.standard.set(cat.breakReminders, forKey: "breakReminders")
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

    @objc private func changeCoat(_ sender: NSMenuItem) {
        cat.coat = Coat.allCases[sender.tag]
        UserDefaults.standard.set(cat.coat.rawValue, forKey: "coat")
    }

    @objc private func changeSize(_ sender: NSMenuItem) {
        cat.scale = Self.sizes[sender.tag].scale
        UserDefaults.standard.set(Double(cat.scale), forKey: "scale")
    }
}
