import AppKit
import SwiftUI

// Zeichnet das Einstellungsfenster, das Aufgabenfenster und alle Seiten der Einrichtung als Bild, zur Sichtprüfung
MainActor.assumeIsolated {
    _ = NSApplication.shared
    let settings = AppSettings()
    settings.taskItems = [TaskItem(text: "Wasser trinken", time: 9 * 60 + 30), TaskItem(text: "Mama anrufen", time: 12 * 60),
                          TaskItem(text: "Steuererklärung abgeben", time: 16 * 60 + 45)]
    settings.motivationSayings = ["Du schaffst das!", "Heute rockst du das Meeting."]
    settings.breakByActivity = CommandLine.arguments.contains("--activity")
    if let i = CommandLine.arguments.firstIndex(of: "--lang"), i + 1 < CommandLine.arguments.count {
        settings.language = CommandLine.arguments[i + 1] == "en" ? .english : .german
    }
    let base = CommandLine.arguments[1]

    func shoot<V: View>(_ view: V, width: CGFloat, height: CGFloat, to path: String, appearance: NSAppearance.Name = .aqua) {
        let host = NSHostingView(rootView: view.frame(width: width, height: height))
        host.appearance = NSAppearance(named: appearance)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }

    // Ganze Seite: so hoch, dass alles hineinpasst
    shoot(SettingsView(settings: settings, focus: FocusMonitor()), width: 520, height: 2900, to: base)
    shoot(SettingsView(settings: settings, focus: FocusMonitor()), width: 520, height: 660,
          to: base.replacingOccurrences(of: ".png", with: "-dunkel.png"), appearance: .darkAqua)
    shoot(TasksView(settings: settings), width: 560, height: 620,
          to: base.replacingOccurrences(of: "einstellungen", with: "aufgabenfenster"))
    for step in OnboardingView.Step.allCases {
        shoot(OnboardingView(settings: settings, start: step), width: 620, height: 500,
              to: base.replacingOccurrences(of: "einstellungen", with: "einrichtung-\(step.rawValue + 1)"))
    }
    shoot(OnboardingView(settings: settings, start: .reminders), width: 620, height: 500,
          to: base.replacingOccurrences(of: "einstellungen", with: "einrichtung-dunkel"), appearance: .darkAqua)
    // Jedes Fell färbt die Fenster: schwarz dunkel, orange hell mit Orangestich, grau hell und leicht grau
    for coat in Coat.allCases {
        settings.coat = coat
        let look: NSAppearance.Name = coat == .black ? .darkAqua : .aqua
        shoot(SettingsView(settings: settings, focus: FocusMonitor()), width: 520, height: 660,
              to: base.replacingOccurrences(of: "einstellungen", with: "fell-\(coat.rawValue)-einstellungen"), appearance: look)
        shoot(OnboardingView(settings: settings, start: .coat), width: 620, height: 500,
              to: base.replacingOccurrences(of: "einstellungen", with: "fell-\(coat.rawValue)-einrichtung"), appearance: look)
        shoot(TasksView(settings: settings), width: 560, height: 620,
              to: base.replacingOccurrences(of: "einstellungen", with: "fell-\(coat.rawValue)-aufgaben"), appearance: look)
    }
    settings.coat = .black
    // Letzte Seite am Abend: mit Zylinder und Fliege
    settings.currentOutfit = { Frames.Outfit(hat: Frames.topHat, collar: Frames.bowTie) }
    shoot(OnboardingView(settings: settings, start: .done), width: 620, height: 500,
          to: base.replacingOccurrences(of: "einstellungen", with: "einrichtung-abend"), appearance: .darkAqua)
    settings.currentOutfit = nil

    // Statistik mit Beispieldaten: diese Woche bis heute und die Wochen davor
    let stats = StatsStore(url: nil)
    var seed: UInt64 = 7
    func random(_ range: ClosedRange<Int>) -> Int {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return range.lowerBound + Int((seed >> 33) % UInt64(range.count))
    }
    for back in 0..<30 {
        let date = Calendar.current.date(byAdding: .day, value: -back, to: Date())!
        let weekday = Calendar.current.component(.weekday, from: date)
        guard weekday != 1, weekday != 7 else { continue }
        stats.record(at: date) {
            $0.activeSeconds = Double(random(200...420)) * 60
            $0.breaksTaken = random(2...6)
            $0.breaksSkipped = random(0...3)
            $0.pomodoros = random(0...5)
            $0.drinks = random(2...7)
            $0.drinksSkipped = random(0...2)
        }
    }
    for coat in [Coat.orange, Coat.black] {
        settings.coat = coat
        shoot(StatsView(store: stats, settings: settings), width: 640, height: 1080,
              to: base.replacingOccurrences(of: "einstellungen", with: "statistik-\(coat.rawValue)"),
              appearance: coat == .black ? .darkAqua : .aqua)
    }
    settings.coat = .black
}
