import AppKit
import SwiftUI

// Zeichnet das Einstellungsfenster (ganze Seite) als Bild – zur Sichtprüfung
MainActor.assumeIsolated {
    _ = NSApplication.shared
    let settings = AppSettings()
    settings.taskItems = ["Mama anrufen", "Steuererklärung abgeben"]
    settings.breakByActivity = CommandLine.arguments.contains("--activity")
    let view = NSHostingView(rootView: SettingsView(settings: settings, focus: FocusMonitor()).frame(width: 520))
    view.frame = NSRect(x: 0, y: 0, width: 520, height: 3200)
    view.layoutSubtreeIfNeeded()
    let height = min(3200, view.fittingSize.height)
    view.frame = NSRect(x: 0, y: 0, width: 520, height: height)
    view.layoutSubtreeIfNeeded()
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    print("Höhe", height)
}
