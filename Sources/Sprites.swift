import AppKit

/// Fellfarben. Die Pixelraster benutzen Platzhalter-Buchstaben, jede Fellfarbe legt fest,
/// wie sie aussehen: "K" Umriss, "O" Fell, "h" Glanz, "s" Streifen, "W" Brust/Pfoten,
/// "E" Augen, "c" geschlossene Augen, "P" Nase/Ohren, "w" Schnurrhaare, "t" Zunge. "." ist durchsichtig.
enum Coat: String, CaseIterable {
    case orange, black, gray

    var title: String {
        switch self {
        case .orange: return L10n.s("Orange getigert", "Orange tabby")
        case .black: return L10n.s("Schwarz", "Black")
        case .gray: return L10n.s("Grau getigert", "Gray tabby")
        }
    }

    var colors: [Character: CGColor] {
        switch self {
        case .orange: return Coat.orangeColors
        case .black: return Coat.blackColors
        case .gray: return Coat.grayColors
        }
    }

    private static let orangeColors = rgbPalette([
        "K": 0x2B1D16, "O": 0xF2A14B, "h": 0xF6B263, "s": 0xC96F2E, "W": 0xFFF4E2,
        "E": 0x2E5E2A, "c": 0x2B1D16, "P": 0xF49AAE, "t": 0xE8768E,
    ])

    private static let blackColors = rgbPalette([
        "K": 0x0B0A0F, "O": 0x26232E, "h": 0x4B4659, "s": 0x26232E, "W": 0x26232E,
        "E": 0x7BC95A, "c": 0x6A6480, "P": 0x7A7584, "w": 0x8E889C, "t": 0xD9667F,
    ])

    private static let grayColors = rgbPalette([
        "K": 0x1E1F25, "O": 0x8D9099, "h": 0xA8ABB3, "s": 0x6A6D76, "W": 0xEDEEF1,
        "E": 0xE3AE45, "c": 0x3E4048, "P": 0xD9A0AD, "w": 0xEDEEF1, "t": 0xE8768E,
    ])
}

/// Farben für Napf und Wollknäuel – unabhängig von der Fellfarbe.
enum PropColors {
    static let colors = rgbPalette([
        "K": 0x2B1D16, // Umriss
        "B": 0xD9534F, // Napf
        "b": 0xA83A37, // Napf, Schatten
        "F": 0xA8733F, // Futter
        "f": 0x6E4826, // Futter, dunkel
        "R": 0xE7698F, // Wolle
        "r": 0xB23C68, // Wolle, Fäden
        "N": 0x5E86B0, // Wassernapf
        "n": 0x3F6189, // Wassernapf, Schatten
        "A": 0x7FCBF2, // Wasser
        "a": 0x4FA3D6, // Wasser, Welle
        "L": 0xE3F6FF, // Wasser, Glanz
    ])
}

func rgbPalette(_ hex: [Character: UInt32]) -> [Character: CGColor] {
    hex.mapValues { value in
        CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
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

    /// Um 90° gegen den Uhrzeigersinn gedreht: Aus „schaut nach rechts“ wird „schaut nach oben“.
    var rotatedCounterclockwise: Sprite {
        var result: [Character] = []
        for y in 0..<width {
            for x in 0..<height { result.append(pixel(width - 1 - y, x)) }
        }
        return Sprite(width: height, height: width, pixels: result)
    }

    /// Um 90° im Uhrzeigersinn gedreht: Aus „schaut nach rechts“ wird „schaut nach unten“.
    var rotatedClockwise: Sprite {
        var result: [Character] = []
        for y in 0..<width {
            for x in 0..<height { result.append(pixel(y, height - 1 - x)) }
        }
        return Sprite(width: height, height: width, pixels: result)
    }

    /// Wo der Kopf oben ist: Mitte zwischen den Ohren (Spalte) und Zeile der Ohren.
    /// nil, wenn der Kopf nicht aufrecht ist (Klettern, auf dem Rücken).
    lazy var earAnchor: (center: Int, row: Int)? = {
        for row in 0..<height {
            let ears = (0..<width).filter { pixel($0, row) == "P" }
            guard !ears.isEmpty else { continue }
            guard ears.count == 2, ears[1] - ears[0] == 5, pixel(ears[0], row + 1) == "h" else { return nil }
            return ((ears[0] + ears[1] + 1) / 2, row)
        }
        return nil
    }()

    /// Zeichnet das Bild; `x`/`y` sind die linke untere Ecke in Pixeleinheiten.
    func draw(in ctx: CGContext, x: CGFloat, y: CGFloat, scale: CGFloat, colors: [Character: CGColor]) {
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

    /// Tatze nach vorn – schlägt nach dem Wollknäuel.
    static let bat = Sprite(Array(upperBody[0...8]) + [
        "..KOOsOOsOOsOOOOOKKKKK..",
        "..KOWWWWWWWWWWWOOOOWWK..",
        "..KKKKKKKKKKKKKKKKKKKK..",
        "...KOK.KOK..KOK.........",
        "...KWK.KWK..KWK.........",
        "...KKK.KKK..KKK.........",
    ])

    /// Trinken: Kopf unten im Wassernapf, die Zunge schlabbert (A: Zunge im Wasser, B: Zunge wieder drin).
    static let drinkA = Sprite(eatRows.enumerated().map { i, row in
        i == 11 ? "...KWK.KWK..KWK.KWKtt..." : row
    })
    static let drinkB = Sprite(eatRows)

    /// Kopf unten im Napf, Augen zu.
    private static let eatRows = [
        ".KKK....................",
        "KhOK....................",
        "KhK.....................",
        "KsK.....................",
        "KOKKKKKKKKKKKKK.K....K..",
        ".KOhhhhhhhhhhhhKPKKKKPK.",
        "..KOOsOOsOOsOOOKhhhhhhK.",
        "..KOOsOOsOOsOOOKOcOOcOK.",
        "..KOWWWWWWWWWWOKOWPPWOKw",
        "..KKKKKKKKKKKKKKWWWWWWK.",
        "...KOK.KOK..KOK.KOKKKKK.",
        "...KWK.KWK..KWK.KWK.....",
        "...KKK.KKK..KKK.KKK.....",
    ]
    static let eatA = Sprite(eatRows)
    static let eatB = Sprite(eatRows.enumerated().map { i, row in
        i == 8 ? "..KOWWWWWWWWWWOKOWKKWOKw" : row // kauen
    })

    // Strecken in mehreren Bildern: vorne absenken → tief strecken (wippen, Schwanz pendelt)
    // → aufrichten → Hinterbein nach hinten. Augen genüsslich zu.

    /// Tief gestreckt: vorne runter, Po hoch, Pfoten weit nach vorn.
    private static let bowRows = [
        ".KKK....................",
        "KhOK....................",
        "KhK.....................",
        "KsKKKKK.................",
        "KOKhhhhKKK.....K....K...",
        ".KOOOOOOhhKKKKKPKKKKPK..",
        "..KOOsOOsOOhhhKhhhhhhK..",
        "..KOOOOOOOOOOOKOEOOEOK..",
        "..KOWWWWWWWWOOKOEOOEOK..",
        "..KKKKKKKKKOOOKOWPPWOKw.",
        "...KOK.KOKKOOOKWWWWWWKw.",
        "...KOK.KOK.KKKKKKKKKKKKK",
        "...KWK.KWK.KOOOOOOOOWWWK",
        "...KKK.KKK.KKKKKKKKKKKKK",
    ]
    static let stretchBowA = Sprite(bowRows).withClosedEyes
    /// Dieselbe Pose, Schwanz aufgerichtet und ein Stückchen tiefer – im Wechsel wippt sie.
    static let stretchBowB = Sprite(["....................", "..K....................."]
        + ["KhK.....................", "KhK.....................", "KsKKKKK................."]
        + Array(bowRows[4...])).withClosedEyes

    /// Halb abgesenkt: Übergang zwischen Stehen und tiefem Strecken – mit offenen Augen die Lauerstellung.
    private static let halfRows = [
        ".KKK....................",
        "KhOK....................",
        "KhK............K....K...",
        "KsK...........KPKKKKPK..",
        "KOKKKKKKKK....KhhhhhhK..",
        ".KOhhhhhhhKKKKKOEOOEOK..",
        "..KOOsOOsOOhhhKOEOOEOK..",
        "..KOOsOOsOOOOOKOWPPWOKw.",
        "..KOOOOOOOOOOOKWWWWWWKw.",
        "..KOWWWWWWWWOOOKWWWWK...",
        "..KKKKKKKKKKKOOOKKKK....",
        "...KOK.KOK..KOOK........",
        "...KOK.KOK..KOOOK.......",
        "...KWK.KWK...KWWWK......",
        "...KKK.KKK...KKKKK......",
    ]
    static let stretchHalf = Sprite(halfRows).withClosedEyes
    /// Lauern: vorne geduckt, Blick nach vorn – vor dem Sprung auf den Mauszeiger
    static let crouch = Sprite(halfRows)

    /// Zum Schluss ein Hinterbein genüsslich nach hinten ausstrecken.
    static let stretchHind = Sprite(Array(upperBody[0...10]) + [
        "KKKKKKKKKKKKKKKKKK......",
        "KWOK...KOK..KOK.KOK.....",
        "KKK....KWK..KWK.KWK.....",
        ".......KKK..KKK.KKK.....",
    ]).withClosedEyes

    private static let sitRows = [
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
    ]
    static let sit = Sprite(sitRows)

    /// Ersetzt einzelne Zeilen der Sitzpose.
    private static func sitVariant(_ rows: [Int: String]) -> Sprite {
        Sprite(sitRows.enumerated().map { i, row in rows[i] ?? row })
    }

    static let yawn = sitVariant([
        5: ".............wKOWKKWOKw.",
        6: "...........KKKKWKPPKWKw.",
        7: "..........KhhhOKWKKWK...",
    ]).withClosedEyes

    /// Pfote zum Maul heben und ablecken.
    private static let groomPaw = [
        7: "..........KhhhOKWKWKK...",
        8: ".........KhOOsOOKKWK....",
        9: "........KhOOOsOOKOK.....",
    ]
    static let groomA = sitVariant(groomPaw.merging([6: "...........KKKKWWKPKWKw."]) { $1 }).withClosedEyes
    static let groomB = sitVariant(groomPaw.merging([6: "...........KKKKWWKWKWKw."]) { $1 }).withClosedEyes

    /// Pfote über Gesicht und Ohr streichen.
    private static let headWashPaw = [
        2: "..............KhhhhhhKWK",
        3: "..............KOEOOEOKWK",
        4: "..............KOEOOEOKWK",
        5: ".............wKOWPPWOKWK",
        6: "...........KKKKWWWWWWKWK",
        7: "..........KhhhOKWWWWKWK.",
        8: ".........KhOOsOOKKKKWK..",
        9: "........KhOOOsOOWKWK....",
    ]
    static let headWashA = sitVariant(headWashPaw.merging([
        0: "...............K....KKKK",
        1: "..............KPKKKKPKWK",
    ]) { $1 }).withClosedEyes
    static let headWashB = sitVariant(headWashPaw.merging([
        1: "..............KPKKKKPKKK",
    ]) { $1 }).withClosedEyes

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

    /// Auf dem Rücken, Pfoten in der Luft, Kopf verkehrt herum.
    private static let backRoll = Sprite([
        "..KKK.KKK.KKKKKK........",
        "..KWK.KWK.KWKKWK.KKKKKK.",
        "..KOK.KOK.KOKKOKKWWWWWWK",
        ".KKKKKKKKKKKKKKKKOWPPWOK",
        "KWWWWWWWWWWWWWWOKOEOOEOK",
        "KOOOOOOOOOOOOOOOKOEOOEOK",
        "KOOsOOsOOsOOOOOOKhhhhhhK",
        ".KOOOOOOOOOOOOOOKPKKKKPK",
        "..KKKKKKKKKKKKKK.K....K.",
    ])
    static let rollA = backRoll.withHappyEyes
    /// Vorderpfoten eingeknickt: Die Pfoten rutschen eine Zeile tiefer.
    static let rollB = rollA.mapped { x, y, c in
        guard (10...15).contains(x), y <= 2 else { return c }
        return y == 0 ? "." : rollA.pixel(x, y - 1)
    }

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

    // An einer Fensterkante: Pfoten an der Wand rechts, Kopf oben bzw. unten.
    static let climbUpA = walkA.rotatedCounterclockwise
    static let climbUpB = walkB.rotatedCounterclockwise
    /// Kopf unten, Pfoten an der Wand links
    static let climbDownA = walkA.rotatedClockwise
    static let climbDownB = walkB.rotatedClockwise

    static let all: [Sprite] = [
        stand, walkA, walkB, sit, yawn, stretchHalf, stretchBowA, stretchBowB, stretchHind,
        groomA, groomB, headWashA, headWashB, lie, lieTailUp,
        sleepB, rollA, rollB, eatA, eatB, bat,
        startled, petStandTall, petLieNuzzle,
        climbUpA, climbUpB, climbDownA, climbDownB,
    ]

    // MARK: Napf und Wollknäuel

    static let bowlFull = Sprite([
        "...fFFfFF...",
        ".KFFfFFfFFK.",
        "KBBBBBBBBBBK",
        ".KBBBBBBbbK.",
        "..KKKKKKKK..",
    ])
    static let bowlHalf = Sprite([
        "............",
        ".KKKfFFfKKK.",
        "KBBBBBBBBBBK",
        ".KBBBBBBbbK.",
        "..KKKKKKKK..",
    ])
    static let bowlEmpty = Sprite([
        "............",
        ".KKKKKKKKKK.",
        "KBBBBBBBBBBK",
        ".KBBBBBBbbK.",
        "..KKKKKKKK..",
    ])

    /// Von hinten: sitzt am Fenster und schaut hinaus. Der Schwanz liegt seitlich und zuckt ab und zu (A/B).
    private static let backRows = [
        "..K......K......",
        ".KOK....KOK.....",
        ".KOOKKKKOOK.....",
        "KOOOOOOOOOOK....",
        "KOhOOOOOOhOK....",
        "KOOOOOOOOOOK....",
        ".KOOOOOOOOK.....",
        "..KKOOOOKK......",
        ".KOOOOOOOOK.....",
        "KOOsOOOOsOOK....",
        "KOOOsOOsOOOK.KK.",
        "KOOOOOOOOOOK.KOK",
        "KOOOOOOOOOOKKOK.",
        "KOOOOOOOOOOOOK..",
        ".KKKKKKKKKKKKK..",
    ]
    static let sitBackA = backSprite(backRows)
    static let sitBackB = backSprite(backRows.enumerated().map { i, row in
        switch i {
        case 10: return "KOOOsOOsOOOK...."
        case 11: return "KOOOOOOOOOOK.KK."
        case 12: return "KOOOOOOOOOOKKOOK"
        default: return row
        }
    })
    /// Von hinten sieht man keine Ohr-Innenseiten – wo der Hut sitzt, steht deshalb hier
    private static func backSprite(_ rows: [String]) -> Sprite {
        let sprite = Sprite(rows)
        sprite.earAnchor = (center: 5, row: 0)
        return sprite
    }

    /// Wassernapf: voll mit Wellen (A/B im Wechsel), halb, leer
    static let waterFullA = Sprite([
        "............",
        ".KALAAaAAAK.",
        "KNNNNNNNNNNK",
        ".KNNNNNNnnK.",
        "..KKKKKKKK..",
    ])
    static let waterFullB = Sprite([
        "............",
        ".KAAaAALAAK.",
        "KNNNNNNNNNNK",
        ".KNNNNNNnnK.",
        "..KKKKKKKK..",
    ])
    static let waterHalf = Sprite([
        "............",
        ".KKKAaALKKK.",
        "KNNNNNNNNNNK",
        ".KNNNNNNnnK.",
        "..KKKKKKKK..",
    ])
    static let waterEmpty = Sprite([
        "............",
        ".KKKKKKKKKK.",
        "KNNNNNNNNNNK",
        ".KNNNNNNnnK.",
        "..KKKKKKKK..",
    ])

    static let yarnA = Sprite([
        "..KKK..",
        ".KRrRK.",
        "KRRrRRK",
        "KrRRRrK",
        "KRRrRRK",
        ".KRrRK.",
        "..KKK..",
    ])
    static let yarnB = Sprite([
        "..KKK..",
        ".KrRRK.",
        "KRrRRrK",
        "KRRrRRK",
        "KrRRrRK",
        ".KRRrK.",
        "..KKK..",
    ])

    // MARK: Verkleidungen (an Feiertagen automatisch)

    /// Weihnachtsmütze (24./25. Dezember)
    static let santaHat = Sprite([
        "....KKK.....",
        "...KRRRK.KK.",
        "..KRRRRRKWWK",
        "..KRRRRRRKK.",
        ".KWWWWWWWWK.",
        ".KWWWWWWWWK.",
        "..KKKKKKKK..",
    ])

    /// Partyhut (31. Dezember und 1. Januar)
    static let partyHat = Sprite([
        "...Y...",
        "..YGY..",
        "...K...",
        "..KBK..",
        "..KYK..",
        ".KBYBK.",
        ".KYBYK.",
        "KBYBYBK",
        "KKKKKKK",
    ])

    /// Geschnitzter Kürbis mit leuchtendem Gesicht (Halloween, 31. Oktober)
    static let pumpkinHat = Sprite([
        "....KKK....",
        "....KTK....",
        ".KKKKTKKKK.",
        "KUuUUuUUuUK",
        "KUYYUuUYYUK",
        "KUuUUuUUuUK",
        "KUYuYUYuYUK",
        "KUuYUYUYuUK",
        ".KKKKKKKKK.",
    ])

    static let accessoryColors = rgbPalette([
        "K": 0x2B1D16, "R": 0xD7263D, "W": 0xFFFFFF, "B": 0x3E7BD6, "Y": 0xF5C542, "G": 0xFFF3B0,
        "U": 0xF28C28, "u": 0xC2611B, "T": 0x4F8A3C,
    ])

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
