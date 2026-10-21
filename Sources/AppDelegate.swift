import AppKit

/// Menüleisten-App: Katzensymbol oben rechts mit Menü für alles Weitere.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let sizes: [(name: String, scale: CGFloat)] = [
        ("Klein", 2), ("Mittel", 3), ("Groß", 4),
    ]

    private var statusItem: NSStatusItem!
    private var cat: CatController!
    private var toggleItem: NSMenuItem!
    private var pomodoroItem: NSMenuItem!
    private var pomodoroInfoItem: NSMenuItem!
    private var reminderItem: NSMenuItem!
    private var soundItem: NSMenuItem!
    private var climbItem: NSMenuItem!
    private var feedItem: NSMenuItem!
    private var playItem: NSMenuItem!
    private var startleItem: NSMenuItem!
    private var sleepItem: NSMenuItem!
    private var sizeItems: [NSMenuItem] = []
    private var coatItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "scale": 3.0, "coat": Coat.black.rawValue, "breakReminders": false, "sounds": true, "climbing": false,
        ])
        let coat = Coat(rawValue: defaults.string(forKey: "coat") ?? "") ?? .black
        cat = CatController(scale: defaults.double(forKey: "scale"), coat: coat)
        cat.breakReminders = defaults.bool(forKey: "breakReminders")
        cat.sounds = defaults.bool(forKey: "sounds")
        cat.climbing = defaults.bool(forKey: "climbing")
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

        pomodoroItem = item("Pomodoro starten", #selector(togglePomodoro))
        menu.addItem(pomodoroItem)
        pomodoroInfoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        pomodoroInfoItem.isEnabled = false
        menu.addItem(pomodoroInfoItem)
        reminderItem = item("Pausen-Erinnerung", #selector(toggleReminders))
        menu.addItem(reminderItem)
        menu.addItem(.separator())

        soundItem = item("Miauen", #selector(toggleSounds))
        menu.addItem(soundItem)
        climbItem = item("Klettern", #selector(toggleClimbing))
        menu.addItem(climbItem)

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

        if let pomodoro = cat.pomodoro {
            pomodoroItem.title = "Pomodoro beenden"
            pomodoroItem.state = .on
            let minutes = max(1, Int((pomodoro.ends.timeIntervalSinceNow / 60).rounded(.up)))
            pomodoroInfoItem.title = pomodoro.stage == .focus
                ? "Fokus: noch \(minutes) Min. – die Katze schläft"
                : "Pause: noch \(minutes) Min. – Zeit zum Strecken"
            pomodoroInfoItem.isHidden = false
        } else {
            pomodoroItem.title = "Pomodoro starten"
            pomodoroItem.state = .off
            pomodoroInfoItem.isHidden = true
        }
        reminderItem.state = cat.breakReminders ? .on : .off
        soundItem.state = cat.sounds ? .on : .off
        climbItem.state = cat.climbing ? .on : .off
        reminderItem.isEnabled = cat.pomodoro == nil

        // Während der Fokuszeit schläft die Katze – dann gibt es nichts zu füttern oder zu spielen
        let awake = !cat.isInFocus
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

    @objc private func toggleSounds() {
        cat.sounds.toggle()
        UserDefaults.standard.set(cat.sounds, forKey: "sounds")
        // Zum Probehören
        if cat.sounds { Meow.play(.breakStarts) }
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
