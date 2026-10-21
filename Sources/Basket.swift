import AppKit
import ApplicationServices

/// Katzenkörbchen als Dock-Symbol: Ist die Katze auf Streifzug, schläft sie hier –
/// sie atmet und hebt ab und zu die Schwanzspitze.
@MainActor
final class BasketTileView: NSView {
    var catInside = false { didSet { if catInside != oldValue { needsDisplay = true } } }
    var coat: Coat = .black { didSet { needsDisplay = true } }
    var breathIn = false { didSet { if breathIn != oldValue { needsDisplay = true } } }
    var tailUp = false { didSet { if tailUp != oldValue { needsDisplay = true } } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.setShouldAntialias(false)
        let art = BasketArt.shared
        let scale = min(bounds.width / CGFloat(art.width), bounds.height / CGFloat(art.height)) * 0.94
        let ox = (bounds.width / scale - CGFloat(art.width)) / 2
        let oy = (bounds.height / scale - CGFloat(art.height)) / 2 - 2
        // hinten: Rand und Kissen, dann die Katze, vorne das Geflecht
        art.back.draw(in: ctx, x: ox, y: oy + CGFloat(art.backY), scale: scale, colors: BasketArt.colors)
        if catInside {
            let cat = breathIn ? (tailUp ? Frames.sleepBTailUp : Frames.sleepB)
                               : (tailUp ? Frames.sleepATailUp : Frames.sleepA)
            cat.draw(in: ctx, x: ox + CGFloat((art.width - cat.width) / 2), y: oy + CGFloat(art.catY),
                     scale: scale, colors: coat.colors)
        }
        art.front.draw(in: ctx, x: ox, y: oy, scale: scale, colors: BasketArt.colors)
    }
}

/// Pixelbilder des Körbchens (einmal berechnet).
@MainActor
struct BasketArt {
    static let shared = BasketArt()
    static let colors = rgbPalette([
        "K": 0x3B2414, "L": 0xE2B276, "B": 0xB97E42, "b": 0x8A5627, "C": 0xD9536A, "c": 0xA8384F,
    ])

    let width = 40
    let height = 26
    /// Vorderseite: geflochtener Korb mit Rand oben
    let front: Sprite
    /// Hinterer Rand mit Kissen
    let back: Sprite
    let backY = 8
    /// Wo die Katze liegt (Unterkante, von unten gezählt) – ihr Bauch verschwindet hinter dem Rand
    let catY = 12

    init() {
        // Vorderseite: 40 × 14, nach unten etwas schmaler
        var rows: [String] = []
        for y in 0..<14 {
            var line = [Character](repeating: ".", count: width)
            let inset = y < 4 ? 0 : (y - 4) / 3 + 1
            for x in inset..<(width - inset) {
                let edge = x == inset || x == width - inset - 1
                switch y {
                case 0, 3, 13: line[x] = "K"
                case 1, 2: line[x] = edge ? "K" : ((x + y) % 3 == 0 ? "B" : "L")      // geflochtener Rand
                default: line[x] = edge ? "K" : ((x / 3 + y / 2) % 2 == 0 ? "B" : "b") // Korbgeflecht
                }
            }
            rows.append(String(line))
        }
        front = Sprite(rows)

        // Hinten: Rand-Bogen und Kissen, 40 × 10
        var backRows: [String] = []
        for y in 0..<10 {
            var line = [Character](repeating: ".", count: width)
            let inset = max(1, 5 - y)
            for x in inset..<(width - inset) {
                let edge = x == inset || x == width - inset - 1
                switch y {
                case 0: line[x] = "K"
                case 1, 2: line[x] = edge ? "K" : "b"
                default: line[x] = edge ? "K" : ((x + y) % 7 == 0 ? "c" : "C")
                }
            }
            backRows.append(String(line))
        }
        back = Sprite(backRows)
    }
}

/// Wo das Körbchen im Dock sitzt (Bildschirm-x der Mitte).
/// Exakt über die Bedienungshilfen (falls freigegeben), sonst geschätzt aus den Dock-Einstellungen.
enum DockLocator {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Fragt einmalig nach der Freigabe „Bedienungshilfen“.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func basketCenterX(appName: String, screen: NSScreen) -> CGFloat? {
        exactCenterX(appName: appName) ?? estimatedCenterX(screen: screen)
    }

    /// Über die Bedienungshilfen: das Dock-Element mit unserem Namen suchen.
    private static func exactCenterX(appName: String) -> CGFloat? {
        guard isTrusted,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        for list in children(of: app) {
            for item in children(of: list) {
                var title: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &title)
                guard (title as? String) == appName else { continue }
                var positionValue: CFTypeRef?
                var sizeValue: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue)
                AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue)
                var position = CGPoint.zero
                var size = CGSize.zero
                if let positionValue { AXValueGetValue(positionValue as! AXValue, .cgPoint, &position) }
                if let sizeValue { AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) }
                return position.x + size.width / 2
            }
        }
        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        return value as? [AXUIElement] ?? []
    }

    /// Schätzung: Das Dock ist zentriert; laufende, nicht angeheftete Apps stehen hinter den angehefteten,
    /// rechts folgen Trennstrich, Ordner und Papierkorb. Pixelcat sitzt meist als letzte laufende App.
    private static func estimatedCenterX(screen: NSScreen) -> CGFloat? {
        let prefs = UserDefaults(suiteName: "com.apple.dock")
        guard (prefs?.string(forKey: "orientation") ?? "bottom") == "bottom" else { return nil }
        let tile = CGFloat(prefs?.double(forKey: "tilesize") ?? 0) > 0 ? CGFloat(prefs!.double(forKey: "tilesize")) : 48
        let pinned = (prefs?.array(forKey: "persistent-apps") as? [[String: Any]]) ?? []
        let pinnedIDs = Set(pinned.compactMap { (($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String) })
        let others = (prefs?.array(forKey: "persistent-others") as? [Any])?.count ?? 0
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !pinnedIDs.contains($0.bundleIdentifier ?? "") && $0.bundleIdentifier != "com.apple.finder"
        }.count
        let showRecents = prefs?.object(forKey: "show-recents") as? Bool ?? true
        let recents = showRecents ? ((prefs?.array(forKey: "recent-apps") as? [Any])?.count ?? 0) : 0

        let appCount = CGFloat(1 + pinned.count + running)            // Finder + angeheftete + laufende
        let rightCount = CGFloat(others + 1 + recents)                 // Ordner, Papierkorb, zuletzt benutzte
        let separators: CGFloat = recents > 0 ? 2 : 1
        // Wird das Dock zu breit, verkleinert macOS die Symbole
        var pitch = tile * 1.1
        var width = (appCount + rightCount) * pitch + (separators + 1) * pitch * 0.36
        let available = screen.frame.width * 0.98
        if width > available {
            pitch *= available / width
            width = available
        }
        let left = screen.frame.midX - width / 2 + pitch * 0.18
        let x = left + (appCount - 0.5) * pitch
        return min(max(x, screen.frame.minX + pitch), screen.frame.maxX - pitch)
    }
}
