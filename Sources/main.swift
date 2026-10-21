import AppKit

let arguments = CommandLine.arguments

// Hilfsmodi für build.sh und zum Ansehen der Sprites
if let i = arguments.firstIndex(of: "--export-icon"), i + 1 < arguments.count {
    try Exporter.exportIconSet(to: arguments[i + 1])
    exit(0)
}
if let i = arguments.firstIndex(of: "--export-preview"), i + 1 < arguments.count {
    try Exporter.exportPreview(to: arguments[i + 1])
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
