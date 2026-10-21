import AppKit

/// Farbpalette: Jeder Buchstabe im Pixelraster steht für eine Farbe, "." ist durchsichtig.
enum Palette {
    static let colors: [Character: CGColor] = [
        "K": rgb(0x0B0A0F), // Umriss
        "O": rgb(0x26232E), // Fell
        "h": rgb(0x4B4659), // Glanz auf dem Fell (Licht von oben)
        "E": rgb(0xF2C94C), // Augen
        "c": rgb(0x6A6480), // geschlossene Augen
        "P": rgb(0xC47A8E), // Nase, Ohren
        "w": rgb(0x8E889C), // Schnurrhaare
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
        ".KKK..........KhhhhhhK..",
        "KhOK..........KOEOOEOK..",
        "KhK...........KOEOOEOK..",
        "KOK..........wKOOPPOOKw.",
        "KOKKKKKKKKKKKKKOOOOOOKw.",
        ".KOhhhhhhhhhhhhKOOOOK...",
        "..KOOOOOOOOOOOOOKKKK....",
        "..KOOOOOOOOOOOOOOK......",
        "..KOOOOOOOOOOOOOOK......",
        "..KKKKKKKKKKKKKKKK......",
    ]

    static let stand = Sprite(upperBody + [
        "...KOK.KOK..KOK.KOK.....",
        "...KOK.KOK..KOK.KOK.....",
        "...KKK.KKK..KKK.KKK.....",
    ])

    static let walkA = Sprite(upperBody + [
        "..KOK...KOK.KOK...KOK...",
        "..KOK...KOK.KOK...KOK...",
        "..KKK...KKK.KKK...KKK...",
    ])

    static let walkB = Sprite(upperBody + [
        "....KOKKOK....KOKKOK....",
        "....KOKKOK....KOKKOK....",
        "....KKKKKK....KKKKKK....",
    ])

    /// Auf Zehenspitzen – drückt sich beim Streicheln gegen die Hand.
    private static let standTall = Sprite(upperBody + [
        "...KOK.KOK..KOK.KOK.....",
        "...KOK.KOK..KOK.KOK.....",
        "...KOK.KOK..KOK.KOK.....",
        "...KKK.KKK..KKK.KKK.....",
    ])

    static let sit = Sprite([
        "...............K....K...",
        "..............KPKKKKPK..",
        "..............KhhhhhhK..",
        "..............KOEOOEOK..",
        "..............KOEOOEOK..",
        ".............wKOOPPOOKw.",
        "...........KKKKOOOOOOKw.",
        "..........KhhhOKOOOOK...",
        ".........KhOOOOOKKKK....",
        "........KhOOOOOOOK......",
        "........KOOOOOOOOK......",
        "........KOOOOOOOOK......",
        "........KOOOOOKOK.......",
        ".KKKKKKKKOOOOOKOK.......",
        "KhhhhhhhOOOOOOKOK.......",
        "KKKKKKKKKKKKKKKKK.......",
    ])

    static let lie = Sprite([
        "................K....K..",
        "...............KPKKKKPK.",
        "...............KhhhhhhK.",
        "...............KOEOOEOK.",
        "..KKKKKKKKKKKKKKOEOOEOK.",
        ".KhhhhhhhhhhhhhKOOPPOOKw",
        "KhOOOOOOOOOOOOOKOOOOOOKw",
        "KhhhhhhhOOOOOOOOKOOKOOK.",
        "KKKKKKKKKKKKKKKKKKKKKKK.",
    ])

    /// Liegen beim Einatmen: Der Rücken hebt sich ein Stück.
    private static let lieBreathIn = Sprite([
        "................K....K..",
        "...............KPKKKKPK.",
        "...............KhhhhhhK.",
        "....KKKKKKKK...KOEOOEOK.",
        "..KKhhhhhhhhKKKKOEOOEOK.",
        ".KhhOOOOOOOOOOOKOOPPOOKw",
        "KhOOOOOOOOOOOOOKOOOOOOKw",
        "KhhhhhhhOOOOOOOOKOOKOOK.",
        "KKKKKKKKKKKKKKKKKKKKKKK.",
    ])

    /// Liegen und den Kopf in die streichelnde Hand recken.
    private static let lieNuzzle = Sprite([
        "................K....K..",
        "...............KPKKKKPK.",
        "...............KhhhhhhK.",
        "...............KOEOOEOK.",
        "...............KOEOOEOK.",
        "..KKKKKKKKKKKKKKOOPPOOKw",
        ".KhhhhhhhhhhhhhKOOOOOOKw",
        "KhOOOOOOOOOOOOOOKOOOOK..",
        "KhhhhhhhOOOOOOOOKOOKOOK.",
        "KKKKKKKKKKKKKKKKKKKKKKK.",
    ])

    static let startled = Sprite([
        "..K............K....K...",
        ".KOK..........KPKKKKPK..",
        "KOOOK.........KhhhhhhK..",
        "KOhOK.........KOEOOEOK..",
        "KOOOK....KKK..KOEOOEOK..",
        ".KOK...KKhhhKKKOOPPOOKw.",
        ".KOK.KKhhOOOOOKOOKKOOK..",
        "..KKhhOOOOOOOOOKOOOOK...",
        "..KOOOOOOOOOOOOOKKKK....",
        "..KOOOOOOOOOOOOOOK......",
        "..KKKKKKKKKKKKKKKK......",
        "..KOK.............KOK...",
        "..KOK.............KOK...",
        ".KOK...............KOK..",
        ".KOK...............KOK..",
        ".KKK...............KKK..",
    ])

    static let standBlink = stand.withClosedEyes
    static let sitBlink = sit.withClosedEyes
    static let lieBlink = lie.withClosedEyes
    static let sleepA = lie.withClosedEyes
    static let sleepB = lieBreathIn.withClosedEyes
    static let petStand = stand.withHappyEyes
    static let petStandTall = standTall.withHappyEyes
    static let petLie = lie.withHappyEyes
    static let petLieNuzzle = lieNuzzle.withHappyEyes

    /// Katzenkopf für die Menüleiste: nur die Umrisslinie, damit er dezent bleibt.
    static let menuBarHead = Sprite([
        ".K.........K.",
        ".KK.......KK.",
        ".K.K.....K.K.",
        ".K..KKKKK..K.",
        "K...........K",
        "K...K...K...K",
        "K...K...K...K",
        "K.....K.....K",
        ".K.........K.",
        "..KKKKKKKKK..",
    ])

    static let all: [(String, Sprite)] = [
        ("stand", stand), ("walkA", walkA), ("walkB", walkB), ("standBlink", standBlink),
        ("sit", sit), ("sitBlink", sitBlink), ("lie", lie), ("sleepA", sleepA),
        ("sleepB", sleepB), ("startled", startled), ("petStand", petStand),
        ("petStandTall", petStandTall), ("petLie", petLie), ("petLieNuzzle", petLieNuzzle),
        ("menuBarHead", menuBarHead),
    ]

    /// Vorlagenbild für die Menüleiste (macOS färbt es passend zum hellen/dunklen Modus).
    static func menuBarIcon() -> NSImage {
        let head = menuBarHead
        let px: CGFloat = 1
        let image = NSImage(size: NSSize(width: CGFloat(head.width) * px,
                                         height: CGFloat(head.height) * px),
                            flipped: true) { _ in
            NSColor.black.withAlphaComponent(0.85).setFill()
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
