import AppKit

/// Farbpalette: Jeder Buchstabe im Pixelraster steht für eine Farbe, "." ist durchsichtig.
enum Palette {
    static let colors: [Character: CGColor] = [
        "K": rgb(0x2B1D16), // Umriss
        "O": rgb(0xF2A14B), // Fell
        "o": rgb(0xC96F2E), // Streifen
        "W": rgb(0xFFF4E2), // Brust, Pfoten, Schrift
        "P": rgb(0xF49AAE), // Nase, Ohren
        "E": rgb(0x2E5E2A), // Augen
        "Y": rgb(0xFFD447), // Ausrufezeichen
    ]

    private static func rgb(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
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
            return pixel(x, y + 1) == "E" ? "O" : "K"
        }
    }

    /// Zieht einen dunklen Rand um alles Sichtbare (damit Einblendungen auf jedem Hintergrund lesbar sind).
    var outlined: Sprite {
        let w = width + 2, h = height + 2
        var result = [Character](repeating: ".", count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let c = pixel(x - 1, y - 1)
                if c != "." {
                    result[y * w + x] = c
                    continue
                }
                var touches = false
                for dy in -1...1 {
                    for dx in -1...1 where pixel(x - 1 + dx, y - 1 + dy) != "." {
                        touches = true
                    }
                }
                if touches { result[y * w + x] = "K" }
            }
        }
        return Sprite(width: w, height: h, pixels: result)
    }

    /// Zeichnet das Bild; `x`/`y` sind die linke untere Ecke in Pixeleinheiten.
    func draw(in ctx: CGContext, x: CGFloat, y: CGFloat, scale: CGFloat) {
        for row in 0..<height {
            for col in 0..<width {
                guard let color = Palette.colors[pixel(col, row)] else { continue }
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
        ".KK...........KOOOOOOK..",
        "KOK...........KOEOOEOK..",
        "KOK...........KOEOOEOK..",
        "KoK...........KOWPPWOK..",
        "KOKKKKKKKKKKKKKWWWWWWK..",
        ".KOOOoOOoOOoOOOKWWWWK...",
        "..KOOoOOoOOoOOOOKKKK....",
        "..KOOOOOOOOOOOOOOK......",
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

    static let sit = Sprite([
        "...............K....K...",
        "..............KPKKKKPK..",
        "..............KOOOOOOK..",
        "..............KOEOOEOK..",
        "..............KOEOOEOK..",
        "..............KOWPPWOK..",
        "...........KKKKWWWWWWK..",
        "..........KOOoOKWWWWK...",
        ".........KOOOoOOKKKK....",
        "........KOOOOoOOWK......",
        "........KOOOOOOOWK......",
        "........KOOOOOOWWK......",
        "........KOOOOOKOK.......",
        ".KKKKKKKKOOOOOKWK.......",
        "KOOOoOOOOOOOOOKWK.......",
        "KKKKKKKKKKKKKKKKK.......",
    ])

    static let lie = Sprite([
        "................K....K..",
        "...............KPKKKKPK.",
        "...............KOOOOOOK.",
        "...............KOEOOEOK.",
        "..KKKKKKKKKKKKKKOEOOEOK.",
        ".KOOoOOoOOoOOOOKOWPPWOK.",
        "KOOOOOOOOOOOOOOKWWWWWWK.",
        "KoooooooOOOOOOOOKWWKWWK.",
        "KKKKKKKKKKKKKKKKKKKKKKK.",
    ])

    /// Liegen beim Einatmen: Der Rücken hebt sich ein Stück.
    private static let lieBreathIn = Sprite([
        "................K....K..",
        "...............KPKKKKPK.",
        "...............KOOOOOOK.",
        "....KKKKKKKK...KOEOOEOK.",
        "..KKOOOOOOOOKKKKOEOOEOK.",
        ".KOOoOOoOOoOOOOKOWPPWOK.",
        "KOOOOOOOOOOOOOOKWWWWWWK.",
        "KoooooooOOOOOOOOKWWKWWK.",
        "KKKKKKKKKKKKKKKKKKKKKKK.",
    ])

    static let startled = Sprite([
        "..K............K....K...",
        ".KOK..........KPKKKKPK..",
        "KOOOK.........KOOOOOOK..",
        "KOoOK.........KOEOOEOK..",
        "KOOOK....KKK..KOEOOEOK..",
        ".KoK...KKOOOKKKOWPPWOK..",
        ".KOK.KKOOoOOOOKWWKKWWK..",
        "..KKOOoOOoOOOOOKWWWWK...",
        "..KOOOOOOOOOOOOOKKKK....",
        "..KOOOOOOOOOOOOOOK......",
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
    static let sleepA = lie.withClosedEyes
    static let sleepB = lieBreathIn.withClosedEyes

    static let zGlyph = Sprite([
        "WWWW",
        "..W.",
        ".W..",
        "WWWW",
    ]).outlined

    static let bang = Sprite([
        "YY",
        "YY",
        "YY",
        "..",
        "YY",
    ]).outlined

    static let all: [(String, Sprite)] = [
        ("stand", stand), ("walkA", walkA), ("walkB", walkB), ("standBlink", standBlink),
        ("sit", sit), ("sitBlink", sitBlink), ("lie", lie), ("sleepA", sleepA),
        ("sleepB", sleepB), ("startled", startled), ("z", zGlyph), ("!", bang),
    ]

    /// Katzenkopf als Vorlage für die Menüleiste (macOS färbt ihn passend zum hellen/dunklen Modus).
    static func menuBarIcon() -> NSImage {
        let head = Sprite([
            "K.........K",
            "KK.......KK",
            "KKK.....KKK",
            "KKKKKKKKKKK",
            "KK.KKKKK.KK",
            "KK.KKKKK.KK",
            "KKKKK.KKKKK",
            "KKKKKKKKKKK",
            ".KKKKKKKKK.",
        ])
        let px: CGFloat = 2
        let image = NSImage(size: NSSize(width: CGFloat(head.width) * px,
                                         height: CGFloat(head.height) * px),
                            flipped: true) { _ in
            NSColor.black.setFill()
            for y in 0..<head.height {
                for x in 0..<head.width where head.pixel(x, y) != "." {
                    NSRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
