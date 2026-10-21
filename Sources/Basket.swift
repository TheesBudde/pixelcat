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

/// Pixelbilder des Körbchens (einmal berechnet): ein rundes, weiches Katzenbett mit dicker Polsterrolle
/// als Rand und einem Kissen in der Mulde. Der hintere Teil liegt hinter, der vordere vor der Katze.
/// Kompakt, damit die Katze es gut ausfüllt.
@MainActor
struct BasketArt {
    static let shared = BasketArt()
    static let colors = rgbPalette([
        "K": 0x5E4440, // Umriss
        "H": 0xF6D9D3, // Glanz oben auf der Rolle
        "S": 0xE4B5AE, // Plüsch
        "s": 0xC68F89, // Schatten
        "d": 0xA26F6B, // tiefer Schatten (Innenwand, unten)
        "C": 0xF7ECDD, // Kissen
        "c": 0xE3D3BE, // Kissen, Falten
    ])

    let width = 32
    let height = 24
    let back: Sprite
    let front: Sprite
    let backY = 0
    /// Unterkante der Katze (von unten gezählt) – ihr Bauch verschwindet hinter der vorderen Rolle
    let catY = 6

    init() {
        let w = width, h = height
        let (cx, ocy, orx, ory) = (15.5, 14.2, 15.7, 9.6)   // äußerer Rand
        let (icy, irx, iry) = (11.2, 10.0, 4.4)             // Mulde, etwas nach hinten versetzt
        func outer(_ x: Int, _ y: Int) -> Double {
            let dx = (Double(x) - cx) / orx, dy = (Double(y) - ocy) / ory
            return (dx * dx + dy * dy).squareRoot()
        }
        func inner(_ x: Int, _ y: Int) -> Double {
            let dx = (Double(x) - cx) / irx, dy = (Double(y) - icy) / iry
            return (dx * dx + dy * dy).squareRoot()
        }

        var backGrid = [[Character]](repeating: [Character](repeating: ".", count: w), count: h)
        var frontGrid = backGrid
        for y in 0..<h {
            for x in 0..<w where outer(x, y) <= 1 {
                let i = inner(x, y)
                if i <= 1 {
                    // Kissen in der Mulde; zum Rand hin etwas dunkler, mit weichen Falten
                    var c: Character = i > 0.8 ? "c" : "C"
                    if (x * 5 + y * 3) % 13 == 0 { c = "c" }
                    if inner(x, y - 1) > 1 { c = "s" } // hintere Kante der Mulde
                    backGrid[y][x] = c
                    continue
                }
                // Lage auf der Polsterrolle: 0 = Innenkante, 1 = Außenkante
                let t = min(1, max(0, (i - 1) / max(0.01, i / max(outer(x, y), 0.01) - 1)))
                let front = Double(y) > icy
                var c: Character
                switch t {
                case ..<0.18: c = front ? "d" : "s"           // Innenwand
                case ..<0.32: c = "S"
                case ..<0.62: c = "H"                         // Glanz oben auf der Rolle
                case ..<0.82: c = "S"
                default: c = front ? "s" : "S"                // Außenseite
                }
                if front, outer(x, y + 1) > 1 || outer(x, y + 2) > 1 { c = "d" } // Unterkante
                if c == "S", (x + 3 * y) % 9 == 0 { c = "H" }                   // Flausch-Tupfer
                if front { frontGrid[y][x] = c } else { backGrid[y][x] = c }
            }
        }
        // Umriss ums ganze Bett
        for y in 0..<h {
            for x in 0..<w where outer(x, y) > 1 {
                guard [(0, 1), (0, -1), (1, 0), (-1, 0)].contains(where: { outer(x + $0.0, y + $0.1) <= 1 }) else { continue }
                if Double(y) > icy { frontGrid[y][x] = "K" } else { backGrid[y][x] = "K" }
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
