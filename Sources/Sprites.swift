import AppKit

/// Fellfarben. Die Pixelraster benutzen Platzhalter-Buchstaben, jede Fellfarbe legt fest,
/// wie sie aussehen: "K" Umriss, "O" Fell, "h" Glanz, "s" Streifen, "W" Brust/Pfoten,
/// "E" Augen, "c" geschlossene Augen, "P" Nase/Ohren, "w" Schnurrhaare. "." ist durchsichtig.
enum Coat: String, CaseIterable {
    case orange, black, gray

    var title: String {
        switch self {
        case .orange: return "Orange getigert"
        case .black: return "Schwarz"
        case .gray: return "Grau getigert"
        }
    }

    var colors: [Character: CGColor] {
        switch self {
        case .orange: return Coat.orangeColors
        case .black: return Coat.blackColors
        case .gray: return Coat.grayColors
        }
    }

    private static let orangeColors = palette([
        "K": 0x2B1D16, "O": 0xF2A14B, "h": 0xF6B263, "s": 0xC96F2E, "W": 0xFFF4E2,
        "E": 0x2E5E2A, "c": 0x2B1D16, "P": 0xF49AAE,
    ])

    private static let blackColors = palette([
        "K": 0x0B0A0F, "O": 0x26232E, "h": 0x4B4659, "s": 0x26232E, "W": 0x26232E,
        "E": 0x7BC95A, "c": 0x6A6480, "P": 0x7A7584, "w": 0x8E889C,
    ])

    private static let grayColors = palette([
        "K": 0x1E1F25, "O": 0x8D9099, "h": 0xA8ABB3, "s": 0x6A6D76, "W": 0xEDEEF1,
        "E": 0xE3AE45, "c": 0x3E4048, "P": 0xD9A0AD, "w": 0xEDEEF1,
    ])

    private static func palette(_ hex: [Character: UInt32]) -> [Character: CGColor] {
        hex.mapValues { value in
            CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                    green: CGFloat((value >> 8) & 0xFF) / 255,
                    blue: CGFloat(value & 0xFF) / 255,
                    alpha: 1)
        }
    }
}

/// Ein Pixelbild aus Textzeilen. Zeile 0 ist oben, Spalte 0 links.
final class Sprite {
    let width: Int
    let height: Int
    private let pixels: [Character]

    init(_ rows: [String]) {
        height = rows.count
        width = rows.map(\.count).max() ?? 0
        var pixels: [Character] = []
        for row in rows {
            let chars = Array(row)
            pixels += chars + Array(repeating: ".", count: width - chars.count)
        }
        self.pixels = pixels
    }

    private init(width: Int, height: Int, pixels: [Character]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    func pixel(_ x: Int, _ y: Int) -> Character {
        guard x >= 0, y >= 0, x < width, y < height else { return "." }
        return pixels[y * width + x]
    }

    func mapped(_ transform: (Int, Int, Character) -> Character) -> Sprite {
        var result = pixels
        for y in 0..<height {
            for x in 0..<width {
                result[y * width + x] = transform(x, y, pixel(x, y))
            }
        }
        return Sprite(width: width, height: height, pixels: result)
    }

    /// Augen zu: Das obere Augenpixel wird Fell, das untere ein Strich.
    var withClosedEyes: Sprite {
        mapped { x, y, c in
            guard c == "E" else { return c }
            return pixel(x, y + 1) == "E" ? "O" : "c"
        }
    }

    /// Zufrieden zugekniffene Augen: Der Strich sitzt oben.
    var withHappyEyes: Sprite {
        mapped { x, y, c in
            guard c == "E" else { return c }
            return pixel(x, y + 1) == "E" ? "c" : "O"
        }
    }

    /// Zeichnet das Bild; `x`/`y` sind die linke untere Ecke in Pixeleinheiten.
    func draw(in ctx: CGContext, x: CGFloat, y: CGFloat, scale: CGFloat, coat: Coat) {
        let colors = coat.colors
        for row in 0..<height {
            for col in 0..<width {
                guard let color = colors[pixel(col, row)] else { continue }
                ctx.setFillColor(color)
                ctx.fill(CGRect(x: (x + CGFloat(col)) * scale,
                                y: (y + CGFloat(height - 1 - row)) * scale,
                                width: scale, height: scale))
            }
        }
    }
}

/// Alle Posen der Katze (schaut nach rechts; nach links wird gespiegelt).
enum Frames {
    private static let upperBody = [
        "...............K....K...",
        "..............KPKKKKPK..",
        ".KKK..........KhhhhhhK..",
        "KhOK..........KOEOOEOK..",
        "KhK...........KOEOOEOK..",
        "KsK..........wKOWPPWOKw.",
        "KOKKKKKKKKKKKKKWWWWWWKw.",
        ".KOhhhhhhhhhhhhKWWWWK...",
        "..KOOsOOsOOsOOOOKKKK....",
        "..KOOsOOsOOsOOOOOK......",
        "..KOWWWWWWWWWWWOOK......",
        "..KKKKKKKKKKKKKKKK......",
    ]

    static let stand = Sprite(upperBody + [
        "...KOK.KOK..KOK.KOK.....",
        "...KWK.KWK..KWK.KWK.....",
        "...KKK.KKK..KKK.KKK.....",
    ])

    static let walkA = Sprite(upperBody + [
        "..KOK...KOK.KOK...KOK...",
        "..KWK...KWK.KWK...KWK...",
        "..KKK...KKK.KKK...KKK...",
    ])

    static let walkB = Sprite(upperBody + [
        "....KOKKOK....KOKKOK....",
        "....KWKKWK....KWKKWK....",
        "....KKKKKK....KKKKKK....",
    ])

    /// Auf Zehenspitzen – drückt sich beim Streicheln gegen die Hand.
    private static let standTall = Sprite(upperBody + [
        "...KOK.KOK..KOK.KOK.....",
        "...KOK.KOK..KOK.KOK.....",
        "...KWK.KWK..KWK.KWK.....",
        "...KKK.KKK..KKK.KKK.....",
    ])

    static let sit = Sprite([
        "...............K....K...",
        "..............KPKKKKPK..",
        "..............KhhhhhhK..",
        "..............KOEOOEOK..",
        "..............KOEOOEOK..",
        ".............wKOWPPWOKw.",
        "...........KKKKWWWWWWKw.",
        "..........KhhhOKWWWWK...",
        ".........KhOOsOOKKKK....",
        "........KhOOOsOOWK......",
        "........KOOOOOOOWK......",
        "........KOOOOOOWWK......",
        "........KOOOOOKOK.......",
        ".KKKKKKKKOOOOOKWK.......",
        "KhhhsOOOOOOOOOKWK.......",
        "KKKKKKKKKKKKKKKKK.......",
    ])

    // Im Liegen liegt der Schwanz hinten auf dem Boden (unten links).
    static let lie = Sprite([
        "................K....K..",
        "...............KPKKKKPK.",
        "...............KhhhhhhK.",
        "...............KOEOOEOK.",
        ".....KKKKKKKKKKKOEOOEOK.",
        "....KhhhhhhhhhhKOWPPWOKw",
        "...KhOOsOOsOOsOKWWWWWWKw",
        "KKKKOOOOOOOOOOOOKWWKWWK.",
        "KhshOOOOOOOOOOOOKWWKWWK.",
        "KKKKKKKKKKKKKKKKKKKKKKK.",
    ])

    /// Liegen beim Einatmen: Der Rücken hebt sich ein Stück.
    private static let lieBreathIn = Sprite([
        "................K....K..",
        "...............KPKKKKPK.",
        "...............KhhhhhhK.",
        ".......KKKKKK..KOEOOEOK.",
        ".....KKhhhhhhKKKOEOOEOK.",
        "....KhhOOOOOOOOKOWPPWOKw",
        "...KhOOsOOsOOsOKWWWWWWKw",
        "KKKKOOOOOOOOOOOOKWWKWWK.",
        "KhshOOOOOOOOOOOOKWWKWWK.",
        "KKKKKKKKKKKKKKKKKKKKKKK.",
    ])

    /// Liegen und den Kopf in die streichelnde Hand recken.
    private static let lieNuzzle = Sprite([
        "................K....K..",
        "...............KPKKKKPK.",
        "...............KhhhhhhK.",
        "...............KOEOOEOK.",
        "...............KOEOOEOK.",
        ".....KKKKKKKKKKKOWPPWOKw",
        "....KhhhhhhhhhhKWWWWWWKw",
        "...KhOOsOOsOOsOOKWWWWK..",
        "KKKKOOOOOOOOOOOOKWWKWWK.",
        "KhshOOOOOOOOOOOOKWWKWWK.",
        "KKKKKKKKKKKKKKKKKKKKKKK.",
    ])

    /// Schwanzspitze leicht angehoben (ersetzt die unteren linken 4×4 Pixel einer Liegepose).
    private static let tailUpPatch = [
        "KK.K",
        "KhKK",
        "KKsh",
        ".KKK",
    ].map(Array.init)

    private static func withTailUp(_ sprite: Sprite) -> Sprite {
        sprite.mapped { x, y, c in
            let py = y - (sprite.height - tailUpPatch.count)
            guard x < 4, py >= 0 else { return c }
            return tailUpPatch[py][x]
        }
    }

    static let startled = Sprite([
        "..K............K....K...",
        ".KOK..........KPKKKKPK..",
        "KOOOK.........KhhhhhhK..",
        "KOsOK.........KOEOOEOK..",
        "KOOOK....KKK..KOEOOEOK..",
        ".KsK...KKhhhKKKOWPPWOKw.",
        ".KOK.KKhhOOOOOKWWKKWWK..",
        "..KKhhOOsOOsOOOKWWWWK...",
        "..KOOOOOOOOOOOOOKKKK....",
        "..KOWWWWWWWWWWWOOK......",
        "..KKKKKKKKKKKKKKKK......",
        "..KOK.............KOK...",
        "..KOK.............KOK...",
        ".KOK...............KOK..",
        ".KWK...............KWK..",
        ".KKK...............KKK..",
    ])

    static let standBlink = stand.withClosedEyes
    static let sitBlink = sit.withClosedEyes
    static let lieBlink = lie.withClosedEyes
    static let lieTailUp = withTailUp(lie)
    static let lieBlinkTailUp = withTailUp(lieBlink)
    static let sleepA = lie.withClosedEyes
    static let sleepB = lieBreathIn.withClosedEyes
    static let sleepATailUp = withTailUp(sleepA)
    static let sleepBTailUp = withTailUp(sleepB)
    static let petStand = stand.withHappyEyes
    static let petStandTall = standTall.withHappyEyes
    static let petLie = lie.withHappyEyes
    static let petLieNuzzle = lieNuzzle.withHappyEyes

    static let all: [Sprite] = [
        stand, walkA, walkB, standBlink, sit, lie, lieTailUp, sleepA, sleepBTailUp,
        startled, petStandTall, petLie, petLieNuzzle,
    ]

    /// Katzenkopf für die Menüleiste als Vektorgrafik – gestochen scharf auf jedem Bildschirm.
    /// Als Vorlagenbild färbt macOS ihn passend zum hellen/dunklen Modus.
    static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            NSColor.black.set()

            let head = NSBezierPath()
            head.move(to: NSPoint(x: 10, y: 1.6))
            head.curve(to: NSPoint(x: 2.4, y: 7.2),
                       controlPoint1: NSPoint(x: 5.2, y: 1.6), controlPoint2: NSPoint(x: 2.4, y: 3.8))
            head.line(to: NSPoint(x: 3.0, y: 14.6))
            head.line(to: NSPoint(x: 7.4, y: 11.4))
            head.curve(to: NSPoint(x: 12.6, y: 11.4),
                       controlPoint1: NSPoint(x: 9.0, y: 12.0), controlPoint2: NSPoint(x: 11.0, y: 12.0))
            head.line(to: NSPoint(x: 17.0, y: 14.6))
            head.line(to: NSPoint(x: 17.6, y: 7.2))
            head.curve(to: NSPoint(x: 10, y: 1.6),
                       controlPoint1: NSPoint(x: 17.6, y: 3.8), controlPoint2: NSPoint(x: 14.8, y: 1.6))
            head.close()
            head.lineWidth = 1.3
            head.lineJoinStyle = .round
            head.stroke()

            // Augen
            NSBezierPath(ovalIn: NSRect(x: 6.1, y: 6.3, width: 1.8, height: 2.6)).fill()
            NSBezierPath(ovalIn: NSRect(x: 12.1, y: 6.3, width: 1.8, height: 2.6)).fill()

            // Nase
            let nose = NSBezierPath()
            nose.move(to: NSPoint(x: 9.1, y: 5.4))
            nose.line(to: NSPoint(x: 10.9, y: 5.4))
            nose.line(to: NSPoint(x: 10, y: 4.4))
            nose.close()
            nose.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
