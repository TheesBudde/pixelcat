import AppKit

/// Menüleisten-App: Katzensymbol oben rechts mit Menü zum Ein-/Ausschalten.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let sizes: [(name: String, scale: CGFloat)] = [
        ("Klein", 2), ("Mittel", 3), ("Groß", 4),
    ]

    private var statusItem: NSStatusItem!
    private var cat: CatController!
    private var toggleItem: NSMenuItem!
    private var sizeItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["scale": 3.0])
        cat = CatController(scale: UserDefaults.standard.double(forKey: "scale"))
        setUpStatusItem()
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
        statusItem.button?.toolTip = "Pixelkatze"

        let menu = NSMenu()
        menu.delegate = self

        toggleItem = item("Katze ausblenden", #selector(toggleCat), key: "k")
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(item("Aufscheuchen", #selector(startle)))
        menu.addItem(item("Schlafen legen", #selector(goToSleep)))
        menu.addItem(.separator())

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

    func menuWillOpen(_ menu: NSMenu) {
        toggleItem.title = cat.isVisible ? "Katze ausblenden" : "Katze einblenden"
        for item in sizeItems {
            item.state = Self.sizes[item.tag].scale == cat.scale ? .on : .off
        }
    }

    @objc private func toggleCat() {
        cat.isVisible ? cat.hide() : cat.show()
    }

    @objc private func startle() {
        cat.show()
        cat.startle()
    }

    @objc private func goToSleep() {
        cat.show()
        cat.goToSleep()
    }

    @objc private func changeSize(_ sender: NSMenuItem) {
        cat.scale = Self.sizes[sender.tag].scale
        UserDefaults.standard.set(Double(cat.scale), forKey: "scale")
    }
}
