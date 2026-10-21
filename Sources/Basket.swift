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

/// Pixelbilder des Körbchens (einmal berechnet): ein rundes, weiches Katzenbett –
/// ein ovaler Plüschrand mit Kissen in der Mulde. Hinterer Teil hinter, vorderer Teil vor der Katze.
@MainActor
struct BasketArt {
    static let shared = BasketArt()
    static let colors = rgbPalette([
        "K": 0x6B5446, // Umriss
        "S": 0xE8D5BE, // Plüsch
        "H": 0xF7EDE0, // Glanz
        "s": 0xC9B094, // Schatten
        "C": 0x9DB4D8, // Kissen
        "c": 0x7F98C0, // Kissen, Falten
    ])

    let width = 40
    let height = 25
    /// Hinterer Rand und Kissen (wird zuerst gezeichnet)
    let back: Sprite
    /// Vorderer Rand – verdeckt den Bauch der Katze
    let front: Sprite
    let backY = 0
    /// Unterkante der Katze (von unten gezählt)
    let catY = 7

    init() {
        let w = width, h = height
        // Außen-Oval (Rand) und Mulde, die Mulde etwas nach hinten (oben) versetzt
        let (ocx, ocy, orx, ory) = (19.5, 14.0, 19.6, 10.4)
        let (icx, icy, irx, iry) = (19.5, 11.5, 12.6, 4.4)
        func inOuter(_ x: Int, _ y: Int) -> Bool {
            let dx = (Double(x) - ocx) / orx, dy = (Double(y) - ocy) / ory
            return dx * dx + dy * dy <= 1
        }
        func inInner(_ x: Int, _ y: Int) -> Bool {
            let dx = (Double(x) - icx) / irx, dy = (Double(y) - icy) / iry
            return dx * dx + dy * dy <= 1
        }

        var backGrid = [[Character]](repeating: [Character](repeating: ".", count: w), count: h)
        var frontGrid = backGrid
        for y in 0..<h {
            for x in 0..<w where inOuter(x, y) {
                if inInner(x, y) {
                    // Kissen in der Mulde, mit ein paar weichen Falten
                    backGrid[y][x] = (x * 3 + y * 5) % 11 == 0 ? "c" : "C"
                    // Rand der Mulde: dunklerer Übergang zum Plüsch
                    if !inInner(x, y - 1) || !inInner(x - 1, y) || !inInner(x + 1, y) { backGrid[y][x] = "s" }
                    continue
                }
                // Plüsch wie ein Donut: oben Glanz, unten Schatten, Innenwand vorne etwas dunkler,
                // dazwischen ein paar flauschige Tupfer
                let topEdge = !inOuter(x, y - 1) || !inOuter(x, y - 2)
                let bottomEdge = !inOuter(x, y + 1) || !inOuter(x, y + 2) || !inOuter(x, y + 3)
                let innerWall = Double(y) > icy && (inInner(x, y - 1) || inInner(x, y - 2))
                let frontCrest = Double(y) > icy && (inInner(x, y - 3) || inInner(x, y - 4)) && !innerWall
                var c: Character = (x + 2 * y) % 7 == 0 ? "H" : "S"
                if topEdge || frontCrest { c = "H" }
                if bottomEdge || innerWall { c = "s" }
                if y < Int(icy) { backGrid[y][x] = c } else { frontGrid[y][x] = c }
            }
        }
        // Umriss um das ganze Bett (auf beide Teile verteilt)
        for y in 0..<h {
            for x in 0..<w where !inOuter(x, y) {
                let near = [(0, 1), (0, -1), (1, 0), (-1, 0)].contains { inOuter(x + $0.0, y + $0.1) }
                if near { if y < Int(icy) { backGrid[y][x] = "K" } else { frontGrid[y][x] = "K" } }
            }
        }
        back = Sprite(backGrid.map { String($0) })
        front = Sprite(frontGrid.map { String($0) })
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
