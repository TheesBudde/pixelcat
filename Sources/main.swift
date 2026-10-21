import AppKit

let arguments = CommandLine.arguments

// Hilfsmodi für build.sh und zum Ansehen der Sprites
if let i = arguments.firstIndex(of: "--export-icon"), i + 1 < arguments.count {
    try Exporter.exportIconSet(to: arguments[i + 1])
    exit(0)
}
if let i = arguments.firstIndex(of: "--export-preview"), i + 1 < arguments.count {
    let coat = i + 2 < arguments.count ? Coat(rawValue: arguments[i + 2]) ?? .orange : .orange
    try Exporter.exportPreview(to: arguments[i + 1], coat: coat)
    exit(0)
}
if let i = arguments.firstIndex(of: "--export-sounds"), i + 1 < arguments.count {
    MainActor.assumeIsolated {
        let dir = URL(fileURLWithPath: arguments[i + 1])
        try? Meow.meow.write(to: dir.appendingPathComponent("miau.wav"))
        try? Meow.trill.write(to: dir.appendingPathComponent("mrrp.wav"))
    }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
