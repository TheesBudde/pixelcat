import AppKit
import SwiftUI

// Zeichnet das Einstellungsfenster, das Aufgabenfenster und alle Seiten der Einrichtung als Bild, zur Sichtprüfung
MainActor.assumeIsolated {
    _ = NSApplication.shared
    let settings = AppSettings()
    settings.taskItems = [TaskItem(text: "Mama anrufen", minutes: 120), TaskItem(text: "Wasser trinken", minutes: 5),
                          TaskItem(text: "Steuererklärung abgeben", minutes: 90)]
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
}
