import AppKit
import SwiftUI

// Zeichnet das Einstellungsfenster (ganze Seite) als Bild – zur Sichtprüfung
MainActor.assumeIsolated {
    _ = NSApplication.shared
    let settings = AppSettings()
    settings.taskItems = [TaskItem(text: "Mama anrufen", minutes: 120), TaskItem(text: "Wasser trinken", minutes: 5),
                          TaskItem(text: "Steuererklärung abgeben", minutes: 90)]
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

    // Das Aufgabenfenster
    let tasks = NSHostingView(rootView: TasksView(settings: settings).frame(width: 560))
    tasks.frame = NSRect(x: 0, y: 0, width: 560, height: 1200)
    tasks.layoutSubtreeIfNeeded()
    tasks.frame = NSRect(x: 0, y: 0, width: 560, height: min(1200, tasks.fittingSize.height))
    tasks.layoutSubtreeIfNeeded()
    let tasksRep = tasks.bitmapImageRepForCachingDisplay(in: tasks.bounds)!
    tasks.cacheDisplay(in: tasks.bounds, to: tasksRep)
    let tasksPath = CommandLine.arguments[1].replacingOccurrences(of: "einstellungen", with: "aufgabenfenster")
    try! tasksRep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: tasksPath))
}
