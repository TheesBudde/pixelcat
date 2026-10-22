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
    /// Nur zum Nachmessen: gar nichts zeichnen
    var blank = false { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        guard !blank else { return }
        ctx.setShouldAntialias(false)
        let art = BasketArt.shared
        let scale = art.scale(forTile: min(bounds.width, bounds.height))
        let ox = (bounds.width / scale - CGFloat(art.width)) / 2
        let oy = (bounds.height / scale - CGFloat(art.height)) / 2 - CGFloat(BasketArt.lift)
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

/// Pixelbilder des Körbchens (einmal berechnet) – nach dem Vorbild eines ovalen Plüschbetts:
/// außen eine dunkle, gerippte Cord-Wand, oben ein cremefarbener, umgeschlagener Plüschrand,
/// innen ein weiches Kissen. Der hintere Teil liegt hinter, der vordere vor der Katze.
@MainActor
struct BasketArt {
    static let shared = BasketArt()
    static let colors = rgbPalette([
        "K": 0x2E282E, // Umriss
        "W": 0x5A535E, // Cord-Wand
        "w": 0x726A77, // Rippe, Licht
        "v": 0x443E47, // Rille, Schatten
        "H": 0xFCF8EF, // Plüschrand, Glanz
        "C": 0xF0E7D6, // Plüsch
        "c": 0xDACDB5, // Plüsch, Falten und Schatten
        "s": 0xBFAE93, // Plüsch, tiefe Falte
        "f": 0xE8DCC6, // Kissen in der Mulde
    ])

    let width = 32
    let height = 24
    let back: Sprite
    let front: Sprite
    let backY = 0
    /// Unterkante der Katze (von unten gezählt) – ihr Bauch verschwindet hinter dem vorderen Rand
    let catY = 11
    /// So weit sitzt das Bett unter der Mitte des Symbols (in Bildpixeln)
    static let lift = 2

    /// Größe eines Bildpixels bei dieser Symbolgröße
    func scale(forTile tile: CGFloat) -> CGFloat { tile * 0.94 / CGFloat(width) }
    /// Wo die Unterkante der Katze im Symbol liegt – gemessen von der Mitte des Symbols
    func catBottom(fromCenterOfTile tile: CGFloat) -> CGFloat {
        CGFloat(catY - height / 2 - Self.lift) * scale(forTile: tile)
    }

    init() {
        let w = width, h = height
        let (cx, rcy, rrx, rry) = (15.5, 9.6, 15.4, 6.0)    // Oberkante des Betts (Plüschrand außen)
        let (hcy, hrx, hry) = (8.7, 11.2, 3.1)              // Mulde
        let wallHeight = 6.0                                 // Cord-Wand unter dem vorderen Rand
        func rim(_ x: Int, _ y: Int) -> Double {
            let dx = (Double(x) - cx) / rrx, dy = (Double(y) - rcy) / rry
            // leicht gewellt: flauschige Büschel am Rand
            return (dx * dx + dy * dy).squareRoot() - 0.035 * sin(Double(x) * 1.9 + Double(y) * 0.7)
        }
        func hole(_ x: Int, _ y: Int) -> Double {
            let dx = (Double(x) - cx) / hrx, dy = (Double(y) - hcy) / hry
            return (dx * dx + dy * dy).squareRoot()
        }
        /// Die Wand: dieselbe Ellipse, nach unten verschoben und zum Boden hin rund eingezogen
        func inWall(_ x: Int, _ y: Int) -> Bool {
            guard Double(y) > rcy else { return false }
            return stride(from: 0.0, through: wallHeight, by: 0.5).contains { d in
                let rx = rrx * (1 - 0.09 * pow(d / wallHeight, 2))
                let dx = (Double(x) - cx) / rx, dy = (Double(y) - rcy - d) / rry
                return dx * dx + dy * dy <= 1
            }
        }
        func inBed(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < w && y < h && (rim(x, y) <= 1 || inWall(x, y))
        }

        var backGrid = [[Character]](repeating: [Character](repeating: ".", count: w), count: h)
        var frontGrid = backGrid
        for y in 0..<h {
            for x in 0..<w where inBed(x, y) {
                if rim(x, y) > 1 {
                    // Cord-Wand: senkrechte Rippen, oben Schatten unter dem Plüschrand, an den Seiten dunkler
                    let dx = abs((Double(x) - cx) / rrx)
                    var c: Character = x % 3 == 0 ? "v" : x % 3 == 1 ? "w" : "W"
                    if dx > 0.86, c == "w" { c = "W" }
                    if rim(x, y - 1) <= 1 { c = "v" }
                    if !inBed(x, y + 1) { c = "v" }
                    frontGrid[y][x] = c
                    continue
                }
                let i = hole(x, y)
                if i <= 1 {
                    // Kissen; hinten fällt der Schatten der Rückwand darauf
                    var c: Character = "f"
                    if hole(x, y - 1) > 1 { c = "s" }
                    else if hole(x, y - 2) > 1 { c = "c" }
                    else if (x * 5 + y * 3) % 17 == 0 { c = "c" }
                    backGrid[y][x] = c
                    continue
                }
                // Plüschrand, rund umgeschlagen: 0 = Innenkante, 1 = Außenkante
                let o = rim(x, y)
                let t = min(1, max(0, (i - 1) / max(0.01, i / max(o, 0.01) - 1)))
                let isFront = Double(y) > hcy
                var c: Character
                if isFront {
                    c = t < 0.2 ? "s" : t < 0.35 ? "C" : t < 0.7 ? "H" : "C"
                    if rim(x, y + 1) > 1 { c = "c" }                     // Unterkante des Wulsts
                } else {
                    c = t < 0.35 ? "C" : t < 0.75 ? "H" : "C"           // Innenseite der Rückwand
                }
                // weiche Falten im Plüsch
                if c != "c", (x * 2 + y * 5) % 9 == 0 { c = "c" }
                if isFront { frontGrid[y][x] = c } else { backGrid[y][x] = c }
            }
        }
        // Umriss ums ganze Bett
        for y in 0..<h {
            for x in 0..<w where !inBed(x, y) {
                guard [(0, 1), (0, -1), (1, 0), (-1, 0)].contains(where: { inBed(x + $0.0, y + $0.1) }) else { continue }
                if Double(y) > hcy { frontGrid[y][x] = "K" } else { backGrid[y][x] = "K" }
            }
        }
        back = Sprite(backGrid.map { String($0) })
        front = Sprite(frontGrid.map { String($0) })
    }
}

/// Wo das Körbchen im Dock sitzt und wie groß das Symbol gerade ist.
/// Exakt über die Bedienungshilfen (falls freigegeben), sonst geschätzt aus den Dock-Einstellungen.
enum DockLocator {
    /// Das Dock-Symbol: Mitte (Bildschirmkoordinaten) und Kantenlänge
    struct Tile {
        let center: CGPoint
        let size: CGFloat
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    enum Edge { case bottom, left, right }

    private static var prefs: UserDefaults? { UserDefaults(suiteName: "com.apple.dock") }

    /// Wo das Dock steht (Einstellung „Position auf dem Bildschirm“)
    static var edge: Edge {
        switch prefs?.string(forKey: "orientation") {
        case "left": return .left
        case "right": return .right
        default: return .bottom
        }
    }

    /// Der Bildschirm, auf dem das Dock gerade ist: Dort lässt macOS am Rand Platz dafür frei.
    /// Bei automatisch ausgeblendetem Dock gibt es keinen freien Rand – dann der Hauptbildschirm.
    static func dockScreen() -> NSScreen? {
        let edge = edge
        return NSScreen.screens.first { screen in
            switch edge {
            case .bottom: return screen.visibleFrame.minY - screen.frame.minY > 4
            case .left: return screen.visibleFrame.minX - screen.frame.minX > 4
            case .right: return screen.frame.maxX - screen.visibleFrame.maxX > 4
            }
        } ?? NSScreen.screens.first
    }

    /// Fragt einmalig nach der Freigabe „Bedienungshilfen“.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func basketTile(appName: String, screen: NSScreen) -> Tile? {
        guard let slot = exactTile(appName: appName) ?? estimatedTile(screen: screen) else { return nil }
        // Am Bildschirmfoto nachgemessen (Dock-Größe 44): Das Dock zeichnet das Symbol etwas kleiner als
        // seinen Platz (36,8 statt 38,5 pt), knapp über der Mitte des Dock-Streifens
        let size = slot.size * 0.955
        let dockHeight = screen.visibleFrame.minY - screen.frame.minY
        return Tile(center: CGPoint(x: slot.center.x, y: screen.frame.minY + dockHeight / 2 + 0.054 * size), size: size)
    }

    /// Für die Fehlersuche: was die Bedienungshilfen und die Schätzung sagen
    static func debugDescription(appName: String, screen: NSScreen) -> String {
        "trusted=\(isTrusted) ax=\(exactTile(appName: appName).map { "\($0)" } ?? "nil") "
            + "schätzung=\(estimatedTile(screen: screen).map { "\($0)" } ?? "nil")"
    }

    /// Über die Bedienungshilfen: das Dock-Element mit unserem Namen suchen. Sein Rahmen ist so breit wie
    /// das Symbol und reicht oben ein Stück darüber hinaus – das Symbol sitzt unten darin.
    private static func exactTile(appName: String) -> Tile? {
        guard isTrusted,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let top = NSScreen.screens.first?.frame.maxY
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
                // Gerade erst aufgetaucht (Symbol wächst noch)? Dann lieber schätzen
                guard size.width > 16 else { return nil }
                // Bedienungshilfen zählen y von oben; der Rahmen ist so breit wie der Platz des Symbols
                let bottom = top - (position.y + size.height)
                return Tile(center: CGPoint(x: position.x + size.width / 2, y: bottom + size.height / 2),
                            size: size.width)
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
    /// rechts folgen Trennstrich, Ordner und Papierkorb. Wurde Pixelcat im Dock behalten (und vielleicht
    /// verschoben), steht es an seinem Platz unter den angehefteten, sonst unter den laufenden Apps.
    /// Die Symbole stehen dicht an dicht; an beiden Enden und am Trennstrich ist je knapp ein halbes Symbol Luft
    /// (nachgemessen am echten Dock).
    private static func estimatedTile(screen: NSScreen) -> Tile? {
        let prefs = prefs
        guard edge == .bottom else { return nil }
        let tile = CGFloat(prefs?.double(forKey: "tilesize") ?? 0) > 0 ? CGFloat(prefs!.double(forKey: "tilesize")) : 48
        let pinned = (prefs?.array(forKey: "persistent-apps") as? [[String: Any]]) ?? []
        func bundleID(_ entry: [String: Any]) -> String? {
            (entry["tile-data"] as? [String: Any])?["bundle-identifier"] as? String
        }
        /// Platzbedarf eines angehefteten Eintrags: Abstandshalter sind halb bzw. ganz so breit wie ein Symbol
        func width(_ entry: [String: Any]) -> CGFloat {
            entry["tile-type"] as? String == "small-spacer-tile" ? 0.5 : 1
        }
        let pinnedIDs = Set(pinned.compactMap(bundleID))
        let others = (prefs?.array(forKey: "persistent-others") as? [Any])?.count ?? 0
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !pinnedIDs.contains($0.bundleIdentifier ?? "") && $0.bundleIdentifier != "com.apple.finder"
        }
        let running = runningApps.count
        let showRecents = prefs?.object(forKey: "show-recents") as? Bool ?? true
        let recents = showRecents ? ((prefs?.array(forKey: "recent-apps") as? [Any])?.count ?? 0) : 0

        let pinnedWidth = pinned.reduce(0) { $0 + width($1) }
        let appCount = 1 + pinnedWidth + CGFloat(running)              // Finder + angeheftete + laufende
        // Wie viele Symbolbreiten links von Pixelcat liegen.
        // Laufende Apps stehen in Startreihenfolge hinter den angehefteten.
        let myLaunch = NSRunningApplication.current.launchDate ?? .distantFuture
        let otherApps = runningApps.filter { $0.processIdentifier != NSRunningApplication.current.processIdentifier }
        let startedEarlier = CGFloat(otherApps.filter { ($0.launchDate ?? .distantPast) < myLaunch }.count)
        let before: CGFloat
        if let index = pinned.firstIndex(where: { bundleID($0) == Bundle.main.bundleIdentifier }) {
            // Steht Pixelcat als letzte angeheftete App gespeichert, ist es meist ganz nach rechts gezogen oder mit
            // „Im Dock behalten“ dort geblieben – dann hinter den laufenden Apps. (Nur nach einem Neustart des Docks
            // stünde es davor; die Bedienungshilfen kennen die genaue Stelle.)
            before = 1 + pinned[..<index].reduce(0) { $0 + width($1) }
                + (index == pinned.count - 1 ? CGFloat(otherApps.count) : 0)
        } else {
            before = 1 + pinnedWidth + startedEarlier
        }
        let rightCount = CGFloat(others + 1 + recents)                 // Ordner, Papierkorb, zuletzt benutzte
        let separators: CGFloat = recents > 0 ? 2 : 1
        let pad: CGFloat = 0.47, gap: CGFloat = 0.45                   // Luft am Rand bzw. am Trennstrich (in Symbolen)
        let slots = appCount + rightCount + 2 * pad + separators * gap
        // Wird das Dock zu breit, verkleinert macOS die Symbole
        let size = min(tile, screen.frame.width * 0.98 / slots)
        let left = screen.frame.midX - slots * size / 2
        let x = left + (pad + before + 0.5) * size
        return Tile(center: CGPoint(x: min(max(x, screen.frame.minX + size), screen.frame.maxX - size), y: 0),
                    size: size)
    }
}
